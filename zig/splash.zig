const std = @import("std");

var line = [_]u8{ 0x1b, '[', '4', '8', ';', '5', ';', '0', '0', '0', 'm', ' ' } ** 80 ++
    [_]u8{ 0x1b, '[', '0', 'm', '\n' };

const Machine = struct {
    t: u32,

    pub fn init() Machine {
        return .{ .t = 0 };
    }

    pub fn step(m: *Machine) u8 {
        const t = m.t;
        m.t += 1;
        const result = t * t >> 16;
        return @truncate(u4, result);
    }
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var lim: usize = 80;
    var m = Machine.init();

    while (lim > 0) : (lim -= 1) {
        var offset: u32 = 7;
        var i: u32 = 64;
        while (i > 0) : ({
            i -= 1;
            offset += 12;
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
    }
}
