const std = @import("std");

const Token = union(enum) {
    Nil,
    False,
    True,
    FixInt: u7,
    NegativeFixInt: i5,
    U8: u8,
};

const TokenParser = struct {
    index: usize = 0,
    buffer: []const u8,
    state: State = .Start,

    const State = enum { Start, U8 };

    pub fn next(p: *TokenParser) !?Token {
        while (p.index < p.buffer.len) : (p.index += 1) {
            defer p.index += 1;
            const c = p.buffer[p.index];
            switch (p.state) {
                .Start => switch (c) {
                    0xc0 => return .Nil,
                    0xc1 => return error.UnusedType,
                    0xc2 => return .False,
                    0xc3 => return .True,
                    0x00...0x7f => return Token{ .FixInt = @truncate(u7, c & 0x7f) },
                    0xe0...0xff => return Token{ .NegativeFixInt = -@truncate(i5, @intCast(i9, c)) },
                    0xcc => p.state = .U8,
                    else => return error.TODO,
                },
                .U8 => {
                    p.state = .Start;
                    return Token{ .U8 = c };
                },
            }
        }
        return null;
    }
};

// zig fmt: off
const example_message = &[_]u8{
        0xc0, // nil
        0xc2, // false
        0xc3, // true
        0x05, // positive fixint
        0xff, // negative fixint
        0xcc,  0xff, // u8
        0xcd, 0x00, 0xff, // u16
        0xce, 0x00, 0x00, 0x00, 0xff, // u32
        0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, // u64
};
// zig fmt: on

fn ok(buffer: []const u8, comptime expected: []const Token) !void {
    var p = TokenParser{ .buffer = buffer };
    for (expected) |result, i| {
        while (try p.next()) |value| {
            if (!std.meta.eql(value, result)) {
                std.log.err(
                    \\
                    \\
                    \\for item {}
                    \\
                    \\expected:
                    \\
                    \\    {}
                    \\
                    \\got:
                    \\
                    \\    {}
                    \\
                    \\
                , .{ i, result, value });
            }
        } else return error.ValueExpected;
    }
}

test "parse-single" {
    try ok(&[_]u8{ 0xc0, 0xc0 }, &[_]Token{ .Nil, .Nil });
    try ok(&[_]u8{0xc2}, &[_]Token{.False});
    try ok(&[_]u8{0xc3}, &[_]Token{.True});
    try ok(&[_]u8{ 0xc0, 0x05 }, &[_]Token{ .Nil, .{ .FixInt = 5 } });
    try ok(&[_]u8{ 0xff, 0xc0 }, &[_]Token{ .{ .NegativeFixInt = 1 }, .Nil });
}

test "parse-unsigned" {
    try ok(&[_]u8{ 0xcc, 0xff }, &[_]Token{.{ .U8 = 0xff }});
    //    try ok(&[_]u8{ 0xcd, 0x00, 0xff }, &[_]Token{});
    //   try ok(&[_]u8{ 0xce, 0x00, 0x00, 0x00, 0xff }, &[_]Token{});
    //  try ok(&[_]u8{ 0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff }, &[_]Token{});
}
