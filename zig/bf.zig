const std = @import("std");

const BF = struct {
    ip: usize,
    program: []const u8,
    stack: []usize,

    pub fn init(program: []const u8, stack: []usize) BF {
        return .{
            .ip = 0,
            .program = program,
            .stack = stack,
        };
    }

    pub fn step(self: *BF) void {
        switch (self.program[self.ip]) {
            '+' => {
                self.memory[self.position] +%= 1;
                self.ip += 1;
            },
            '-' => {
                self.memory[self.position] -%= 1;
                self.ip += 1;
            },
        }
    }
};
