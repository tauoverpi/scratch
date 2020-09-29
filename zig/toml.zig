const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const parser = @import("utf8-parser.zig");
const P = parser.P;
const ParserOptions = parser.ParserOptions;

//! Backtracking TOML parser library with type specialization and error logging.

const log = std.log.scoped(.@"toml parser");

fn comment(p: *P) !void {
    try p.expect('#');
    while (!p.newline()) _ = try p.consume();
}

test "comments" {
    var p = P{ .text = "# this is a comment\n" };
    try comment(&p);
}

// String handling

pub const String = struct {
    text: []const u8,
    len: usize,
    escape: bool,

    const State = enum { Skip, Copy, Escape };

    /// Unescape a string given by the string and multiline string parser
    pub fn unescape(str: String, output: []u8) void {
        std.debug.assert(output.len >= str.len);
        var byte: usize = 0;
        var state: State = .Copy;
        var index: usize = 0;
        var limit: u32 = 200;
        while (limit > 0 and index < str.text.len) : (limit -= 1) {
            const c = str.text[index];
            const size = std.unicode.utf8ByteSequenceLength(c) catch unreachable;
            switch (state) {
                .Copy => switch (c) {
                    '\\' => {
                        state = .Escape;
                        index += 1;
                    },
                    else => for (str.text[index .. index + size]) |part| {
                        output[byte] = part;
                        index += 1;
                        byte += 1;
                    },
                },
                .Skip => switch (c) {
                    ' ', '\n' => index += 1,
                    else => for (str.text[index .. index + size]) |part| {
                        output[byte] = part;
                        index += 1;
                        byte += 1;
                    } else {
                        state = .Copy;
                    },
                },
                .Escape => {
                    switch (c) {
                        '\\' => output[byte] = '\\',
                        '"' => output[byte] = '"',
                        'n' => output[byte] = '\n',
                        't' => output[byte] = '\t',
                        'r' => output[byte] = '\r',
                        '\n' => {
                            index += 1;
                            state = .Skip;
                            continue;
                        },
                        else => unreachable,
                    }
                    byte += 1;
                    index += 1;
                    state = .Copy;
                },
            }
        }
    }
};

fn inlineString(p: *P) !String {
    var escape = false;
    var len: usize = 0;
    var limit: usize = p.options.iterations;

    try p.expect('"');
    const start = p.index;

    while (try p.peek()) |char| {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;

        if (char == '"') {
            const result = p.text[start..p.index];
            try p.expect('"');
            return String{ .text = result, .len = len, .escape = escape };
        } else if (char == '\\') {
            escape = true;
            switch (try p.consume()) {
                'n', 't', 'r', '"', '\\' => {},
                else => return error.UnexpectedCharacter,
            }
        } else len += try std.unicode.utf8CodepointSequenceLength(try p.consume());
    }
    return error.UnexpectedEof;
}

test "string-plain" {
    var p = P{
        .text =
        \\"this is a\n string"
    };
    var result = try inlineString(&p);
    testing.expect(result.len + 1 == result.text.len);
    testing.expectEqualStrings("this is a\\n string", result.text);
    var buffer: [17]u8 = undefined;
    result.unescape(&buffer);
    testing.expectEqualStrings("this is a\n string", &buffer);

    p = P{
        .text =
        \\""
    };
    var result2 = try inlineString(&p);
    testing.expect(result2.len == 0);
}

fn multilineString(p: *P) !String {
    // TODO: improve this implementation to not do as much redundant work
    var escape = false;
    var skip = false;
    var len: usize = 0;
    var limit: usize = p.options.iterations;

    try p.exact("\"\"\"");
    const start = p.index;

    while (try p.peek()) |char| {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;
        if (skip and (char == ' ' or char == '\n' or char == '\r')) {
            _ = try p.consume();
            continue;
        } else skip = false;
        if (char == '"') {
            const end = p.index;

            if (p.exact("\"\"\"")) {
                const result = p.text[start..end];

                return String{ .text = result, .escape = escape, .len = if (len == 0) 0 else len + 1 };
            } else |e| switch (e) {
                error.UnexpectedCharacter => {},
                else => return e,
            }
        } else if (char == '\\') {
            _ = try p.expect('\\');
            escape = true;
            switch (try p.consume()) {
                '\n' => skip = true,
                'n', 't', 'r', '"', '\\' => {},
                else => return error.UnexpectedCharacter,
            }
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
    testing.expectEqualStrings(
        \\this is a string\
        \\  that spans multiple\n
        \\lines and I loſt the game therefore you will aſ well
    , result.text);

    var buffer: [91]u8 = undefined;
    result.unescape(&buffer);

    testing.expectEqualStrings(
        \\this is a stringthat spans multiple
        \\
        \\lines and I loſt the game therefore you will aſ well
    , &buffer);

    p = P{
        .text =
        \\""""""
    };
    const result2 = try multilineString(&p);
    testing.expect(result2.len == 0);
}

fn inlineLiteralString(p: *P) !String {
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

    const result = try inlineLiteralString(&p);
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

// Keys

fn key(p: *P) !String {
    return inlineString(p) catch inlineLiteralString(p) catch |e| switch (e) {
        error.UnexpectedCharacter => {
            @panic("idhfh");
        },
        else => return e,
    };
}
