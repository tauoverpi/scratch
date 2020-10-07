const std = @import("std");

pub const Context = struct {
    text: []const u8,
    offset: usize = 0,
    column: usize = 0,
    line: usize = 0,

    fn peek(self: *Context) ?u8 {
        return if (self.offset < self.text.len) self.text[self.offset] else null;
    }

    fn consume(self: *Context) !u8 {
        if (self.offset < self.text.len) return self.consumeNoEof();
        return error.UnexpectedEof;
    }

    fn consumeNoEof(self: *Context) u8 {
        std.debug.assert(self.offset < self.text.len);
        const c = self.text[self.offset];

        if (c == '\n') {
            self.line += 1;
            self.column = 0;
        } else {
            self.column += 1;
        }

        return c;
    }

    fn eat(self: *Context, c: u8) bool {
        self.expect(c) catch return false;
        return true;
    }

    fn expect(self: *Context, expected: u8) !void {
        if (self.peek()) |c| {
            if (c != expected) return error.UnexpectedCharacter;
            _ = self.consumeNoEof();
        } else return error.UnexpectedEof;
    }

    fn spaces(self: *Context) void {
        while (self.eat(' ')) {}
    }

    fn exact(self: *Context, s: []const u8) !void {
        if (self.offset + s.len > self.text.len) return error.UnexpectedEof;
        for (s) |c| try self.expect(c);
    }
};

const Rule = struct { text: []const u8, actions: []Action, constraints: []Constraint };

const Sum = struct { operator: Operator, token: []const u8 };

const FFI = struct {
    name: []const u8,
    args: []const Arg,
    pub const Arg = union(enum) {
        literal: []const u8,
        pointer: []const u8,
    };
};

const Command = union(enum) {
    reset,
    say: []const []const u8,
    die,
    win,
    save: []const u8,
    load: []const u8,
    call: FFI,
    goto: []const u8,
};

const Action = union(enum) {
    token: []const u8,
    sum: Sum,
    command: Command,
};

fn string(self: *Context) ![]const u8 {
    try ctx.exact('"');
    const start = ctx.offset;
    while (ctx.peek()) |c| switch (c) {
        '"' => break,
        '\n' => return error.UnexpectedEol,
        ' ', '!', '#'...'~' => ctx.consumeNoEof(),
        else => return error.UnexpectedCharacter,
    };
    const end = ctx.offset;
    try ctx.exact('"');
    return ctx.text[start..end];
}
