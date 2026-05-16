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

fn parseGpuCrc(args: []const []const u8) bool {
    return hasArg(args, "--gpu-crc");
}

fn parseDumpVramPath(args: []const []const u8) !?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--dump-vram")) {
            if (i + 1 >= args.len) return error.MissingDumpVramPath;
            return args[i + 1];
        }
    }

    return null;
}

fn parseDumpDisplayPath(args: []const []const u8) !?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--dump-display")) {
            if (i + 1 >= args.len) return error.MissingDumpDisplayPath;
            return args[i + 1];
        }
    }

    return null;
}

fn programPath(args: []const []const u8) ?[]const u8 {
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--frames") or
            std.mem.eql(u8, args[i], "--dump-vram") or
            std.mem.eql(u8, args[i], "--dump-display"))
        {
            i += 1;
            continue;
        }

        if (std.mem.startsWith(u8, args[i], "--")) {
            continue;
        }

        return args[i];
    }

    return null;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) {
        std.debug.print("usage: ZPSX <bios.bin> [program.exe] [--headless] [--frames N] [--gpu-crc] [--dump-vram out.ppm]\n", .{});
        return;
    }

    const headless = hasArg(args, "--headless");
    const frame_limit = try parseFrames(args);
    const print_gpu_crc = parseGpuCrc(args);
    const dump_vram_path = try parseDumpVramPath(args);
    const dump_display_path = try parseDumpDisplayPath(args);
    const program_path = programPath(args);
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

    const delayed_exe_load = if (program_path) |path|
        try psxexe.shouldDelayLoad(init.io, path)
    else
        false;

    if (!delayed_exe_load) {
        if (program_path) |path| {
            try psxexe.loadPsExe(allocator, init.io, bus, &cpu, path);
            loaded_exe = true;
        }
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
            if (program_path) |path| {
                try psxexe.loadPsExe(allocator, init.io, bus, &cpu, path);
                loaded_exe = true;
            }
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
    if (print_gpu_crc) {
        std.debug.print("GPU VRAM CRC32: 0x{X:0>8}\n", .{bus.gpu.vramCrc32()});
    }

    if (dump_vram_path) |path| {
        try std.Io.Dir.cwd().createDirPath(init.io, "ppm");

        const file = try std.Io.Dir.cwd().createFile(init.io, path, .{});
        defer file.close(init.io);

        try bus.gpu.writeVramPpm(init.io, file);
    }

    if (dump_display_path) |path| {
        if (std.fs.path.dirname(path)) |dir| {
            try std.Io.Dir.cwd().createDirPath(init.io, dir);
        }

        const file = try std.Io.Dir.cwd().createFile(init.io, path, .{});
        defer file.close(init.io);

        try bus.gpu.writeDisplayPpm(init.io, file);
    }
}
