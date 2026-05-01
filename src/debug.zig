const std = @import("std");
const cpu_f = @import("cpu.zig");
const debugPanic = std.debug.panic;
const debugPrint = std.debug.print;

pub fn getInput(init: std.process.Init) !bool {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            debugPrint("Debug Works!\n", .{});
            return true;
        }
    }
    return false;
}

pub fn instructionTrace(cpu: *const cpu_f.Cpu, instr: cpu_f.Instruction) void {
    debugPrint(
        "PC=0x{X:0>8} RAW=0x{X:0>8} OP=0x{X}\n",
        .{ cpu.pc, instr.raw, instr.op() },
    );
}

pub fn unhandledPrimary(instr: cpu_f.Instruction) noreturn {
    debugPanic(
        "Unhandled primary opcode 0x{X} instruction 0x{X:0>8}\n",
        .{ instr.op(), instr.raw },
    );
}

pub fn unhandledSpecial(funct: cpu_f.SpecialOpcodes, instr: cpu_f.Instruction) noreturn {
    debugPanic(
        "Unhandled SPECIAL funct {} instruction 0x{X:0>8}\n",
        .{ funct, instr.raw },
    );
}
pub fn unknownSpecial(instr: cpu_f.Instruction) noreturn {
    debugPanic(
        "Unknown SPECIAL funct 0x{X} instruction 0x{X:0>8}\n",
        .{ instr.funct(), instr.raw },
    );
}
pub fn cpuDebug(cpu: *const cpu_f.Cpu) void {
    debugPrint(
        "NEXT=0x{X:0>8} R8=0x{X:0>8} R9=0x{X:0>8} SP=0x{X:0>8} RA=0x{X:0>8}\n",
        .{
            cpu.pc_next,
            cpu.regs[8],
            cpu.regs[9],
            cpu.regs[29],
            cpu.regs[31],
        },
    );
}

pub const BIOSError = error{
    InvalidBiosSize,
    FileReadError,
};
