const std = @import("std");
const debug_f = @import("debug.zig");

pub const Gpu = struct {
    pub const GP0: u32 = 0x1F80_1810;
    pub const GP1: u32 = 0x1F80_1814;

    unsupported_gp0_log_count: u32 = 0,

    status: u32 = 0x1C00_0000,

    gp0_last: u32 = 0,
    gp1_last: u32 = 0,

    gpu_info_response: u32 = 0,

    gp0_mode: u8 = 0, // 0=command, 1=A0 pos, 2=A0 size, 3=A0 data, 4=C0 pos, 5=C0 size
    gp0_words_remaining: u32 = 0,
    gp0_skip_words: u32 = 0,

    gp0_quad_active: bool = false,
    gp0_quad_color: u16 = 0,
    gp0_quad_vertices: [4]u32 = [_]u32{0} ** 4,
    gp0_quad_vertex_index: u8 = 0,

    vram: [1024 * 512]u16 = [_]u16{0} ** (1024 * 512),

    vram_x: u16 = 0,
    vram_y: u16 = 0,
    vram_w: u16 = 0,
    vram_h: u16 = 0,

    image_x: u16 = 0,
    image_y: u16 = 0,
    image_w: u16 = 0,
    image_h: u16 = 0,
    image_index: u32 = 0,

    display_x: u16 = 0,
    display_y: u16 = 0,
    display_h_start: u16 = 0,
    display_h_end: u16 = 0,
    display_v_start: u16 = 0,
    display_v_end: u16 = 0,
    display_mode: u32 = 0,
    dma_direction: u32 = 0,
    display_disabled: bool = true,

    draw_mode: u32 = 0,

    gp0_textured_quad_color: u32 = 0,
    gp0_textured_quad_active: bool = false,
    gp0_textured_quad_words: [8]u32 = [_]u32{0} ** 8,
    gp0_textured_quad_index: u8 = 0,

    gp0_dot_color: u16 = 0,
    gp0_dot_active: bool = false,

    gp0_sprite_color: u16 = 0,
    gp0_sprite_words: [3]u32 = [_]u32{0} ** 3,
    gp0_sprite_index: u8 = 0,
    gp0_sprite_active: bool = false,

    gp0_fixed_rect_color: u16 = 0,
    gp0_fixed_rect_w: u32 = 0,
    gp0_fixed_rect_h: u32 = 0,
    gp0_fixed_rect_active: bool = false,

    gp0_vram_fill_color: u16 = 0,
    gp0_vram_fill_words: [2]u32 = [_]u32{0} ** 2,
    gp0_vram_fill_index: u8 = 0,
    gp0_vram_fill_active: bool = false,

    gp0_textured_rect_words: [3]u32 = [_]u32{0} ** 3,
    gp0_textured_rect_index: u8 = 0,
    gp0_textured_rect_active: bool = false,

    gp0_fixed_textured_rect_words: [2]u32 = [_]u32{0} ** 2,
    gp0_fixed_textured_rect_index: u8 = 0,
    gp0_fixed_textured_rect_w: u32 = 0,
    gp0_fixed_textured_rect_h: u32 = 0,
    gp0_fixed_textured_rect_active: bool = false,

    draw_area_left: i32 = 0,
    draw_area_top: i32 = 0,
    draw_area_right: i32 = 1023,
    draw_area_bottom: i32 = 511,
    draw_offset_x: i32 = 0,
    draw_offset_y: i32 = 0,

    pub fn readStatus(self: *const Gpu) u32 {
        var value: u32 = self.status;

        // Bit 23: display disabled.
        if (self.display_disabled) {
            value |= @as(u32, 1) << 23;
        } else {
            value &= ~(@as(u32, 1) << 23);
        }

        // Bits 29-30: DMA direction.
        value &= ~(@as(u32, 0x3) << 29);
        value |= (self.dma_direction & 0x3) << 29;

        // Ready for command, ready to send VRAM, ready for DMA block.
        value |= 0x1C00_0000;

        return value;
    }

    fn xyX(word: u32) i32 {
        const raw: u16 = @intCast(word & 0xFFFF);
        const signed: i16 = @bitCast(raw);
        return @as(i32, signed);
    }

    fn xyY(word: u32) i32 {
        const raw: u16 = @intCast((word >> 16) & 0xFFFF);
        const signed: i16 = @bitCast(raw);
        return @as(i32, signed);
    }

    fn uvU(word: u32) u32 {
        return word & 0xFF;
    }

    fn uvV(word: u32) u32 {
        return (word >> 8) & 0xFF;
    }

    fn clutX(word: u32) u32 {
        return ((word >> 16) & 0x3F) * 16;
    }

    fn clutY(word: u32) u32 {
        return (word >> 22) & 0x1FF;
    }

    fn texturePageBaseX(draw_mode: u32) u32 {
        return (draw_mode & 0xF) * 64;
    }

    fn texturePageBaseY(draw_mode: u32) u32 {
        return ((draw_mode >> 4) & 0x1) * 256;
    }

    fn textureMode(draw_mode: u32) u32 {
        return (draw_mode >> 7) & 0x3;
    }

    fn sampleTexture4BitClut(self: *const Gpu, tex_base_x: u32, tex_base_y: u32, clut_x: u32, clut_y: u32, u: u32, v: u32) u16 {
        const tex_x = tex_base_x + (u / 4);
        const tex_y = tex_base_y + v;
        if (tex_x >= 1024 or tex_y >= 512) return 0;
        if (clut_x >= 1024 or clut_y >= 512) return 0;

        const _packed = self.vram[@intCast(tex_y * 1024 + tex_x)];
        const shift: u4 = @intCast((u & 3) * 4);
        const index: u32 = (_packed >> shift) & 0xF;

        return self.vram[@intCast(clut_y * 1024 + clut_x + index)];
    }

    fn sampleTexture8BitClut(self: *const Gpu, tex_base_x: u32, tex_base_y: u32, clut_x: u32, clut_y: u32, u: u32, v: u32) u16 {
        const tex_x = tex_base_x + (u / 2);
        const tex_y = tex_base_y + v;
        if (tex_x >= 1024 or tex_y >= 512) return 0;
        if (clut_x >= 1024 or clut_y >= 512) return 0;

        const _packed = self.vram[@intCast(tex_y * 1024 + tex_x)];
        const shift: u4 = if ((u & 1) == 0) 0 else 8;
        const index: u32 = (_packed >> shift) & 0xFF;

        return self.vram[@intCast(clut_y * 1024 + clut_x + index)];
    }

    fn sampleTexture15Bit(self: *const Gpu, tex_base_x: u32, tex_base_y: u32, u: u32, v: u32) u16 {
        const tex_x = tex_base_x + u;
        const tex_y = tex_base_y + v;
        if (tex_x >= 1024 or tex_y >= 512) return 0;

        return self.vram[@intCast(tex_y * 1024 + tex_x)];
    }

    fn sampleTexture(self: *const Gpu, tex_base_x: u32, tex_base_y: u32, clut_x: u32, clut_y: u32, u: u32, v: u32) u16 {
        return switch (textureMode(self.draw_mode)) {
            0 => self.sampleTexture4BitClut(tex_base_x, tex_base_y, clut_x, clut_y, u, v),
            1 => self.sampleTexture8BitClut(tex_base_x, tex_base_y, clut_x, clut_y, u, v),
            2 => self.sampleTexture15Bit(tex_base_x, tex_base_y, u, v),
            else => 0,
        };
    }
    fn drawTexturedQuad2C(self: *Gpu) void {
        const xy0_word = self.gp0_textured_quad_words[0];
        const uv0_word = self.gp0_textured_quad_words[1];
        const xy1_word = self.gp0_textured_quad_words[2];
        const uv1_word = self.gp0_textured_quad_words[3];
        const xy2_word = self.gp0_textured_quad_words[4];
        const uv2_word = self.gp0_textured_quad_words[5];
        const xy3_word = self.gp0_textured_quad_words[6];

        const x0 = xyX(xy0_word) + self.draw_offset_x;
        const y0 = xyY(xy0_word) + self.draw_offset_y;
        const x1 = xyX(xy1_word) + self.draw_offset_x;
        const y1 = xyY(xy1_word) + self.draw_offset_y;
        const x2 = xyX(xy2_word) + self.draw_offset_x;
        const y2 = xyY(xy2_word) + self.draw_offset_y;
        const x3 = xyX(xy3_word) + self.draw_offset_x;
        const y3 = xyY(xy3_word) + self.draw_offset_y;

        var min_x = x0;
        var max_x = x0;
        var min_y = y0;
        var max_y = y0;

        if (x1 < min_x) min_x = x1;
        if (x1 > max_x) max_x = x1;
        if (y1 < min_y) min_y = y1;
        if (y1 > max_y) max_y = y1;

        if (x2 < min_x) min_x = x2;
        if (x2 > max_x) max_x = x2;
        if (y2 < min_y) min_y = y2;
        if (y2 > max_y) max_y = y2;

        if (x3 < min_x) min_x = x3;
        if (x3 > max_x) max_x = x3;
        if (y3 < min_y) min_y = y3;
        if (y3 > max_y) max_y = y3;

        if (max_x < 0 or max_y < 0 or min_x >= 1024 or min_y >= 512) return;

        if (min_x < 0) min_x = 0;
        if (min_y < 0) min_y = 0;
        if (max_x > 1023) max_x = 1023;
        if (max_y > 511) max_y = 511;

        if (min_x < self.draw_area_left) min_x = self.draw_area_left;
        if (min_y < self.draw_area_top) min_y = self.draw_area_top;
        if (max_x > self.draw_area_right) max_x = self.draw_area_right;
        if (max_y > self.draw_area_bottom) max_y = self.draw_area_bottom;

        if (max_x < min_x or max_y < min_y) return;

        const tex_u0 = uvU(uv0_word);
        const tex_v0 = uvV(uv0_word);
        const tex_u1 = uvU(uv1_word);
        const tex_v2 = uvV(uv2_word);

        const clx = clutX(uv0_word);
        const cly = clutY(uv0_word);

        const tex_base_x = texturePageBaseX(self.draw_mode);
        const tex_base_y = texturePageBaseY(self.draw_mode);

        const dst_w_i = max_x - min_x + 1;
        const dst_h_i = max_y - min_y + 1;
        if (dst_w_i <= 0 or dst_h_i <= 0) return;

        const dst_w: u32 = @intCast(dst_w_i);
        const dst_h: u32 = @intCast(dst_h_i);

        const tex_w: u32 = if (tex_u1 >= tex_u0) (tex_u1 - tex_u0 + 1) else 1;
        const tex_h: u32 = if (tex_v2 >= tex_v0) (tex_v2 - tex_v0 + 1) else 1;

        var dy: u32 = 0;
        while (dy < dst_h) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < dst_w) : (dx += 1) {
                const tu = tex_u0 + (dx * tex_w) / dst_w;
                const tv = tex_v0 + (dy * tex_h) / dst_h;

                const px = self.sampleTexture(tex_base_x, tex_base_y, clx, cly, tu, tv);
                // In PS1 textured drawing, palette index/color 0 often acts transparent depending mode.
                // For BIOS logo this is useful; later make this respect transparency/semi-transparency rules.

                // TEMP: draw even px==0 for debugging? no, keep transparency.
                if (px == 0) continue;

                const dst_x: u32 = @intCast(min_x + @as(i32, @intCast(dx)));
                const dst_y: u32 = @intCast(min_y + @as(i32, @intCast(dy)));

                self.vram[@intCast(dst_y * 1024 + dst_x)] = px;
            }
        }
    }

    fn drawFilledRect(self: *Gpu, x: i32, y: i32, w: u32, h: u32, color: u16) void {
        var yy: u32 = 0;
        while (yy < h) : (yy += 1) {
            var xx: u32 = 0;
            while (xx < w) : (xx += 1) {
                self.putPixel(
                    x + @as(i32, @intCast(xx)),
                    y + @as(i32, @intCast(yy)),
                    color,
                );
            }
        }
    }

    fn drawTexturedRect4Bit(self: *Gpu, x: i32, y: i32, uv_word: u32, w: u32, h: u32) void {
        const tex_u0 = uvU(uv_word);
        const tex_v0 = uvV(uv_word);
        const clx = clutX(uv_word);
        const cly = clutY(uv_word);

        const tex_base_x = texturePageBaseX(self.draw_mode);
        const tex_base_y = texturePageBaseY(self.draw_mode);

        var yy: u32 = 0;
        while (yy < h) : (yy += 1) {
            var xx: u32 = 0;
            while (xx < w) : (xx += 1) {
                const px = self.sampleTexture(
                    tex_base_x,
                    tex_base_y,
                    clx,
                    cly,
                    tex_u0 + xx,
                    tex_v0 + yy,
                );
                if (px == 0) continue;

                self.putPixel(
                    x + @as(i32, @intCast(xx)),
                    y + @as(i32, @intCast(yy)),
                    px,
                );
            }
        }
    }

    pub fn writeGp0(self: *Gpu, pc: u32, value: u32) void {
        const cmd: u8 = @intCast(value >> 24);
        self.gp0_last = value;

        if (self.gp0_dot_active) {
            const x = xyX(value) + self.draw_offset_x;
            const y = xyY(value) + self.draw_offset_y;
            self.putPixel(x, y, self.gp0_dot_color);
            self.gp0_dot_active = false;
            return;
        }

        if (self.gp0_fixed_rect_active) {
            const x = xyX(value) + self.draw_offset_x;
            const y = xyY(value) + self.draw_offset_y;

            self.drawFilledRect(
                x,
                y,
                self.gp0_fixed_rect_w,
                self.gp0_fixed_rect_h,
                self.gp0_fixed_rect_color,
            );
            self.gp0_fixed_rect_active = false;
            return;
        }

        if (self.gp0_textured_rect_active) {
            self.gp0_textured_rect_words[self.gp0_textured_rect_index] = value;
            self.gp0_textured_rect_index += 1;

            if (self.gp0_textured_rect_index == 3) {
                const xy = self.gp0_textured_rect_words[0];
                const uv = self.gp0_textured_rect_words[1];
                const size = self.gp0_textured_rect_words[2];

                const x = xyX(xy) + self.draw_offset_x;
                const y = xyY(xy) + self.draw_offset_y;
                const w: u32 = @intCast(size & 0xFFFF);
                const h: u32 = @intCast((size >> 16) & 0xFFFF);

                self.drawTexturedRect4Bit(x, y, uv, w, h);

                self.gp0_textured_rect_active = false;
                self.gp0_textured_rect_index = 0;
            }

            return;
        }

        if (self.gp0_fixed_textured_rect_active) {
            self.gp0_fixed_textured_rect_words[self.gp0_fixed_textured_rect_index] = value;
            self.gp0_fixed_textured_rect_index += 1;

            if (self.gp0_fixed_textured_rect_index == 2) {
                const xy = self.gp0_fixed_textured_rect_words[0];
                const uv = self.gp0_fixed_textured_rect_words[1];

                const x = xyX(xy) + self.draw_offset_x;
                const y = xyY(xy) + self.draw_offset_y;

                self.drawTexturedRect4Bit(
                    x,
                    y,
                    uv,
                    self.gp0_fixed_textured_rect_w,
                    self.gp0_fixed_textured_rect_h,
                );

                self.gp0_fixed_textured_rect_active = false;
                self.gp0_fixed_textured_rect_index = 0;
            }

            return;
        }

        if (self.gp0_sprite_active) {
            self.gp0_sprite_words[self.gp0_sprite_index] = value;
            self.gp0_sprite_index += 1;

            if (self.gp0_sprite_index == 3) {
                const xy = self.gp0_sprite_words[0];
                const size = self.gp0_sprite_words[2];

                const x = xyX(xy) + self.draw_offset_x;
                const y = xyY(xy) + self.draw_offset_y;
                const w: u32 = @intCast(size & 0xFFFF);
                const h: u32 = @intCast((size >> 16) & 0xFFFF);

                self.drawFilledRect(x, y, w, h, self.gp0_sprite_color);
                self.gp0_sprite_active = false;
                self.gp0_sprite_index = 0;
            }
            return;
        }

        if (self.gp0_vram_fill_active) {
            self.gp0_vram_fill_words[self.gp0_vram_fill_index] = value;
            self.gp0_vram_fill_index += 1;

            if (self.gp0_vram_fill_index == 2) {
                const xy = self.gp0_vram_fill_words[0];
                const size = self.gp0_vram_fill_words[1];

                const x: i32 = @intCast(xy & 0xFFFF);
                const y: i32 = @intCast((xy >> 16) & 0xFFFF);
                const w: u32 = @intCast(size & 0xFFFF);
                const h: u32 = @intCast((size >> 16) & 0xFFFF);

                self.drawFilledRect(x, y, w, h, self.gp0_vram_fill_color);
                self.gp0_vram_fill_active = false;
                self.gp0_vram_fill_index = 0;
            }
            return;
        }

        if (self.gp0_textured_quad_active) {
            self.gp0_textured_quad_words[self.gp0_textured_quad_index] = value;
            self.gp0_textured_quad_index += 1;

            if (self.gp0_textured_quad_index == 8) {
                self.drawTexturedQuad2C();
                self.gp0_textured_quad_active = false;
                self.gp0_textured_quad_index = 0;
            }

            return;
        }

        if (self.gp0_quad_active) {
            self.gp0_quad_vertices[self.gp0_quad_vertex_index] = value;
            self.gp0_quad_vertex_index += 1;

            if (self.gp0_quad_vertex_index == 4) {
                self.drawFilledQuadBBox();
                self.gp0_quad_active = false;
                self.gp0_quad_vertex_index = 0;
            }

            return;
        }

        if (self.gp0_skip_words > 0) {
            self.gp0_skip_words -= 1;
            return;
        }

        switch (self.gp0_mode) {
            1 => {
                self.vram_x = @intCast(value & 0xFFFF);
                self.vram_y = @intCast((value >> 16) & 0xFFFF);
                self.gp0_mode = 2;
                return;
            },

            2 => {
                self.vram_w = @intCast(value & 0xFFFF);
                self.vram_h = @intCast((value >> 16) & 0xFFFF);

                // PS1 GPU treats 0 as max dimension for image copy commands.
                if (self.vram_w == 0) self.vram_w = 1024;
                if (self.vram_h == 0) self.vram_h = 512;

                const pixels: u32 = @as(u32, self.vram_w) * @as(u32, self.vram_h);

                self.gp0_words_remaining = (pixels + 1) / 2;
                self.image_x = self.vram_x;
                self.image_y = self.vram_y;
                self.image_w = self.vram_w;
                self.image_h = self.vram_h;
                self.image_index = 0;
                self.gp0_mode = 3;

                return;
            },

            3 => {
                self.writeImageData(value);
                return;
            },

            4 => {
                self.vram_x = @intCast(value & 0xFFFF);
                self.vram_y = @intCast((value >> 16) & 0xFFFF);
                self.gp0_mode = 5;
                return;
            },

            5 => {
                self.vram_w = @intCast(value & 0xFFFF);
                self.vram_h = @intCast((value >> 16) & 0xFFFF);

                if (self.vram_w == 0) self.vram_w = 1024;
                if (self.vram_h == 0) self.vram_h = 512;

                self.gp0_mode = 0;

                //std.debug.print(
                //  "GP0 IMAGE READ x={} y={} w={} h={}\n",
                //.{
                //  self.vram_x,
                //self.vram_y,
                //self.vram_w,
                //self.vram_h,
                //},
                //);

                return;
            },

            else => {},
        }

        switch (cmd) {
            0x00 => {}, // NOP
            0x01 => {}, // clear cache
            0x02 => {
                self.gp0_vram_fill_color = rgb24ToRgb555(value);
                self.gp0_vram_fill_active = true;
                self.gp0_vram_fill_index = 0;
            },
            0x28 => {
                //std.debug.print("GP0 QUAD 0x28 color=0x{X:0>6}\n", .{value & 0x00FF_FFFF});
                self.gp0_quad_color = rgb24ToRgb555(value);
                self.gp0_quad_active = true;
                self.gp0_quad_vertex_index = 0;
            },
            0x30 => {
                self.gp0_skip_words = 5;
            },
            0x38 => {
                self.gp0_skip_words = 7;
            },
            0x2C => {
                self.gp0_textured_quad_color = value;
                self.gp0_textured_quad_active = true;
                self.gp0_textured_quad_index = 0;
                return;
            },
            0x60 => {
                self.gp0_sprite_color = rgb24ToRgb555(value);
                self.gp0_sprite_active = true;
                self.gp0_sprite_index = 0;
            },
            0x62 => {
                self.gp0_sprite_color = rgb24ToRgb555(value);
                self.gp0_sprite_active = true;
                self.gp0_sprite_index = 0;
            },
            0x64, 0x65 => {
                self.gp0_textured_rect_active = true;
                self.gp0_textured_rect_index = 0;
            },

            0x68 => {
                self.gp0_dot_color = rgb24ToRgb555(value);
                self.gp0_dot_active = true;
            },
            0x70 => {
                self.gp0_fixed_rect_color = rgb24ToRgb555(value);
                self.gp0_fixed_rect_w = 8;
                self.gp0_fixed_rect_h = 8;
                self.gp0_fixed_rect_active = true;
            },
            0x72 => {
                self.gp0_fixed_rect_color = rgb24ToRgb555(value);
                self.gp0_fixed_rect_w = 8;
                self.gp0_fixed_rect_h = 8;
                self.gp0_fixed_rect_active = true;
            },
            0x74, 0x75 => {
                self.gp0_fixed_textured_rect_w = 8;
                self.gp0_fixed_textured_rect_h = 8;
                self.gp0_fixed_textured_rect_active = true;
                self.gp0_fixed_textured_rect_index = 0;
            },
            0x78 => {
                self.gp0_fixed_rect_color = rgb24ToRgb555(value);
                self.gp0_fixed_rect_w = 16;
                self.gp0_fixed_rect_h = 16;
                self.gp0_fixed_rect_active = true;
            },
            0x7A => {
                self.gp0_fixed_rect_color = rgb24ToRgb555(value);
                self.gp0_fixed_rect_w = 16;
                self.gp0_fixed_rect_h = 16;
                self.gp0_fixed_rect_active = true;
            },

            0x7C, 0x7D => {
                self.gp0_fixed_textured_rect_w = 16;
                self.gp0_fixed_textured_rect_h = 16;
                self.gp0_fixed_textured_rect_active = true;
                self.gp0_fixed_textured_rect_index = 0;
            },

            0xE1 => {
                self.draw_mode = value & 0x00FF_FFFF;
            }, // draw mode
            0xE2 => {}, // texture window
            0xE3 => {
                const p = value & 0x00FF_FFFF;
                self.draw_area_left = @intCast(p & 0x3FF);
                self.draw_area_top = @intCast((p >> 10) & 0x1FF);
            }, // drawing area top-left
            0xE4 => {
                const p = value & 0x00FF_FFFF;
                self.draw_area_right = @intCast(p & 0x3FF);
                self.draw_area_bottom = @intCast((p >> 10) & 0x1FF);
            }, // drawing area bottom-right
            0xE5 => {
                const p = value & 0x00FF_FFFF;
                const ox_raw: u16 = @intCast(p & 0x7FF);
                const oy_raw: u16 = @intCast((p >> 11) & 0x7FF);
                var ox: i32 = @intCast(ox_raw);
                var oy: i32 = @intCast(oy_raw);
                if ((ox_raw & 0x400) != 0) ox -= 0x800;
                if ((oy_raw & 0x400) != 0) oy -= 0x800;

                self.draw_offset_x = ox;
                self.draw_offset_y = oy;
            }, // drawing offset
            0xE6 => {}, // mask bit setting

            0xA0 => {
                self.gp0_mode = 1;
            },

            0xC0 => {
                self.gp0_mode = 4;
            },

            else => {
                if (debug_f.enable_gpu_unsupported_trace and self.unsupported_gp0_log_count < 128) {
                    self.unsupported_gp0_log_count += 1;
                    std.debug.print(
                        "UNSUPPORTED GP0 PC=0x{X:0>8} cmd=0x{X:0>2} value=0x{X:0>8}\n",
                        .{ pc, cmd, value },
                    );
                }
            },
        }
    }
    pub fn readGP0(self: *const Gpu) u32 {
        return self.gpu_info_response;
    }

    fn writeImageData(self: *Gpu, value: u32) void {
        const lo: u16 = @intCast(value & 0xFFFF);
        const hi: u16 = @intCast((value >> 16) & 0xFFFF);

        const pixel_count: u32 = @as(u32, self.image_w) * @as(u32, self.image_h);

        self.writeImagePixel(lo, pixel_count);
        self.writeImagePixel(hi, pixel_count);

        if (self.gp0_words_remaining > 0) {
            self.gp0_words_remaining -= 1;
        }

        if (self.gp0_words_remaining == 0) {
            self.gp0_mode = 0;
            self.status |= 0x1C00_0000;
        }
    }

    fn writeImagePixel(self: *Gpu, pixel: u16, pixel_count: u32) void {
        if (self.image_index >= pixel_count) return;

        const px = self.image_index % self.image_w;
        const py = self.image_index / self.image_w;
        const x = @as(u32, self.image_x) + px;
        const y = @as(u32, self.image_y) + py;

        if (x < 1024 and y < 512) {
            self.vram[@intCast(y * 1024 + x)] = pixel;
        }

        self.image_index += 1;
    }

    fn putPixel(self: *Gpu, x: i32, y: i32, color: u16) void {
        if (x < 0 or y < 0) return;
        if (x > 1023 or y > 511) return;
        if (x < self.draw_area_left or y < self.draw_area_top) return;
        if (x > self.draw_area_right or y > self.draw_area_bottom) return;

        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);
        self.vram[@intCast(uy * 1024 + ux)] = color;
    }

    fn rgb24ToRgb555(value: u32) u16 {
        const r8: u16 = @intCast(value & 0xFF);
        const g8: u16 = @intCast((value >> 8) & 0xFF);
        const b8: u16 = @intCast((value >> 16) & 0xFF);
        const r5 = r8 >> 3;
        const g5 = g8 >> 3;
        const b5 = b8 >> 3;
        return r5 | (g5 << 5) | (b5 << 10);
    }

    fn vertexX(v: u32) i32 {
        const raw: u16 = @intCast(v & 0xFFFF);
        const signed: i16 = @bitCast(raw);
        return @as(i32, signed);
    }
    fn vertexY(v: u32) i32 {
        const raw: u16 = @intCast((v >> 16) & 0xFFFF);
        const signed: i16 = @bitCast(raw);
        return @as(i32, signed);
    }
    fn drawFilledQuadBBox(self: *Gpu) void {
        var min_x = vertexX(self.gp0_quad_vertices[0]) + self.draw_offset_x;
        var max_x = min_x;
        var min_y = vertexY(self.gp0_quad_vertices[0]) + self.draw_offset_y;
        var max_y = min_y;
        var i: usize = 1;

        while (i < 4) : (i += 1) {
            const x = vertexX(self.gp0_quad_vertices[i]) + self.draw_offset_x;
            const y = vertexY(self.gp0_quad_vertices[i]) + self.draw_offset_y;

            if (x < min_x) min_x = x;
            if (x > max_x) max_x = x;
            if (y < min_y) min_y = y;
            if (y > max_y) max_y = y;
        }
        if (max_x < 0 or max_y < 0 or min_x >= 1024 or min_y >= 512) return;

        if (min_x < 0) min_x = 0;
        if (min_y < 0) min_y = 0;
        if (max_x > 1023) max_x = 1023;
        if (max_y > 511) max_y = 511;

        if (min_x < self.draw_area_left) min_x = self.draw_area_left;
        if (min_y < self.draw_area_top) min_y = self.draw_area_top;
        if (max_x > self.draw_area_right) max_x = self.draw_area_right;
        if (max_y > self.draw_area_bottom) max_y = self.draw_area_bottom;

        if (max_x < min_x or max_y < min_y) return;

        var y: i32 = min_y;
        while (y <= max_y) : (y += 1) {
            var x: i32 = min_x;
            while (x <= max_x) : (x += 1) {
                const idx: usize = @intCast(@as(u32, @intCast(y)) * 1024 + @as(u32, @intCast(x)));
                self.vram[idx] = self.gp0_quad_color;
            }
        }
    }

    pub fn writeGp1(self: *Gpu, pc: u32, value: u32) void {
        self.gp1_last = value;
        _ = pc;
        const cmd: u8 = @intCast(value >> 24);
        const param: u32 = value & 0x00FF_FFFF;

        switch (cmd) {
            0x00 => {
                // Reset GPU.
                self.status = 0x1C00_0000;
                self.gp0_mode = 0;
                self.gp0_words_remaining = 0;
                self.dma_direction = 0;
                self.display_disabled = true;
            },

            0x01 => {
                // Reset command buffer.
                self.gp0_mode = 0;
                self.gp0_words_remaining = 0;
            },

            0x02 => {
                // Acknowledge GPU IRQ.
                self.status &= ~(@as(u32, 1) << 24);
            },

            0x03 => {
                self.display_disabled = (param & 1) != 0;
                //  std.debug.print("GP1 display enable disabled={}\n", .{self.display_disabled});
            },
            0x04 => {
                self.dma_direction = param & 0x3;
            },

            0x05 => {
                self.display_x = @intCast(param & 0x3FF);
                self.display_y = @intCast((param >> 10) & 0x1FF);

                //std.debug.print("GP1 display start x={} y={}\n", .{ self.display_x, self.display_y });
            },

            0x06 => {
                self.display_h_start = @intCast(param & 0xFFF);
                self.display_h_end = @intCast((param >> 12) & 0xFFF);

                //std.debug.print("GP1 display h range {}..{}\n", .{ self.display_h_start, self.display_h_end });
            },

            0x07 => {
                self.display_v_start = @intCast(param & 0x3FF);
                self.display_v_end = @intCast((param >> 10) & 0x3FF);

                //std.debug.print("GP1 display v range {}..{}\n", .{ self.display_v_start, self.display_v_end });
            },

            0x08 => {
                self.display_mode = param;

                //std.debug.print("GP1 display mode 0x{X:0>6}\n", .{self.display_mode});
            },
            0x10 => {
                self.gpu_info_response = switch (param & 0xF) {
                    0x2 => @as(u32, self.display_x) | (@as(u32, self.display_y) << 10),
                    0x3 => @as(u32, self.display_h_start) | (@as(u32, self.display_h_end) << 12),
                    0x4 => @as(u32, self.display_v_start) | (@as(u32, self.display_v_end) << 10),
                    0x5 => self.display_mode,
                    0x7 => 2,
                    else => 0,
                };
            },

            else => {
                //std.debug.print(
                //  "GP1 CMD PC=0x{X:0>8} cmd=0x{X:0>2} value=0x{X:0>8}\n",
                //.{ pc, cmd, value },
                //);
            },
        }

        self.status |= 0x1C00_0000;
    }
};
