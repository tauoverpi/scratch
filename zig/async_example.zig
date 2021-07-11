const std = @import("std");
const meta = std.meta;

const ThreadA = struct {
    pub fn main() !void {
        try print("Thread A", .{});

        while (true) {
            var guess = load(&global);
            try print("A: {} + {} = {}", .{ guess, guess, add(u16, guess, guess) });
            try print("A: guess {} + 1", .{guess});
            while (cmpxchgStrong(u16, &global, guess, guess +% 1)) |value| {
                try print("A: failed, guessed {} value {}", .{ guess, value });
                guess = value;
            }
            try print("A: success on guess {}", .{guess});
        }
    }
};

const ThreadB = struct {
    pub fn main() !void {
        try print("Thread B", .{});

        while (true) {
            var guess = load(&global);
            try print("B: pow pow: {}", .{pow(u16, 2, guess & 7)});
            try print("B: guess {} + 1", .{guess});
            while (cmpxchgStrong(u16, &global, guess, guess +% 1)) |value| {
                try print("B: failed, guessed {} value {}", .{ guess, value });
                guess = value;
            }
            try print("B: success on guess {}", .{guess});
        }
    }
};

var global: u16 = 0;

test {
    var a = async ThreadA.main();
    var b = async ThreadB.main();
    _ = a;
    _ = b;
    try cpu.run();
}

// EVERYTHING BELOW THIS LINE EMULATES A MULTI-THREAD PROGRAM
// ----------------------------------------------------------

const Schedule = std.TailQueue(anyframe);

const cpu = struct {
    pub var schedule: Schedule = .{};

    var count: u32 = 5;

    pub fn yield() void {
        if (count == 0) {
            count = 5;
            suspend {
                var frame = @frame();
                var node: Schedule.Node = .{
                    .next = undefined,
                    .prev = undefined,
                    .data = frame,
                };

                cpu.schedule.prepend(&node);
            }
        } else {
            count -= 1;
        }
    }

    pub fn yieldSyscall() void {
        suspend {
            var frame = @frame();
            var node: Schedule.Node = .{
                .next = undefined,
                .prev = undefined,
                .data = frame,
            };

            cpu.schedule.prepend(&node);
        }
    }

    pub fn run() !void {
        while (schedule.pop()) |thread| {
            resume thread.data;
        }
    }
};

fn cmpxchgStrong(comptime T: type, ptr: *T, expected: T, new: T) ?T {
    const old = ptr.*;
    if (old == expected) {
        ptr.* = new;
        cpu.yield();
        return null;
    } else {
        cpu.yield();
        return old;
    }
}

fn add(comptime T: type, a: T, b: T) T {
    cpu.yield();
    return a +% b;
}

fn sub(comptime T: type, a: T, b: T) T {
    cpu.yield();
    return a -% b;
}

fn mul(comptime T: type, a: T, b: T) T {
    cpu.yield();
    return a *% b;
}

fn pow(comptime T: type, a: T, b: T) T {
    var times: T = b;
    var result: T = 1;
    while (times > 0) : (times -= 1) result = mul(T, result, a);
    return result;
}

fn load(p: anytype) meta.Child(@TypeOf(p)) {
    cpu.yield();
    return p.*;
}

fn print(comptime fmt: []const u8, value: anytype) !void {
    const stdout = std.io.getStdOut().writer();
    cpu.yieldSyscall();
    try stdout.print(fmt ++ "\n", value);
}
