const std = @import("std");
const C = @import("C");
const display = @import("display.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");
const bus_f = @import("Memory.zig");
const cpu_f = @import("cpu.zig");
const gpu_f = @import("gpu.zig");
const psxexe = @import("psxexe.zig");
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    // initialisation of variables
    var sdl = display.SDL{};
    var config: display.displayConfig = undefined;
    var emu_state: display.EmuState = .RUNNING;
    try display.displaySetConfig(&config);
    try display.SDL_INIT(&sdl, &config);
    const debug_enabled = try debug.getInput(init);
    defer display.cleanup(&sdl) catch {};

    // load bios
    const bus = bus_f.Bus.init(allocator);
    defer bus.deinit();

    const args = try init.minimal.args.toSlice(allocator);
    try bus.loadBios(init.io, args[1]);
    var loaded_exe = false;
    // cpu init
    var cpu = cpu_f.Cpu.init(bus);
    defer cpu.deinit();

    //gpu init
    var dumped_vram = false;
    // main loop
    while (emu_state != .Quit) {
        try controls.inputControls(&emu_state);

        var i: usize = 0;
        while (i < 100_000) : (i += 1) {
            cpu.step(debug_enabled);
        }
        if (!loaded_exe and cpu.current_pc >= 0x8000_0000 and cpu.instruction_count > 5_000_000) {
            try psxexe.loadPsExe(allocator, init.io, bus, &cpu, args[2]);
            loaded_exe = true;
        }

        if (!dumped_vram and
            bus.gpu.gp0_mode == 0 and
            bus.gpu.image_w == 60 and
            bus.gpu.image_h == 48 and
            bus.gpu.image_index >= 2880)
        {
            try bus.gpu.dumpVramRectPPM("vram_832_0.ppm", init.io, 832, 0, 60, 48);
            dumped_vram = true;

            std.debug.print(
                "Dumped VRAM rect to vram_640_0.ppm image_index={} mode={}\n",
                .{ bus.gpu.image_index, bus.gpu.gp0_mode },
            );
        }

        if (!dumped_vram and bus.gpu.debug_dump_640_ready) {
            try bus.gpu.dumpVramRectPPM("vram_640_0.ppm", init.io, 640, 0, 60, 48);
            dumped_vram = true;

            std.debug.print("Dumped VRAM rect to vram_640_0.ppm\n", .{});
        }

        try display.clearScreen(&sdl, config);
        try display.updateScreen(&sdl, &config);

        C.SDL_Delay(16);
    }
}
