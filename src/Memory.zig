const std = @import("std");
const BIOS = @import("bios.zig");
const debug_f = @import("debug.zig");

pub const MEMORY_MASK_REGION = [_]u32{
    0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, //KUSEG
    0x7fffffff, //KUSEG0
    0x1fffffff, //KUSEG1
    0xffffffff, 0xffffffff, //KUSEG2
};

pub fn maskRegion(address: u32) u32 {
    const index: usize = @intCast(address >> 29);
    return address & MEMORY_MASK_REGION[index];
}

pub const Ram = struct {
    pub const Size: usize = 2 * 1024 * 1024;
    pub const Start: u32 = 0x0000_0000;
    pub const End: u32 = 0x001f_ffff;

    allocator: std.mem.Allocator,
    data: [Size]u8,

    pub fn init(allocator: std.mem.Allocator) *@This() {
        const self = allocator.create(@This()) catch @panic("PANIC");
        self.* = .{
            .allocator = allocator,
            .data = undefined,
        };
        @memset(&self.data, 0);
        return self;
    }
    pub fn deinit(self: *@This()) void {
        self.allocator.destroy(self);
    }
};

pub const Bus = struct {
    tick_count: u64 = 0,

    allocator: std.mem.Allocator,
    ram: *Ram,
    bios: ?*BIOS.Bios = null,
    debug_cpu_pc: u32 = 0,

    interrupt_status: u32 = 0,
    interrupt_mask: u32 = 0,

    scratchpad: [ScratchPad.Size]u8 = [_]u8{0} ** ScratchPad.Size,
    hw_regs: [HardwareRegisters.Size]u8 = [_]u8{0} ** HardwareRegisters.Size,
    unknown_hw_log_count: u32 = 0,

    spu_regs: [0x200]u8 = [_]u8{0} ** 0x200,
    cdrom_regs: [0x20]u8 = [_]u8{0} ** 0x20,

    gpu_status: u32 = 0x1C00_0000,
    gpu_gpu0: u32 = 0,
    gpu_gpu1: u32 = 0,

    root_counter0: u16 = 0,
    root_counter1: u16 = 0,
    root_counter2: u16 = 0,

    root_mode0: u16 = 0,
    root_mode1: u16 = 0,
    root_mode2: u16 = 0,

    root_target0: u16 = 0xFFFF,
    root_target1: u16 = 0xFFFF,
    root_target2: u16 = 0xFFFF,

    pub fn init(allocator: std.mem.Allocator) *@This() {
        const self = allocator.create(@This()) catch @panic("failed to allocate Bus");

        self.* = .{
            .allocator = allocator,
            .ram = Ram.init(allocator),
        };
        self.hwWrite32Raw(0x1F80_1060, 0x00000B88);
        self.hwWrite32Raw(0x1F80_10E0, 0x0000_0000);
        self.hwWrite32Raw(0x1F80_10E4, 0x0000_0000);
        self.hwWrite32Raw(0x1F80_10E8, 0x0000_0000);
        self.hwWrite32Raw(0x1F80_10F0, 0x07654321);
        self.hwWrite32Raw(0x1F80_10F4, 0x00000000);
        return self;
    }

    pub fn deinit(self: *@This()) void {
        if (self.bios) |b| {
            b.deinit();
        }
        self.ram.deinit();
        self.allocator.destroy(self);
    }

    pub const Spu = struct {
        pub const Start: u32 = 0x1f80_1c00;
        pub const End: u32 = 0x1f80_1dff;
    };
    pub const Gpu = struct {
        pub const GP0: u32 = 0x1f80_1810;
        pub const GP1: u32 = 0x1f80_1814;
    };

    fn traceEventMem(self: *Bus, kind: []const u8, physical: u32, value: u32, bits: u8) void {
        if (!debug_f.enable_event_mem_trace) return;

        const interesting =
            (physical >= 0x0000_8600 and physical <= 0x0000_88FF) or
            (physical >= 0x001F_F000 and physical <= 0x001F_FFFF);

        if (!interesting) return;

        std.debug.print(
            "EVENT MEM {s}{} PC=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
            .{ kind, bits, self.debug_cpu_pc, physical, value },
        );
    }

    pub fn traceRamWrite(self: *Bus, address: u32, physical: u32, value: u32, size: u8) void {
        if (!debug_f.enable_ram_write_trace) return;
        if (physical >= 0x0000_00B0 and physical <= 0x0000_00BF) {
            std.debug.print(
                "B0 WRITE{} PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ size, self.debug_cpu_pc, address, physical, value },
            );
        }

        if (physical >= 0x0000_0600 and physical <= 0x0000_063F and value != 0) {
            std.debug.print(
                "NONZERO 0600 WRITE{} PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ size, self.debug_cpu_pc, address, physical, value },
            );
        }

        if (physical >= 0x0000_0900 and physical <= 0x0000_0A20 and value != 0) {
            std.debug.print(
                "NONZERO TABLE WRITE{} PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ size, self.debug_cpu_pc, address, physical, value },
            );
        }
    }
    fn traceInterestingHwRead(self: *Bus, physical: u32, value: u32, bits: u8) void {
        // Only trace likely polling/status registers.
        const interesting =
            physical == 0x1F80_1070 or // I_STAT
            physical == 0x1F80_1074 or // I_MASK
            physical == 0x1F80_1100 or physical == 0x1F80_1104 or physical == 0x1F80_1108 or
            physical == 0x1F80_1110 or physical == 0x1F80_1114 or physical == 0x1F80_1118 or
            physical == 0x1F80_1120 or physical == 0x1F80_1124 or physical == 0x1F80_1128 or
            physical == 0x1F80_1810 or // GPU GP0
            physical == 0x1F80_1814 or // GPU STAT
            physical == 0x1F80_1800 or physical == 0x1F80_1801 or
            physical == 0x1F80_1802 or physical == 0x1F80_1803; // CDROM

        if (!interesting) return;

        std.debug.print(
            "HW READ{} PC=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
            .{ bits, self.debug_cpu_pc, physical, value },
        );
    }
    fn readRootCounter16(self: *Bus, physical: u32) ?u16 {
        return switch (physical) {
            0x1F80_1100 => self.root_counter0,
            0x1F80_1104 => self.root_mode0,
            0x1F80_1108 => self.root_target0,

            0x1F80_1110 => self.root_counter1,
            0x1F80_1114 => self.root_mode1,
            0x1F80_1118 => self.root_target1,

            0x1F80_1120 => self.root_counter2,
            0x1F80_1124 => self.root_mode2,
            0x1F80_1128 => self.root_target2,

            else => null,
        };
    }
    fn writeRootCounter16(self: *Bus, physical: u32, value: u16) bool {
        switch (physical) {
            0x1F80_1100 => self.root_counter0 = value,
            0x1F80_1104 => self.root_mode0 = value,
            0x1F80_1108 => self.root_target0 = value,

            0x1F80_1110 => self.root_counter1 = value,
            0x1F80_1114 => self.root_mode1 = value,
            0x1F80_1118 => self.root_target1 = value,

            0x1F80_1120 => self.root_counter2 = value,
            0x1F80_1124 => self.root_mode2 = value,
            0x1F80_1128 => self.root_target2 = value,

            else => return false,
        }

        return true;
    }
    pub fn tick(self: *Bus) void {
        self.tick_count +%= 1;

        self.root_counter0 +%= 1;
        self.root_counter1 +%= 1;
        self.root_counter2 +%= 1;

        if (self.root_counter0 == self.root_target0) {
            //self.interrupt_status |= 1 << 4;
            self.root_counter0 = 0;
        }

        if (self.root_counter1 == self.root_target1) {
            //self.interrupt_status |= 1 << 5;
            self.root_counter1 = 0;
        }

        if (self.root_counter2 == self.root_target2) {
            // self.interrupt_status |= 1 << 6;
            self.root_counter2 = 0;
        }

        // Fake VBlank, but only raise it if VBlank is not already pending.
        // This prevents constantly reasserting bit 0 immediately after BIOS clears it.
        if ((self.tick_count % 1_000_000) == 0) {
            if ((self.interrupt_status & 1) == 0) {
                self.interrupt_status |= 1;

                if ((self.interrupt_mask & 1) != 0) {
                    std.debug.print(
                        "VBLANK SET tick={} I_STAT=0x{X:0>8} I_MASK=0x{X:0>8}\n",
                        .{ self.tick_count, self.interrupt_status, self.interrupt_mask },
                    );
                }
            }
        }
    }
    pub fn hwOffSet(physical: u32) usize {
        return @intCast(physical - HardwareRegisters.Start);
    }
    pub fn hwRead8Raw(self: *const Bus, physical: u32) u8 {
        return self.hw_regs[hwOffSet(physical)];
    }
    pub fn hwWrite8Raw(self: *Bus, physical: u32, value: u8) void {
        self.hw_regs[hwOffSet(physical)] = value;
    }
    pub fn hwRead32Raw(self: *const Bus, physical: u32) u32 {
        const offset = hwOffSet(physical);

        return @as(u32, self.hw_regs[offset]) |
            (@as(u32, self.hw_regs[offset + 1]) << 8) |
            (@as(u32, self.hw_regs[offset + 2]) << 16) |
            (@as(u32, self.hw_regs[offset + 3]) << 24);
    }
    pub fn hwWrite32Raw(self: *Bus, physical: u32, value: u32) void {
        const offset = hwOffSet(physical);

        self.hw_regs[offset] = @intCast(value & 0xFF);
        self.hw_regs[offset + 1] = @intCast((value >> 8) & 0xFF);
        self.hw_regs[offset + 2] = @intCast((value >> 16) & 0xFF);
        self.hw_regs[offset + 3] = @intCast((value >> 24) & 0xFF);
    }

    fn isMemControlE0Range(physical: u32) bool {
        return physical >= 0x1F80_1000 and physical <= 0x1F80_10FF;
    }

    pub fn isKnownHwRegister(physical: u32) bool {
        return (physical >= 0x1F80_1000 and physical <= 0x1F80_10FF) or
            (physical >= 0x1F80_1070 and physical <= 0x1F80_1077) or
            (physical >= 0x1F80_1800 and physical <= 0x1F80_181F) or
            (physical >= 0x1F80_1810 and physical <= 0x1F80_1817) or
            (physical >= Spu.Start and physical <= Spu.End);
    }
    pub fn traceUnknownHw(
        self: *Bus,
        kind: []const u8,
        address: u32,
        physical: u32,
        value: ?u32,
        size: u8,
    ) void {
        if (isKnownHwRegister(physical)) return;
        if (self.unknown_hw_log_count >= 256) return;

        self.unknown_hw_log_count += 1;
        if (value) |v| {
            std.debug.print(
                "HW {s}{} PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ kind, size, self.debug_cpu_pc, address, physical, v },
            );
        } else {
            std.debug.print(
                "HW {s}{} PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8}\n",
                .{ kind, size, self.debug_cpu_pc, address, physical },
            );
        }
    }

    pub fn read8(self: *Bus, address: u32) u8 {
        const physical = maskRegion(address);

        if (physical >= Ram.Start and physical <= Ram.End) {
            const offset: usize = @intCast(physical - Ram.Start);
            const value = self.ram.data[offset];
            self.traceEventMem("READ", physical, value, 8);
            return value;
        }

        if (physical >= ScratchPad.Start and physical <= ScratchPad.End) {
            const offset: usize = @intCast(physical - ScratchPad.Start);
            return self.scratchpad[offset];
        }

        if (physical >= BIOS.Bios.Start and physical <= BIOS.Bios.End) {
            if (self.bios) |b| {
                return b.read8(physical);
            }
            std.debug.panic("BIOS read but no BIOS loaded\n", .{});
        }

        if (physical >= Expansion1.Start and physical <= Expansion1.End) {
            return 0xFF;
        }

        if (physical >= HardwareRegisters.Start and physical <= HardwareRegisters.End) {
            if (physical >= 0x1F80_1070 and physical <= 0x1F80_1073) {
                const shift: u5 = @intCast((physical - 0x1F80_1070) * 8);
                return @intCast((self.interrupt_status >> shift) & 0xFF);
            }

            if (physical >= 0x1F80_1074 and physical <= 0x1F80_1077) {
                const shift: u5 = @intCast((physical - 0x1F80_1074) * 8);
                return @intCast((self.interrupt_mask >> shift) & 0xFF);
            }

            if (physical >= 0x1F80_1810 and physical <= 0x1F80_1813) {
                const shift: u5 = @intCast((physical - 0x1F80_1810) * 8);
                return @intCast((self.gpu_gpu0 >> shift) & 0xFF);
            }

            if (physical >= 0x1F80_1814 and physical <= 0x1F80_1817) {
                const shift: u5 = @intCast((physical - 0x1F80_1814) * 8);
                const value: u8 = @intCast((self.gpu_status >> shift) & 0xFF);

                self.traceInterestingHwRead(physical, value, 8);
                return value;
            }

            if (physical >= Spu.Start and physical <= Spu.End) {
                const offset: usize = @intCast(physical - Spu.Start);
                return self.spu_regs[offset];
            }
            if (physical >= Cdrom.Start and physical <= Cdrom.End) {
                const offset: usize = @intCast(physical - Cdrom.Start);

                const value: u8 = if (offset == 0)
                    0x18
                else
                    self.cdrom_regs[offset];

                self.traceInterestingHwRead(physical, value, 8);
                return value;
            }
            if (physical >= 0x1F80_1060 and physical <= 0x1F80_1063) {
                const value = self.hwRead8Raw(physical);
                self.traceInterestingHwRead(physical, value, 8);
                return value;
            }
            if (physical >= 0x1F80_10F0 and physical <= 0x1F80_10F7) {
                const value = self.hwRead8Raw(physical);
                self.traceInterestingHwRead(physical, value, 8);
                return value;
            }

            self.traceUnknownHw("READ", address, physical, null, 8);
            const value = self.hwRead8Raw(physical);
            if (isMemControlE0Range(physical)) {
                std.debug.print(
                    "MEMCTRL READ8 PC=0x{X:0>8} addr=0x{X:0>8} value=0x{X:0>2}\n",
                    .{ self.debug_cpu_pc, physical, value },
                );
            }
            self.traceInterestingHwRead(physical, value, 8);
            return value;
        }

        // Kernel control / cache control area. Ignore for now.
        if (physical >= 0xfffe_0000 and physical <= 0xffff_ffff) {
            return 0;
        }

        std.debug.panic("Unhandled read8 at 0x{X:0>8}", .{address});
    }
    pub fn read16(self: *Bus, address: u32) u16 {
        if ((address & 1) != 0) {
            std.debug.panic("Unaligned read16 at 0x{X:0>8}", .{address});
        }

        const physical = maskRegion(address);

        if (physical >= 0x1F80_1100 and physical <= 0x1F80_112B) {
            if (self.readRootCounter16(physical)) |value| {
                self.traceInterestingHwRead(physical, value, 16);
                return value;
            }
        }

        if (physical == 0x1F80_1070) {
            const value: u16 = @intCast(self.interrupt_status & 0xFFFF);
            self.traceInterestingHwRead(physical, value, 16);
            return value;
        }

        if (physical == 0x1F80_1074) {
            const value: u16 = @intCast(self.interrupt_mask & 0xFFFF);
            self.traceInterestingHwRead(physical, value, 16);
            return value;
        }

        const lo = @as(u16, self.read8(address));
        const hi = @as(u16, self.read8(address + 1)) << 8;
        return lo | hi;
    }
    pub fn read32(self: *Bus, address: u32) u32 {
        if ((address & 3) != 0) {
            std.debug.panic("Unaligned read32 at 0x{X:0>8}", .{address});
        }

        const physical = maskRegion(address);

        // TEMP TEST: force this specific memory-control register.
        // Must be BEFORE the 0x1F801000..0x1F8010FF generic block.
        if (physical == 0x1F80_10E8) {
            const value: u32 = 0x0000_0000;

            //std.debug.print(
            // "MEMCTRL READ32 PC=0x{X:0>8} addr=0x{X:0>8} value=0x{X:0>8} FORCED\n",
            //.{ self.debug_cpu_pc, physical, value },
            //);

            return value;
        }
        if (physical == 0x1F80_10A8) {
            const raw =
                @as(u32, self.hwRead8Raw(physical)) |
                (@as(u32, self.hwRead8Raw(physical + 1)) << 8) |
                (@as(u32, self.hwRead8Raw(physical + 2)) << 16) |
                (@as(u32, self.hwRead8Raw(physical + 3)) << 24);

            // DMA channel 2 GPU CHCR:
            // Clear bit 24 so BIOS sees DMA as completed.
            const value = raw & ~@as(u32, 0x0100_0000);

            //std.debug.print(
            //  "DMA2 CHCR READ32 PC=0x{X:0>8} raw=0x{X:0>8} value=0x{X:0>8}\n",
            //.{ self.debug_cpu_pc, raw, value },
            //);

            return value;
        }

        // Interrupt registers should also be BEFORE the generic mem-control block.
        if (physical == 0x1F80_1070) {
            const value = self.interrupt_status;
            self.traceInterestingHwRead(physical, value, 32);
            return value;
        }

        if (physical == 0x1F80_1074) {
            const value = self.interrupt_mask;
            self.traceInterestingHwRead(physical, value, 32);
            return value;
        }

        // Generic memory-control register readback.
        if (physical >= 0x1F80_1000 and physical <= 0x1F80_10FF) {
            const value =
                @as(u32, self.hwRead8Raw(physical)) |
                (@as(u32, self.hwRead8Raw(physical + 1)) << 8) |
                (@as(u32, self.hwRead8Raw(physical + 2)) << 16) |
                (@as(u32, self.hwRead8Raw(physical + 3)) << 24);

            //std.debug.print(
            //"MEMCTRL READ32 PC=0x{X:0>8} addr=0x{X:0>8} value=0x{X:0>8}\n",
            //.{ self.debug_cpu_pc, physical, value },
            //);

            return value;
        }

        if (physical == 0x1F80_1814) {
            const value = self.gpu_status;
            self.traceInterestingHwRead(physical, value, 32);
            return value;
        }

        if (physical >= 0x1F80_1100 and physical <= 0x1F80_112B) {
            const lo = @as(u32, self.read16(address));
            const hi = @as(u32, self.read16(address + 2)) << 16;
            return lo | hi;
        }

        const b0 = @as(u32, self.read8(address));
        const b1 = @as(u32, self.read8(address + 1)) << 8;
        const b2 = @as(u32, self.read8(address + 2)) << 16;
        const b3 = @as(u32, self.read8(address + 3)) << 24;

        return b0 | b1 | b2 | b3;
    }

    pub fn write8(self: *Bus, address: u32, value: u8) void {
        const physical = maskRegion(address);

        if (physical >= Ram.Start and physical <= Ram.End) {
            self.traceRamWrite(address, physical, value, 8);
            self.traceEventMem("WRITE", physical, value, 8);

            const offset: usize = @intCast(physical - Ram.Start);
            self.ram.data[offset] = value;
            return;
        }

        if (physical >= ScratchPad.Start and physical <= ScratchPad.End) {
            const offset: usize = @intCast(physical - ScratchPad.Start);
            self.scratchpad[offset] = value;
            return;
        }

        if (physical >= BIOS.Bios.Start and physical <= BIOS.Bios.End) {
            std.debug.panic("Attempted write8 to BIOS ROM at 0x{X:0>8}\n", .{address});
        }

        if (physical >= HardwareRegisters.Start and physical <= HardwareRegisters.End) {
            // Generic backing first. This lets BIOS config write/read checks pass.
            self.hwWrite8Raw(physical, value);
            if (isMemControlE0Range(physical)) {
                std.debug.print(
                    "MEMCTRL WRITE8 PC=0x{X:0>8} addr=0x{X:0>8} value=0x{X:0>2}\n",
                    .{ self.debug_cpu_pc, physical, value },
                );
            }

            if (physical >= 0x1F80_1070 and physical <= 0x1F80_1073) {
                const shift: u5 = @intCast((physical - 0x1F80_1070) * 8);
                const mask: u32 = @as(u32, 0xFF) << shift;

                // Minimal I_STAT behavior for now.
                self.interrupt_status =
                    (self.interrupt_status & ~mask) |
                    ((@as(u32, value) << shift) & mask);

                self.hwWrite32Raw(0x1F80_1070, self.interrupt_status);
                return;
            }

            if (physical >= 0x1F80_1074 and physical <= 0x1F80_1077) {
                const shift: u5 = @intCast((physical - 0x1F80_1074) * 8);
                const mask: u32 = @as(u32, 0xFF) << shift;

                self.interrupt_mask =
                    (self.interrupt_mask & ~mask) |
                    ((@as(u32, value) << shift) & mask);

                self.hwWrite32Raw(0x1F80_1074, self.interrupt_mask);
                return;
            }

            if (physical >= 0x1F80_1810 and physical <= 0x1F80_1813) {
                const shift: u5 = @intCast((physical - 0x1F80_1810) * 8);
                const mask: u32 = @as(u32, 0xFF) << shift;

                self.gpu_gpu0 =
                    (self.gpu_gpu0 & ~mask) |
                    ((@as(u32, value) << shift) & mask);

                return;
            }

            if (physical >= 0x1F80_1814 and physical <= 0x1F80_1817) {
                const shift: u5 = @intCast((physical - 0x1F80_1814) * 8);
                const mask: u32 = @as(u32, 0xFF) << shift;

                self.gpu_gpu1 =
                    (self.gpu_gpu1 & ~mask) |
                    ((@as(u32, value) << shift) & mask);

                self.gpu_status = 0x1C00_0000;
                return;
            }

            if (physical >= Spu.Start and physical <= Spu.End) {
                const offset: usize = @intCast(physical - Spu.Start);
                self.spu_regs[offset] = value;
                return;
            }

            if (physical >= Cdrom.Start and physical <= Cdrom.End) {
                const offset: usize = @intCast(physical - Cdrom.Start);
                self.cdrom_regs[offset] = value;
                return;
            }

            self.traceUnknownHw("WRITE", address, physical, value, 8);
            return;
        }

        if (physical >= 0xfffe_0000 and physical <= 0xffff_ffff) {
            return;
        }

        std.debug.panic("Unhandled write8 at 0x{X:0>8} value=0x{X:0>2}", .{ address, value });
    }

    pub fn write16(self: *Bus, address: u32, value: u16) void {
        if ((address & 1) != 0) {
            std.debug.panic("Unaligned write16 at 0x{X:0>8}", .{address});
        }

        const physical = maskRegion(address);

        if (physical == 0x1F80_1070) {
            self.interrupt_status &= @as(u32, value);
            self.hwWrite32Raw(0x1F80_1070, self.interrupt_status);

            std.debug.print(
                "I_STAT WRITE16 PC=0x{X:0>8} value=0x{X:0>4} new_stat=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, value, self.interrupt_status },
            );

            return;
        }

        if (physical == 0x1F80_1074) {
            self.interrupt_mask = (self.interrupt_mask & 0xFFFF_0000) | @as(u32, value);
            self.hwWrite32Raw(0x1F80_1074, self.interrupt_mask);

            std.debug.print(
                "I_MASK WRITE16 PC=0x{X:0>8} value=0x{X:0>4} new_mask=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, value, self.interrupt_mask },
            );

            return;
        }
        if (physical >= 0x1F80_1100 and physical <= 0x1F80_112B) {
            if (self.writeRootCounter16(physical, value)) {
                self.hwWrite8Raw(physical, @intCast(value & 0x00FF));
                self.hwWrite8Raw(physical + 1, @intCast((value >> 8) & 0x00FF));
                return;
            }
        }

        self.write8(address, @intCast(value & 0x00FF));
        self.write8(address + 1, @intCast((value >> 8) & 0x00FF));
    }
    pub fn write32(self: *Bus, address: u32, value: u32) void {
        if ((address & 3) != 0) {
            std.debug.panic("Unaligned write32 at 0x{X:0>8}", .{address});
        }

        const physical = maskRegion(address);

        // I_STAT acknowledge: write clears acknowledged bits.
        // Must be BEFORE generic 0x1F801000..0x1F8010FF handling.
        if (physical == 0x1F80_1070) {
            self.interrupt_status &= value;
            self.hwWrite32Raw(0x1F80_1070, self.interrupt_status);

            std.debug.print(
                "I_STAT WRITE32 PC=0x{X:0>8} value=0x{X:0>8} new_stat=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, value, self.interrupt_status },
            );

            return;
        }

        // I_MASK write.
        // Must be BEFORE generic 0x1F801000..0x1F8010FF handling.
        if (physical == 0x1F80_1074) {
            self.interrupt_mask = value;
            self.hwWrite32Raw(0x1F80_1074, self.interrupt_mask);

            std.debug.print(
                "I_MASK WRITE32 PC=0x{X:0>8} value=0x{X:0>8} new_mask=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, value, self.interrupt_mask },
            );

            return;
        }

        // DMA2 GPU CHCR: complete immediately for now.
        if (physical == 0x1F80_10A8) {
            const completed_value = value & ~@as(u32, 0x0100_0000);

            self.hwWrite32Raw(physical, completed_value);

            //std.debug.print(
            //  "DMA2 CHCR WRITE32 PC=0x{X:0>8} value=0x{X:0>8} stored=0x{X:0>8}\n",
            // .{ self.debug_cpu_pc, value, completed_value },
            //);

            return;
        }

        // Generic memory-control / DMA register backing.
        if (physical >= 0x1F80_1000 and physical <= 0x1F80_10FF) {
            self.hwWrite32Raw(physical, value);

            //std.debug.print(
            //  "MEMCTRL WRITE32 PC=0x{X:0>8} addr=0x{X:0>8} value=0x{X:0>8}\n",
            //.{ self.debug_cpu_pc, physical, value },
            //);

            return;
        }

        if (physical >= 0x1F80_1100 and physical <= 0x1F80_112B) {
            self.write16(address, @intCast(value & 0xFFFF));
            self.write16(address + 2, @intCast((value >> 16) & 0xFFFF));
            return;
        }

        self.write8(address, @intCast(value & 0x000000FF));
        self.write8(address + 1, @intCast((value >> 8) & 0x000000FF));
        self.write8(address + 2, @intCast((value >> 16) & 0x000000FF));
        self.write8(address + 3, @intCast((value >> 24) & 0x000000FF));
    }
    pub fn loadBios(self: *Bus, io: std.Io, path: []const u8) !void {
        if (self.bios) |old| {
            old.deinit();
            self.bios = null;
        }
        self.bios = try BIOS.Bios.loadBios(self.allocator, io, path);
    }
};

pub const ScratchPad = struct {
    pub const Size: usize = End - Start + 1;
    pub const Start: u32 = 0x1f80_0000;
    pub const End: u32 = 0x1f80_03ff;
};
pub const Expansion1 = struct {
    pub const Start: u32 = 0x1f00_0000;
    pub const End: u32 = 0x1f7f_ffff;
};
pub const HardwareRegisters = struct {
    pub const Size: usize = End - Start + 1;
    pub const Start: u32 = 0x1f80_1000;
    pub const End: u32 = 0x1f80_2fff;
};
pub const Expansion2 = struct {
    pub const Start: u32 = 0x1f80_2000;
    pub const End: u32 = 0x1f80_3fff;
};
pub const Cdrom = struct {
    pub const Start: u32 = 0x1f80_1800;
    pub const End: u32 = 0x1f80_1803;
};
pub const HwPortRange = struct {
    pub const Start: u32 = 0x1f80_1800;
    pub const End: u32 = 0x1f80_181f;
};
