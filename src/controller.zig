const std = @import("std");
pub const Button = enum(u16) {
    Select = 1 << 0,
    L3 = 1 << 1,
    R3 = 1 << 2,
    Start = 1 << 3,
    Up = 1 << 4,
    Right = 1 << 5,
    Down = 1 << 6,
    Left = 1 << 7,
    L2 = 1 << 8,
    R2 = 1 << 9,
    L1 = 1 << 10,
    R1 = 1 << 11,
    Triangle = 1 << 12,
    Circle = 1 << 13,
    Cross = 1 << 14,
    Square = 1 << 15,
};

pub const Controller = struct {
    buttons: u16 = 0xFFFF,

    joy_mode: u16 = 0,
    joy_ctrl: u16 = 0,
    joy_baud: u16 = 0,

    response: [8]u8 = [_]u8{0} ** 8,
    response_len: u8 = 0,
    response_index: u8 = 0,

    selected: bool = false,

    pub fn setButton(self: *Controller, button: Button, pressed: bool) void {
        const mask = @intFromEnum(button);

        if (pressed) {
            self.buttons &= ~mask;
        } else {
            self.buttons |= mask;
        }
    }
    pub fn writeData(self: *Controller, value: u8) void {
        std.debug.print("JOY writeData value=0x{X:0>2} selected={}\n", .{ value, self.selected });
        if (!self.selected) return;

        if (value == 0x01) {
            self.response = [_]u8{0} ** 8;
            self.response_len = 0;
            self.response_index = 0;

            self.pushResponse(0xFF);
            return;
        }
        if (value == 0x42) {
            self.response = [_]u8{0} ** 8;
            self.response_len = 0;
            self.response_index = 0;

            self.pushResponse(0x41);
            self.pushResponse(0x5A);
            self.pushResponse(@intCast(self.buttons & 0x00FF));
            self.pushResponse(@intCast((self.buttons >> 8) & 0x00FF));
            return;
        }
    }
    pub fn readData(self: *Controller) u8 {
        const value: u8 = if (!self.selected) 0xFF else blk: {
            if (self.response_index < self.response_len) {
                const v = self.response[self.response_index];
                self.response_index += 1;
                break :blk v;
            }
            break :blk 0xFF;
        };

        std.debug.print(
            "JOY readData value=0x{X:0>2} index={} len={} selected={}\n",
            .{ value, self.response_index, self.response_len, self.selected },
        );

        return value;
    }

    pub fn readStat(self: *const Controller) u16 {
        _ = self;
        return 0x0007;
    }

    pub fn writeCtrl(self: *Controller, value: u16) void {
        std.debug.print("JOY writeCtrl value=0x{X:0>4}\n", .{value});

        self.joy_ctrl = value;
        self.selected = (value & 0x0002) != 0;

        if ((value & 0x0040) != 0) {
            self.response_len = 0;
            self.response_index = 0;
        }
    }

    pub fn readCtrl(self: *const Controller) u16 {
        return self.joy_ctrl;
    }

    pub fn writeMode(self: *Controller, value: u16) void {
        self.joy_mode = value;
    }

    pub fn readMode(self: *const Controller) u16 {
        return self.joy_mode;
    }

    pub fn writeBaud(self: *Controller, value: u16) void {
        self.joy_baud = value;
    }

    pub fn readBaud(self: *const Controller) u16 {
        return self.joy_baud;
    }

    fn pushResponse(self: *Controller, value: u8) void {
        if (self.response_len >= self.response.len) return;
        self.response[self.response_len] = value;
        self.response_len += 1;
    }
};
