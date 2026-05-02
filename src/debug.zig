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

pub fn unhandledCop0(instr: cpu_f.Instruction) noreturn {
    debugPanic(
        "Unhandled COP0 rs=0x{X} rd={} rt={} instruction 0x{X:0>8}\n",
        .{ instr.rs(), instr.rd(), instr.rt(), instr.raw },
    );
}

pub fn cpuDebug(cpu: *const cpu_f.Cpu) void {
    debugPrint(
        "NEXT=0x{X:0>8} R1=0x{X:0>8} R2=0x{X:0>8} R3=0x{X:0>8} R4=0x{X:0>8} R6=0x{X:0>8} R7=0x{X:0>8} R8=0x{X:0>8} R9=0x{X:0>8} R10=0x{X:0>8} R11=0x{X:0>8} R26=0x{X:0>8} SP=0x{X:0>8} RA=0x{X:0>8}\n",
        .{
            cpu.pc_next,
            cpu.regs[1],
            cpu.regs[2],
            cpu.regs[3],
            cpu.regs[4],
            cpu.regs[6],
            cpu.regs[7],
            cpu.regs[8],
            cpu.regs[9],
            cpu.regs[10],
            cpu.regs[11],
            cpu.regs[26], // R26 / k0
            cpu.regs[29], // SP
            cpu.regs[31], // RA
        },
    );
}
pub fn instructionTraceAt(pc: u32, instr: cpu_f.Instruction) void {
    debugPrint(
        "PC=0x{X:0>8} RAW=0x{X:0>8} OP=0x{X}\n",
        .{ pc, instr.raw, instr.op() },
    );
}

pub const BIOSError = error{
    InvalidBiosSize,
    FileReadError,
};
