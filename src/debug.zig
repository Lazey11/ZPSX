const std = @import("std");
const debugPrint = std.debug.print;

pub fn getInput(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            debugPrint("Debug Works!", .{});
            return;
        }
    }
}
