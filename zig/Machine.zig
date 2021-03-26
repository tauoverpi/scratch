const std = @import("std");
const mem = std.mem;
const math = std.math;
const testing = std.testing;

pub const Machine = @This();

program: Program,
reg: [16]u64,
ip: usize,

pub const Program = [512]Instruction;

pub const Instruction = extern union {
    op: Opcode,
    binary: packed struct { op: Opcode, dst: u4, src: u4, imm: u4 },
    unary: packed struct { op: Opcode, dst: u4, imm: u8 },

    pub const Opcode = enum(u4) {
        nop,
        add,
        sub,
        mul,

        shl,
        shr,
        ror,
        cmp,

        @"and",
        @"or",
        xor,
        mov,

        inv,
        pop,
        lit,
        ret,
    };
};

pub fn init(program: Program) Machine {
    var machine: Machine = undefined;
    machine.reset();
    machine.program = program;
    return machine;
}

pub fn reset(self: *Machine) void {
    self.reg = mem.zeroes([16]u64);
    self.ip = 0;
}

pub fn step(self: *Machine) !?u64 {
    if (self.ip == self.program.len) return error.UnexpectedEndOfProgram;
    const inst = self.program[self.ip];
    defer self.ip += 1;
    switch (inst.op) {
        .nop => {},
        .add => self.reg[inst.binary.dst] +%= self.reg[inst.binary.src] +% inst.binary.imm,
        .sub => self.reg[inst.binary.dst] -%= self.reg[inst.binary.src] -% inst.binary.imm,
        .mul => self.reg[inst.binary.dst] *%= self.reg[inst.binary.src] *% inst.binary.imm,

        .shl => self.reg[inst.binary.dst] <<= @truncate(u6, self.reg[inst.binary.src]),
        .shr => self.reg[inst.binary.dst] <<= @truncate(u6, self.reg[inst.binary.src]),
        .ror => {
            const tmp = self.reg[inst.binary.dst];
            const offset = @truncate(u6, self.reg[inst.binary.src]);
            self.reg[inst.binary.dst] = (tmp >> offset) | (tmp << offset);
        },
        .cmp => {
            const src = self.reg[inst.binary.src];
            const imm = self.reg[inst.binary.imm];
            self.reg[inst.binary.dst] = if (src == imm) 0 else if (src > imm) @as(u64, 1) else math.maxInt(u64);
        },

        .@"and" => self.reg[inst.binary.dst] &= self.reg[inst.binary.src],
        .@"or" => self.reg[inst.binary.dst] |= self.reg[inst.binary.src],
        .xor => self.reg[inst.binary.dst] ^= self.reg[inst.binary.src],
        .mov => self.reg[inst.binary.dst] = self.reg[inst.binary.src],

        .inv => self.reg[inst.binary.dst] = ~self.reg[inst.binary.dst],
        .pop => self.reg[inst.binary.dst] = @popCount(u64, self.reg[inst.binary.dst]),
        .lit => self.reg[inst.unary.dst] = inst.unary.imm,
        .ret => return self.reg[inst.unary.dst],
    }
    return null;
}

test "machine all instructions" {
    var machine: Machine = undefined;
    machine.reset();
    mem.copy(Machine.Instruction, &machine.program, &.{
        .{ .op = .nop },
        .{ .unary = .{ .op = .lit, .dst = 1, .imm = 1 } },
        .{ .binary = .{ .op = .mov, .dst = 2, .src = 1, .imm = 0 } },
        .{ .binary = .{ .op = .sub, .dst = 0, .src = 1, .imm = 0 } },
        .{ .binary = .{ .op = .mul, .dst = 1, .src = 1, .imm = 5 } },
    });

    testing.expectEqual(@as(?u64, null), try machine.step());
    testing.expectEqual(@as(?u64, null), try machine.step());
    testing.expectEqual(@as(u64, 1), machine.reg[1]);

    testing.expectEqual(@as(?u64, null), try machine.step());
    testing.expectEqual(@as(u64, 1), machine.reg[2]);

    testing.expectEqual(@as(?u64, null), try machine.step());
    testing.expectEqual(@as(u64, 0xffffffff_ffffffff), machine.reg[0]);

    testing.expectEqual(@as(?u64, null), try machine.step());
    testing.expectEqual(@as(u64, 5), machine.reg[1]);
}
