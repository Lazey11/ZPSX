const std = @import("std");
const C = @import("C");
const display = @import("display.zig");
const controls = @import("controls.zig");
const bus_f = @import("Memory.zig");
const cpu_f = @import("cpu.zig");
const psxexe = @import("psxexe.zig");

const steps_per_frame: usize = @intCast(bus_f.CPU_CYCLES_PER_FRAME);
const exe_load_after_instructions: u64 = 25_000_000;
const enable_fps_log = false;

fn hasArg(args: []const []const u8, name: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, name)) return true;
    }
    return false;
}

fn parseFrames(args: []const []const u8) !?u64 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--frames")) {
            if (i + 1 >= args.len) return error.MissingFrameCount;
            return try std.fmt.parseInt(u64, args[i + 1], 10);
        }
    }
    return null;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) {
        std.debug.print("usage: ZPSX <bios.bin> [program.exe] [--headless] [--frames N]\n", .{});
        return;
    }

    const headless = hasArg(args, "--headless");
    const frame_limit = try parseFrames(args);

    var sdl = display.SDL{};
    var config: display.displayConfig = undefined;
    var emu_state: display.EmuState = .RUNNING;

    if (!headless) {
        try display.displaySetConfig(&config);
        try display.SDL_INIT(&sdl, &config);
    }
    defer {
        if (!headless) {
            display.cleanup(&sdl) catch {};
        }
    }

    const bus = bus_f.Bus.init(allocator);
    defer bus.deinit();

    try bus.loadBios(init.io, args[1]);

    var cpu = cpu_f.Cpu.init(bus);
    defer cpu.deinit();

    var loaded_exe = false;

    const delayed_exe_load = if (args.len >= 3)
        try psxexe.shouldDelayLoad(init.io, args[2])
    else
        false;

    if (!delayed_exe_load and args.len >= 3) {
        try psxexe.loadPsExe(allocator, init.io, bus, &cpu, args[2]);
        loaded_exe = true;
    }

    var fps_frame_count: u32 = 0;
    var fps_last_time_ms: u64 = C.SDL_GetTicks();
    var fps_last_instruction_count: u64 = cpu.instruction_count;

    var frames_run: u64 = 0;

    while (emu_state != .Quit) {
        if (!headless) {
            try controls.inputControls(&emu_state, bus);
        }

        var i: usize = 0;
        while (i < steps_per_frame) : (i += 1) {
            cpu.step(false);
        }

        if (delayed_exe_load and !loaded_exe and cpu.instruction_count >= exe_load_after_instructions) {
            try psxexe.loadPsExe(allocator, init.io, bus, &cpu, args[2]);
            loaded_exe = true;
        }

        if (!headless) {
            try display.clearScreen(&sdl, config);
            try display.drawVramToScreen(&sdl, &config, &bus.gpu);
            try display.updateScreen(&sdl, &config);
            C.SDL_Delay(16);
        }

        frames_run += 1;
        if (headless) {
            if (frame_limit) |limit| {
                if (frames_run >= limit) break;
            }
        }

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
    }
}
