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

    transaction_active: bool = false,
    phase: u8 = 0,

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
        if (!self.selected) {
            self.transaction_active = false;
            self.phase = 0;
            return;
        }

        switch (value) {
            0x01 => {
                self.transaction_active = true;
                self.phase = 0;
            },

            0x42 => {
                self.transaction_active = true;
                self.phase = 1;
            },

            else => {},
        }
    }
    pub fn readData(self: *Controller) u8 {
        if (!self.selected or !self.transaction_active) {
            return 0xFF;
        }

        const value: u8 = switch (self.phase) {
            0 => 0xFF,
            1 => 0x41,
            2 => 0x5A,
            3 => @intCast(self.buttons & 0x00FF),
            4 => @intCast((self.buttons >> 8) & 0x00FF),
            else => 0xFF,
        };

        self.phase +%= 1;

        if (self.phase > 5) {
            self.transaction_active = false;
            self.phase = 0;
        }

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
        self.joy_ctrl = value;
        self.selected = (value & 0x0002) != 0;

        if ((value & 0x0040) != 0) {
            self.transaction_active = false;
            self.phase = 0;
        }
    }

    pub fn readBaud(self: *const Controller) u16 {
        return self.joy_baud;
    }

    pub fn writeBaud(self: *Controller, value: u16) void {
        self.joy_baud = value;
    }
};
