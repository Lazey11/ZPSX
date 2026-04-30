const std = @import("std");
const C = @import("C");
const display = @import("display.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");
const bus_f = @import("Memory.zig");
const cpu_f = @import("cpu.zig");
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    // initialisation of variables
    var sdl = display.SDL{};
    var config: display.displayConfig = undefined;
    var emu_state: display.EmuState = .RUNNING;
    try debug.getInput(init);
    try display.displaySetConfig(&config);
    try display.SDL_INIT(&sdl, &config);
    defer display.cleanup(&sdl) catch {};

    // load bios
    const bus = bus_f.Bus.init(allocator);
    defer bus.deinit();

    const args = try init.minimal.args.toSlice(allocator);
    try bus.loadBios(init.io, args[1]);

    // cpu init
    var cpu = cpu_f.Cpu.init(bus);
    defer cpu.deinit();
    // main loop
    while (emu_state != .Quit) {
        try controls.inputControls(&emu_state);
        cpu.step();
        try display.clearScreen(&sdl, config);

        try display.updateScreen(&sdl, &config);

        C.SDL_Delay(16);
    }
}
