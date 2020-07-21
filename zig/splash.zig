const std = @import("std");
const time = std.time;

const size = 256;

var line = blk: {
    @setEvalBranchQuota(10000);
    const string = "\x1b[38;5;000m\x1b[48;5;000m▄" ** size;
    var buffer: [string.len]u8 = undefined;
    for (string) |_, i| {
        buffer[i] = string[i];
    }
    break :blk buffer;
};

const Machine = struct {
    t: u32,
    src: []const u8,

    pub fn init(src: []const u8) Machine {
        return .{ .t = 0, .src = src };
    }

    pub fn step(m: *Machine) u8 {
        const t = m.t;
        m.t +%= 1;
        var stack: [256]u32 = [_]u32{0} ** 256;
        var index: usize = 0;
        for (m.src) |byte| {
            switch (byte) {
                '%', '&', '^', '+', '*', '/', '>', '<', '-' => {
                    const a = stack[index - 1];
                    const b = stack[index - 2];
                    index -= 1;
                    switch (byte) {
                        '&' => stack[index - 1] = a & b,
                        '^' => stack[index - 1] = a ^ b,
                        '+' => stack[index - 1] = a +% b,
                        '-' => stack[index - 1] = a -% b,
                        '*' => stack[index - 1] = a *% b,
                        '/' => stack[index - 1] = a / b,
                        '%' => stack[index - 1] = a % b,
                        '>' => stack[index - 1] = a >> @truncate(u5, b),
                        '<' => stack[index - 1] = a << @truncate(u5, b),
                        else => unreachable,
                    }
                },
                '~', 'f' => switch (byte) {
                    '~' => stack[index - 1] = ~stack[index - 1],
                    'f' => stack[index - 1] = (stack[index - 1] << 16) | (stack[index - 1] >> 16),
                    else => unreachable,
                },
                't', 'm', 'l', 'h', 'd', 'o' => {
                    switch (byte) {
                        't' => stack[index] = t,
                        'm' => stack[index] = 0xffffffff,
                        'l' => stack[index] = 0x0000ffff,
                        'h' => stack[index] = 0xffff0000,
                        'o' => stack[index] = stack[index - 2],
                        'd' => stack[index] = stack[index - 1],
                        else => unreachable,
                    }
                    index += 1;
                },
                '0'...'9', 'A'...'Z' => {
                    stack[index] = byte -% @as(u32, if (byte > '9') '7' else '0');
                    index += 1;
                },
                else => {},
            }
        }
        return @truncate(u8, stack[index - 1]);
    }
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var lim: usize = 80;
    if (std.os.argv.len != 2 and std.os.argv.len != 3) {
        try stdout.writeAll(
            \\usage: splash track [offset]
            \\  t8t>&                fractal
            \\  AAA**t/AAA**1+t/^t*   jumper
            \\  Gt>1t++t^t/          cyclic
            \\  Gt>1+At>&t*          42 cycle
            \\
        );
        std.os.exit(0);
    }
    var m = Machine.init(std.os.argv[1][0..std.mem.len(std.os.argv[1])]);
    if (std.os.argv.len == 3) {
        m.t = try std.fmt.parseInt(u32, std.os.argv[2][0..std.mem.len(std.os.argv[2])], 16);
    }

    var child = try std.ChildProcess.init(&[_][]const u8{ "aplay", "-q", "-" }, std.heap.page_allocator);
    child.stdin_behavior = .Pipe;
    try child.spawn();
    defer {
        _ = child.kill() catch unreachable;
    }
    const writer = (child.stdin orelse return error.CantGetStdIn).writer();
    var audio: [size]u8 = undefined;

    while (true) {
        var offset: u32 = 18;
        var i: u32 = size;
        while (i > 0) : ({
            i -= 1;
            offset += 25;
        }) {
            const step = m.step();
            _ = std.fmt.formatIntBuf(
                line[offset .. offset + 3],
                step,
                10,
                false,
                .{ .alignment = .Right, .fill = '0', .width = 3 },
            );
            audio[size - i] = step;
        }
        try writer.writeAll(&audio);

        i = size;
        offset = 7;
        while (i > 0) : ({
            i -= 1;
            offset += 25;
        }) {
            const step = m.step();
            _ = std.fmt.formatIntBuf(
                line[offset .. offset + 3],
                step,
                10,
                false,
                .{ .alignment = .Right, .fill = '0', .width = 3 },
            );
            audio[size - i] = step;
        }
        try stdout.writeAll(line[0..]);
        try stdout.print("\x1b[0m{} - {}\n", .{ m.t - 512, m.t });
        try writer.writeAll(&audio);
        time.sleep(time.ns_per_s / 16);
    }
}
