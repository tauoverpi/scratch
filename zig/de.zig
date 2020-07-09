const std = @import("std");

const Op = packed enum(u4) {
    Nop, // no operation
    Add, // addition
    Sub, // subtraction
    Mul, // multiplication
    Lit, // literal
    Lda, // load
    Sta, // store
    Pop, // pop count
    Shl, // shift left
    Shr, // shift right
    And, // bitwise and
    Or, // bitwise or
    Xor, // bitwise xor
    Ror, // roll right
    Rol, // roll left
    Inv, // invert value
};

const OpCode = packed struct { reg: u4, op: Op };

const Program = struct {
    program: []OpCode,

    pub fn init(buffer: []OpCode) Program {
        return .{ .program = buffer };
    }

    pub const Analysis = struct { length: usize, redundant: usize };

    pub fn analysis(self: Program) Analysis {
        var result = .{ .length = 0, .redundant = 0 };
        //var state = .{ .redundant = null };
        for (self.program) |op, i| {
            if (op.op != .Nop) result.length += 1;
            switch (self.program[self.program - (1 + i)].op) {
                else => {},
            }
            //if (state.redundant) |_| result.redundant += 1;
        }
    }

    pub fn run(self: Program, input: u32) u32 {
        var register = std.mem.zeroes([16]u32);
        register[0] = input;
        for (self.program) |op| {
            switch (op.op) {
                .Nop => {},
                .Add => register[0] +%= register[op.reg],
                .Sub => register[0] -%= register[op.reg],
                .Mul => register[0] *%= register[op.reg],
                .Lit => register[0] = op.reg,
                .Lda => register[0] = register[op.reg],
                .Sta => register[op.reg] = register[0],
                .Pop => register[0] = @popCount(u32, register[op.reg]),
                .Shl => register[0] <<= @truncate(u5, register[op.reg]),
                .Shr => register[0] >>= @truncate(u5, register[op.reg]),
                .And => register[0] |= register[op.reg],
                .Or => register[0] |= register[op.reg],
                .Xor => register[0] |= register[op.reg],
                .Ror => {
                    const left = register[0] << @truncate(u5, 32 - register[op.reg]);
                    const right = register[0] >> @truncate(u5, register[op.reg]);
                    register[0] = left + right;
                },
                .Rol => {
                    const left = register[0] >> @truncate(u5, 32 - register[op.reg]);
                    const right = register[0] << @truncate(u5, register[op.reg]);
                    register[0] = left + right;
                },
                .Inv => register[0] = ~register[0],
            }
        }
        return register[0];
    }
};

test "" {
    std.debug.print("\n", .{});
    var buffer = [_]OpCode{
        .{ .reg = 1, .op = .Sta },
        .{ .reg = 0, .op = .Add },
        .{ .reg = 1, .op = .Shr },
    };
    var program = Program.init(buffer[0..]);
    std.debug.assert(program.run(1) == 1);
    buffer = [_]OpCode{
        .{ .reg = 1, .op = .Sta },
        .{ .reg = 1, .op = .Ror },
        .{ .reg = 1, .op = .Rol },
    };
    program = Program.init(buffer[0..]);
    std.debug.assert(program.run(1) == 1);
    buffer = [_]OpCode{
        .{ .reg = 1, .op = .Nop },
        .{ .reg = 1, .op = .Nop },
        .{ .reg = 1, .op = .Inv },
    };
    program = Program.init(buffer[0..]);
    std.debug.assert(program.run(0) == 0xffffffff);
}
