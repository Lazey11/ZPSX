const std = @import("std");
const BIOS = @import("bios.zig");
const debug_f = @import("debug.zig");
const gpu_f = @import("gpu.zig");
const cdrom_f = @import("cdrom.zig");
const controller_f = @import("controller.zig");

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
    cdrom: cdrom_f.Cdrom,

    tick_count: u64 = 0,
    cycles_until_vblank: u64 = CPU_CYCLES_PER_FRAME,
    cycles_until_hblank: u64 = CPU_CYCLES_PER_SCANLINE,
    hblank_pulse: bool = false,
    dotclock_accum: u8 = 0,
    dotclock_pulse: bool = false,

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

    gpu: gpu_f.Gpu = .{},
    controller: controller_f.Controller = .{},
    dma_dicr: u32 = 0,

    root_counter0: u16 = 0,
    root_counter1: u16 = 0,
    root_counter2: u16 = 0,

    root_mode0: u16 = 0,
    root_mode1: u16 = 0,
    root_mode2: u16 = 0,

    root_target0: u16 = 0x0000,
    root_target1: u16 = 0x0000,
    root_target2: u16 = 0x0000,

    pub fn init(allocator: std.mem.Allocator) *@This() {
        const self = allocator.create(@This()) catch @panic("failed to allocate Bus");

        self.* = .{
            .allocator = allocator,
            .ram = Ram.init(allocator),
            .cdrom = cdrom_f.Cdrom.init(allocator),
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

        self.cdrom.deinit();
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
    fn runDma2Gpu(self: *Bus) void {
        const madr = self.hwRead32Raw(0x1F80_10A0);
        const bcr = self.hwRead32Raw(0x1F80_10A4);
        const chcr = self.hwRead32Raw(0x1F80_10A8);

        const direction_from_ram_to_gpu = (chcr & 1) == 1;
        if (!direction_from_ram_to_gpu) return;

        const sync_mode = (chcr >> 9) & 0x3;

        if (sync_mode == 2) {
            self.runDma2GpuLinkedList();
            return;
        }

        const block_size = bcr & 0xFFFF;
        const block_count = (bcr >> 16) & 0xFFFF;
        const words = if (block_count == 0) block_size else block_size * block_count;

        if (debug_f.enable_dma_trace) {
            std.debug.print(
                "DMA2 GPU block madr=0x{X:0>8} bcr=0x{X:0>8} chcr=0x{X:0>8} words={}\n",
                .{ madr, bcr, chcr, words },
            );
        }
        var addr = madr & 0x001F_FFFC;
        var i: u32 = 0;
        while (i < words) : (i += 1) {
            const word = self.ramRead32Physical(addr);
            self.gpu.writeGp0(self.debug_cpu_pc, word);
            addr = (addr +% 4) & 0x001F_FFFC;
        }
    }
    fn runDma2GpuLinkedList(self: *Bus) void {
        var addr = self.hwRead32Raw(0x1F80_10A0) & 0x001F_FFFC;

        var packets: u32 = 0;
        while (packets < 4096) : (packets += 1) {
            const header = self.ramRead32Physical(addr);
            const count: u32 = header >> 24;
            const next_raw: u32 = header & 0x00FF_FFFF;

            if (packets < 8) {
                //
            }

            var word_addr = (addr +% 4) & 0x001F_FFFC;
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                const word = self.ramRead32Physical(word_addr);
                self.gpu.writeGp0(self.debug_cpu_pc, word);
                word_addr = (word_addr +% 4) & 0x001F_FFFC;
            }

            if (next_raw == 0x00FF_FFFF) {
                packets += 1;
                break;
            }

            const next_addr = next_raw & 0x001F_FFFC;

            if (next_raw == 0x00FF_FFFF or next_addr == addr) {
                packets += 1;
                break;
            }

            addr = next_addr;
        }
    }
    fn traceInterestingHwRead(self: *Bus, physical: u32, value: u32, bits: u8) void {
        _ = self;
        _ = physical;
        _ = value;
        _ = bits;
        return;
    }
    fn runDma6Otc(self: *Bus) void {
        const madr = self.hwRead32Raw(0x1F80_10E0);
        const bcr = self.hwRead32Raw(0x1F80_10E4);

        var addr = madr & 0x001F_FFFC;
        var count = bcr & 0xFFFF;

        //std.debug.print(
        //"DMA6 OTC madr=0x{X:0>8} bcr=0x{X:0>8} count={}\n",
        //  .{ madr, bcr, count },
        //);

        while (count > 0) : (count -= 1) {
            const value: u32 = if (count == 1)
                0x00FF_FFFF
            else
                (addr -% 4) & 0x001F_FFFC;

            self.ramWrite32Physical(addr, value);
            addr = (addr -% 4) & 0x001F_FFFC;
        }
    }
    fn signalKernelVblankWord(self: *Bus) void {
        const physical: u32 = 0x0007_9D9C;
        const old = self.ramRead32Physical(physical);
        const new = old +% 1;
        // Incrementing is safer than returning a constant:
        // wait loops often compare "did this counter change?"
        self.ramWrite32Physical(physical, new);
    }
    pub fn ramWrite8Physical(self: *Bus, physical: u32, value: u8) void {
        const offset: usize = @intCast(physical - Ram.Start);
        self.ram.data[offset] = value;
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
    fn ramRead32Physical(self: *const Bus, physical: u32) u32 {
        const offset: usize = @intCast(physical - Ram.Start);

        return @as(u32, self.ram.data[offset]) |
            (@as(u32, self.ram.data[offset + 1]) << 8) |
            (@as(u32, self.ram.data[offset + 2]) << 16) |
            (@as(u32, self.ram.data[offset + 3]) << 24);
    }

    fn ramWrite32Physical(self: *Bus, physical: u32, value: u32) void {
        const offset: usize = @intCast(physical - Ram.Start);

        self.ram.data[offset] = @intCast(value & 0xFF);
        self.ram.data[offset + 1] = @intCast((value >> 8) & 0xFF);
        self.ram.data[offset + 2] = @intCast((value >> 16) & 0xFF);
        self.ram.data[offset + 3] = @intCast((value >> 24) & 0xFF);
    }

    fn deliverBiosVblankEvent(self: *Bus) void {
        const vblank_entry: u32 = 0x0000_8674;

        const state = self.ramRead32Physical(vblank_entry);

        if (state != 0) {
            self.ramWrite32Physical(vblank_entry, state | 0x0000_1000);
        }
    }

    fn updateCdromIrqLine(self: *Bus) void {
        const I_STAT_CDROM: u32 = 1 << 2;

        if (self.cdrom.irqPending()) {
            self.interrupt_status |= I_STAT_CDROM;
        } else {
            self.interrupt_status &= ~I_STAT_CDROM;
        }

        self.hwWrite32Raw(0x1F80_1070, self.interrupt_status);
    }

    fn tickRootCounters(self: *Bus) void {
        if (self.shouldTickRootCounter0()) {
            self.tickRootCounter(&self.root_counter0, self.root_mode0, self.root_target0, 4);
        }

        if (self.shouldTickRootCounter1()) {
            self.tickRootCounter(&self.root_counter1, self.root_mode1, self.root_target1, 5);
        }

        if (self.shouldTickRootCounter2()) {
            self.tickRootCounter(&self.root_counter2, self.root_mode2, self.root_target2, 6);
        }
    }

    fn shouldTickRootCounter0(self: *const Bus) bool {
        const use_dotclock = (self.root_mode0 & (1 << 8)) != 0;
        if (use_dotclock) {
            return self.dotclock_pulse;
        }
        return true;
    }

    fn shouldTickRootCounter1(self: *const Bus) bool {
        const use_hblank_clock = (self.root_mode1 & (1 << 8)) != 0;
        if (use_hblank_clock) {
            return self.hblank_pulse;
        }
        return true;
    }

    fn shouldTickRootCounter2(self: *const Bus) bool {
        const use_system_clock_div8 = (self.root_mode2 & (1 << 9) != 0);
        if (use_system_clock_div8) {
            return (self.tick_count & 7) == 0;
        }
        return true;
    }

    fn tickRootCounter(
        self: *Bus,
        counter: *u16,
        mode: u16,
        target: u16,
        irq_bit: u5,
    ) void {
        const old_counter = counter.*;
        const new_counter = old_counter +% 1;
        counter.* = new_counter;

        const reset_on_target = (mode & (1 << 3)) != 0;
        const irq_on_target = (mode & (1 << 4)) != 0;
        const irq_on_overflow = (mode & (1 << 5)) != 0;

        const hit_target = new_counter == target;
        const overflowed = new_counter == 0 and old_counter == std.math.maxInt(u16);

        if (hit_target) {
            if (irq_on_target) {
                self.interrupt_status |= @as(u32, 1) << irq_bit;
                self.hwWrite32Raw(0x1F80_1070, self.interrupt_status);
            }

            if (reset_on_target) {
                counter.* = 0;
            }
        }

        if (overflowed and irq_on_overflow) {
            self.interrupt_status |= @as(u32, 1) << irq_bit;
            self.hwWrite32Raw(0x1F80_1070, self.interrupt_status);
        }
    }
    pub fn tick(self: *Bus) void {
        self.tick_count +%= 1;

        self.hblank_pulse = false;
        self.dotclock_pulse = false;

        self.dotclock_accum +%= 1;
        if (self.dotclock_accum >= 5) {
            self.dotclock_accum = 0;
            self.dotclock_pulse = true;
        }

        if (self.cycles_until_hblank > 0) {
            self.cycles_until_hblank -= 1;
        }

        if (self.cycles_until_hblank == 0) {
            self.cycles_until_hblank = CPU_CYCLES_PER_SCANLINE;
            self.hblank_pulse = true;
        }

        self.tickRootCounters();

        if (self.cycles_until_vblank > 0) {
            self.cycles_until_vblank -= 1;
        }

        if (self.cycles_until_vblank == 0) {
            self.cycles_until_vblank = CPU_CYCLES_PER_FRAME;

            self.signalKernelVblankWord();

            if ((self.interrupt_status & 1) == 0) {
                self.interrupt_status |= 1;
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
            (physical >= 0x1F80_1040 and physical <= 0x1F80_104F) or
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
        if (!debug_f.enable_unknown_hw_trace) return;
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
                return @intCast((self.gpu.gp0_last >> shift) & 0xFF);
            }

            if (physical >= 0x1F80_1814 and physical <= 0x1F80_1817) {
                const shift: u5 = @intCast((physical - 0x1F80_1814) * 8);
                const status = self.gpu.readStatus();
                const value: u8 = @intCast((status >> shift) & 0xFF);

                self.traceInterestingHwRead(physical, value, 8);
                return value;
            }

            if (physical >= Spu.Start and physical <= Spu.End) {
                const offset: usize = @intCast(physical - Spu.Start);
                return self.spu_regs[offset];
            }
            if (physical >= Cdrom.Start and physical <= Cdrom.End) {
                const offset: u2 = @intCast(physical - Cdrom.Start);
                const value = self.cdrom.readRegister(offset);
                self.updateCdromIrqLine();
                return value;
            }

            if (physical == JOY_DATA) {
                return self.controller.readData();
            }
            if (physical >= JOY_STAT and physical <= JOY_STAT + 3) {
                const value = @as(u32, self.controller.readStat());
                const shift: u5 = @intCast((physical - JOY_STAT) * 8);
                return @intCast((value >> shift) & 0xFF);
            }
            if (physical >= JOY_MODE and physical <= JOY_MODE + 1) {
                const value = @as(u32, self.controller.readMode());
                const shift: u5 = @intCast((physical - JOY_MODE) * 8);
                return @intCast((value >> shift) & 0xFF);
            }

            if (physical >= JOY_CTRL and physical <= JOY_CTRL + 1) {
                const value = @as(u32, self.controller.readCtrl());
                const shift: u5 = @intCast((physical - JOY_CTRL) * 8);
                return @intCast((value >> shift) & 0xFF);
            }

            if (physical >= JOY_BAUD and physical <= JOY_BAUD + 1) {
                const value = @as(u32, self.controller.readBaud());
                const shift: u5 = @intCast((physical - JOY_BAUD) * 8);
                return @intCast((value >> shift) & 0xFF);
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
            if (debug_f.enable_unknown_hw_trace and isMemControlE0Range(physical)) {
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

        if (physical == JOY_STAT) {
            return self.controller.readStat();
        }

        if (physical == JOY_MODE) {
            return self.controller.readMode();
        }

        if (physical == JOY_CTRL) {
            return self.controller.readCtrl();
        }

        if (physical == JOY_BAUD) {
            return self.controller.readBaud();
        }

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
            std.debug.print(
                "UNALIGNED READ32 PC=0x{X:0>8} addr=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, address },
            );
            std.debug.panic("Unaligned read32 at 0x{X:0>8}", .{address});
        }

        const physical = maskRegion(address);

        if (false and physical == 0x0007_9D9C and self.debug_cpu_pc >= 0x8005_9DC8 and self.debug_cpu_pc <= 0x8005_9E10) {
            const value = self.ramRead32Physical(physical);
            std.debug.print(
                "WAIT79D9C PC=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, value },
            );
            return value;
        }

        if (false and physical == 0x0007_9D9C and
            self.debug_cpu_pc >= 0x8005_9DC8 and self.debug_cpu_pc <= 0x8005_9E10)
        {
            const value = self.ramRead32Physical(physical);

            std.debug.print(
                "WAIT79D9C READ32 PC=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, value },
            );

            return value;
        }

        if (false and physical >= 0x0000_8648 and physical <= 0x0000_8908 and
            self.debug_cpu_pc >= 0x0000_3EA8 and self.debug_cpu_pc <= 0x0000_3EB4)
        {
            const value =
                @as(u32, self.read8(address)) |
                (@as(u32, self.read8(address + 1)) << 8) |
                (@as(u32, self.read8(address + 2)) << 16) |
                (@as(u32, self.read8(address + 3)) << 24);

            std.debug.print(
                "EVENT_TABLE READ32 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );

            return value;
        }

        if (false and (physical == 0x000D_61E8 or physical == 0x000D_61EC)) {
            const value =
                @as(u32, self.read8(address)) |
                (@as(u32, self.read8(address + 1)) << 8) |
                (@as(u32, self.read8(address + 2)) << 16) |
                (@as(u32, self.read8(address + 3)) << 24);

            std.debug.print(
                "BITMAP READ32 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );

            return value;
        }

        if (false and (address == 0x8007_9D9C or physical == 0x0007_9D9C)) {
            const value: u32 = 0x7FFF_FFFF;

            std.debug.print(
                "WATCH 80079D9C READ32 FORCED PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );

            return value;
        }

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
        if (physical == 0x1F80_10F4) {
            return self.dma_dicr;
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
        if (physical == JOY_DATA) {
            return self.controller.readData();
        }
        if (physical == JOY_STAT) {
            return self.controller.readStat();
        }
        if (physical == JOY_MODE) {
            return self.controller.readMode();
        }
        if (physical == JOY_CTRL) {
            return self.controller.readCtrl();
        }
        if (physical == JOY_BAUD) {
            return self.controller.readBaud();
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

        if (physical == 0x1F80_1810) {
            return self.gpu.readGP0();
        }

        if (physical == 0x1F80_1814) {
            const value = self.gpu.readStatus();

            if (debug_f.enable_gpu_loop59_trace and
                self.debug_cpu_pc >= 0x8005_9DC0 and
                self.debug_cpu_pc <= 0x8005_9E20)
            {
                std.debug.print(
                    "GPUSTAT LOOP59 READ PC=0x{X:0>8} value=0x{X:0>8}\n",
                    .{ self.debug_cpu_pc, value },
                );
            }

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

        if (false and physical >= 0x000D_61E8 and physical <= 0x000D_61EF) {
            std.debug.print(
                "BITMAP WRITE8 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>2}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );
        }

        if (false and physical >= 0x0007_9D9C and physical <= 0x0007_9D9F) {
            std.debug.print(
                "WATCH 80079D9C WRITE8 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>2}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );
        }

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
            if (physical == JOY_DATA) {
                self.controller.writeData(value);
                return;
            }

            if (physical >= JOY_MODE and physical <= JOY_MODE + 1) {
                var old = self.controller.readMode();
                const shift: u4 = @intCast((physical - JOY_MODE) * 8);
                const mask: u16 = @as(u16, 0xFF) << shift;
                old = (old & ~mask) | ((@as(u16, value) << shift) & mask);
                self.controller.writeMode(old);
                return;
            }

            if (physical >= JOY_CTRL and physical <= JOY_CTRL + 1) {
                var old = self.controller.readCtrl();
                const shift: u4 = @intCast((physical - JOY_CTRL) * 8);
                const mask: u16 = @as(u16, 0xFF) << shift;
                old = (old & ~mask) | ((@as(u16, value) << shift) & mask);
                self.controller.writeCtrl(old);
                return;
            }

            if (physical >= JOY_BAUD and physical <= JOY_BAUD + 1) {
                var old = self.controller.readBaud();
                const shift: u4 = @intCast((physical - JOY_BAUD) * 8);
                const mask: u16 = @as(u16, 0xFF) << shift;
                old = (old & ~mask) | ((@as(u16, value) << shift) & mask);
                self.controller.writeBaud(old);
                return;
            }

            // Generic backing first. This lets BIOS config write/read checks pass.
            self.hwWrite8Raw(physical, value);
            if (debug_f.enable_unknown_hw_trace and isMemControlE0Range(physical)) {
                std.debug.print(
                    "MEMCTRL WRITE8 PC=0x{X:0>8} addr=0x{X:0>8} value=0x{X:0>2}\n",
                    .{ self.debug_cpu_pc, physical, value },
                );
            }
            if (false and physical >= 0x001F_FBAC and physical <= 0x001F_FBAF) {
                std.debug.print(
                    "STACK RA SLOT WRITE8 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>2}\n",
                    .{ self.debug_cpu_pc, address, physical, value },
                );
            }

            if (physical >= 0x1F80_1070 and physical <= 0x1F80_1073) {
                const shift: u5 = @intCast((physical - 0x1F80_1070) * 8);
                const byte_mask: u32 = @as(u32, 0xFF) << shift;
                const written: u32 = @as(u32, value) << shift;

                // I_STAT acknowledge behavior:
                // writing 0 clears pending bits, writing 1 leaves them unchanged.
                const clear_mask = written | ~byte_mask;
                self.interrupt_status &= clear_mask;

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

                self.gpu.gp0_last =
                    (self.gpu.gp0_last & ~mask) |
                    ((@as(u32, value) << shift) & mask);

                return;
            }

            if (physical >= 0x1F80_1814 and physical <= 0x1F80_1817) {
                const shift: u5 = @intCast((physical - 0x1F80_1814) * 8);
                const mask: u32 = @as(u32, 0xFF) << shift;

                self.gpu.gp1_last =
                    (self.gpu.gp1_last & ~mask) |
                    ((@as(u32, value) << shift) & mask);

                self.gpu.status |= 0x1C00_0000;
                return;
            }

            if (physical >= Spu.Start and physical <= Spu.End) {
                const offset: usize = @intCast(physical - Spu.Start);
                self.spu_regs[offset] = value;
                return;
            }

            if (physical >= Cdrom.Start and physical <= Cdrom.End) {
                const offset: u2 = @intCast(physical - Cdrom.Start);
                self.cdrom.writeRegister(offset, value);
                self.updateCdromIrqLine();
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

        if (physical == JOY_MODE) {
            self.controller.writeMode(value);
            return;
        }

        if (physical == JOY_CTRL) {
            self.controller.writeCtrl(value);
            return;
        }

        if (physical == JOY_BAUD) {
            self.controller.writeBaud(value);
            return;
        }

        if (false and physical >= 0x000D_61E8 and physical <= 0x000D_61EF) {
            std.debug.print(
                "BITMAP WRITE16 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>4}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );
        }

        if (false and (physical == 0x001F_FBAC or physical == 0x001F_FBAE)) {
            std.debug.print(
                "STACK RA SLOT WRITE16 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>4}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );
        }

        if (physical == 0x1F80_1070) {
            self.interrupt_status &= @as(u32, value);
            self.hwWrite32Raw(0x1F80_1070, self.interrupt_status);

            if (debug_f.enable_irq_register_trace) {
                std.debug.print(
                    "I_STAT WRITE16 PC=0x{X:0>8} value=0x{X:0>4} new_stat=0x{X:0>8}\n",
                    .{ self.debug_cpu_pc, value, self.interrupt_status },
                );
            }

            return;
        }

        if (physical == 0x1F80_1074) {
            self.interrupt_mask = (self.interrupt_mask & 0xFFFF_0000) | @as(u32, value);
            self.hwWrite32Raw(0x1F80_1074, self.interrupt_mask);

            if (debug_f.enable_irq_register_trace) {
                std.debug.print(
                    "I_MASK WRITE16 PC=0x{X:0>8} value=0x{X:0>4} new_mask=0x{X:0>8}\n",
                    .{ self.debug_cpu_pc, value, self.interrupt_mask },
                );
            }

            return;
        }

        if (physical >= 0x1F80_1100 and physical <= 0x1F80_112B) {
            if (self.writeRootCounter16(physical, value)) {
                self.hwWrite8Raw(physical, @intCast(value & 0x00FF));
                self.hwWrite8Raw(physical + 1, @intCast((value >> 8) & 0x00FF));
                return;
            }
        }
        if (false and physical == 0x0007_9D9C) {
            std.debug.print(
                "WATCH 80079D9C WRITE16 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );
        }

        self.write8(address, @intCast(value & 0x00FF));
        self.write8(address + 1, @intCast((value >> 8) & 0x00FF));
    }
    pub fn write32(self: *Bus, address: u32, value: u32) void {
        if ((address & 3) != 0) {
            std.debug.panic("Unaligned write32 at 0x{X:0>8}", .{address});
        }

        const physical = maskRegion(address);
        if (false and physical >= 0x0000_8648 and physical <= 0x0000_8908 and ((physical - 0x0000_8648) % 0x2C) == 0) {
            std.debug.print(
                "EVENT_STATE WRITE32 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );
        }

        if (false and physical >= 0x000D_61E8 and physical <= 0x000D_61EF) {
            std.debug.print(
                "BITMAP WRITE32 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );
        }

        if (false and physical == 0x001F_FBAC) {
            std.debug.print(
                "STACK RA SLOT WRITE32 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );
        }

        if (false and physical == 0x0007_9D9C) {
            std.debug.print(
                "WATCH 80079D9C WRITE32 PC=0x{X:0>8} addr=0x{X:0>8} physical=0x{X:0>8} value=0x{X:0>8}\n",
                .{ self.debug_cpu_pc, address, physical, value },
            );
        }

        if (physical == 0x1F80_1070) {
            self.interrupt_status &= value;
            self.hwWrite32Raw(0x1F80_1070, self.interrupt_status);

            if (debug_f.enable_irq_register_trace) {
                std.debug.print(
                    "I_STAT WRITE32 PC=0x{X:0>8} value=0x{X:0>8} new_stat=0x{X:0>8}\n",
                    .{ self.debug_cpu_pc, value, self.interrupt_status },
                );
            }

            return;
        }

        if (physical == 0x1F80_1074) {
            self.interrupt_mask = value;
            self.hwWrite32Raw(0x1F80_1074, self.interrupt_mask);

            if (debug_f.enable_irq_register_trace) {
                std.debug.print(
                    "I_MASK WRITE32 PC=0x{X:0>8} value=0x{X:0>8} new_mask=0x{X:0>8}\n",
                    .{ self.debug_cpu_pc, value, self.interrupt_mask },
                );
            }

            return;
        }
        if (physical == 0x1F80_10E8) {
            const started = (value & 0x0100_0000) != 0;

            self.hwWrite32Raw(physical, value);

            if (started) {
                self.runDma6Otc();
            }

            const completed_value = value & ~@as(u32, 0x0100_0000);
            self.hwWrite32Raw(physical, completed_value);

            return;
        }

        // DMA2 GPU CHCR: complete immediately for now.
        if (physical == 0x1F80_10A8) {
            // DMA2 GPU CHCR.
            const started = (value & 0x0100_0000) != 0;

            // Store original CHCR first so runDma2Gpu() can inspect direction/mode.
            self.hwWrite32Raw(physical, value);

            if (started) {
                self.runDma2Gpu();
            }

            // Complete immediately for now.
            const completed_value = value & ~@as(u32, 0x0100_0000);
            self.hwWrite32Raw(physical, completed_value);
            self.gpu.status |= 0x1C00_0000;

            if (started) {
                // DMA2 IRQ flag: bit 26.
                self.dma_dicr |= @as(u32, 1) << 26;

                const dma_master_enable = (self.dma_dicr & (@as(u32, 1) << 23)) != 0;
                const dma2_irq_enable = (self.dma_dicr & (@as(u32, 1) << 18)) != 0;

                if (dma_master_enable and dma2_irq_enable) {
                    // DICR master IRQ flag.
                    self.dma_dicr |= @as(u32, 1) << 31;

                    // I_STAT bit 3 = DMA.
                    self.interrupt_status |= @as(u32, 1) << 3;
                    self.hwWrite32Raw(0x1F80_1070, self.interrupt_status);
                }
            }

            return;
        }
        if (physical == 0x1F80_10F4) {
            const old_flags = self.dma_dicr & 0x7F00_0000;
            const ack_flags = value & 0x7F00_0000;
            const new_control = value & 0x00FF_FFFF;

            const new_flags = old_flags & ~ack_flags;

            // Clear master flag if no channel IRQ flags remain.
            if ((new_flags & 0x7F00_0000) == 0) {
                self.dma_dicr = new_control;
            } else {
                self.dma_dicr = new_control | new_flags | (@as(u32, 1) << 31);
            }

            return;
        }
        if (physical == 0x1F80_1810) {
            self.gpu.writeGp0(self.debug_cpu_pc, value);
            return;
        }
        if (physical == 0x1F80_1814) {
            self.gpu.writeGp1(self.debug_cpu_pc, value);
            return;
        }
        if (physical == JOY_DATA) {
            self.controller.writeData(@intCast(value & 0xFF));
            return;
        }
        if (physical == JOY_MODE) {
            self.controller.writeMode(@intCast(value & 0xFFFF));
            return;
        }
        if (physical == JOY_CTRL) {
            self.controller.writeCtrl(@intCast(value & 0xFFFF));
            return;
        }
        if (physical == JOY_BAUD) {
            self.controller.writeBaud(@intCast(value & 0xFFFF));
            return;
        }

        // Generic mem-control registers.
        // Keep this AFTER I_STAT/I_MASK/DMA special cases.
        if (physical >= 0x1F80_1000 and physical <= 0x1F80_10FF) {
            self.hwWrite32Raw(physical, value);
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
const JOY_DATA: u32 = 0x1F80_1040;
const JOY_STAT: u32 = 0x1F80_1044;
const JOY_MODE: u32 = 0x1F80_1048;
const JOY_CTRL: u32 = 0x1F80_104A;
const JOY_BAUD: u32 = 0x1F80_104E;
pub const CPU_CLOCK_HZ: u64 = 33_868_800;
pub const VIDEO_FPS: u64 = 60;
pub const SCANLINES_PER_FRAME: u64 = 263;

// Temporary compatibility timing for BIOS boot.
// The old BIOS-logo path depended on vblank being raised at this fake interval.
pub const CPU_CYCLES_PER_FRAME: u64 = 500_000;
pub const CPU_CYCLES_PER_SCANLINE: u64 = CPU_CYCLES_PER_FRAME / SCANLINES_PER_FRAME;
