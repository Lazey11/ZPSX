const std = @import("std");

pub const Cdrom = struct {
    allocator: std.mem.Allocator,
    data: []u8 = &[_]u8{},

    pub fn init(allocator: std.mem.Allocator) Cdrom {
        return .{
            .allocator = allocator,
            .data = &[_]u8{},
        };
    }

    pub fn deinit(self: *Cdrom) void {
        if (self.data.len != 0) {
            self.allocator.free(self.data);
            self.data = &[_]u8{};
        }
    }

    pub fn loadBin(self: *Cdrom, io: std.Io, path: []const u8) !void {
        if (self.data.len != 0) {
            self.allocator.free(self.data);
            self.data = &[_]u8{};
        }

        var file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);

        const stat = try file.stat(io);
        const size: usize = @intCast(stat.size);

        self.data = try self.allocator.alloc(u8, size);
        errdefer {
            self.allocator.free(self.data);
            self.data = &[_]u8{};
        }
        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);
        const reader = &file_reader.interface;

        try reader.readSliceAll(self.data);
    }
};
