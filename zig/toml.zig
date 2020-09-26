const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

//! Backtracking TOML parser library with type specialization and error logging.

const log = std.log.scoped(.@"toml parser");

const ParserOptions = struct {
    allocator: ?*Allocator = null,
    iterations: usize = max,

    const max = std.math.maxInt(usize);
};

const P = struct {
    text: []const u8,
    index: usize = 0,
    line: usize = 0,
    column: usize = 0,
    options: ParserOptions = .{},

    pub fn peek(p: P) !?u21 {
        if (p.index < p.text.len) {
            const byte = p.text[p.index];
            if (byte > 0x1f) {
                const len = try std.unicode.utf8ByteSequenceLength(byte);
                return try std.unicode.utf8Decode(p.text[p.index .. p.index + len]);
            } else return byte;
        } else return null;
    }

    pub fn consume(p: *P) !u21 {
        if (try p.peek()) |byte| {
            if (byte > 0x1f) {
                const len = try std.unicode.utf8CodepointSequenceLength(byte);
                defer {
                    for (p.text[p.index .. p.index + len]) |_| _ = p.consumeNoEof();
                }
                return try std.unicode.utf8Decode(p.text[p.index .. p.index + len]);
            }
            return p.consumeNoEof();
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

    pub fn expect(p: *P, expected: u21) !void {
        if (try p.peek()) |char| {
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

    pub fn eat(p: *P, expected: u21) bool {
        p.expect(expected) catch return false;
        return true;
    }

    pub fn oneOf(p: *P, expected: []const u21) !u21 {
        for (expected) |codepoint| {
            p.expect(codepoint) catch |e| switch (e) {
                error.UnexpectedCharacter => continue,
                else => return e,
            };
            return codepoint;
        }
        return error.UnexpectedCharacter;
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

// String handling

const String = struct {
    text: []const u8,
    len: usize,
    escape: bool,
};

fn string(p: *P) !String {
    var escape = false;
    var escaped = false;
    var len: usize = 0;
    var limit: usize = p.options.iterations;

    try p.expect('"');
    const start = p.index;

    while (try p.peek()) |char| {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;

        if (char == '"' and !escape) {
            const result = p.text[start..p.index];
            try p.expect('"');
            return String{ .text = result, .len = len, .escape = escaped };
        } else if (char == '\\' and !escape) {
            escape = true;
            escaped = true;
        } else escape = false;

        len += try std.unicode.utf8CodepointSequenceLength(try p.consume());
    }
    return error.UnexpectedEof;
}

test "string-plain" {
    var p = P{
        .text =
        \\"this is a string"
    };
    const result = try string(&p);
    testing.expect(result.len == result.text.len);
    testing.expectEqualStrings("this is a string", result.text);
}

fn multilineString(p: *P) !String {
    // TODO: improve this implementation to not do as much redundant work
    var escape = false;
    var escaped = false;
    var skip = false;
    var len: usize = 0;
    var limit: usize = p.options.iterations;

    try p.exact("\"\"\"");
    const start = p.index;

    while (try p.peek()) |char| {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;

        if (char == '"') {
            const end = p.index;

            if (p.exact("\"\"\"")) {
                const result = p.text[start..end];

                return String{ .text = result, .escape = escaped, .len = len };
            } else |e| switch (e) {
                error.UnexpectedCharacter => {},
                else => return e,
            }
        } else if (char == '\\' and !escape) {
            escape = true;
            escaped = true;
            if ((try p.oneOf(&[_]u21{ '\n', 'n', 't', 'r', '\"', '\\' })) == '\n') skip = true;
        } else if (skip and char == ' ') {
            try p.expect(' ');
        } else {
            escape = false;
            skip = false;
            len += try std.unicode.utf8CodepointSequenceLength(try p.consume());
        }
    }
    return error.UnexpectedEof;
}

test "string-multiline" {
    var p = P{
        .text =
        \\"""this is a string\
        \\  that spans multiple\n
        \\lines and I loſt the game therefore you will aſ well"""
    };

    const result = try multilineString(&p);
    testing.expect(result.len != result.text.len);
    testing.expect(result.len + 2 == result.text.len);
    testing.expectEqualStrings(
        \\this is a string\
        \\  that spans multiple\n
        \\lines and I loſt the game therefore you will aſ well
    , result.text);
}

fn literalString(p: *P) !String {
    var limit: usize = p.options.iterations;

    try p.expect('`');
    const start = p.index;
    while (try p.peek()) |char| {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;

        if (char == '`') {
            const result = p.text[start..p.index];
            try p.expect('`');

            return String{ .text = result, .len = result.len, .escape = false };
        } else {
            _ = try p.consume();
        }
    }
    return error.UnexpectedEof;
}

test "string-literal" {
    var p = P{
        .options = .{ .iterations = 100 },
        .text =
        \\`this is a literal "with" """quotes""" and no escapes//\\`
    };

    const result = try literalString(&p);
    testing.expect(result.len == result.text.len);
    testing.expectEqualStrings(
        \\this is a literal "with" """quotes""" and no escapes//\\
    , result.text);
}

fn multilineLiteralString(p: *P) !String {
    var limit: usize = p.options.iterations;

    try p.exact("'''");
    const start = p.index;

    while (try p.peek()) |char| {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;

        if (char == '\'') {
            const end = p.index;

            if (p.exact("'''")) {
                const result = p.text[start..end];
                return String{ .text = result, .len = result.len, .escape = false };
            } else |e| switch (e) {
                error.UnexpectedCharacter => _ = try p.consume(),
                else => return e,
            }
        } else _ = try p.consume();
    }
    return error.UnexpectedEof;
}

test "string-multiline-literal" {
    var p = P{
        .text =
        \\'''this is a literal multi-line
        \\"with" """quotes""" and no'' ' escapes//\\'''
    };

    const result = try multilineLiteralString(&p);
    testing.expect(result.len == result.text.len);
    testing.expectEqualStrings(
        \\this is a literal multi-line
        \\"with" """quotes""" and no'' ' escapes//\\
    , result.text);
}
