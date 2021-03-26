const std = @import("std");
const testing = std.testing;

pub const Token = struct {
    /// Syntactic atom which this token represents.
    tag: Tag,

    /// Position where this token resides within the text.
    data: Data,

    pub const Data = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        eof,
        invalid,
        space,
        newline,
        text,
        fence,
        l_brace,
        r_brace,
        dot,
        identifier,
        equal,
        string,
        hash,
    };
};

const Tokenizer = struct {
    text: []const u8,
    index: usize = 0,

    const State = enum {
        start,
        fence,
        ignore,
        identifier,
        string,
        space,
    };

    pub fn next(self: *Tokenizer) Token {
        // since there are different kinds of fences we'll keep track
        // of which by storing the first byte. We don't care more than
        // this though as the parser is in charge of validating further.
        var fence: u8 = undefined;

        var token: Token = .{
            .tag = .eof,
            .data = .{
                .start = self.index,
                .end = undefined,
            },
        };

        var state: State = .start;

        while (self.index < self.text.len) : (self.index += 1) {
            const c = self.text[self.index];
            switch (state) {
                .start => switch (c) {
                    // simple tokens return their result directly

                    '{' => {
                        token.tag = .l_brace;
                        self.index += 1;
                        break;
                    },

                    '}' => {
                        token.tag = .r_brace;
                        self.index += 1;
                        break;
                    },

                    '.' => {
                        token.tag = .dot;
                        self.index += 1;
                        break;
                    },

                    '#' => {
                        token.tag = .hash;
                        self.index += 1;
                        break;
                    },

                    '=' => {
                        token.tag = .equal;
                        self.index += 1;
                        break;
                    },

                    '\n' => {
                        token.tag = .newline;
                        self.index += 1;
                        break;
                    },

                    // longer tokens require scanning further to fully resolve them

                    ' ' => {
                        token.tag = .space;
                        state = .space;
                    },

                    '`', '~', ':' => |ch| {
                        token.tag = .fence;
                        state = .fence;
                        fence = ch;
                    },

                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {
                        token.tag = .identifier;
                        state = .identifier;
                    },

                    '"' => {
                        token.tag = .string;
                        state = .string;
                    },

                    // ignore anything we don't understand and pretend it's just
                    // regular text

                    else => {
                        token.tag = .text;
                        state = .ignore;
                    },
                },

                // states below match multi-character tokens

                .fence => if (c != fence) {
                    if (self.index - token.data.start < 3) {
                        // not enough fence characters to be a fence and the
                        // rest we have no clue what to do with nor do we really
                        // care.
                        state = .ignore;
                        token.tag = .eof;
                    } else break;
                },

                .identifier => switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                    else => break,
                },

                .string => switch (c) {
                    '\n', '\r' => {
                        token.tag = .invalid;
                        self.index += 1;
                        break;
                    },
                    '"' => {
                        self.index += 1;
                        break;
                    },
                    else => {},
                },

                .space => switch (c) {
                    ' ' => {},
                    else => break,
                },

                .ignore => switch (c) {
                    '\n' => {
                        token.tag = .text;
                        break;
                    },
                    else => {},
                },
            }
        } else switch (token.tag) {
            // eof before terminating the string
            .string => token.tag = .invalid,
            else => {},
        }

        // finally set the length
        token.data.end = self.index;

        return token;
    }
};

fn testTokenizer(text: []const u8, tags: []const Token.Tag) void {
    var p: Tokenizer = .{ .text = text };
    for (tags) |tag, i| {
        const token = p.next();
        testing.expectEqual(tag, token.tag);
    }
    testing.expectEqual(Token.Tag.eof, p.next().tag);
    testing.expectEqual(text.len, p.index);
}

test "fences" {
    testTokenizer("```", &.{.fence});
    testTokenizer("~~~", &.{.fence});
    testTokenizer(":::", &.{.fence});
    testTokenizer(",,,", &.{.text});
}

test "language" {
    testTokenizer("```zig", &.{ .fence, .identifier });
}

test "definition" {
    testTokenizer("```{.zig #example}", &.{
        .fence,
        .l_brace,
        .dot,
        .identifier,
        .space,
        .hash,
        .identifier,
        .r_brace,
    });
}

test "caption" {
    testTokenizer(
        \\~~~{.zig caption="example"}
        \\some arbitrary text
        \\
        \\more
        \\~~~
    , &.{
        .fence,
        .l_brace,
        .dot,
        .identifier,
        .space,
        .identifier,
        .equal,
        .string,
        .r_brace,
        .newline,
        // newline
        // note: this entire block is what you would ignore in the parser until
        // you see the sequence .newline, .fence which either closes or opens a
        // code block. If there's no .l_brace then it can be ignored as it's not
        // a literate block. This is based on how entangled worked before 1.0
        .identifier,
        .space,
        .identifier,
        .space,
        .identifier,
        .newline,
        // newline
        .newline,
        // newline
        .identifier,
        // The sequence which terminates the block follows.
        .newline,
        // newline
        .fence,
    });
}
