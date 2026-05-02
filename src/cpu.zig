const std = @import("std");
const Bus = @import("Memory.zig");
const debug_f = @import("debug.zig");

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

    pub fn immSigned32(self: Instruction) i32 {
        const imm_signed: i16 = @bitCast(self.imm());
        return @as(i32, imm_signed);
    }

    pub fn immSignedU32(self: Instruction) u32 {
        return @bitCast(self.immSigned32());
    }
};

pub const Cpu = struct {
    instruction_count: u64 = 0,
    current_pc: u32 = 0,

    regs: [32]u32 = [_]u32{0} ** 32,

    hi: u32 = 0,
    lo: u32 = 0,

    pc: u32 = 0xBFC0_0000,
    pc_next: u32 = 0xBFC0_0004,

    cop0: [32]u32 = [_]u32{0} ** 32,

    bus: *Bus.Bus,

    pub fn init(bus: *Bus.Bus) @This() {
        return .{
            .bus = bus,
        };
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn step(self: *@This(), debug_enabled: bool) void {
        const current_pc = self.pc;
        const raw = self.bus.read32(current_pc);
        const instr = Instruction{ .raw = raw };

        self.current_pc = current_pc;
        self.instruction_count += 1;

        if (debug_enabled and self.instruction_count % 100_000 == 0) {
            debug_f.instructionTraceAt(current_pc, instr);
            debug_f.cpuDebug(self);
        }

        self.pc = self.pc_next;
        self.pc_next +%= 4;

        self.execute(instr);

        self.regs[0] = 0;
    }

    pub fn setReg(self: *@This(), index: usize, value: u32) void {
        if (index == 0) return;

        if (index == 26) {
            std.debug.print(
                "WRITE r26/k0 at PC=0x{X:0>8}: 0x{X:0>8}\n",
                .{ self.current_pc, value },
            );
        }

        self.regs[index] = value;
    }
    fn cacheIsolated(self: *const @This()) bool {
        // COP0 Status register is r12.
        // Bit 16 is IsC / isolate cache on the R3000A.
        return (self.cop0[12] & 0x0001_0000) != 0;
    }
    pub fn execute(self: *@This(), instr: Instruction) void {
        switch (instr.op()) {
            @intFromEnum(PrimaryOpcodes.SPECIAL) => self.executeSpecial(instr),
            @intFromEnum(PrimaryOpcodes.REGIMM) => self.executeRegimm(instr),

            @intFromEnum(PrimaryOpcodes.J) => self.opJ(instr),
            @intFromEnum(PrimaryOpcodes.JAL) => self.opJal(instr),

            @intFromEnum(PrimaryOpcodes.BEQ) => self.opBeq(instr),
            @intFromEnum(PrimaryOpcodes.BNE) => self.opBne(instr),
            @intFromEnum(PrimaryOpcodes.BGTZ) => self.opBgtz(instr),
            @intFromEnum(PrimaryOpcodes.BLEZ) => self.opBlez(instr),

            @intFromEnum(PrimaryOpcodes.ADDI) => self.opAddi(instr),
            @intFromEnum(PrimaryOpcodes.ADDIU) => self.opAddiu(instr),
            @intFromEnum(PrimaryOpcodes.ANDI) => self.opAndi(instr),
            @intFromEnum(PrimaryOpcodes.ORI) => self.opOri(instr),
            @intFromEnum(PrimaryOpcodes.XORI) => self.opXori(instr),
            @intFromEnum(PrimaryOpcodes.LUI) => self.opLui(instr),

            @intFromEnum(PrimaryOpcodes.SLTI) => self.opSlti(instr),
            @intFromEnum(PrimaryOpcodes.SLTIU) => self.opSltiu(instr),

            @intFromEnum(PrimaryOpcodes.LB) => self.opLb(instr),
            @intFromEnum(PrimaryOpcodes.LBU) => self.opLbu(instr),
            @intFromEnum(PrimaryOpcodes.LH) => self.opLh(instr),
            @intFromEnum(PrimaryOpcodes.LHU) => self.opLhu(instr),
            @intFromEnum(PrimaryOpcodes.LW) => self.opLw(instr),

            @intFromEnum(PrimaryOpcodes.SB) => self.opSb(instr),
            @intFromEnum(PrimaryOpcodes.SH) => self.opSh(instr),
            @intFromEnum(PrimaryOpcodes.SW) => self.opSw(instr),

            @intFromEnum(PrimaryOpcodes.COP0) => self.executeCop0(instr),

            else => debug_f.unhandledPrimary(instr),
        }
    }

    pub fn executeSpecial(self: *@This(), instr: Instruction) void {
        const funct = std.enums.fromInt(SpecialOpcodes, instr.funct()) orelse {
            debug_f.unknownSpecial(instr);
        };

        switch (funct) {
            .SYSCALL => self.opSyscall(instr),
            .BREAK => self.opBreak(instr),

            .SLL => self.opSll(instr),
            .SRL => self.opSrl(instr),
            .SRA => self.opSra(instr),
            .SLLV => self.opSllv(instr),
            .SRLV => self.opSrlv(instr),
            .SRAV => self.opSrav(instr),

            .JR => self.opJr(instr),
            .JALR => self.opJalr(instr),

            .ADD => self.opAdd(instr),
            .ADDU => self.opAddu(instr),
            .SUB => self.opSub(instr),
            .SUBU => self.opSubu(instr),

            .MFHI => self.opMfhi(instr),
            .MFLO => self.opMflo(instr),

            .AND => self.opAnd(instr),
            .OR => self.opOr(instr),
            .XOR => self.opXor(instr),
            .NOR => self.opNor(instr),

            .SLT => self.opSlt(instr),
            .SLTU => self.opSltu(instr),

            .DIV => self.opDiv(instr),
            .DIVU => self.opDivu(instr),

            .MULT => self.opMult(instr),
            .MULTU => self.opMultu(instr),

            else => debug_f.unhandledSpecial(funct, instr),
        }
    }

    pub fn executeCop0(self: *@This(), instr: Instruction) void {
        switch (instr.rs()) {
            @intFromEnum(COP0Opcode.MFC0) => self.opMfc0(instr),
            @intFromEnum(COP0Opcode.MTC0) => self.opMtc0(instr),
            @intFromEnum(COP0Opcode.RFE) => self.opRfe(instr),
            else => debug_f.unhandledCop0(instr),
        }
    }

    pub fn opSyscall(self: *@This(), instr: Instruction) void {
        _ = instr;
        self.cop0[13] = (self.cop0[13] & ~@as(u32, 0x7C)) | (8 << 2);
        self.cop0[14] = self.current_pc;

        self.cop0[12] = (self.cop0[12] & ~@as(u32, 0x3F)) | ((self.cop0[12] << 2) & 0x3F);
        self.pc_next = 0x8000_0080;
    }
    pub fn opBreak(self: *@This(), instr: Instruction) void {
        _ = instr;
        self.cop0[13] = (self.cop0[13] & ~@as(u32, 0x7C)) | (9 << 2);
        self.cop0[14] = self.current_pc;

        self.cop0[12] = (self.cop0[12] & ~@as(u32, 0x3F)) | ((self.cop0[12] << 2) & 0x3F);
        self.pc_next = 0x8000_0080;
    }

    pub fn opAdd(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        const lhs: i32 = @bitCast(self.regs[rs]);
        const rhs: i32 = @bitCast(self.regs[rt]);
        const result = lhs +% rhs;

        self.setReg(rd, @bitCast(result));
    }

    pub fn opAddi(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        const lhs: i32 = @bitCast(self.regs[rs]);
        const rhs = instr.immSigned32();
        const result = lhs +% rhs;

        self.setReg(rt, @bitCast(result));
    }

    pub fn opAddiu(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        self.setReg(rt, self.regs[rs] +% instr.immSignedU32());
    }

    pub fn opAddu(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rd, self.regs[rs] +% self.regs[rt]);
    }

    pub fn opAnd(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rd, self.regs[rs] & self.regs[rt]);
    }

    pub fn opAndi(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        self.setReg(rt, self.regs[rs] & @as(u32, instr.imm()));
    }
    pub fn opXor(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rd, self.regs[rs] ^ self.regs[rt]);
    }
    pub fn opNor(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rd, ~(self.regs[rs] | self.regs[rt]));
    }
    pub fn opXori(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        self.setReg(rt, self.regs[rs] ^ @as(u32, instr.imm()));
    }

    pub fn opOr(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rd, self.regs[rs] | self.regs[rt]);
    }

    pub fn opOri(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        self.setReg(rt, self.regs[rs] | @as(u32, instr.imm()));
    }

    pub fn opLui(self: *@This(), instr: Instruction) void {
        const rt: usize = @intCast(instr.rt());

        self.setReg(rt, @as(u32, instr.imm()) << 16);
    }

    pub fn opSll(self: *@This(), instr: Instruction) void {
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rd, self.regs[rt] << instr.shamt());
    }
    pub fn opSrl(self: *@This(), instr: Instruction) void {
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rd, self.regs[rt] >> instr.shamt());
    }
    pub fn opSra(self: *@This(), instr: Instruction) void {
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());
        const value: i32 = @bitCast(self.regs[rt]);
        const result = value >> instr.shamt();
        self.setReg(rd, @bitCast(result));
    }
    pub fn opSllv(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());
        const shift: u5 = @intCast(self.regs[rs] & 0x1F);
        self.setReg(rd, self.regs[rt] << shift);
    }
    pub fn opSrlv(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());
        const shift: u5 = @intCast(self.regs[rs] & 0x1F);

        self.setReg(rd, self.regs[rt] >> shift);
    }
    pub fn opSrav(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());
        const shift: u5 = @intCast(self.regs[rs] & 0x1F);
        const value: i32 = @bitCast(self.regs[rt]);
        self.setReg(rd, @bitCast(value >> shift));
    }

    pub fn opSlt(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        const lhs: i32 = @bitCast(self.regs[rs]);
        const rhs: i32 = @bitCast(self.regs[rt]);

        self.setReg(rd, if (lhs < rhs) 1 else 0);
    }

    pub fn opSltu(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rd, if (self.regs[rs] < self.regs[rt]) 1 else 0);
    }

    pub fn opJ(self: *@This(), instr: Instruction) void {
        const target = @as(u32, instr.target()) << 2;
        const jump_addr = ((self.current_pc +% 4) & 0xF000_0000) | target;

        std.debug.print(
            "J from PC=0x{X:0>8} -> 0x{X:0>8}\n",
            .{ self.current_pc, jump_addr },
        );

        self.pc_next = jump_addr;
    }

    pub fn opJal(self: *@This(), instr: Instruction) void {
        const target = @as(u32, instr.target()) << 2;
        const jump_addr = ((self.current_pc +% 4) & 0xF000_0000) | target;

        std.debug.print(
            "JAL from PC=0x{X:0>8} -> 0x{X:0>8}, RA=0x{X:0>8}\n",
            .{ self.current_pc, jump_addr, self.pc_next },
        );

        self.setReg(31, self.current_pc +% 8);
        self.pc_next = jump_addr;
    }
    pub fn opJalr(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rd: usize = @intCast(instr.rd());

        const target = self.regs[rs];
        const return_addr = self.current_pc +% 8;

        std.debug.print(
            "JALR from PC=0x{X:0>8} r{}=0x{X:0>8}, rd={}, RA=0x{X:0>8}\n",
            .{ self.current_pc, rs, target, rd, return_addr },
        );

        self.setReg(rd, return_addr);
        self.pc_next = target;
    }

    pub fn opJr(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const target = self.regs[rs];

        if (target == 0xA0 or target == 0xB0 or target == 0xC0) {
            std.debug.print(
                "BIOS vector call target=0x{X:0>8} r9/function=0x{X:0>2} RA=0x{X:0>8}: [0]=0x{X:0>8} [4]=0x{X:0>8} [8]=0x{X:0>8} [C]=0x{X:0>8}\n",
                .{
                    target,
                    self.regs[9],
                    self.regs[31],
                    self.bus.read32(target + 0),
                    self.bus.read32(target + 4),
                    self.bus.read32(target + 8),
                    self.bus.read32(target + 12),
                },
            );
        }

        if (target == 0x5C0 or target == 0x5C4 or target == 0x5E0 or target == 0x5E4 or target == 0x600) {
            std.debug.print(
                "BIOS dispatcher target=0x{X:0>8} r9/function=0x{X:0>2} RA=0x{X:0>8}\n",
                .{ target, self.regs[9], self.regs[31] },
            );
        }

        if (target == 0xBFC01920) {
            std.debug.print(
                "ENTER BFC01920 via JR at PC=0x{X:0>8}, r9/function=0x{X:0>2}, RA=0x{X:0>8}\n",
                .{ self.current_pc, self.regs[9], self.regs[31] },
            );
        }

        if (rs == 26 and self.regs[26] == 0) {
            std.debug.panic(
                "JR k0 with k0=0 at PC=0x{X:0>8} raw=0x{X:0>8} RA=0x{X:0>8}\n",
                .{ self.current_pc, instr.raw, self.regs[31] },
            );
        }

        std.debug.print(
            "JR from PC=0x{X:0>8} raw=0x{X:0>8} r{}=0x{X:0>8} RA=0x{X:0>8}\n",
            .{ self.current_pc, instr.raw, rs, self.regs[rs], self.regs[31] },
        );

        self.pc_next = target;
    }

    pub fn opBeq(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        if (self.regs[rs] == self.regs[rt]) {
            const offset: i32 = instr.immSigned32() << 2;
            self.pc_next = self.pc +% @as(u32, @bitCast(offset));
        }
    }

    pub fn opBne(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        if (self.regs[rs] != self.regs[rt]) {
            const offset: i32 = instr.immSigned32() << 2;
            self.pc_next = self.pc +% @as(u32, @bitCast(offset));
        }
    }
    pub fn opBgtz(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const value: i32 = @bitCast(self.regs[rs]);

        if (value > 0) {
            const offset: i32 = instr.immSigned32() << 2;
            self.pc_next = self.pc +% @as(u32, @bitCast(offset));
        }
    }
    pub fn opBlez(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const value: i32 = @bitCast(self.regs[rs]);

        if (value <= 0) {
            const offset: i32 = instr.immSigned32() << 2;
            self.pc_next = self.pc +% @as(u32, @bitCast(offset));
        }
    }
    pub fn opBltz(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const value: i32 = @bitCast(self.regs[rs]);

        if (value < 0) {
            const offset: i32 = instr.immSigned32() << 2;
            self.pc_next = self.pc +% @as(u32, @bitCast(offset));
        }
    }

    pub fn opBgez(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const value: i32 = @bitCast(self.regs[rs]);

        if (value >= 0) {
            const offset: i32 = instr.immSigned32() << 2;
            self.pc_next = self.pc +% @as(u32, @bitCast(offset));
        }
    }

    pub fn opBltzal(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const value: i32 = @bitCast(self.regs[rs]);

        self.setReg(31, self.current_pc +% 8);

        if (value < 0) {
            const offset: i32 = instr.immSigned32() << 2;
            self.pc_next = self.pc +% @as(u32, @bitCast(offset));
        }
    }

    pub fn opBgezal(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const value: i32 = @bitCast(self.regs[rs]);

        self.setReg(31, self.current_pc +% 8);

        if (value >= 0) {
            const offset: i32 = instr.immSigned32() << 2;
            self.pc_next = self.pc +% @as(u32, @bitCast(offset));
        }
    }

    pub fn opLw(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        const address = self.regs[rs] +% instr.immSignedU32();
        const value = self.bus.read32(address);

        if (rt == 26) {
            std.debug.print(
                "LW -> k0 at PC=0x{X:0>8}: addr=0x{X:0>8} value=0x{X:0>8} base r{}=0x{X:0>8} imm=0x{X:0>4}\n",
                .{ self.current_pc, address, value, rs, self.regs[rs], instr.imm() },
            );
        }

        self.setReg(rt, value);
    }

    pub fn opLb(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        const address = self.regs[rs] +% instr.immSignedU32();

        const byte = self.bus.read8(address);
        const signed_byte: i8 = @bitCast(byte);
        const signed_32: i32 = @as(i32, signed_byte);

        self.setReg(rt, @bitCast(signed_32));
    }

    pub fn opLbu(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        const address = self.regs[rs] +% instr.immSignedU32();

        self.setReg(rt, self.bus.read8(address));
    }
    pub fn opLh(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        const address = self.regs[rs] +% instr.immSignedU32();
        const half = self.bus.read16(address);
        const signed_half: i16 = @bitCast(half);
        const signed_32: i32 = @as(i32, signed_half);

        self.setReg(rt, @bitCast(signed_32));
    }
    pub fn opLhu(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        const address = self.regs[rs] +% instr.immSignedU32();

        self.setReg(rt, self.bus.read16(address));
    }

    pub fn opSw(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        const address = self.regs[rs] +% instr.immSignedU32();

        if (self.cacheIsolated()) return;

        self.bus.write32(address, self.regs[rt]);
    }
    pub fn opSh(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        const address = self.regs[rs] +% instr.immSignedU32();
        const value: u16 = @intCast(self.regs[rt] & 0xFFFF);

        if (self.cacheIsolated()) return;

        self.bus.write16(address, value);
    }
    pub fn opSb(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());

        const address = self.regs[rs] +% instr.immSignedU32();
        const value: u8 = @intCast(self.regs[rt] & 0xFF);

        if (self.cacheIsolated()) return;

        self.bus.write8(address, value);
    }
    pub fn opSlti(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const lhs: i32 = @bitCast(self.regs[rs]);
        const rhs: i32 = @bitCast(instr.immSigned32());
        self.setReg(rt, if (lhs < rhs) 1 else 0);
    }
    pub fn opSltiu(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const imm = instr.immSignedU32();
        self.setReg(rt, if (self.regs[rs] < imm) 1 else 0);
    }
    pub fn opSub(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        const lhs: i32 = @bitCast(self.regs[rs]);
        const rhs: i32 = @bitCast(self.regs[rt]);
        const result = lhs -% rhs;

        self.setReg(rd, @bitCast(result));
    }
    pub fn opMfhi(self: *@This(), instr: Instruction) void {
        const rd: usize = @intCast(instr.rd());
        self.setReg(rd, self.hi);
    }
    pub fn opMflo(self: *@This(), instr: Instruction) void {
        const rd: usize = @intCast(instr.rd());
        self.setReg(rd, self.lo);
    }
    pub fn opDiv(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const numerator: i32 = @bitCast(self.regs[rs]);
        const denominator: i32 = @bitCast(self.regs[rt]);
        if (denominator == 0) {
            self.lo = if (numerator >= 0) 0xFFFF_FFFF else 1;
            self.hi = @bitCast(numerator);
            return;
        }
        if (numerator == std.math.minInt(i32) and denominator == -1) {
            self.lo = @bitCast(numerator);
            self.hi = 0;
            return;
        }
        const quotient = @divTrunc(numerator, denominator);
        const remainder = @rem(numerator, denominator);
        self.lo = @bitCast(quotient);
        self.hi = @bitCast(remainder);
    }
    pub fn opDivu(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const numerator = self.regs[rs];
        const denominator = self.regs[rt];
        if (denominator == 0) {
            self.lo = 0xFFFF_FFFF;
            self.hi = numerator;
            return;
        }
        self.lo = numerator / denominator;
        self.hi = numerator % denominator;
    }
    pub fn opMult(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const lhs: i32 = @bitCast(self.regs[rs]);
        const rhs: i32 = @bitCast(self.regs[rt]);
        const result: i64 = @as(i64, lhs) * @as(i64, rhs);
        const result_u: i64 = @bitCast(result);
        self.lo = @intCast(result_u & 0xFFFF_FFFF);
        self.hi = @intCast(result_u >> 32);
    }
    pub fn opMultu(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const result: u64 = @as(u64, self.regs[rs]) * @as(u64, self.regs[rt]);

        self.lo = @intCast(result & 0xFFFF_FFFF);
        self.hi = @intCast(result >> 32);
    }

    pub fn opSubu(self: *@This(), instr: Instruction) void {
        const rs: usize = @intCast(instr.rs());
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rd, self.regs[rs] -% self.regs[rt]);
    }

    pub fn opMfc0(self: *@This(), instr: Instruction) void {
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.setReg(rt, self.cop0[rd]);
    }

    pub fn opMtc0(self: *@This(), instr: Instruction) void {
        const rt: usize = @intCast(instr.rt());
        const rd: usize = @intCast(instr.rd());

        self.cop0[rd] = self.regs[rt];
    }

    pub fn opRfe(self: *@This(), instr: Instruction) void {
        _ = instr;

        const status_index = 12;
        const status = self.cop0[status_index];

        self.cop0[status_index] = (status & 0xFFFF_FFF0) | ((status >> 2) & 0xF);
    }
    pub fn executeRegimm(self: *@This(), instr: Instruction) void {
        const rt = std.enums.fromInt(RegimmOpcode, instr.rt()) orelse {
            debug_f.unhandledPrimary(instr);
        };

        switch (rt) {
            .BLTZ => self.opBltz(instr),
            .BGEZ => self.opBgez(instr),
            .BLTZAL => self.opBltzal(instr),
            .BGEZAL => self.opBgezal(instr),
        }
    }
};
