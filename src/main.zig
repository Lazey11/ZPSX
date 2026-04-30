const std = @import("std");
const C = @import("C");
const display = @import("display.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");

pub fn main(init: std.process.Init) !void {

    // initialisation of variables
    var sdl = display.SDL{};
    var config: display.displayConfig = undefined;
    var emu_state: display.EmuState = .RUNNING;
    try debug.getInput(init);
    try display.displaySetConfig(&config);
    try display.SDL_INIT(&sdl, &config);
    defer display.cleanup(&sdl) catch {};
    // main loop
    while (emu_state != .Quit) {
        try controls.inputControls(&emu_state);

        try display.clearScreen(&sdl, config);

        try display.updateScreen(&sdl, &config);

        C.SDL_Delay(16);
    }
}
