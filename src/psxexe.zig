const std = @import("std");
const bus_f = @import("Memory.zig");
const cpu_f = @import("cpu.zig");

fn readLe32(data: []const u8) u32 {
    return @as(u32, data[0]) |
        (@as(u32, data[1]) << 8) |
        (@as(u32, data[2]) << 16) |
        (@as(u32, data[3]) << 24);
}

pub fn loadPsExe(
    allocator: std.mem.Allocator,
    io: std.Io,
    bus: *bus_f.Bus,
    cpu: *cpu_f.Cpu,
    path: []const u8,
) !void {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    const file_size: usize = @intCast(stat.size);

    const file_data = try allocator.alloc(u8, file_size);
    defer allocator.free(file_data);

    var buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    const reader = &file_reader.interface;
    try reader.readSliceAll(file_data);

    if (file_data.len < 0x800) {
        return error.InvalidPsExe;
    }

    if (!std.mem.eql(u8, file_data[0..8], "PS-X EXE")) {
        return error.InvalidPsExe;
    }

    const pc = readLe32(file_data[0x10..0x14]);
    const dest = readLe32(file_data[0x18..0x1C]);
    const size = readLe32(file_data[0x1C..0x20]);
    const sp_base = readLe32(file_data[0x30..0x34]);
    const sp_offset = readLe32(file_data[0x34..0x38]);

    const payload = file_data[0x800..];
    const copy_size: usize = @min(@as(usize, @intCast(size)), payload.len);

    var i: usize = 0;
    while (i < copy_size) : (i += 1) {
        const physical = (dest & 0x001F_FFFF) + @as(u32, @intCast(i));
        bus.ramWrite8Physical(physical, payload[i]);
    }

    cpu.pc = pc;
    cpu.pc_next = pc +% 4;

    if (sp_base != 0) {
        cpu.regs[29] = sp_base +% sp_offset;
    }
    // If PS-EXE header stack is zero, keep the current CPU stack.
    // Some BIOS/libps tests rely on the BIOS/runtime stack already being valid.
    std.debug.print(
        "Loaded PS-EXE {s}: pc=0x{X:0>8} dest=0x{X:0>8} size=0x{X} sp=0x{X:0>8}\n",
        .{ path, pc, dest, size, cpu.regs[29] },
    );

    const pc_offset: usize = @intCast(pc -% dest);

    if (pc_offset + 16 <= payload.len) {
        std.debug.print(
            "EXE code at PC offset 0x{X}: {X:0>8} {X:0>8} {X:0>8} {X:0>8}\n",
            .{
                pc_offset,
                readLe32(payload[pc_offset + 0 .. pc_offset + 4]),
                readLe32(payload[pc_offset + 4 .. pc_offset + 8]),
                readLe32(payload[pc_offset + 8 .. pc_offset + 12]),
                readLe32(payload[pc_offset + 12 .. pc_offset + 16]),
            },
        );
    }
    std.debug.print(
        "RAM code at PC: {X:0>8} {X:0>8} {X:0>8} {X:0>8}\n",
        .{
            bus.read32(pc),
            bus.read32(pc + 4),
            bus.read32(pc + 8),
            bus.read32(pc + 12),
        },
    );
}
pub fn shouldDelayLoad(io: std.Io, path: []const u8) !bool {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var header: [0x800]u8 = undefined;

    var buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    const reader = &file_reader.interface;
    try reader.readSliceAll(&header);

    if (!std.mem.eql(u8, header[0..8], "PS-X EXE")) {
        return false;
    }

    const sp_base = readLe32(header[0x30..0x34]);

    // Header stack 0 usually means BIOS/libps runtime should already be initialized.
    return sp_base == 0;
}
