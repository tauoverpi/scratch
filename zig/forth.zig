const std = @import("std");

fn Stack(size: usize) type {
    return struct {
        stack: [size]u16 = undefined,
        index: usize = 0,

        const Self = @This();

        pub fn pop(m: *Self) !u16 {
            if (m.index == 0) return error.StackUndeflow;
            m.index -= 1;
            return m.stack[m.index];
        }

        pub fn push(m: *Self, word: u16) !void {
            if (m.index > m.stack.len) return error.StackOverflow;
            m.stack[m.index] = word;
            m.index += 1;
        }
    };
}

const Forth = struct {
    data: Stack(8) = Stack(8){},
    cont: Stack(16) = Stack(16){},
    ip: u16 = 0,
    memory: []u8,

    pub const Instruction = packed enum(u16) {
        next,
        halt,
        jz,
        add,
        fetch,
        store,
        lit,
        docol,
        _,
    };

    fn peek(vm: *Forth) ?u16 {
        if (vm.ip + 4 < vm.memory.len) {
            return std.mem.readIntSliceLittle(u16, vm.memory[vm.ip + 2 .. vm.ip + 4]);
        } else return null;
    }

    pub fn step(vm: *Forth) !void {
        errdefer |e| {
            std.debug.print(
                \\vm crash {} {}
                \\
            , .{ vm.ip, @errorName(e) });
        }

        const instruction = @intToEnum(Instruction, std.mem.readIntSliceLittle(u16, vm.memory[vm.ip .. vm.ip + 2]));

        std.debug.print("data ", .{});
        for (vm.data.stack[0..vm.data.index]) |word| std.debug.print("{} ", .{word});
        std.debug.print("\ncont ", .{});
        for (vm.data.stack[0..vm.cont.index]) |word| std.debug.print("{} ", .{word});
        std.debug.print("\n[{x:0>4}]: {}\n", .{ vm.ip, instruction });

        switch (instruction) {
            .docol => {
                try vm.cont.push(vm.ip + 2);
                if (vm.peek()) |word| {
                    vm.ip = word;
                } else return error.OutOfBoundsJump;
            },
            .next => {
                vm.ip = try vm.cont.pop();
            },

            .halt => return error.Halt,

            .jz => {
                if (vm.peek()) |word| {
                    if (word + 2 > vm.memory.len) return error.OutOfBoundsJump;
                    if (word & 1 == 1) return error.UnalignedJump;
                    if ((try vm.data.pop()) == 0) {
                        vm.ip = word;
                    } else vm.ip += 4;
                } else return error.OutOfBounds;
            },

            .add => {
                defer vm.ip += 2;
                if (vm.data.index > 2) return error.StackUndeflow;
                const value = try vm.data.pop();
                vm.data.stack[vm.data.index - 1] +%= value;
            },

            .lit => {
                defer vm.ip += 4;
                if (vm.peek()) |word| {
                    try vm.data.push(word);
                } else return error.OutOfBoundsFetch;
            },

            else => return error.UnknownInstruction,
        }
    }
};

fn b(comptime in: Forth.Instruction) [2]u8 {
    return @bitCast([2]u8, @enumToInt(in));
}

fn image(comptime tup: anytype) [std.meta.fields(@TypeOf(tup)).len * 2]u8 {
    const T = @TypeOf(tup);
    comptime var buffer: []const u8 = &[_]u8{};
    const fields = std.meta.fields(T);
    inline for (fields) |field| {
        buffer = buffer ++ switch (field.field_type) {
            comptime_int => @bitCast([2]u8, @as(u16, @field(tup, field.name))),
            else => @bitCast([2]u8, @enumToInt(@field(Forth.Instruction, @tagName(@field(tup, field.name))))),
        };
    }
    var result: [std.meta.fields(@TypeOf(tup)).len * 2]u8 = undefined;
    std.mem.copy(u8, &result, buffer);
    return result;
}

const program = image(.{ .lit, 0xfffe, .lit, 2, .add, .jz, 0 });

test "" {
    var memory = program ++ (b(.halt) ** (1024 * 1024 - program.len));
    var vm = Forth{ .memory = &memory };

    var limit: usize = 10;
    while (vm.step()) : (limit -= 1) {
        if (limit == 0) return error.IterationLimitReached;
    } else |e| return e;
}
