const std = @import("std");
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

    pub fn peek(p: P) !?u21 {
        if (p.index < p.text.len) {
            const byte = p.text[p.index];
            const len = try std.unicode.utf8ByteSequenceLength(byte);
            return try std.unicode.utf8Decode(p.text[p.index .. p.index + len]);
        } else return null;
    }

    pub fn consume(p: *P) !u21 {
        if (try p.peek()) |byte| {
            const len = try std.unicode.utf8CodepointSequenceLength(byte);
            defer {
                for (p.text[p.index .. p.index + len]) |_| _ = p.consumeNoEof();
            }
            return try std.unicode.utf8Decode(p.text[p.index .. p.index + len]);
        }
        return error.UnexpectedEof;
    }

    fn consumeNoEof(p: *P) u8 {
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
            _ = try p.consume();
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

    pub fn range(p: *P, start: u21, end: u21) !u21 {
        std.debug.assert(start < end);
        if (try p.peek()) |codepoint| {
            if (codepoint >= start and codepoint <= end) {
                return try p.consume();
            } else return error.UnexpectedCharacter;
        }
        return error.UnexpectedEof;
    }

    pub fn decimal(p: *P) !u21 {
        if (try p.peek()) |codepoint| {
            switch (codepoint) {
                '0'...'9' => return try p.consume(),
                else => return error.UnexpectedCharacter,
            }
        }
        return error.UnexpectedEof;
    }

    pub fn hexadecimal(p: *P) !u21 {
        if (try p.peek()) |codepoint| {
            switch (codepoint) {
                '0'...'9', 'A'...'F', 'a'...'f' => return try p.consume(),
                else => return error.UnexpectedCharacter,
            }
        }
        return error.UnexpectedEof;
    }

    pub fn string(p: *P, pass: anytype) ![]const u8 {
        const start = p.index;
        var limit: usize = p.options.iterations;
        while (pass(p)) {
            if (limit == 0) return error.IterationLimitReached;
            limit -= 1;
        } else |e| switch (e) {
            error.UnexpectedCharacter => {},
            else => return e,
        }
        return p.text[start..p.index];
    }

    pub fn string1(p: *P, pass: anytype) ![]const u8 {
        const start = p.index;
        _ = try pass(p);
        var limit: usize = p.options.iterations;
        while (pass(p)) {
            if (limit == 0) return error.IterationLimitReached;
            limit -= 1;
        } else |e| switch (e) {
            error.UnexpectedCharacter => {},
            else => return e,
        }
        return p.text[start..p.index];
    }

    pub fn not(p: *P, stop: u21) !u21 {
        if (try p.peek()) |codepoint| {
            if (codepoint == stop) return error.UnexpectedCharacter;
            return try p.consume();
        }
        return error.UnexpectedEof;
    }
};
