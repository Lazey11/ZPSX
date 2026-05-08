const std = @import("std");
const Bus = @import("Memory.zig");
const Cpu = @import("cpu.zig");

fn readLe32(data: []const u8, off: usize) u32 {
    return @as(u32, data[off]) |
        (@as(u32, data[off + 1]) << 8) |
        (@as(u32, data[off + 2]) << 16) |
        (@as(u32, data[off + 3]) << 24);
}

pub fn loadPsExe(
    allocator: std.mem.Allocator,
    io: std.Io,
    bus: *Bus.Bus,
    cpu: *Cpu.Cpu,
    path: []const u8,
) !void {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    const data = try allocator.alloc(u8, @intCast(stat.size));
    defer allocator.free(data);

    var reader_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &reader_buffer);
    const reader = &file_reader.interface;
    try reader.readSliceAll(data);

    if (data.len < 0x800) return error.BadPsExe;
    if (!std.mem.eql(u8, data[0..8], "PS-X EXE")) return error.BadPsExeMagic;

    const initial_pc = readLe32(data, 0x10);
    const dest = readLe32(data, 0x18);
    const size = readLe32(data, 0x1C);
    const sp_base = readLe32(data, 0x30);
    const sp_offset = readLe32(data, 0x34);

    if (0x800 + size > data.len) return error.BadPsExeSize;

    var i: u32 = 0;
    while (i < size) : (i += 1) {
        const addr = Bus.maskRegion(dest +% i);
        bus.ramWrite8Physical(addr, data[0x800 + i]);
    }

    cpu.pc = initial_pc;
    cpu.pc_next = initial_pc +% 4;
    cpu.current_pc = initial_pc;

    cpu.regs = [_]u32{0} ** 32;
    cpu.hi = 0;
    cpu.lo = 0;

    if (sp_base != 0) {
        cpu.regs[29] = sp_base +% sp_offset;
    }

    std.debug.print(
        "Loaded PS-EXE {s}: pc=0x{X:0>8} dest=0x{X:0>8} size=0x{X} sp=0x{X:0>8}\n",
        .{ path, initial_pc, dest, size, cpu.regs[29] },
    );
}
