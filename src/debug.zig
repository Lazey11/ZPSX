const std = @import("std");
const cpu_f = @import("cpu.zig");
const debugPanic = std.debug.panic;
const debugPrint = std.debug.print;
pub const enable_pc_progress_trace = false;
pub const enable_unknown_hw_trace = false;
pub const enable_dma_trace = false;
pub const enable_event_loop_trace = false;
pub const enable_event_mem_trace = false;

pub const enable_bios_loop_trace = false;
pub const enable_branch_trace = false;
pub const enable_bios_vector_trace = false;
pub const max_bios_loop_trace: u32 = 80;
pub const max_branch_trace: u32 = 80;

var bios_loop_trace_count: u32 = 0;
var branch_trace_count: u32 = 0;
pub const enable_event_core_trace = false;
pub const enable_jump_trace = false;
pub const enable_jal_trace = false;
pub const enable_jr_trace = false;
pub const enable_jalr_trace = false;

pub const enable_ram_write_trace = false;
pub const enable_irq_check_trace = false;

pub const enable_bios_copy_progress = false;
pub const enable_rfe_trace = false;
pub const enable_irq_exception_trace = false;
pub const enable_irq_register_trace = false;

pub const enable_status_watch_trace = false;
pub const enable_mtc0_trace = false;
pub const enable_loop59_trace = false;
pub const enable_gpu_loop59_trace = false;
pub const enable_loop541_trace = false;
pub const enable_a100_trace = false;

pub const enable_cdrom_trace = false;

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
        .{ cpu.current_pc, instr.raw, instr.op() },
    );
}
pub fn branchTrace(pc: u32, raw: u32, taken: bool, target: u32, pc_after_step: u32, pc_next_after_step: u32) void {
    if (!enable_branch_trace) return;
    if (branch_trace_count >= max_branch_trace) return;
    branch_trace_count += 1;

    debugPrint(
        "BRANCH PC=0x{X:0>8} RAW=0x{X:0>8} taken={} target=0x{X:0>8} pc=0x{X:0>8} pc_next=0x{X:0>8}\n",
        .{
            pc,
            raw,
            taken,
            target,
            pc_after_step,
            pc_next_after_step,
        },
    );
}

pub fn biosLoopTrace(cpu: *const cpu_f.Cpu, raw: u32) void {
    if (!enable_bios_loop_trace) return;

    // Only trace the suspicious BIOS byte-loop routine.
    if (!(cpu.current_pc >= 0xBFC0_2B50 and cpu.current_pc <= 0xBFC0_2B90)) return;

    if (bios_loop_trace_count >= max_bios_loop_trace) return;
    bios_loop_trace_count += 1;

    debugPrint(
        "LOOP PC=0x{X:0>8} RAW=0x{X:0>8} pc=0x{X:0>8} pc_next=0x{X:0>8} r4=0x{X:0>8} r5=0x{X:0>8} r6=0x{X:0>8} r14=0x{X:0>8} ra=0x{X:0>8}\n",
        .{
            cpu.current_pc,
            raw,
            cpu.pc,
            cpu.pc_next,
            cpu.regs[4],
            cpu.regs[5],
            cpu.regs[6],
            cpu.regs[14],
            cpu.regs[31],
        },
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
        "pc=0x{X:0>8} pc_next=0x{X:0>8} R1=0x{X:0>8} R2=0x{X:0>8} R3=0x{X:0>8} R4=0x{X:0>8} R5=0x{X:0>8} R6=0x{X:0>8} R7=0x{X:0>8} R8=0x{X:0>8} R9=0x{X:0>8} R10=0x{X:0>8} R11=0x{X:0>8} R26=0x{X:0>8} SP=0x{X:0>8} RA=0x{X:0>8}\n",
        .{
            cpu.pc,
            cpu.pc_next,
            cpu.regs[1],
            cpu.regs[2],
            cpu.regs[3],
            cpu.regs[4],
            cpu.regs[5],
            cpu.regs[6],
            cpu.regs[7],
            cpu.regs[8],
            cpu.regs[9],
            cpu.regs[10],
            cpu.regs[11],
            cpu.regs[26],
            cpu.regs[29],
            cpu.regs[31],
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
