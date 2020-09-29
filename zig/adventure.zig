const std = @import("std");
const testing = std.testing;
const parser = @import("utf8-parser.zig");
const P = parser.P;
const ParserOptions = parser.ParserOptions;

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

        _ = try parser.alpha(p);
        _ = parser.string(p, parser.alpha) catch break;
        parser.expect(p, '.') catch break;
    }
}

test "adv-identifier" {
    var p = P{ .text = "thing.with.dots" };
    try identifier(&p);
}

fn string(p: *P) !void {
    errdefer std.debug.print(">{}\n", .{p.text[p.index..]});
    try parser.newline(p);
    if (try parser.peek(p)) |codepoint| if (codepoint != '|') return error.UnexpectedCharacter;

    var limit = p.options.iterations;
    while (true) : (limit -= 1) {
        if (limit == 0) return error.IterationLimitReached;

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
        \\| this is a string
        \\| with multiple lines
        \\;
    };
    try string(&p);
}
