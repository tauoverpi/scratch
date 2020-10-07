const std = @import("std");
const P = struct {
    telegram: []const u8,
    index: usize = 0,
    state: State = .startbyte,
    checksum: u8 = 0,
    length: u8 = 0,
    byte: u8 = 0,

    var frame: @Frame(consume) = undefined;

    const Error = error{UnexpectedEof};

    const State = enum { startbyte, lengthbyte, control, address, info };

    pub fn init(telegram: []const u8) P {
        var p = P{ .telegram = telegram };
        frame = async p.consume();
        return p;
    }

    pub fn consume(p: *P) error{UnexpectedEof}!void {
        suspend;
        std.debug.print("{}\n", .{p});
        if (p.index < p.telegram.len) return error.UnexpectedEof;
        p.byte = p.telegram[p.index];
        p.index += 1;
        wait consume(p);
    }
};

test "" {
    var p = P.init(&[_]u8{ 0x68, 0x3, 0x3, 0x68 });
    resume P.frame;
    resume P.frame;
}
