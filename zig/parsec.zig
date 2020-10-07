const std = @import("std");
const testing = std.testing;

const ParserContext = struct {
    text: []const u8,
    index: usize = 0,
    column: usize = 0,
    line: usize = 0,
    // checksum: u8 = 0,

    pub fn peek(p: *ParserContext) ?u8 {
        return if (p.index < p.text.len) p.text[p.index] else null;
    }

    pub fn consume(p: *ParserContext) !u8 {
        if (p.index < p.text.len) return p.consumeNoEof();
        return error.UnexpectedEof;
    }

    fn consumeNoEof(p: *ParserContext) u8 {
        std.debug.assert(p.index < p.text.len);
        const c = p.text[p.index];
        p.index += 1;

        if (c == '\n') {
            p.column = 0;
            p.line += 1;
        } else {
            p.column += 1;
        }

        return c;
    }

    pub fn eat(p: *ParserContext, char: u8) bool {
        p.expect(char) catch return false;
        return true;
    }

    pub fn expect(p: *ParserContext, expected: u8) !void {
        if (p.index < p.text.len) {
            if (p.peek()) |got| {
                if (got != expected) return error.UnexpectedCharacter;
                _ = p.consumeNoEof();
                return;
            }
        }
        return error.UnexpectedEof;
    }

    pub fn exact(p: *ParserContext, string: []const u8) !void {
        if (p.text.len < string.len + p.index) return error.UnexpectedEof;
        if (std.mem.startsWith(u8, p.text[p.index..], string)) {
            var i: usize = 0;
            while (i < string.len) : (i += 1) _ = p.consumeNoEof();
        } else return error.UnexpectedCharacter;
    }

    pub fn many(p: *ParserContext, pass: fn (u8) bool) ![]const u8 {
        const start = p.index;
        while (p.peek()) |char| if (!pass(char)) {
            break;
        } else {
            _ = p.consumeNoEof();
        };
        return p.text[start..p.index];
    }

    pub fn many1(p: *ParserContext, pass: fn (u8) bool) ![]const u8 {
        const start = p.index;
        if (p.peek()) |char| if (!pass(char)) return error.UnexpectedCharacter;
        while (p.peek()) |char| if (!pass(char)) {
            break;
        } else {
            _ = p.consumeNoEof();
        };
        return p.text[start..p.index];
    }
};

test "basic" {
    var p = ParserContext{ .text = "hello world" };
    try p.exact("hello");
    try p.expect(' ');
    try p.exact("world");
}

test "many" {
    var p = ParserContext{ .text = "12345678 world" };
    const digits = try p.many1(std.ascii.isDigit);
    const spaces = try p.many((struct {
        pub fn pass(char: u8) bool {
            return ' ' == char;
        }
    }).pass);
    const alphas = try p.many1(std.ascii.isAlpha);
    testing.expect(spaces.len == 1);
    testing.expectEqualStrings("12345678", digits);
    testing.expectEqualStrings("world", alphas);

    p = ParserContext{ .text = "12345678world" };
    _ = try p.many1(std.ascii.isDigit);
    const new = try p.many((struct {
        pub fn pass(char: u8) bool {
            return ' ' == char;
        }
    }).pass);
    _ = try p.many1(std.ascii.isAlpha);
    testing.expect(new.len == 0);
}

fn parenExpression(p: *ParserContext) !void {
    const reset = p.*;
    errdefer p.* = reset;

    try p.expect('(');
    try expression(p);
    try p.expect(')');
}

fn expression(p: *ParserContext) anyerror!void {
    const reset = p.*;
    errdefer p.* = reset;

    p.expect('+') catch try p.expect('-');
    while (p.expect(' ')) {
        _ = p.many1(std.ascii.isDigit) catch try parenExpression(p);
    } else |_| {}
}

test "nesting" {
    var p = ParserContext{ .text = "+ (- 2 (+ 3 4 444) (+ 4 3) 12)" };
    try expression(&p);
    testing.expect(p.text.len == p.index);
}

fn controlTelegram(p: *ParserContext) !void {
    const initial = p.index;
    errdefer p.index = initial;

    try p.expect(0x68);
    const len = try p.consume();
    const len_check = try p.consume();
    if (len != 3) return error.NotAControlTelegram;
    if (len != len_check) return error.LengthMismatch;
    try p.expect(0x68);
    const control = try p.consume();
    const address = try p.consume();
    const info = try p.consume();
    const checksum = try p.consume();
    if (control +% address +% info != checksum) return error.InvalidChecksum;
    try p.expect(0x16); // stop byte
}

const Telegram = union(enum) {
    ack,
    long: void,
    short: void,
    control: void,
};

// zig fmt: off
fn telegram(p: *ParserContext) !Telegram {
    return p.expect(0xe5) // ack
     catch shortTelegram(p)
     catch controlTelegram(p)
     catch try longTelegram(p);
}
// zig fmt: on

test "control" {
    var p = ParserContext{ .text = &[_]u8{ 0x68, 0x03, 0x03, 0x68, 0, 0, 0, 0, 0x16 } };
    try controlTelegram(&p);
}
