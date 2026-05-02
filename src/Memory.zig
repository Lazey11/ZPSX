const std = @import("std");
const BIOS = @import("bios.zig");
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
    allocator: std.mem.Allocator,
    ram: *Ram,
    bios: ?*BIOS.Bios = null,
    debug_cpu_pc: u32 = 0,

    interrupt_status: u32 = 0,
    interrupt_mask: u32 = 0,
    memory_control_regs: [0x100]u8 = [_]u8{0} ** 0x100,

    spu_regs: [0x200]u8 = [_]u8{0} ** 0x200,
    cdrom_regs: [0x20]u8 = [_]u8{0} ** 0x20,

    gpu_status: u32 = 0x1C00_0000,
    gpu_gpu0: u32 = 0,
    gpu_gpu1: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) *@This() {
        const self = allocator.create(@This()) catch @panic("failed to allocate Bus");

        self.* = .{
            .allocator = allocator,
            .ram = Ram.init(allocator),
        };

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

    pub fn traceRamWrite(self: *Bus, address: u32, physical: u32, value: u32, size: u8) void {
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

    pub fn read8(self: *Bus, address: u32) u8 {
        const physical = maskRegion(address);
        if (physical == 0x1F80_1070) return @intCast(self.interrupt_status & 0xFF);
        if (physical == 0x1F80_1071) return @intCast((self.interrupt_status >> 8) & 0xFF);
        if (physical == 0x1F80_1072) return @intCast((self.interrupt_status >> 16) & 0xFF);
        if (physical == 0x1F80_1073) return @intCast((self.interrupt_status >> 24) & 0xFF);

        if (physical == 0x1F80_1074) return @intCast(self.interrupt_mask & 0xFF);
        if (physical == 0x1F80_1075) return @intCast((self.interrupt_mask >> 8) & 0xFF);
        if (physical == 0x1F80_1076) return @intCast((self.interrupt_mask >> 16) & 0xFF);
        if (physical == 0x1F80_1077) return @intCast((self.interrupt_mask >> 24) & 0xFF);

        if (physical >= 0x1F80_1000 and physical <= 0x1F80_10FF) {
            const offset: usize = @intCast(physical - 0x1F80_1000);
            return self.memory_control_regs[offset];
        }
        if (physical >= 0x1F80_1810 and physical <= 0x1F80_1813) {
            const shift: u5 = @intCast((physical - 0x1F80_1810) * 8);
            return @intCast((self.gpu_gpu0 >> shift) & 0xFF);
        }
        if (physical >= 0x1F80_1814 and physical <= 0x1F80_1817) {
            const shift: u5 = @intCast((physical - 0x1F80_1814) * 8);
            return @intCast((self.gpu_status >> shift) & 0xFF);
        }
        if (physical >= Ram.Start and physical <= Ram.End) {
            const offset: usize = @intCast(physical - Ram.Start);
            return self.ram.data[offset];
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
        if (physical >= Spu.Start and physical <= Spu.End) {
            const offset: usize = @intCast(physical - Spu.Start);
            return self.spu_regs[offset];
        }
        if (physical >= Cdrom.Start and physical <= Cdrom.End) {
            const offset: usize = @intCast(physical - Cdrom.Start);
            if (offset == 0) return 0x18;
            return self.cdrom_regs[offset];
        }

        std.debug.panic("Unhandled read8 at 0x{X:0>8}", .{address});
    }
    pub fn read16(self: *Bus, address: u32) u16 {
        var bytes: [2]u8 = undefined;
        bytes[0] = self.read8(address);
        bytes[1] = self.read8(address + 1);
        return std.mem.readInt(u16, &bytes, .little);
    }
    pub fn read32(self: *Bus, address: u32) u32 {
        var bytes: [4]u8 = undefined;
        bytes[0] = self.read8(address);
        bytes[1] = self.read8(address + 1);
        bytes[2] = self.read8(address + 2);
        bytes[3] = self.read8(address + 3);
        return std.mem.readInt(u32, &bytes, .little);
    }

    pub fn write8(self: *Bus, address: u32, value: u8) void {
        const physical = maskRegion(address);
        if (physical >= Ram.Start and physical <= Ram.End) {
            self.traceRamWrite(address, physical, value, 8);
            const offset: usize = @intCast(physical - Ram.Start);
            self.ram.data[offset] = value;
            return;
        }

        if (physical >= BIOS.Bios.Start and physical <= BIOS.Bios.End) {
            std.debug.panic("Attempted write8 to BIOS ROM at 0x{X:0>8}\n", .{address});
        }
        if (physical >= 0x1F80_1070 and physical <= 0x1F80_1073) {
            const shift: u5 = @intCast((physical - 0x1F80_1070) * 8);
            const mask: u32 = @as(u32, 0xFF) << shift;

            // I_STAT is usually acknowledged by writing 0 bits.
            // For now, byte-level approximation:
            self.interrupt_status =
                (self.interrupt_status & ~mask) |
                ((@as(u32, value) << shift) & mask);
            return;
        }
        if (physical >= 0x1F80_1000 and physical <= 0x1F80_10FF) {
            const offset: usize = @intCast(physical - 0x1F80_1000);
            self.memory_control_regs[offset] = value;
            return;
        }
        if (physical >= 0x1F80_1074 and physical <= 0x1F80_1077) {
            const shift: u5 = @intCast((physical - 0x1F80_1074) * 8);
            const mask: u32 = @as(u32, 0xFF) << shift;

            self.interrupt_mask =
                (self.interrupt_mask & ~mask) |
                ((@as(u32, value) << shift) & mask);
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
        if (physical >= HardwareRegisters.Start and physical <= HardwareRegisters.End) {
            return;
        }
        if (physical >= 0xfffe_0000 and physical <= 0xffff_ffff) {
            return;
        }

        std.debug.panic("Unhandled write8 at 0x{X:0>8}", .{address});
    }

    pub fn write16(self: *Bus, address: u32, value: u16) void {
        const physical = maskRegion(address);
        self.traceRamWrite(address, physical, value, 16);
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, value, .little);
        self.write8(address, bytes[0]);
        self.write8(address + 1, bytes[1]);
    }

    pub fn write32(self: *Bus, address: u32, value: u32) void {
        const physical = maskRegion(address);
        self.traceRamWrite(address, physical, value, 32);
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        self.write8(address, bytes[0]);
        self.write8(address + 1, bytes[1]);
        self.write8(address + 2, bytes[2]);
        self.write8(address + 3, bytes[3]);
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
    pub const Size: usize = 1024;
    pub const Start: u32 = 0x1f80_0000;
    pub const End: u32 = 0x1f80_03ff;
};
pub const Expansion1 = struct {
    pub const Start: u32 = 0x1f00_0000;
    pub const End: u32 = 0x1f7f_ffff;
};
pub const HardwareRegisters = struct {
    pub const Start: u32 = 0x1f80_1000;
    pub const End: u32 = 0x1f80_2fff;
};
pub const Expansion2 = struct {
    pub const Start: u32 = 0x1f80_2000;
    pub const End: u32 = 0x1f80_3fff;
};
pub const Cdrom = struct {
    pub const Start: u32 = 0x1f80_1800;
    pub const End: u32 = 0x1f80_181f;
};
