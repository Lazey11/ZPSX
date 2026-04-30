const std = @import("std");
const Bus = @import("Memory.zig");

pub const PrimaryOpcodes = enum(u6) {
    SPECIAL = 0x00,
    REGIMM = 0x01,
    J = 0x02,
    JAL = 0x03,
    BEQ = 0x04,
    BNE = 0x05,
    BLEZ = 0x06,
    BGTZ = 0x07,
    ADDI = 0x08,
    ADDIU = 0x09,
    SLTI = 0x0A,
    SLTIU = 0x0B,
    ANDI = 0x0C,
    ORI = 0x0D,
    XORI = 0x0E,
    LUI = 0x0F,
    COP0 = 0x10,
    COP1 = 0x11,
    COP2 = 0x12,
    COP3 = 0x13,
    LB = 0x20,
    LH = 0x21,
    LWL = 0x22,
    LW = 0x23,
    LBU = 0x24,
    LHU = 0x25,
    LWR = 0x26,
    SB = 0x28,
    SH = 0x29,
    SWL = 0x2A,
    SW = 0x2B,
    SWR = 0x2E,
    LWC0 = 0x30,
    LWC1 = 0x31,
    LWC2 = 0x32,
    LWC3 = 0x33,
    SWC0 = 0x38,
    SWC1 = 0x39,
    SWC2 = 0x3A,
    SWC3 = 0x3B,
};
pub const SpecialOpcodes = enum(u6) {
    SLL = 0x00,
    SRL = 0x02,
    SRA = 0x03,
    SLLV = 0x04,
    SRLV = 0x06,
    SRAV = 0x07,
    JR = 0x08,
    JALR = 0x09,
    SYSCALL = 0x0C,
    BREAK = 0x0D,
    MFHI = 0x10,
    MTHI = 0x11,
    MFLO = 0x12,
    MTLO = 0x13,
    MULT = 0x18,
    MULTU = 0x19,
    DIV = 0x1A,
    DIVU = 0x1B,
    ADD = 0x20,
    ADDU = 0x21,
    SUB = 0x22,
    SUBU = 0x23,
    AND = 0x24,
    OR = 0x25,
    XOR = 0x26,
    NOR = 0x27,
    SLT = 0x2A,
    SLTU = 0x2B,
};

pub const RegimmOpcode = enum(u5) {
    BLTZ = 0x00,
    BGEZ = 0x01,
    BLTZAL = 0x10,
    BGEZAL = 0x11,
};
pub const COP0Opcode = enum(u5) {
    MFC0 = 0x00,
    CFC0 = 0x02,
    MTC0 = 0x04,
    CTC0 = 0x06,
    BC0 = 0x08,
    RFE = 0x10,
};

pub const Instruction = struct {
    raw: u32,

    pub fn op(self: Instruction) u6 {
        return @intCast((self.raw >> 26) & 0x3F);
    }
    pub fn rs(self: Instruction) u5 {
        return @intCast((self.raw >> 21) & 0x1F);
    }
    pub fn rt(self: Instruction) u5 {
        return @intCast((self.raw >> 16) & 0x1F);
    }
    pub fn rd(self: Instruction) u5 {
        return @intCast((self.raw >> 11) & 0x1F);
    }
    pub fn shamt(self: Instruction) u5 {
        return @intCast((self.raw >> 6) & 0x1F);
    }
    pub fn funct(self: Instruction) u6 {
        return @intCast(self.raw & 0x3F);
    }
    pub fn imm(self: Instruction) u16 {
        return @intCast(self.raw & 0xFFFF);
    }
    pub fn target(self: Instruction) u26 {
        return @intCast(self.raw & 0x03FF_FFFF);
    }
};
pub const Cpu = struct {
    regs: [32]u32 = [_]u32{0} ** 32,

    hi: u32 = 0,
    lo: u32 = 0,

    pc: u32 = 0xbfc0_0000,
    pc_next: u32 = 0xbfc0_0004,

    bus: *Bus.Bus,
    pub fn init(bus: *Bus.Bus) @This() {
        return .{
            .bus = bus,
        };
    }
    pub fn step(self: *@This()) void {
        const current_pc = self.pc;
        const raw = self.bus.read32(current_pc);
        const instr = Instruction{ .raw = raw };

        std.debug.print("PC=0x{X:0>8} RAW=0x{X:0>8}\n", .{ current_pc, raw });

        self.pc = self.pc_next;
        self.pc_next +%= 4;
        self.execute(instr);
        self.regs[0] = 0;
    }
    pub fn execute(self: *@This(), instr: Instruction) void {
        switch (instr.op()) {
            @intFromEnum(PrimaryOpcodes.LUI) => self.opLui(instr),

            else => std.debug.panic("Unhandled opcode 0x{X} instruction 0x{X:0>8}\n", .{
                instr.op(),
                instr.raw,
            }),
        }
    }
    pub fn opLui(self: *@This(), instr: Instruction) void {
        const rt: usize = @intCast(instr.rt());
        self.regs[rt] = @as(u32, instr.imm()) << 16;
    }
    pub fn deinit(self: *@This()) void {
        _ = self;
    }
};
