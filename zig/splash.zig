const std = @import("std");
const time = std.time;

var line = blk: {
    @setEvalBranchQuota(10000);
    const string = "\x1b[38;5;000m\x1b[48;5;000m▄" ** 64;
    var buffer: [string.len]u8 = undefined;
    for (string) |_, i| {
        buffer[i] = string[i];
    }
    break :blk buffer;
};

test "" {
    var bar = string ** 32 ++ [_]u8{};
    std.debug.print("{}\n", .{bar});
}

const Machine = struct {
    t: u32,

    pub fn init() Machine {
        return .{ .t = 0 };
    }

    pub fn step(m: *Machine) u8 {
        const t = m.t;
        m.t +%= 1;
        const result = t *% t >> 16;
        return @truncate(u8, result);
    }
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var lim: usize = 80;
    var m = Machine.init();

    while (true) {
        var offset: u32 = 18;
        var i: u32 = 64;
        while (i > 0) : ({
            i -= 1;
            offset += 25;
        }) {
            _ = std.fmt.formatIntBuf(
                line[offset .. offset + 3],
                m.step(),
                10,
                false,
                .{ .alignment = .Right, .fill = '0', .width = 3 },
            );
        }
        i = 64;
        offset = 7;
        while (i > 0) : ({
            i -= 1;
            offset += 25;
        }) {
            _ = std.fmt.formatIntBuf(
                line[offset .. offset + 3],
                m.step(),
                10,
                false,
                .{ .alignment = .Right, .fill = '0', .width = 3 },
            );
        }
        try stdout.writeAll(line[0..]);
        try stdout.print("\x1b[0m{}\n", .{m.t});
        time.sleep(time.ns_per_s / 26);
    }
}
