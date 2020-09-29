const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const ParserOptions = struct {
    allocator: ?*Allocator = null,
    iterations: usize = max,

    const max = std.math.maxInt(usize);
};

pub const P = struct {
    text: []const u8,
    index: usize = 0,
    line: usize = 0,
    column: usize = 0,
    options: ParserOptions = .{},
};

pub fn peek(p: *P) !?u21 {
    if (p.index < p.text.len) {
        const byte = p.text[p.index];
        const len = try std.unicode.utf8ByteSequenceLength(byte);
        return try std.unicode.utf8Decode(p.text[p.index .. p.index + len]);
    } else return null;
}

test "parser-peek" {
    {
        var p = P{ .text = "example" };
        testing.expect((try peek(&p)).? == 'e');
    }
    {
        var p = P{ .text = "" };
        testing.expect((try peek(&p)) == null);
    }
}

pub fn consume(p: *P) !u21 {
    if (try peek(p)) |byte| {
        const len = try std.unicode.utf8CodepointSequenceLength(byte);
        const result = try std.unicode.utf8Decode(p.text[p.index .. p.index + len]);
        p.index += len;

        if (result == '\n') {
            p.line += 1;
            p.column = 0;
        } else {
            p.column += 1;
        }
        return result;
    }
    return error.UnexpectedEof;
}

test "parser-consume" {
    {
        var p = P{ .text = "example" };
        testing.expect((try consume(&p)) == 'e');
    }
    {
        var p = P{ .text = "" };
        testing.expectError(error.UnexpectedEof, consume(&p));
    }
}

pub fn expect(p: *P, expected: u21) !void {
    if (try peek(p)) |codepoint| {
        if (codepoint != expected) return error.UnexpectedCharacter;
        _ = try consume(p);
    } else return error.UnexpectedEof;
}

test "parser-expect" {
    {
        var p = P{ .text = "example" };
        try expect(&p, 'e');
        testing.expect(p.index == 1);
        testing.expect(p.column == 1);
        testing.expect(p.line == 0);
    }
}

pub fn exact(p: *P, expected: []const u8) !void {
    if (p.text.len < p.index + expected.len) return error.UnexpectedEof;
    if (std.mem.startsWith(u8, p.text[p.index..], expected)) {
        var remains = expected.len;
        while (remains > 0) {
            remains -= try std.unicode.utf8ByteSequenceLength(p.text[p.index]);
            _ = try consume(p);
        }
    } else return error.UnexpectedCharacter;
}

test "parser-exact" {
    {
        var p = P{ .text = "example" };
        try exact(&p, "example");
        testing.expect(p.index == 7);
        testing.expect(p.column == 7);
        testing.expect(p.line == 0);
    }
}

pub fn newline(p: *P) !void {
    expect(p, '\n') catch try exact(p, "\r\n");
}

test "parser-newline" {
    {
        var p = P{ .text = "\n" };
        try newline(&p);
        testing.expect(p.index == 1);
    }
}

pub fn range(p: *P, start: u21, end: u21) !u21 {
    std.debug.assert(start < end);
    if (try peek(p)) |codepoint| {
        if (codepoint >= start and codepoint <= end) {
            return try consume(p);
        } else return error.UnexpectedCharacter;
    }
    return error.UnexpectedEof;
}

test "parser-range" {
    {
        var p = P{ .text = "abc123" };
        testing.expect((try range(&p, 'a', 'z')) == 'a');
    }
}

pub fn decimal(p: *P) !u21 {
    if (try peek(p)) |codepoint| {
        switch (codepoint) {
            '0'...'9' => return try consume(p),
            else => return error.UnexpectedCharacter,
        }
    }
    return error.UnexpectedEof;
}

test "parser-decimal" {
    {
        var p = P{ .text = "12" };
        testing.expect((try decimal(&p)) == '1');
    }
}

pub fn hexadecimal(p: *P) !u21 {
    if (try peek(p)) |codepoint| {
        switch (codepoint) {
            '0'...'9', 'A'...'F', 'a'...'f' => return try consume(p),
            else => return error.UnexpectedCharacter,
        }
    }
    return error.UnexpectedEof;
}

test "parser-hexadecimal" {
    {
        var p = P{ .text = "a2" };
        testing.expect((try hexadecimal(&p)) == 'a');
    }
}

pub fn string(p: *P, pass: anytype) ![]const u8 {
    const start = p.index;
    var limit: usize = p.options.iterations;
    while (pass(p)) {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;
    } else |e| switch (e) {
        error.UnexpectedEof, error.UnexpectedCharacter => {},
        else => return e,
    }
    return p.text[start..p.index];
}

test "parser-string" {
    {
        var p = P{ .text = "1234567890" };
        testing.expectEqualStrings("1234567890", try string(&p, decimal));
        testing.expect(p.index == 10);
    }
    {
        var p = P{ .text = "12345;67890" };
        testing.expectEqualStrings("12345", try string(&p, decimal));
        testing.expect(p.index == 5);
    }
}

pub fn string1(p: *P, pass: anytype) ![]const u8 {
    const start = p.index;
    _ = try pass(p);
    var limit: usize = p.options.iterations;
    while (pass(p)) {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;
    } else |e| switch (e) {
        error.UnexpectedEof, error.UnexpectedCharacter => {},
        else => return e,
    }
    return p.text[start..p.index];
}

test "parser-string1" {
    {
        var p = P{ .text = "abcdef" };
        testing.expectEqualStrings("abcdef", try string1(&p, hexadecimal));
    }
    {
        var p = P{ .text = "" };
        testing.expectError(error.UnexpectedEof, string1(&p, hexadecimal));
    }
}

pub fn not(p: *P, pass: anytype) !u21 {
    const reset = p.*;
    if (pass(p)) {
        p.* = reset;
        return error.UnexpectedCharacter;
    } else |e| if (error.UnexpectedCharacter != e) return e;
    return try consume(p);
}

test "parser-not" {
    {
        var p = P{ .text = "a" };
        testing.expect((try not(&p, decimal)) == 'a');
    }
}

pub fn alpha(p: *P) !u21 {
    if (try peek(p)) |codepoint| {
        switch (codepoint) {
            'a'...'z', 'A'...'Z' => return try consume(p),
            else => return error.UnexpectedCharacter,
        }
    }
    return error.UnexpectedEof;
}
test "parser-alpha" {
    {
        var p = P{ .text = "a" };
        testing.expect((try alpha(&p)) == 'a');
    }
}
