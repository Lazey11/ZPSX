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
    texture_window: u32 = 0,
    mask_set_on_draw: bool = false,
    mask_check_before_draw: bool = false,
    gp0_draw_semi_transparent: bool = false,

    gp0_quad_active: bool = false,
    gp0_quad_color: u16 = 0,
    gp0_quad_vertices: [4]u32 = [_]u32{0} ** 4,
    gp0_quad_vertex_index: u8 = 0,

    gp0_shaded_tri_color: u16 = 0,
    gp0_shaded_tri_words: [5]u32 = [_]u32{0} ** 5,
    gp0_shaded_tri_index: u8 = 0,
    gp0_shaded_tri_active: bool = false,

    gp0_polyline_color: u16 = 0,
    gp0_polyline_last_xy: u32 = 0,
    gp0_polyline_have_last: bool = false,
    gp0_polyline_active: bool = false,

    gp0_shaded_line_color0: u16 = 0,
    gp0_shaded_line_words: [3]u32 = [_]u32{0} ** 3,
    gp0_shaded_line_index: u8 = 0,
    gp0_shaded_line_active: bool = false,

    gp0_tri_active: bool = false,
    gp0_tri_color: u16 = 0,
    gp0_tri_vertices: [3]u32 = [_]u32{0} ** 3,
    gp0_tri_vertex_index: u8 = 0,

    gp0_line_color: u16 = 0,
    gp0_line_words: [2]u32 = [_]u32{0} ** 2,
    gp0_line_index: u8 = 0,
    gp0_line_active: bool = false,

    gp0_shaded_polyline_last_xy: u32 = 0,
    gp0_shaded_polyline_last_color: u16 = 0,
    gp0_shaded_polyline_pending_color: u16 = 0,
    gp0_shaded_polyline_have_last: bool = false,
    gp0_shaded_polyline_need_xy: bool = true,
    gp0_shaded_polyline_active: bool = false,

    gp0_shaded_quad_color: u16 = 0,
    gp0_shaded_quad_words: [7]u32 = [_]u32{0} ** 7,
    gp0_shaded_quad_index: u8 = 0,
    gp0_shaded_quad_active: bool = false,

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

    gp0_textured_tri_active: bool = false,
    gp0_textured_tri_words: [6]u32 = [_]u32{0} ** 6,
    gp0_textured_tri_index: u8 = 0,

    gp0_shaded_textured_quad_color: u16 = 0,
    gp0_shaded_textured_quad_active: bool = false,
    gp0_shaded_textured_quad_words: [11]u32 = [_]u32{0} ** 11,
    gp0_shaded_textured_quad_index: u8 = 0,

    gp0_shaded_textured_tri_color: u16 = 0,
    gp0_shaded_textured_tri_active: bool = false,
    gp0_shaded_textured_tri_words: [8]u32 = [_]u32{0} ** 8,
    gp0_shaded_textured_tri_index: u8 = 0,

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

    gp0_textured_rect_color: u16 = 0x7FFF,
    gp0_textured_rect_raw_texture: bool = false,
    gp0_textured_rect_words: [3]u32 = [_]u32{0} ** 3,
    gp0_textured_rect_index: u8 = 0,
    gp0_textured_rect_active: bool = false,

    gp0_fixed_textured_rect_words: [2]u32 = [_]u32{0} ** 2,
    gp0_fixed_textured_rect_index: u8 = 0,
    gp0_fixed_textured_rect_w: u32 = 0,
    gp0_fixed_textured_rect_h: u32 = 0,
    gp0_fixed_textured_rect_raw_texture: bool = false,
    gp0_fixed_textured_rect_active: bool = false,

    gp0_vram_copy_words: [3]u32 = [_]u32{0} ** 3,
    gp0_vram_copy_index: u8 = 0,
    gp0_vram_copy_active: bool = false,

    draw_area_left: i32 = 0,
    draw_area_top: i32 = 0,
    draw_area_right: i32 = 1023,
    draw_area_bottom: i32 = 511,
    draw_offset_x: i32 = 0,
    draw_offset_y: i32 = 0,

    pub fn readStatus(self: *const Gpu) u32 {
        var value: u32 = self.status;

        if (self.display_disabled) {
            value |= @as(u32, 1) << 23;
        } else {
            value &= ~(@as(u32, 1) << 23);
        }

        value &= ~(@as(u32, 0x3) << 29);
        value |= (self.dma_direction & 0x3) << 29;

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

    fn textureWindowMaskX(texture_window: u32) u32 {
        return texture_window & 0x1F;
    }

    fn textureWindowMaskY(texture_window: u32) u32 {
        return (texture_window >> 5) & 0x1F;
    }

    fn textureWindowOffsetX(texture_window: u32) u32 {
        return (texture_window >> 10) & 0x1F;
    }

    fn textureWindowOffsetY(texture_window: u32) u32 {
        return (texture_window >> 15) & 0x1F;
    }

    fn applyTextureWindowCoord(coord: u32, mask: u32, offset: u32) u32 {
        const mask_pixels = mask * 8;
        const offset_pixels = offset * 8;
        return (coord & ~mask_pixels) | (offset_pixels & mask_pixels);
    }

    fn textureWindowU(self: *const Gpu, u: u32) u32 {
        return applyTextureWindowCoord(
            u,
            textureWindowMaskX(self.texture_window),
            textureWindowOffsetX(self.texture_window),
        );
    }

    fn textureWindowV(self: *const Gpu, v: u32) u32 {
        return applyTextureWindowCoord(
            v,
            textureWindowMaskY(self.texture_window),
            textureWindowOffsetY(self.texture_window),
        );
    }

    fn sampleTexture4BitClut(self: *const Gpu, tex_base_x: u32, tex_base_y: u32, clut_x: u32, clut_y: u32, u: u32, v: u32) u16 {
        const tex_x = tex_base_x + (u / 4);
        const tex_y = tex_base_y + v;
        if (tex_x >= 1024 or tex_y >= 512) return 0;
        if (clut_x >= 1024 or clut_y >= 512) return 0;

        const tex_word = self.vram[@intCast(tex_y * 1024 + tex_x)];
        const shift: u4 = @intCast((u & 3) * 4);
        const index: u32 = (tex_word >> shift) & 0xF;

        return self.vram[@intCast(clut_y * 1024 + clut_x + index)];
    }

    fn sampleTexture8BitClut(self: *const Gpu, tex_base_x: u32, tex_base_y: u32, clut_x: u32, clut_y: u32, u: u32, v: u32) u16 {
        const tex_x = tex_base_x + (u / 2);
        const tex_y = tex_base_y + v;
        if (tex_x >= 1024 or tex_y >= 512) return 0;
        if (clut_x >= 1024 or clut_y >= 512) return 0;

        const tex_word = self.vram[@intCast(tex_y * 1024 + tex_x)];
        const shift: u4 = if ((u & 1) == 0) 0 else 8;
        const index: u32 = (tex_word >> shift) & 0xFF;

        return self.vram[@intCast(clut_y * 1024 + clut_x + index)];
    }

    fn sampleTexture15Bit(self: *const Gpu, tex_base_x: u32, tex_base_y: u32, u: u32, v: u32) u16 {
        const tex_x = tex_base_x + u;
        const tex_y = tex_base_y + v;
        if (tex_x >= 1024 or tex_y >= 512) return 0;

        return self.vram[@intCast(tex_y * 1024 + tex_x)];
    }

    fn sampleTextureMode(
        self: *const Gpu,
        tex_mode: u32,
        tex_base_x: u32,
        tex_base_y: u32,
        clut_x: u32,
        clut_y: u32,
        u: u32,
        v: u32,
    ) u16 {
        const window_u = self.textureWindowU(u);
        const window_v = self.textureWindowV(v);
        return switch (tex_mode) {
            0 => self.sampleTexture4BitClut(tex_base_x, tex_base_y, clut_x, clut_y, window_u, window_v),
            1 => self.sampleTexture8BitClut(tex_base_x, tex_base_y, clut_x, clut_y, window_u, window_v),
            2 => self.sampleTexture15Bit(tex_base_x, tex_base_y, window_u, window_v),
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
        const uv3_word = self.gp0_textured_quad_words[7];

        const x0 = xyX(xy0_word) + self.draw_offset_x;
        const y0 = xyY(xy0_word) + self.draw_offset_y;
        const x1 = xyX(xy1_word) + self.draw_offset_x;
        const y1 = xyY(xy1_word) + self.draw_offset_y;
        const x2 = xyX(xy2_word) + self.draw_offset_x;
        const y2 = xyY(xy2_word) + self.draw_offset_y;
        const x3 = xyX(xy3_word) + self.draw_offset_x;
        const y3 = xyY(xy3_word) + self.draw_offset_y;

        self.drawTexturedTriangle(x0, y0, uv0_word, x1, y1, uv1_word, x2, y2, uv2_word);
        self.drawTexturedTriangle(x1, y1, uv1_word, x2, y2, uv2_word, x3, y3, uv3_word);
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

    fn drawTexturedRect(self: *Gpu, x: i32, y: i32, uv_word: u32, w: u32, h: u32, raw_texture: bool) void {
        const tex_u0 = uvU(uv_word);
        const tex_v0 = uvV(uv_word);
        const clx = clutX(uv_word);
        const cly = clutY(uv_word);

        const tex_base_x = texturePageBaseX(self.draw_mode);
        const tex_base_y = texturePageBaseY(self.draw_mode);
        const tex_mode = textureMode(self.draw_mode);

        var yy: u32 = 0;
        while (yy < h) : (yy += 1) {
            var xx: u32 = 0;
            while (xx < w) : (xx += 1) {
                const px = self.sampleTextureMode(
                    tex_mode,
                    tex_base_x,
                    tex_base_y,
                    clx,
                    cly,
                    tex_u0 + xx,
                    tex_v0 + yy,
                );
                if (px == 0) continue;

                const out = if (raw_texture) px else modulateRgb555(px, self.gp0_textured_rect_color);

                self.putPixel(
                    x + @as(i32, @intCast(xx)),
                    y + @as(i32, @intCast(yy)),
                    out,
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

        if (self.gp0_vram_copy_active) {
            self.gp0_vram_copy_words[self.gp0_vram_copy_index] = value;
            self.gp0_vram_copy_index += 1;

            if (self.gp0_vram_copy_index == 3) {
                self.copyVramRect(
                    self.gp0_vram_copy_words[0],
                    self.gp0_vram_copy_words[1],
                    self.gp0_vram_copy_words[2],
                );

                self.gp0_vram_copy_active = false;
                self.gp0_vram_copy_index = 0;
            }

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

                self.drawTexturedRect(x, y, uv, w, h, self.gp0_textured_rect_raw_texture);
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

                self.drawTexturedRect(
                    x,
                    y,
                    uv,
                    self.gp0_fixed_textured_rect_w,
                    self.gp0_fixed_textured_rect_h,
                    self.gp0_fixed_textured_rect_raw_texture,
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

        if (self.gp0_shaded_textured_quad_active) {
            self.gp0_shaded_textured_quad_words[self.gp0_shaded_textured_quad_index] = value;
            self.gp0_shaded_textured_quad_index += 1;

            if (self.gp0_shaded_textured_quad_index == 11) {
                const xy0 = self.gp0_shaded_textured_quad_words[0];
                const uv0 = self.gp0_shaded_textured_quad_words[1];
                const c1_word = self.gp0_shaded_textured_quad_words[2];
                const xy1 = self.gp0_shaded_textured_quad_words[3];
                const uv1 = self.gp0_shaded_textured_quad_words[4];
                const c2_word = self.gp0_shaded_textured_quad_words[5];
                const xy2 = self.gp0_shaded_textured_quad_words[6];
                const uv2 = self.gp0_shaded_textured_quad_words[7];
                const c3_word = self.gp0_shaded_textured_quad_words[8];
                const xy3 = self.gp0_shaded_textured_quad_words[9];
                const uv3 = self.gp0_shaded_textured_quad_words[10];

                const x0 = xyX(xy0) + self.draw_offset_x;
                const y0 = xyY(xy0) + self.draw_offset_y;
                const x1 = xyX(xy1) + self.draw_offset_x;
                const y1 = xyY(xy1) + self.draw_offset_y;
                const x2 = xyX(xy2) + self.draw_offset_x;
                const y2 = xyY(xy2) + self.draw_offset_y;
                const x3 = xyX(xy3) + self.draw_offset_x;
                const y3 = xyY(xy3) + self.draw_offset_y;

                const c0 = self.gp0_shaded_textured_quad_color;
                const c1 = rgb24ToRgb555(c1_word);
                const c2 = rgb24ToRgb555(c2_word);
                const c3 = rgb24ToRgb555(c3_word);
                const tpage = (uv1 >> 16) & 0xFFFF;

                self.drawShadedTexturedTriangleWithTpage(
                    x0,
                    y0,
                    uv0,
                    c0,
                    x1,
                    y1,
                    uv1,
                    c1,
                    x2,
                    y2,
                    uv2,
                    c2,
                    tpage,
                );
                self.drawShadedTexturedTriangleWithTpage(
                    x1,
                    y1,
                    uv1,
                    c1,
                    x2,
                    y2,
                    uv2,
                    c2,
                    x3,
                    y3,
                    uv3,
                    c3,
                    tpage,
                );
                self.gp0_shaded_textured_quad_active = false;
                self.gp0_shaded_textured_quad_index = 0;
            }

            return;
        }

        if (self.gp0_shaded_textured_tri_active) {
            self.gp0_shaded_textured_tri_words[self.gp0_shaded_textured_tri_index] = value;
            self.gp0_shaded_textured_tri_index += 1;

            if (self.gp0_shaded_textured_tri_index == 8) {
                const xy0 = self.gp0_shaded_textured_tri_words[0];
                const uv0 = self.gp0_shaded_textured_tri_words[1];
                const xy1 = self.gp0_shaded_textured_tri_words[3];
                const uv1 = self.gp0_shaded_textured_tri_words[4];
                const xy2 = self.gp0_shaded_textured_tri_words[6];
                const uv2 = self.gp0_shaded_textured_tri_words[7];

                const x0 = xyX(xy0) + self.draw_offset_x;
                const y0 = xyY(xy0) + self.draw_offset_y;
                const x1 = xyX(xy1) + self.draw_offset_x;
                const y1 = xyY(xy1) + self.draw_offset_y;
                const x2 = xyX(xy2) + self.draw_offset_x;
                const y2 = xyY(xy2) + self.draw_offset_y;

                const c0 = self.gp0_shaded_textured_tri_color;
                const c1 = rgb24ToRgb555(self.gp0_shaded_textured_tri_words[2]);
                const c2 = rgb24ToRgb555(self.gp0_shaded_textured_tri_words[5]);
                const tpage = (uv1 >> 16) & 0xFFFF;

                self.drawShadedTexturedTriangleWithTpage(
                    x0,
                    y0,
                    uv0,
                    c0,
                    x1,
                    y1,
                    uv1,
                    c1,
                    x2,
                    y2,
                    uv2,
                    c2,
                    tpage,
                );
                self.gp0_shaded_textured_tri_active = false;
                self.gp0_shaded_textured_tri_index = 0;
            }

            return;
        }

        if (self.gp0_textured_tri_active) {
            self.gp0_textured_tri_words[self.gp0_textured_tri_index] = value;
            self.gp0_textured_tri_index += 1;

            if (self.gp0_textured_tri_index == 6) {
                const xy0 = self.gp0_textured_tri_words[0];
                const uv0 = self.gp0_textured_tri_words[1];
                const xy1 = self.gp0_textured_tri_words[2];
                const uv1 = self.gp0_textured_tri_words[3];
                const xy2 = self.gp0_textured_tri_words[4];
                const uv2 = self.gp0_textured_tri_words[5];

                const x0 = xyX(xy0) + self.draw_offset_x;
                const y0 = xyY(xy0) + self.draw_offset_y;
                const x1 = xyX(xy1) + self.draw_offset_x;
                const y1 = xyY(xy1) + self.draw_offset_y;
                const x2 = xyX(xy2) + self.draw_offset_x;
                const y2 = xyY(xy2) + self.draw_offset_y;

                self.drawTexturedTriangle(x0, y0, uv0, x1, y1, uv1, x2, y2, uv2);

                self.gp0_textured_tri_active = false;
                self.gp0_textured_tri_index = 0;
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

        if (self.gp0_shaded_tri_active) {
            self.gp0_shaded_tri_words[self.gp0_shaded_tri_index] = value;
            self.gp0_shaded_tri_index += 1;

            if (self.gp0_shaded_tri_index == 5) {
                const xy0 = self.gp0_shaded_tri_words[0];
                const xy1 = self.gp0_shaded_tri_words[2];
                const xy2 = self.gp0_shaded_tri_words[4];

                const x0 = xyX(xy0) + self.draw_offset_x;
                const y0 = xyY(xy0) + self.draw_offset_y;
                const x1 = xyX(xy1) + self.draw_offset_x;
                const y1 = xyY(xy1) + self.draw_offset_y;
                const x2 = xyX(xy2) + self.draw_offset_x;
                const y2 = xyY(xy2) + self.draw_offset_y;

                const c0 = self.gp0_shaded_tri_color;
                const c1 = rgb24ToRgb555(self.gp0_shaded_tri_words[1]);
                const c2 = rgb24ToRgb555(self.gp0_shaded_tri_words[3]);

                self.drawGouraudTriangle(x0, y0, c0, x1, y1, c1, x2, y2, c2);
                self.gp0_shaded_tri_active = false;
                self.gp0_shaded_tri_index = 0;
            }

            return;
        }

        if (self.gp0_tri_active) {
            self.gp0_tri_vertices[self.gp0_tri_vertex_index] = value;
            self.gp0_tri_vertex_index += 1;

            if (self.gp0_tri_vertex_index == 3) {
                const x0 = vertexX(self.gp0_tri_vertices[0]) + self.draw_offset_x;
                const y0 = vertexY(self.gp0_tri_vertices[0]) + self.draw_offset_y;
                const x1 = vertexX(self.gp0_tri_vertices[1]) + self.draw_offset_x;
                const y1 = vertexY(self.gp0_tri_vertices[1]) + self.draw_offset_y;
                const x2 = vertexX(self.gp0_tri_vertices[2]) + self.draw_offset_x;
                const y2 = vertexY(self.gp0_tri_vertices[2]) + self.draw_offset_y;

                self.drawFilledTriangle(x0, y0, x1, y1, x2, y2, self.gp0_tri_color);

                self.gp0_tri_active = false;
                self.gp0_tri_vertex_index = 0;
            }

            return;
        }

        if (self.gp0_shaded_quad_active) {
            self.gp0_shaded_quad_words[self.gp0_shaded_quad_index] = value;
            self.gp0_shaded_quad_index += 1;

            if (self.gp0_shaded_quad_index == 7) {
                const xy0 = self.gp0_shaded_quad_words[0];
                const xy1 = self.gp0_shaded_quad_words[2];
                const xy2 = self.gp0_shaded_quad_words[4];
                const xy3 = self.gp0_shaded_quad_words[6];

                const x0 = xyX(xy0) + self.draw_offset_x;
                const y0 = xyY(xy0) + self.draw_offset_y;
                const x1 = xyX(xy1) + self.draw_offset_x;
                const y1 = xyY(xy1) + self.draw_offset_y;
                const x2 = xyX(xy2) + self.draw_offset_x;
                const y2 = xyY(xy2) + self.draw_offset_y;
                const x3 = xyX(xy3) + self.draw_offset_x;
                const y3 = xyY(xy3) + self.draw_offset_y;

                const c0 = self.gp0_shaded_quad_color;
                const c1 = rgb24ToRgb555(self.gp0_shaded_quad_words[1]);
                const c2 = rgb24ToRgb555(self.gp0_shaded_quad_words[3]);
                const c3 = rgb24ToRgb555(self.gp0_shaded_quad_words[5]);

                self.drawGouraudTriangle(x0, y0, c0, x1, y1, c1, x2, y2, c2);
                self.drawGouraudTriangle(x1, y1, c1, x2, y2, c2, x3, y3, c3);

                self.gp0_shaded_quad_active = false;
                self.gp0_shaded_quad_index = 0;
            }

            return;
        }

        if (self.gp0_line_active) {
            self.gp0_line_words[self.gp0_line_index] = value;
            self.gp0_line_index += 1;

            if (self.gp0_line_index == 2) {
                const xy0 = self.gp0_line_words[0];
                const xy1 = self.gp0_line_words[1];

                const x0 = xyX(xy0) + self.draw_offset_x;
                const y0 = xyY(xy0) + self.draw_offset_y;
                const x1 = xyX(xy1) + self.draw_offset_x;
                const y1 = xyY(xy1) + self.draw_offset_y;

                self.drawLine(x0, y0, x1, y1, self.gp0_line_color);

                self.gp0_line_active = false;
                self.gp0_line_index = 0;
            }

            return;
        }

        if (self.gp0_polyline_active) {
            if (value == 0x5555_5555 or value == 0x5000_5000) {
                self.gp0_polyline_active = false;
                self.gp0_polyline_have_last = false;
                return;
            }

            if (!self.gp0_polyline_have_last) {
                self.gp0_polyline_last_xy = value;
                self.gp0_polyline_have_last = true;
                return;
            }

            const xy0 = self.gp0_polyline_last_xy;
            const xy1 = value;

            const x0 = xyX(xy0) + self.draw_offset_x;
            const y0 = xyY(xy0) + self.draw_offset_y;
            const x1 = xyX(xy1) + self.draw_offset_x;
            const y1 = xyY(xy1) + self.draw_offset_y;

            self.drawLine(x0, y0, x1, y1, self.gp0_polyline_color);
            self.gp0_polyline_last_xy = value;
            return;
        }

        if (self.gp0_shaded_line_active) {
            self.gp0_shaded_line_words[self.gp0_shaded_line_index] = value;
            self.gp0_shaded_line_index += 1;

            if (self.gp0_shaded_line_index == 3) {
                const xy0 = self.gp0_shaded_line_words[0];
                const color1_word = self.gp0_shaded_line_words[1];
                const xy1 = self.gp0_shaded_line_words[2];

                const x0 = xyX(xy0) + self.draw_offset_x;
                const y0 = xyY(xy0) + self.draw_offset_y;
                const x1 = xyX(xy1) + self.draw_offset_x;
                const y1 = xyY(xy1) + self.draw_offset_y;
                const c1 = rgb24ToRgb555(color1_word);

                self.drawShadedLine(x0, y0, self.gp0_shaded_line_color0, x1, y1, c1);

                self.gp0_shaded_line_active = false;
                self.gp0_shaded_line_index = 0;
            }

            return;
        }

        if (self.gp0_shaded_polyline_active) {
            if (value == 0x5555_5555 or value == 0x5000_5000) {
                self.gp0_shaded_polyline_active = false;
                self.gp0_shaded_polyline_have_last = false;
                self.gp0_shaded_polyline_need_xy = true;
                return;
            }

            if (self.gp0_shaded_polyline_need_xy) {
                if (!self.gp0_shaded_polyline_have_last) {
                    self.gp0_shaded_polyline_last_xy = value;
                    self.gp0_shaded_polyline_last_color = self.gp0_shaded_polyline_pending_color;
                    self.gp0_shaded_polyline_have_last = true;
                } else {
                    const xy0 = self.gp0_shaded_polyline_last_xy;
                    const xy1 = value;

                    const x0 = xyX(xy0) + self.draw_offset_x;
                    const y0 = xyY(xy0) + self.draw_offset_y;
                    const x1 = xyX(xy1) + self.draw_offset_x;
                    const y1 = xyY(xy1) + self.draw_offset_y;

                    self.drawShadedLine(
                        x0,
                        y0,
                        self.gp0_shaded_polyline_last_color,
                        x1,
                        y1,
                        self.gp0_shaded_polyline_pending_color,
                    );

                    self.gp0_shaded_polyline_last_xy = value;
                    self.gp0_shaded_polyline_last_color = self.gp0_shaded_polyline_pending_color;
                }

                self.gp0_shaded_polyline_need_xy = false;
                return;
            }

            self.gp0_shaded_polyline_pending_color = rgb24ToRgb555(value);
            self.gp0_shaded_polyline_need_xy = true;
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
                return;
            },

            else => {},
        }

        switch (cmd) {
            0x00 => {},
            0x01 => {},
            0x03 => {},
            0x02 => {
                self.gp0_draw_semi_transparent = false;
                self.gp0_vram_fill_color = rgb24ToRgb555(value);
                self.gp0_vram_fill_active = true;
                self.gp0_vram_fill_index = 0;
            },
            0x20, 0x22 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_tri_color = rgb24ToRgb555(value);
                self.gp0_tri_active = true;
                self.gp0_tri_vertex_index = 0;
            },
            0x28, 0x2A => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_quad_color = rgb24ToRgb555(value);
                self.gp0_quad_active = true;
                self.gp0_quad_vertex_index = 0;
            },
            0x30, 0x32 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_shaded_tri_color = rgb24ToRgb555(value);
                self.gp0_shaded_tri_active = true;
                self.gp0_shaded_tri_index = 0;
            },
            0x38, 0x3A => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_shaded_quad_color = rgb24ToRgb555(value);
                self.gp0_shaded_quad_active = true;
                self.gp0_shaded_quad_index = 0;
            },
            0x40, 0x42 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_line_color = rgb24ToRgb555(value);
                self.gp0_line_active = true;
                self.gp0_line_index = 0;
            },
            0x48, 0x4A => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_polyline_color = rgb24ToRgb555(value);
                self.gp0_polyline_active = true;
                self.gp0_polyline_have_last = false;
            },
            0x50, 0x52 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_shaded_line_color0 = rgb24ToRgb555(value);
                self.gp0_shaded_line_active = true;
                self.gp0_shaded_line_index = 0;
            },
            0x58, 0x5A => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_shaded_polyline_pending_color = rgb24ToRgb555(value);
                self.gp0_shaded_polyline_active = true;
                self.gp0_shaded_polyline_have_last = false;
                self.gp0_shaded_polyline_need_xy = true;
            },
            0x34, 0x36 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_shaded_textured_tri_color = rgb24ToRgb555(value);
                self.gp0_shaded_textured_tri_active = true;
                self.gp0_shaded_textured_tri_index = 0;
                return;
            },
            0x3C, 0x3E => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_shaded_textured_quad_color = rgb24ToRgb555(value);
                self.gp0_shaded_textured_quad_active = true;
                self.gp0_shaded_textured_quad_index = 0;
                return;
            },
            0x2C, 0x2D, 0x2E, 0x2F => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_textured_quad_color = value;
                self.gp0_textured_quad_active = true;
                self.gp0_textured_quad_index = 0;
                return;
            },
            0x24, 0x25, 0x26, 0x27 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_textured_tri_active = true;
                self.gp0_textured_tri_index = 0;
                return;
            },
            0x60, 0x62, 0x6A => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_sprite_color = rgb24ToRgb555(value);
                self.gp0_sprite_active = true;
                self.gp0_sprite_index = 0;
            },
            0x64, 0x65, 0x66, 0x67 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_textured_rect_color = rgb24ToRgb555(value);
                self.gp0_textured_rect_raw_texture = gp0CommandRawTexture(cmd);
                self.gp0_textured_rect_active = true;
                self.gp0_textured_rect_index = 0;
            },
            0x68 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_dot_color = rgb24ToRgb555(value);
                self.gp0_dot_active = true;
            },
            0x70, 0x72 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_fixed_rect_color = rgb24ToRgb555(value);
                self.gp0_fixed_rect_w = 8;
                self.gp0_fixed_rect_h = 8;
                self.gp0_fixed_rect_active = true;
            },
            0x74, 0x75, 0x76, 0x77 => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_textured_rect_color = rgb24ToRgb555(value);
                self.gp0_fixed_textured_rect_raw_texture = gp0CommandRawTexture(cmd);
                self.gp0_fixed_textured_rect_w = 8;
                self.gp0_fixed_textured_rect_h = 8;
                self.gp0_fixed_textured_rect_active = true;
                self.gp0_fixed_textured_rect_index = 0;
            },
            0x78, 0x7A => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_fixed_rect_color = rgb24ToRgb555(value);
                self.gp0_fixed_rect_w = 16;
                self.gp0_fixed_rect_h = 16;
                self.gp0_fixed_rect_active = true;
            },
            0x80 => {
                self.gp0_draw_semi_transparent = false;
                self.gp0_vram_copy_active = true;
                self.gp0_vram_copy_index = 0;
            },
            0x7C, 0x7D, 0x7E, 0x7F => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_textured_rect_color = rgb24ToRgb555(value);
                self.gp0_fixed_textured_rect_raw_texture = gp0CommandRawTexture(cmd);
                self.gp0_fixed_textured_rect_w = 16;
                self.gp0_fixed_textured_rect_h = 16;
                self.gp0_fixed_textured_rect_active = true;
                self.gp0_fixed_textured_rect_index = 0;
            },
            0x6C, 0x6D, 0x6E, 0x6F => {
                self.gp0_draw_semi_transparent = gp0CommandSemiTransparent(cmd);
                self.gp0_textured_rect_color = rgb24ToRgb555(value);
                self.gp0_fixed_textured_rect_raw_texture = gp0CommandRawTexture(cmd);
                self.gp0_fixed_textured_rect_w = 1;
                self.gp0_fixed_textured_rect_h = 1;
                self.gp0_fixed_textured_rect_active = true;
                self.gp0_fixed_textured_rect_index = 0;
            },
            0xE1 => {
                self.gp0_draw_semi_transparent = false;
                self.draw_mode = value & 0x00FF_FFFF;
            },
            0xE2 => {
                self.texture_window = value & 0x00FF_FFFF;
            },
            0xE3 => {
                const p = value & 0x00FF_FFFF;
                self.draw_area_left = @intCast(p & 0x3FF);
                self.draw_area_top = @intCast((p >> 10) & 0x1FF);
            },
            0xE4 => {
                const p = value & 0x00FF_FFFF;
                self.draw_area_right = @intCast(p & 0x3FF);
                self.draw_area_bottom = @intCast((p >> 10) & 0x1FF);
            },
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
            },
            0xE6 => {
                self.gp0_draw_semi_transparent = false;
                self.mask_set_on_draw = (value & 1) != 0;
                self.mask_check_before_draw = (value & 2) != 0;
            },
            0xA0 => {
                self.gp0_draw_semi_transparent = false;
                self.gp0_mode = 1;
            },
            0xC0 => {
                self.gp0_draw_semi_transparent = false;
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

    fn copyVramRect(self: *Gpu, src_word: u32, dst_word: u32, size_word: u32) void {
        const src_x: u32 = @intCast(src_word & 0xFFFF);
        const src_y: u32 = @intCast((src_word >> 16) & 0xFFFF);
        const dst_x: u32 = @intCast(dst_word & 0xFFFF);
        const dst_y: u32 = @intCast((dst_word >> 16) & 0xFFFF);

        var w: u32 = @intCast(size_word & 0xFFFF);
        var h: u32 = @intCast((size_word >> 16) & 0xFFFF);

        if (w == 0) w = 1024;
        if (h == 0) h = 512;

        var yy: u32 = 0;
        while (yy < h) : (yy += 1) {
            var xx: u32 = 0;
            while (xx < w) : (xx += 1) {
                const sx = src_x + xx;
                const sy = src_y + yy;
                const dx = dst_x + xx;
                const dy = dst_y + yy;

                if (sx >= 1024 or sy >= 512) continue;
                if (dx >= 1024 or dy >= 512) continue;

                const px = self.vram[@intCast(sy * 1024 + sx)];
                self.vram[@intCast(dy * 1024 + dx)] = px;
            }
        }
    }

    fn putPixel(self: *Gpu, x: i32, y: i32, color: u16) void {
        if (x < 0 or y < 0) return;
        if (x > 1023 or y > 511) return;
        if (x < self.draw_area_left or y < self.draw_area_top) return;
        if (x > self.draw_area_right or y > self.draw_area_bottom) return;

        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);

        const index: usize = @intCast(uy * 1024 + ux);

        if (self.mask_check_before_draw and (self.vram[index] & 0x8000) != 0) {
            return;
        }

        var out_color = color & 0x7FFF;

        if (self.gp0_draw_semi_transparent) {
            const dst = self.vram[index] & 0x7FFF;
            out_color = blendSemiTransparent(out_color, dst, semiTransparencyMode(self.draw_mode));
        }

        if (self.mask_set_on_draw) {
            out_color |= 0x8000;
        }

        self.vram[index] = out_color;
    }

    fn drawLine(self: *Gpu, x0_in: i32, y0_in: i32, x1_in: i32, y1_in: i32, color: u16) void {
        var x0 = x0_in;
        var y0 = y0_in;
        const x1 = x1_in;
        const y1 = y1_in;

        const dx = if (x0 < x1) x1 - x0 else x0 - x1;
        const sx: i32 = if (x0 < x1) 1 else -1;
        const dy = -if (y0 < y1) y1 - y0 else y0 - y1;
        const sy: i32 = if (y0 < y1) 1 else -1;

        var err = dx + dy;

        while (true) {
            self.putPixel(x0, y0, color);

            if (x0 == x1 and y0 == y1) break;

            const e2 = err * 2;
            if (e2 >= dy) {
                err += dy;
                x0 += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    fn mixLineColor(c0: u16, c1: u16, step: u32, steps: u32) u16 {
        if (steps == 0) return c0;

        const inv = steps - step;

        const r = (rgb555R(c0) * inv + rgb555R(c1) * step) / steps;
        const g = (rgb555G(c0) * inv + rgb555G(c1) * step) / steps;
        const b = (rgb555B(c0) * inv + rgb555B(c1) * step) / steps;

        return @intCast(r | (g << 5) | (b << 10));
    }

    fn drawShadedLine(self: *Gpu, x0_in: i32, y0_in: i32, c0: u16, x1_in: i32, y1_in: i32, c1: u16) void {
        var x0 = x0_in;
        var y0 = y0_in;
        const x1 = x1_in;
        const y1 = y1_in;

        const dx_abs: u32 = @intCast(if (x0 < x1) x1 - x0 else x0 - x1);
        const dy_abs: u32 = @intCast(if (y0 < y1) y1 - y0 else y0 - y1);
        const steps = if (dx_abs > dy_abs) dx_abs else dy_abs;

        const dx = if (x0 < x1) x1 - x0 else x0 - x1;
        const sx: i32 = if (x0 < x1) 1 else -1;
        const dy = -if (y0 < y1) y1 - y0 else y0 - y1;
        const sy: i32 = if (y0 < y1) 1 else -1;

        var err = dx + dy;
        var step: u32 = 0;

        while (true) {
            self.putPixel(x0, y0, mixLineColor(c0, c1, step, steps));

            if (x0 == x1 and y0 == y1) break;

            const e2 = err * 2;
            if (e2 >= dy) {
                err += dy;
                x0 += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y0 += sy;
            }

            if (step < steps) step += 1;
        }
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

    fn edgeFunction(ax: i32, ay: i32, bx: i32, by: i32, px: i32, py: i32) i64 {
        return @as(i64, bx - ax) * @as(i64, py - ay) -
            @as(i64, by - ay) * @as(i64, px - ax);
    }

    fn edgeFunction2(ax: i32, ay: i32, bx: i32, by: i32, px2: i32, py2: i32) i64 {
        return @as(i64, bx - ax) * @as(i64, py2 - ay * 2) -
            @as(i64, by - ay) * @as(i64, px2 - ax * 2);
    }

    fn isTopLeftEdge(ax: i32, ay: i32, bx: i32, by: i32) bool {
        const dy = by - ay;
        const dx = bx - ax;
        return dy < 0 or (dy == 0 and dx > 0);
    }

    fn edgeInside(value: i64, top_left: bool) bool {
        return value > 0 or (value == 0 and top_left);
    }

    const TriangleBounds = struct {
        min_x: i32,
        max_x: i32,
        min_y: i32,
        max_y: i32,
    };

    const TriangleEdges = struct {
        flip: bool,
        area2_abs: u64,
        e0_tl: bool,
        e1_tl: bool,
        e2_tl: bool,
    };

    const TriangleWeights = struct {
        w0: u64,
        w1: u64,
        w2: u64,
    };

    fn triangleWeights(
        x0: i32,
        y0: i32,
        x1: i32,
        y1: i32,
        x2: i32,
        y2: i32,
        px2: i32,
        py2: i32,
        edges: TriangleEdges,
    ) ?TriangleWeights {
        var ew0 = edgeFunction2(x1, y1, x2, y2, px2, py2);
        var ew1 = edgeFunction2(x2, y2, x0, y0, px2, py2);
        var ew2 = edgeFunction2(x0, y0, x1, y1, px2, py2);

        if (edges.flip) {
            ew0 = -ew0;
            ew1 = -ew1;
            ew2 = -ew2;
        }

        if (!edgeInside(ew0, edges.e0_tl)) return null;
        if (!edgeInside(ew1, edges.e1_tl)) return null;
        if (!edgeInside(ew2, edges.e2_tl)) return null;

        return .{
            .w0 = @intCast(ew0),
            .w1 = @intCast(ew1),
            .w2 = @intCast(ew2),
        };
    }

    fn triangleEdges(x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32) ?TriangleEdges {
        const area = edgeFunction(x0, y0, x1, y1, x2, y2);
        if (area == 0) return null;

        const area_abs: u64 = @intCast(if (area > 0) area else -area);

        return .{
            .flip = area < 0,
            .area2_abs = area_abs * 2,
            .e0_tl = isTopLeftEdge(x1, y1, x2, y2),
            .e1_tl = isTopLeftEdge(x2, y2, x0, y0),
            .e2_tl = isTopLeftEdge(x0, y0, x1, y1),
        };
    }

    fn clippedTriangleBounds(
        self: *const Gpu,
        x0: i32,
        y0: i32,
        x1: i32,
        y1: i32,
        x2: i32,
        y2: i32,
    ) ?TriangleBounds {
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

        if (max_x < 0 or max_y < 0 or min_x >= 1024 or min_y >= 512) return null;

        if (min_x < 0) min_x = 0;
        if (min_y < 0) min_y = 0;
        if (max_x > 1023) max_x = 1023;
        if (max_y > 511) max_y = 511;

        if (min_x < self.draw_area_left) min_x = self.draw_area_left;
        if (min_y < self.draw_area_top) min_y = self.draw_area_top;
        if (max_x > self.draw_area_right) max_x = self.draw_area_right;
        if (max_y > self.draw_area_bottom) max_y = self.draw_area_bottom;

        if (max_x < min_x or max_y < min_y) return null;

        return .{
            .min_x = min_x,
            .max_x = max_x,
            .min_y = min_y,
            .max_y = max_y,
        };
    }

    fn drawFilledTriangle(self: *Gpu, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: u16) void {
        const bounds = self.clippedTriangleBounds(x0, y0, x1, y1, x2, y2) orelse return;
        const edges = triangleEdges(x0, y0, x1, y1, x2, y2) orelse return;

        var y: i32 = bounds.min_y;
        while (y <= bounds.max_y) : (y += 1) {
            var x: i32 = bounds.min_x;
            while (x <= bounds.max_x) : (x += 1) {
                const px2 = x * 2 + 1;
                const py2 = y * 2 + 1;

                if (triangleWeights(x0, y0, x1, y1, x2, y2, px2, py2, edges) == null) continue;
                self.putPixel(x, y, color);
            }
        }
    }

    fn rgb555R(color: u16) u32 {
        return color & 0x1F;
    }

    fn rgb555G(color: u16) u32 {
        return (color >> 5) & 0x1F;
    }

    fn rgb555B(color: u16) u32 {
        return (color >> 10) & 0x1F;
    }

    fn gp0CommandRawTexture(cmd: u8) bool {
        return (cmd & 0x01) != 0;
    }

    fn modulateRgb555(tex: u16, color: u16) u16 {
        const r = (rgb555R(tex) * rgb555R(color)) / 31;
        const g = (rgb555G(tex) * rgb555G(color)) / 31;
        const b = (rgb555B(tex) * rgb555B(color)) / 31;

        return @intCast(r | (g << 5) | (b << 10));
    }

    fn clamp5Signed(value: i32) u32 {
        if (value < 0) return 0;
        if (value > 31) return 31;
        return @intCast(value);
    }

    fn semiTransparencyMode(draw_mode: u32) u32 {
        return (draw_mode >> 5) & 0x3;
    }

    fn blendSemiTransparent(src: u16, dst: u16, mode: u32) u16 {
        const sr: i32 = @intCast(rgb555R(src));
        const sg: i32 = @intCast(rgb555G(src));
        const sb: i32 = @intCast(rgb555B(src));

        const dr: i32 = @intCast(rgb555R(dst));
        const dg: i32 = @intCast(rgb555G(dst));
        const db: i32 = @intCast(rgb555B(dst));

        const r: u32 = switch (mode) {
            0 => clamp5Signed(@divTrunc(dr + sr, 2)),
            1 => clamp5Signed(dr + sr),
            2 => clamp5Signed(dr - sr),
            3 => clamp5Signed(dr + @divTrunc(sr, 4)),
            else => clamp5Signed(sr),
        };

        const g: u32 = switch (mode) {
            0 => clamp5Signed(@divTrunc(dg + sg, 2)),
            1 => clamp5Signed(dg + sg),
            2 => clamp5Signed(dg - sg),
            3 => clamp5Signed(dg + @divTrunc(sg, 4)),
            else => clamp5Signed(sg),
        };

        const b: u32 = switch (mode) {
            0 => clamp5Signed(@divTrunc(db + sb, 2)),
            1 => clamp5Signed(db + sb),
            2 => clamp5Signed(db - sb),
            3 => clamp5Signed(db + @divTrunc(sb, 4)),
            else => clamp5Signed(sb),
        };

        return @intCast(r | (g << 5) | (b << 10));
    }

    fn gp0CommandSemiTransparent(cmd: u8) bool {
        return (cmd & 0x02) != 0;
    }

    fn mixRgb555(c0: u16, c1: u16, c2: u16, w0: u64, w1: u64, w2: u64, area: u64) u16 {
        const r = (rgb555R(c0) * w0 + rgb555R(c1) * w1 + rgb555R(c2) * w2) / area;
        const g = (rgb555G(c0) * w0 + rgb555G(c1) * w1 + rgb555G(c2) * w2) / area;
        const b = (rgb555B(c0) * w0 + rgb555B(c1) * w1 + rgb555B(c2) * w2) / area;

        return @intCast(r | (g << 5) | (b << 10));
    }

    fn drawGouraudTriangle(
        self: *Gpu,
        x0: i32,
        y0: i32,
        c0: u16,
        x1: i32,
        y1: i32,
        c1: u16,
        x2: i32,
        y2: i32,
        c2: u16,
    ) void {
        const bounds = self.clippedTriangleBounds(x0, y0, x1, y1, x2, y2) orelse return;
        const edges = triangleEdges(x0, y0, x1, y1, x2, y2) orelse return;

        var y: i32 = bounds.min_y;
        while (y <= bounds.max_y) : (y += 1) {
            var x: i32 = bounds.min_x;
            while (x <= bounds.max_x) : (x += 1) {
                const px2 = x * 2 + 1;
                const py2 = y * 2 + 1;

                const weights = triangleWeights(x0, y0, x1, y1, x2, y2, px2, py2, edges) orelse continue;

                self.putPixel(
                    x,
                    y,
                    mixRgb555(c0, c1, c2, weights.w0, weights.w1, weights.w2, edges.area2_abs),
                );
            }
        }
    }

    fn drawTexturedTriangleWithTpage(
        self: *Gpu,
        x0: i32,
        y0: i32,
        uv0_word: u32,
        x1: i32,
        y1: i32,
        uv1_word: u32,
        x2: i32,
        y2: i32,
        uv2_word: u32,
        tpage: u32,
    ) void {
        const bounds = self.clippedTriangleBounds(x0, y0, x1, y1, x2, y2) orelse return;
        const edges = triangleEdges(x0, y0, x1, y1, x2, y2) orelse return;

        const tex_u0 = uvU(uv0_word);
        const tex_v0 = uvV(uv0_word);
        const tex_u1 = uvU(uv1_word);
        const tex_v1 = uvV(uv1_word);
        const tex_u2 = uvU(uv2_word);
        const tex_v2 = uvV(uv2_word);

        const clx = clutX(uv0_word);
        const cly = clutY(uv0_word);

        const tex_base_x = texturePageBaseX(tpage);
        const tex_base_y = texturePageBaseY(tpage);
        const tex_mode = textureMode(tpage);

        var y: i32 = bounds.min_y;
        while (y <= bounds.max_y) : (y += 1) {
            var x: i32 = bounds.min_x;
            while (x <= bounds.max_x) : (x += 1) {
                const px2 = x * 2 + 1;
                const py2 = y * 2 + 1;

                const weights = triangleWeights(x0, y0, x1, y1, x2, y2, px2, py2, edges) orelse continue;

                const tu: u32 = @intCast(
                    (@as(u64, tex_u0) * weights.w0 + @as(u64, tex_u1) * weights.w1 + @as(u64, tex_u2) * weights.w2) / edges.area2_abs,
                );
                const tv: u32 = @intCast(
                    (@as(u64, tex_v0) * weights.w0 + @as(u64, tex_v1) * weights.w1 + @as(u64, tex_v2) * weights.w2) / edges.area2_abs,
                );

                const px = self.sampleTextureMode(tex_mode, tex_base_x, tex_base_y, clx, cly, tu, tv);
                if (px == 0) continue;

                self.putPixel(x, y, px);
            }
        }
    }

    fn drawShadedTexturedTriangleWithTpage(
        self: *Gpu,
        x0: i32,
        y0: i32,
        uv0_word: u32,
        c0: u16,
        x1: i32,
        y1: i32,
        uv1_word: u32,
        c1: u16,
        x2: i32,
        y2: i32,
        uv2_word: u32,
        c2: u16,
        tpage: u32,
    ) void {
        const bounds = self.clippedTriangleBounds(x0, y0, x1, y1, x2, y2) orelse return;
        const edges = triangleEdges(x0, y0, x1, y1, x2, y2) orelse return;

        const tex_u0 = uvU(uv0_word);
        const tex_v0 = uvV(uv0_word);
        const tex_u1 = uvU(uv1_word);
        const tex_v1 = uvV(uv1_word);
        const tex_u2 = uvU(uv2_word);
        const tex_v2 = uvV(uv2_word);

        const clx = clutX(uv0_word);
        const cly = clutY(uv0_word);

        const tex_base_x = texturePageBaseX(tpage);
        const tex_base_y = texturePageBaseY(tpage);
        const tex_mode = textureMode(tpage);

        var y: i32 = bounds.min_y;
        while (y <= bounds.max_y) : (y += 1) {
            var x: i32 = bounds.min_x;
            while (x <= bounds.max_x) : (x += 1) {
                const px2 = x * 2 + 1;
                const py2 = y * 2 + 1;

                const weights = triangleWeights(x0, y0, x1, y1, x2, y2, px2, py2, edges) orelse continue;

                const tu: u32 = @intCast(
                    (@as(u64, tex_u0) * weights.w0 + @as(u64, tex_u1) * weights.w1 + @as(u64, tex_u2) * weights.w2) / edges.area2_abs,
                );
                const tv: u32 = @intCast(
                    (@as(u64, tex_v0) * weights.w0 + @as(u64, tex_v1) * weights.w1 + @as(u64, tex_v2) * weights.w2) / edges.area2_abs,
                );

                const tex_px = self.sampleTextureMode(tex_mode, tex_base_x, tex_base_y, clx, cly, tu, tv);
                if (tex_px == 0) continue;

                const shade = mixRgb555(c0, c1, c2, weights.w0, weights.w1, weights.w2, edges.area2_abs);
                self.putPixel(x, y, modulateRgb555(tex_px, shade));
            }
        }
    }

    fn drawTexturedTriangle(
        self: *Gpu,
        x0: i32,
        y0: i32,
        uv0_word: u32,
        x1: i32,
        y1: i32,
        uv1_word: u32,
        x2: i32,
        y2: i32,
        uv2_word: u32,
    ) void {
        const tpage = (uv1_word >> 16) & 0xFFFF;
        self.drawTexturedTriangleWithTpage(x0, y0, uv0_word, x1, y1, uv1_word, x2, y2, uv2_word, tpage);
    }

    fn drawFilledQuadBBox(self: *Gpu) void {
        const x0 = vertexX(self.gp0_quad_vertices[0]) + self.draw_offset_x;
        const y0 = vertexY(self.gp0_quad_vertices[0]) + self.draw_offset_y;
        const x1 = vertexX(self.gp0_quad_vertices[1]) + self.draw_offset_x;
        const y1 = vertexY(self.gp0_quad_vertices[1]) + self.draw_offset_y;
        const x2 = vertexX(self.gp0_quad_vertices[2]) + self.draw_offset_x;
        const y2 = vertexY(self.gp0_quad_vertices[2]) + self.draw_offset_y;
        const x3 = vertexX(self.gp0_quad_vertices[3]) + self.draw_offset_x;
        const y3 = vertexY(self.gp0_quad_vertices[3]) + self.draw_offset_y;

        self.drawFilledTriangle(x0, y0, x1, y1, x2, y2, self.gp0_quad_color);
        self.drawFilledTriangle(x1, y1, x2, y2, x3, y3, self.gp0_quad_color);
    }

    pub fn writeGp1(self: *Gpu, pc: u32, value: u32) void {
        self.gp1_last = value;
        _ = pc;
        const cmd: u8 = @intCast(value >> 24);
        const param: u32 = value & 0x00FF_FFFF;

        switch (cmd) {
            0x00 => {
                self.status = 0x1C00_0000;
                self.gp0_mode = 0;
                self.gp0_words_remaining = 0;
                self.dma_direction = 0;
                self.display_disabled = true;
            },
            0x01 => {
                self.gp0_mode = 0;
                self.gp0_words_remaining = 0;
            },
            0x02 => {
                self.status &= ~(@as(u32, 1) << 24);
            },
            0x03 => {
                self.display_disabled = (param & 1) != 0;
            },
            0x04 => {
                self.dma_direction = param & 0x3;
            },
            0x05 => {
                self.display_x = @intCast(param & 0x3FF);
                self.display_y = @intCast((param >> 10) & 0x1FF);
            },
            0x06 => {
                self.display_h_start = @intCast(param & 0xFFF);
                self.display_h_end = @intCast((param >> 12) & 0xFFF);
            },
            0x07 => {
                self.display_v_start = @intCast(param & 0x3FF);
                self.display_v_end = @intCast((param >> 10) & 0x3FF);
            },
            0x08 => {
                self.display_mode = param;
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
            else => {},
        }

        self.status |= 0x1C00_0000;
    }
};
