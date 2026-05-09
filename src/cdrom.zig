const std = @import("std");
const debug_f = @import("debug.zig");

pub const Cdrom = struct {
    index: u8 = 0,
    status: u8 = 0x18,
    interrupt_enable: u8 = 0,
    interrupt_flag: u8 = 0,
    response_fifo: [16]u8 = [_]u8{0} ** 16,
    response_len: u8 = 0,
    response_index: u8 = 0,

    parameter_fifo: [16]u8 = [_]u8{0} ** 16,
    parameter_len: u8 = 0,
    parameter_index: u8 = 0,

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

    pub fn readRegister(self: *Cdrom, offset: u2) u8 {
        return switch (offset) {
            0 => (self.status & 0xFC) | (self.index & 0x03),
            1 => self.popResponse(),
            2 => self.interrupt_enable,
            3 => self.interrupt_flag,
        };
    }

    pub fn writeRegister(self: *Cdrom, offset: u2, value: u8) void {
        switch (offset) {
            0 => self.index = value & 0x03,
            1 => self.command(value),
            2 => {
                if (self.index == 0) {
                    self.pushParameter(value);
                } else {
                    self.interrupt_enable = value;
                }
            },
            3 => self.interrupt_flag &= ~value,
        }
    }

    fn clearResponse(self: *Cdrom) void {
        self.response_len = 0;
        self.response_index = 0;
    }

    fn pushResponse(self: *Cdrom, value: u8) void {
        if (self.response_len >= self.response_fifo.len) return;
        self.response_fifo[self.response_len] = value;
        self.response_len += 1;
    }

    fn popResponse(self: *Cdrom) u8 {
        if (self.response_index >= self.response_len) return 0x00;
        const value = self.response_fifo[self.response_index];
        self.response_index += 1;
        return value;
    }

    fn clearParameters(self: *Cdrom) void {
        self.parameter_len = 0;
        self.parameter_index = 0;
    }
    fn pushParameter(self: *Cdrom, value: u8) void {
        if (self.parameter_len >= self.parameter_fifo.len) return;
        self.parameter_fifo[self.parameter_len] = value;
        self.parameter_len += 1;
    }
    fn popParameter(self: *Cdrom) u8 {
        if (self.parameter_index >= self.parameter_len) return 0;
        const value = self.parameter_fifo[self.parameter_index];
        self.parameter_index += 1;
        return value;
    }

    fn command(self: *Cdrom, value: u8) void {
        self.clearResponse();
        self.clearParameters();

        switch (value) {
            0x01 => {
                self.pushResponse(0x02);
                self.interrupt_flag |= 0x03;
            },
            0x02 => {
                _ = self.popParameter();
                _ = self.popParameter();
                _ = self.popParameter();

                self.pushResponse(0x02);
                self.interrupt_flag |= 0x03;
            },
            0x06 => {
                self.pushResponse(0x02);
                self.interrupt_flag |= 0x03;
            },
            0x09 => {
                self.pushResponse(0x02);
                self.interrupt_flag |= 0x03;
            },
            0x0A => {
                self.pushResponse(0x02);
                self.interrupt_flag |= 0x03;
            },
            0x19 => {
                self.pushResponse(0x94);
                self.pushResponse(0x09);
                self.pushResponse(0x19);
                self.pushResponse(0xC0);
                self.interrupt_flag |= 0x03;
            },
            0x1A => {
                self.pushResponse(0x02);
                self.pushResponse(0x00);
                self.pushResponse(0x20);
                self.pushResponse(0x00);
                self.pushResponse(0x53);
                self.pushResponse(0x43);
                self.pushResponse(0x45);
                self.pushResponse(0x41);
                self.interrupt_flag |= 0x03;
            },
            else => {
                if (debug_f.enable_cdrom_trace) {
                    std.debug.print(
                        "CDROM unknown command=0x{X:0>2} params_len={}\n",
                        .{ value, self.parameter_len },
                    );
                }
                self.pushResponse(0x00);
                self.interrupt_flag |= 0x05;
            },
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
