const std = @import("std");
const C = @import("C");
const display = @import("display.zig");
const controls = @import("controls.zig");
const bus_f = @import("Memory.zig");
const cpu_f = @import("cpu.zig");

const steps_per_frame: usize = 565_000;
const enable_fps_log = false;
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var sdl = display.SDL{};
    var config: display.displayConfig = undefined;
    var emu_state: display.EmuState = .RUNNING;

    try display.displaySetConfig(&config);
    try display.SDL_INIT(&sdl, &config);
    defer display.cleanup(&sdl) catch {};

    const bus = bus_f.Bus.init(allocator);
    defer bus.deinit();

    const args = try init.minimal.args.toSlice(allocator);
    try bus.loadBios(init.io, args[1]);

    var cpu = cpu_f.Cpu.init(bus);
    defer cpu.deinit();

    var fps_frame_count: u32 = 0;
    var fps_last_time_ms: u64 = C.SDL_GetTicks();
    var fps_last_instruction_count: u64 = cpu.instruction_count;

    while (emu_state != .Quit) {
        try controls.inputControls(&emu_state);

        var i: usize = 0;
        while (i < steps_per_frame) : (i += 1) {
            cpu.step(false);
        }

        try display.clearScreen(&sdl, config);
        try display.drawVramToScreen(&sdl, &config, &bus.gpu);
        try display.updateScreen(&sdl, &config);
        if (enable_fps_log) {
            fps_frame_count += 1;
            const now_ms: u64 = C.SDL_GetTicks();
            const elapsed_ms = now_ms - fps_last_time_ms;

            if (elapsed_ms >= 1000) {
                const instruction_delta = cpu.instruction_count - fps_last_instruction_count;
                const instr_per_sec = (instruction_delta * 1000) / elapsed_ms;

                std.debug.print(
                    "FPS={} elapsed_ms={} instr_per_sec={} total_instr={}\n",
                    .{ fps_frame_count, elapsed_ms, instr_per_sec, cpu.instruction_count },
                );

                fps_frame_count = 0;
                fps_last_time_ms = now_ms;
                fps_last_instruction_count = cpu.instruction_count;
            }
        }

        C.SDL_Delay(16);
    }
}
