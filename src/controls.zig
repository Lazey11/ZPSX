const std = @import("std");
const C = @import("C");
const display = @import("display.zig");
const bus_f = @import("Memory.zig");

pub fn inputControls(emu_state: *display.EmuState, bus: *bus_f.Bus) !void {
    var event: C.SDL_Event = undefined;

    while (C.SDL_PollEvent(&event)) {
        switch (event.type) {
            C.SDL_EVENT_QUIT => {
                emu_state.* = .Quit;
            },

            C.SDL_EVENT_KEY_DOWN, C.SDL_EVENT_KEY_UP => {
                const pressed = event.type == C.SDL_EVENT_KEY_DOWN;

                switch (event.key.key) {
                    C.SDLK_ESCAPE => {
                        if (pressed) emu_state.* = .Quit;
                    },

                    C.SDLK_RETURN => bus.controller.setButton(.Start, pressed),
                    C.SDLK_RSHIFT => bus.controller.setButton(.Select, pressed),

                    C.SDLK_UP => bus.controller.setButton(.Up, pressed),
                    C.SDLK_DOWN => bus.controller.setButton(.Down, pressed),
                    C.SDLK_LEFT => bus.controller.setButton(.Left, pressed),
                    C.SDLK_RIGHT => bus.controller.setButton(.Right, pressed),

                    C.SDLK_Z => bus.controller.setButton(.Cross, pressed),
                    C.SDLK_X => bus.controller.setButton(.Circle, pressed),
                    C.SDLK_A => bus.controller.setButton(.Square, pressed),
                    C.SDLK_S => bus.controller.setButton(.Triangle, pressed),

                    C.SDLK_Q => bus.controller.setButton(.L1, pressed),
                    C.SDLK_W => bus.controller.setButton(.R1, pressed),
                    C.SDLK_1 => bus.controller.setButton(.L2, pressed),
                    C.SDLK_2 => bus.controller.setButton(.R2, pressed),

                    else => {},
                }

                std.debug.print(
                    "PAD buttons=0x{X:0>4} pressed={} key={}\n",
                    .{ bus.controller.buttons, pressed, event.key.key },
                );
            },

            else => {},
        }
    }
}
