const std = @import("std");
const testing = std.testing;
const parser = @import("utf8-parser.zig");
const P = parser.P;
const ParserOptions = parser.ParserOptions;

const Context = struct {
    indent: usize = 0,
};

fn comment(p: *P) !void {
    errdefer std.debug.print(">>> {} <<\n", .{p.text[p.index..]});
    try parser.expect(p, '/');
    var limit = p.options.iterations;
    while (parser.not(p, parser.newline)) {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;
    } else |e| if (e != error.UnexpectedCharacter and e != error.UnexpectedEof) return e;
    try parser.newline(p);
}

test "adv-comment" {
    var p = P{
        .text =
        \\/ comments use negation to parse until EOL
        \\/ and can't span multiple lines
        \\
    };
    try comment(&p);
    try comment(&p);
}

fn identifier(p: *P) !void {
    var limit = p.options.iterations;
    while (true) {
        if (limit == 0) return error.IterationLimitReached;
        limit -= 1;

        _ = try parser.string1(p, parser.alpha);
        skipdash: {
            parser.expect(p, '-') catch break :skipdash;
            _ = try parser.string1(p, parser.alpha);
        }
        parser.expect(p, '.') catch break;
    }
}

test "adv-identifier" {
    var p = P{ .text = "thing.with.dots.and-dashes" };
    try identifier(&p);
    testing.expect(p.index == p.text.len);
}

fn string(p: *P, indent: usize) !void {
    errdefer std.debug.print(">{}\n", .{p});
    try parser.newline(p);
    _ = try parser.string(p, parser.space);
    if (p.column != indent) return error.InvalidIndent;
    if (try parser.peek(p)) |codepoint|
        if (codepoint != '|')
            return error.UnexpectedCharacter;

    var limit = p.options.iterations;
    while (true) : (limit -= 1) {
        if (limit == 0) return error.IterationLimitReached;

        _ = try parser.string(p, parser.space);
        if (p.column != indent) return error.InvalidIndent;
        parser.expect(p, '|') catch break;

        var nested = p.options.iterations;
        while (parser.not(p, parser.newline)) : (nested -= 1) {
            if (nested == 0) return error.IterationLimitReached;
        } else |e| if (e != error.UnexpectedCharacter) return e;
        try parser.newline(p);
    }
    try parser.expect(p, ';');
}

test "adv-string" {
    var p = P{
        .text =
        \\
        \\  | this is a string
        \\  | with multiple lines
        \\  ;
    };
    try string(&p, 2);
}

fn builtin(p: *P) ![]const u8 {
    try parser.expect(p, '#');
    return try parser.string1(p, parser.alpha);
}

test "adv-builtin" {
    var p = P{
        .text =
        \\#say
        \\| introduction to the game
        \\;
    };
    const com = try builtin(&p);
    try string(&p, 0);
}
