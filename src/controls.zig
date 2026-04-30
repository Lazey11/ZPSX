const C = @import("C");
const display = @import("display.zig");

pub fn inputControls(emu_state: *display.EmuState) !void {
    var event: C.SDL_Event = undefined;

    while (C.SDL_PollEvent(&event)) {
        switch (event.type) {
            C.SDL_EVENT_QUIT,
            C.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
            => {
                emu_state.* = .Quit;
            },
            else => {},
        }
    }
}
