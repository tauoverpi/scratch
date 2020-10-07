const std = @import("std");
const testing = std.testing;

const Token = union(enum) {
    Atom: []const u8,
    Number: f64,
    ArrayBegin: []const u8,
    ArrayEnd,
    Comment: []const u8,
};

const TokenParser = struct {
    index: usize = 0,
    indent: usize = 0,
    context: [256]Context = undefined,
    ci: usize = 0,
    text: []const u8,

    const Context = enum { Object, Array };

    pub fn next(p: *TokenParser) !?Token {
        while (p.index < p.text.len) : (p.index += 1) {}
        return null;
    }
};

fn ok(unit: []const u8, comptime out: anytype) !void {
    var p = TokenParser{ .text = unit };
    inline for (out) |expected| {
        if (!std.meta.eql(expected, (try p.next()) orelse return error.UnexpectedEnd))
            return error.OutputNotEqual;
    }
    if (p.index != p.text.len) return error.FailedToConsumeInput;
}

fn err(unit: []const u8, e: anyerror) !void {
    var p = TokenParser{ .text = unit };
    while (try p.next()) |_| {} else |err| {
        if (err == e) return;
        return err;
    }
    return error.ExpectedError;
}

test "parse-comment" {
    try ok("-- this is a comment", .{Token{ .Comment = " this is a comment" }});
}

test "parse-number" {
    try ok("1234567890", .{});
    try ok("12345.456789", .{});
    try ok("1E10", .{});
    try ok("1E-1", .{});
    try ok("1e10", .{});
    try ok("1e-1", .{});
}

test "parse-array" {
    try ok("[1,2,3]", .{ Token{ .Number = 1 }, Token{ .Number = 2 }, Token{ .Number = 3 } });
    try ok(
        \\- one
        \\- two
        \\- three
    , .{
        Token{ .Atom = "one" },
        Token{ .Atom = "two" },
        Token{ .Atom = "three" },
    });
    try ok(
        \\- 1
        \\- 2
        \\- 3
    , .{
        Token{ .Number = 1 },
        Token{ .Number = 2 },
        Token{ .Number = 3 },
    });
    try ok(
        \\- inline: john
        \\- verbatim: |
        \\  text which
        \\  spans multiple lines
        \\- compressed: >
        \\  this is really
        \\  a single line
    , .{});
}
