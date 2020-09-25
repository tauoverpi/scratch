const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.@"toml parser");

const P = struct {
    text: []const u8,
    index: usize = 0,
    line: usize = 0,
    column: usize = 0,

    pub fn peek(p: P) ?u8 {
        return if (p.index < p.text.len) p.text[p.index] else null;
    }

    pub fn peekUtf8(p: P) !?u21 {
        if (p.index < p.text.len) {
            const len = try std.unicode.utf8ByteSequenceLength(p.text[p.index]);
            if (p.index + len < p.text.len) {
                return try std.unicode.utf8Decode(p.text[p.index .. p.index + len]);
            }
        }
        return null;
    }

    pub fn consume(p: *P) !u8 {
        if (p.index < p.text.len) return p.consumeNoEof();
        return error.UnexpectedEof;
    }

    pub fn consumeUtf8(p: *P) !u21 {
        if (p.index < p.text.len) {
            const len = try std.unicode.utf8ByteSequenceLength(p.text[p.index]);
            if (p.index + len < p.text.len) {
                defer {
                    for (p.text[p.index .. p.index + len]) |_| _ = p.consumeNoEof();
                }
                return try std.unicode.utf8Decode(p.text[p.index .. p.index + len]);
            }
        }
        return error.UnexpectedEof;
    }

    fn consumeNoEof(p: *P) u8 {
        std.debug.assert(p.index < p.text.len);
        const c = p.text[p.index];
        p.index += 1;

        if (c == '\n') {
            p.line += 1;
            p.column = 0;
        } else {
            p.column += 1;
        }

        return c;
    }

    pub fn expect(p: *P, expected: u8) !void {
        if (p.peek()) |char| {
            if (char != expected) return error.UnexpectedCharacter;
            _ = p.consumeNoEof();
        } else return error.UnexpectedEof;
    }

    pub fn exact(p: *P, expected: []const u8) !void {
        if (p.text.len < p.index + expected.len) return error.UnexpectedEof;
        if (std.mem.startsWith(u8, p.text[p.index..], expected)) {
            for (expected) |_| _ = p.consumeNoEof();
        } else return error.UnexpectedCharacter;
    }

    pub fn newline(p: *P) bool {
        p.expect('\n') catch p.exact("\r\n") catch return false;
        return true;
    }

    pub fn eat(p: *P, expected: u8) bool {
        p.expect(expected) catch return false;
        return true;
    }
};

fn comment(p: *P) !void {
    try p.expect('#');
    while (!p.newline()) _ = try p.consume();
}

test "comments" {
    var p = P{ .text = "# this is a comment\n" };
    try comment(&p);
}

fn string(p: *P) ![]const u8 {
    try p.expect('"');
}

test "string-plain" {
    if (true) return error.SkipZigTest;
    var p = P{
        .text =
        \\"this is a string"
    };
    const result = try string(&p);
}

fn multilineString(p: *P) ![]const u8 {
    try p.exact("\"\"\"");
    const start = p.index;

    while (p.peek()) |char| {
        if (char == '"') {
            const end = p.index;

            if (p.exact("\"\"\"")) {
                const result = p.text[start..end];
                if (!std.unicode.utf8ValidateSlice(result))
                    return error.InvalidUnicode;

                return result;
            } else |e| switch (e) {
                error.UnexpectedCharacter => {},
                else => return e,
            }
        } else _ = try p.consume();
    }
    return error.UnexpectedEof;
}

test "string-multiline" {
    var p = P{
        .text =
        \\"""this is a string
        \\that spans multiple
        \\lines"""
    };

    const result = try multilineString(&p);
    testing.expectEqualStrings(
        \\this is a string
        \\that spans multiple
        \\lines
    , result);
}

fn literalString(p: *P) ![]const u8 {
    try p.expect('`');
    const start = p.index;
    while (try p.peekUtf8()) |char| {
        if (char == '`') {
            const result = p.text[start..p.index];
            try p.expect('`');

            return result;
        } else _ = try p.consumeUtf8();
    }
    return error.UnexpectedEof;
}

test "string-literal" {
    var p = P{
        .text =
        \\`this is a literal "with" """quotes""" and no escapes//\\`
    };

    const result = try literalString(&p);
    testing.expectEqualStrings(
        \\this is a literal "with" """quotes""" and no escapes//\\
    , result);
}

fn multilineLiteralString(p: *P) ![]const u8 {
    try p.exact("'''");
    const start = p.index;

    while (p.peek()) |char| {
        if (char == '\'') {
            const end = p.index;

            if (p.exact("'''")) {
                const result = p.text[start..end];
                if (!std.unicode.utf8ValidateSlice(result))
                    return error.InvalidUnicode;

                return result;
            } else |e| switch (e) {
                error.UnexpectedCharacter => {},
                else => return e,
            }
        } else _ = try p.consume();
    }
    return error.UnexpectedEof;
}

test "string-literal" {
    var p = P{
        .text =
        \\'''this is a literal multi-line
        \\"with" """quotes""" and no escapes//\\'''
    };

    const result = try multilineLiteralString(&p);
    testing.expectEqualStrings(
        \\this is a literal multi-line
        \\"with" """quotes""" and no escapes//\\
    , result);
}
