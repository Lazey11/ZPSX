const std = @import("std");

pub const Gpu = struct {
    pub const GP0: u32 = 0x1F80_1810;
    pub const GP1: u32 = 0x1F80_1814;

    status: u32 = 0x1C00_0000,

    gp0_last: u32 = 0,
    gp1_last: u32 = 0,

    gp0_mode: u8 = 0, // 0=command, 1=A0 pos, 2=A0 size, 3=A0 data, 4=C0 pos, 5=C0 size
    gp0_words_remaining: u32 = 0,
    gp0_skip_words: u32 = 0,

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
    debug_dump_640_ready: bool = false,

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

    pub fn writeGp0(self: *Gpu, pc: u32, value: u32) void {
        self.gp0_last = value;
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

                std.debug.print(
                    "GP0 IMAGE LOAD x={} y={} w={} h={} words={}\n",
                    .{
                        self.vram_x,
                        self.vram_y,
                        self.vram_w,
                        self.vram_h,
                        self.gp0_words_remaining,
                    },
                );

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

                std.debug.print(
                    "GP0 IMAGE READ x={} y={} w={} h={}\n",
                    .{
                        self.vram_x,
                        self.vram_y,
                        self.vram_w,
                        self.vram_h,
                    },
                );

                return;
            },

            else => {},
        }

        const cmd: u8 = @intCast(value >> 24);

        switch (cmd) {
            0x00 => {}, // NOP
            0x01 => {}, // clear cache
            0x28 => {
                self.gp0_skip_words = 4;
            },
            0xE1 => {}, // draw mode
            0xE2 => {},
            0xE3 => {},
            0xE4 => {},
            0xE5 => {},
            0xE6 => {},

            0xA0 => {
                // Image load to VRAM.
                self.gp0_mode = 1;
            },

            0xC0 => {
                // Image read from VRAM.
                self.gp0_mode = 4;
            },

            else => {
                std.debug.print(
                    "GP0 CMD PC=0x{X:0>8} cmd=0x{X:0>2} value=0x{X:0>8}\n",
                    .{ pc, cmd, value },
                );
            },
        }
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

            if (self.image_x == 640 and
                self.image_y == 0 and
                self.image_w == 60 and
                self.image_h == 48 and
                self.image_index >= 2880)
            {
                self.debug_dump_640_ready = true;
            }
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

    pub fn writeGp1(self: *Gpu, pc: u32, value: u32) void {
        self.gp1_last = value;

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
                // Display enable: bit 0 = 1 means disabled.
                self.display_disabled = (param & 1) != 0;
            },

            0x04 => {
                // DMA direction.
                self.dma_direction = param & 0x3;
            },

            0x05 => {
                // Display VRAM start.
                self.display_x = @intCast(param & 0x3FF);
                self.display_y = @intCast((param >> 10) & 0x1FF);
            },

            0x06 => {
                // Horizontal display range.
                self.display_h_start = @intCast(param & 0xFFF);
                self.display_h_end = @intCast((param >> 12) & 0xFFF);
            },

            0x07 => {
                // Vertical display range.
                self.display_v_start = @intCast(param & 0x3FF);
                self.display_v_end = @intCast((param >> 10) & 0x3FF);
            },

            0x08 => {
                // Display mode.
                self.display_mode = param;
            },

            else => {
                std.debug.print(
                    "GP1 CMD PC=0x{X:0>8} cmd=0x{X:0>2} value=0x{X:0>8}\n",
                    .{ pc, cmd, value },
                );
            },
        }

        self.status |= 0x1C00_0000;
    }
    pub fn dumpVramRectPPM(self: *const Gpu, path: []const u8, io: std.Io, x0: u32, y0: u32, w: u32, h: u32) !void {
        var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_writer = file.writer(io, &buffer);
        const writer = &file_writer.interface;
        try writer.print("P3\n{} {}\n255\n", .{ w, h });
        var y: u32 = 0;
        while (y < h) : (y += 1) {
            var x: u32 = 0;
            while (x < w) : (x += 1) {
                const idx: usize = @intCast((y0 + y) * 1024 + (x0 + x));
                const px = self.vram[idx];

                const r5: u16 = (px >> 0) & 0x1F;
                const g5: u16 = (px >> 5) & 0x1F;
                const b5: u16 = (px >> 10) & 0x1F;

                const r: u16 = (r5 << 3) | (r5 >> 2);
                const g: u16 = (g5 << 3) | (g5 >> 2);
                const b: u16 = (b5 << 3) | (b5 >> 2);
                try writer.print("{} {} {} ", .{ r, g, b });
            }
            try writer.writeAll("\n");
        }
        try writer.flush();
    }
};
