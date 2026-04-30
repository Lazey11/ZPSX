const std = @import("std");
const biosError = @import("debug.zig");

pub const Bios = struct {
    pub const Size: usize = 512 * 1024;
    pub const Start: u32 = 0x1fc0_0000;
    pub const End: u32 = 0x1fc7_ffff;

    allocator: std.mem.Allocator,
    rom: []u8,

    pub fn loadFromBuffer(allocator: std.mem.Allocator, buf: []const u8) !*@This() {
        if (buf.len != Size) {
            std.debug.print("Invalid BIOS size! Expected 512KB, got {}\n", .{buf.len});
            return biosError.BIOSError.InvalidBiosSize;
        }
        const rom = try allocator.alloc(u8, buf.len);
        errdefer allocator.free(rom);
        @memcpy(rom, buf);

        const self = try allocator.create(@This());
        self.* = .{
            .allocator = allocator,
            .rom = rom,
        };
        return self;
    }
    pub fn loadBios(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !*@This() {
        const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| {
            std.debug.print("Failed to open BIOS file: {}\n", .{err});
            return biosError.BIOSError.FileReadError;
        };
        defer file.close(io);

        const fileSize = file.length(io) catch |err| {
            std.debug.print("Failed to get BIOS file size: {}\n", .{err});
            return biosError.BIOSError.FileReadError;
        };
        if (fileSize != Size) {
            std.debug.print("Invalid BIOS size! Expected 512KB, got {}\n", .{fileSize});
            return biosError.BIOSError.InvalidBiosSize;
        }
        var readBuf: [4096]u8 = undefined;
        var reader = file.reader(io, &readBuf);
        const rom = reader.interface.readAlloc(allocator, Size) catch |err| {
            std.debug.print("Failed to read BIOS file: {}\n", .{err});
            return biosError.BIOSError.FileReadError;
        };
        errdefer allocator.free(rom);
        const self = try allocator.create(@This());
        self.* = .{
            .allocator = allocator,
            .rom = rom,
        };
        return self;
    }
    pub fn read8(self: *const @This(), address: u32) u8 {
        std.debug.assert(address >= Start and address <= End);
        const offset: usize = @intCast(address - Start);
        return self.rom[offset];
    }
    pub fn deinit(self: *@This()) void {
        const allocator = self.allocator;
        allocator.free(self.rom);
        allocator.destroy(self);
    }
};
