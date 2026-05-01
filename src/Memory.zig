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

    pub fn read8(self: *Bus, address: u32) u8 {
        const physical = maskRegion(address);

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
            const offset: usize = @intCast(physical - Ram.Start);
            self.ram.data[offset] = value;
            return;
        }

        if (physical >= BIOS.Bios.Start and physical <= BIOS.Bios.End) {
            std.debug.panic("Attempted write8 to BIOS ROM at 0x{X:0>8}", .{address});
        }

        std.debug.panic("Unhandled write8 at 0x{X:0>8}", .{address});
    }

    pub fn write16(self: *Bus, address: u32, value: u16) void {
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, value, .little);
        self.write8(address, bytes[0]);
        self.write8(address + 1, bytes[1]);
    }
    pub fn write32(self: *Bus, address: u32, value: u32) void {
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
    pub const End: u32 = 0x1f80_1803;
};
