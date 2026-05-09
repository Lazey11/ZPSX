const std = @import("std");

pub const Button = enum {
    Select,
    Start,
    Up,
    Right,
    Down,
    Left,
    L2,
    R2,
    L1,
    R1,
    Triangle,
    Circle,
    Cross,
    Square,
};

pub const Controller = struct {
    buttons: u16 = 0xFFFF,

    joy_mode: u16 = 0,
    joy_ctrl: u16 = 0,
    joy_baud: u16 = 0,

    selected: bool = false,
    read_index: u8 = 0,

    pub fn setButton(self: *Controller, button: Button, pressed: bool) void {
        const mask: u16 = switch (button) {
            .Select => 1 << 0,
            .Start => 1 << 3,
            .Up => 1 << 4,
            .Right => 1 << 5,
            .Down => 1 << 6,
            .Left => 1 << 7,
            .L2 => 1 << 8,
            .R2 => 1 << 9,
            .L1 => 1 << 10,
            .R1 => 1 << 11,
            .Triangle => 1 << 12,
            .Circle => 1 << 13,
            .Cross => 1 << 14,
            .Square => 1 << 15,
        };

        if (pressed) {
            self.buttons &= ~mask;
        } else {
            self.buttons |= mask;
        }
    }

    pub fn writeData(self: *Controller, value: u8) void {
        if (value == 0x01 and self.read_index >= 5) {
            self.read_index = 0;
        }
    }

    pub fn readData(self: *Controller) u8 {
        const value: u8 = switch (self.read_index) {
            0 => 0xFF,
            1 => 0x41,
            2 => 0x5A,
            3 => @intCast(self.buttons & 0x00FF),
            4 => @intCast((self.buttons >> 8) & 0x00FF),
            else => 0xFF,
        };

        //std.debug.print(
        //  .{ value, self.read_index, self.selected },
        // );

        self.read_index +%= 1;
        return value;
    }

    pub fn readStat(self: *Controller) u16 {
        _ = self;

        // TX ready + RX available + TX idle + ACK-ish.
        return 0x0087;
    }

    pub fn readMode(self: *const Controller) u16 {
        return self.joy_mode;
    }

    pub fn writeMode(self: *Controller, value: u16) void {
        self.joy_mode = value;
    }

    pub fn readCtrl(self: *const Controller) u16 {
        return self.joy_ctrl;
    }

    pub fn writeCtrl(self: *Controller, value: u16) void {
        //std.debug.print("JOY writeCtrl value=0x{X:0>4}\n", .{value});

        self.joy_ctrl = value;
        self.selected = (value & 0x0002) != 0;

        // if ((value & 0x0040) != 0) {
        //     self.read_index = 0;
        // }
    }

    pub fn readBaud(self: *const Controller) u16 {
        return self.joy_baud;
    }

    pub fn writeBaud(self: *Controller, value: u16) void {
        self.joy_baud = value;
    }
};
