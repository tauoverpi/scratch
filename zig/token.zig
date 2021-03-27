const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

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
        l_chevron,
        r_chevron,
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
        chevron,
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

                    'a'...'z', 'A'...'Z', '_' => {
                        token.tag = .identifier;
                        state = .identifier;
                    },

                    '"' => {
                        token.tag = .string;
                        state = .string;
                    },

                    '<' => {
                        token.tag = .l_chevron;
                        state = .chevron;
                        fence = '<';
                    },

                    '>' => {
                        token.tag = .r_chevron;
                        state = .chevron;
                        fence = '>';
                    },

                    // ignore anything we don't understand and pretend it's just
                    // regular text

                    else => {
                        token.tag = .text;
                        state = .ignore;
                    },
                },

                // states below match multi-character tokens

                .fence => if (c != fence) break,

                .chevron => if (c == fence) {
                    self.index += 1;
                    break;
                } else {
                    token.tag = .text;
                    state = .ignore;
                },

                .identifier => switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => {},
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

test "inline" {
    testTokenizer("`code`{.zig #example}", &.{
        .fence,
        .identifier,
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

test "chevron" {
    testTokenizer("<<this-is-a-placeholder>>", &.{
        .l_chevron,
        .identifier,
        .r_chevron,
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

const NodeList = std.MultiArrayList(Node);
const Node = struct {
    kind: enum(u8) { file, block, placeholder },
    // length of the block
    len: u16,
    token: Index,
    // file: unused
    // block: index of parent file
    // placeholder: index of parent block
    parent: Index,

    pub const Index = u16;
};

const TokenList = struct {
    tag: Token.Tag,
    start: Node.Index,
};

const Tokens = std.MultiArrayList(TokenList);

const Parser = struct {
    text: []const u8,
    allocator: *Allocator,
    index: usize,
    tokens: Tokens.Slice,
    nodes: NodeList,
    name_map: std.StringHashMapUnmanaged(Node.Index),
    strings: std.ArrayListUnmanaged(u8),

    const log = std.log.scoped(.parser);

    pub fn init(allocator: *Allocator, text: []const u8) !Parser {
        var tokens = Tokens{};

        var tokenizer: Tokenizer = .{ .text = text };

        while (tokenizer.index < text.len) {
            const token = tokenizer.next();
            try tokens.append(allocator, .{
                .tag = token.tag,
                .start = @intCast(Node.Index, token.data.start),
            });
        }

        return Parser{
            .text = text,
            .tokens = tokens.toOwnedSlice(),
            .index = 0,
            .nodes = NodeList{},
            .allocator = allocator,
            .name_map = std.StringHashMapUnmanaged(Node.Index){},
            .strings = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(p: *Parser) void {
        p.tokens.deinit(p.allocator);
        p.nodes.deinit(p.allocator);
        p.name_map.deinit(p.allocator);
        p.strings.deinit(p.allocator);
        p.* = undefined;
    }

    fn expect(p: *Parser, tag: Token.Tag) !void {
        if (p.peek() != tag) return error.UnexpectedToken;
        log.debug("expect  | {s}", .{@tagName(tag)});
        p.index += 1;
    }

    fn skip(p: *Parser, tags: []Token.Tag) bool {
        const token = p.peek();
        for (tags) |tag| if (tag == token) {
            log.debug("skip    | {s}", .{@tagName(token)});
            p.index += 1;
            return true;
        };
        return false;
    }

    fn get(p: *Parser, tag: Token.Tag) ![]const u8 {
        if (p.peek() != tag) return error.UnexpectedToken;
        log.debug("get     | {s}", .{@tagName(tag)});
        const slice = p.getIndex(p.index);
        p.index += 1;
        return slice;
    }

    fn getIndex(p: *Parser, index: usize) []const u8 {
        const starts = p.tokens.items(.start);
        var tokenizer: Tokenizer = .{ .text = p.text, .index = starts[index] };
        const token = tokenizer.next();
        return p.text[token.data.start..token.data.end];
    }

    fn consume(p: *Parser) !Token.Tag {
        const token = p.peek();
        log.debug("consume | {s}", .{@tagName(token)});
        p.index += 1;
        return token;
    }

    fn peek(p: *Parser) Token.Tag {
        const tokens = p.tokens.items(.tag);
        return tokens[p.index];
    }

    pub fn resolve(p: *Parser) !void {
        std.testing.log_level = .debug;
        while (p.findStartOfBlock()) |kind| {
            switch (kind) {
                .inline_block => |start| try p.parseInlineBlock(start),
                .fenced_block => try p.parseFencedBlock(),
            }
        }
    }

    fn parseFencedBlock(p: *Parser) !void {
        const fence = (p.get(.fence) catch unreachable).len;
        log.debug("<< fenced block meta >>", .{});

        const meta_index = try p.parseMetaBlock();
        try p.expect(.newline);
        log.debug("<< fenced block >>", .{});
    }

    fn parseInlineBlock(p: *Parser, start: usize) !void {
        p.expect(.fence) catch unreachable;
        log.debug("<< inline block meta >>", .{});

        const meta_index = try p.parseMetaBlock();
        log.debug("<< inline block >>", .{});
        const end = p.index;
        defer p.index = end;
    }

    fn parseMetaBlock(p: *Parser) !void {
        p.expect(.l_brace) catch unreachable;
        var is_file = false;

        try p.expect(.dot);
        const language = try p.get(.identifier);
        try p.expect(.space);

        while (true) {
            switch (try p.consume()) {
                .identifier => {
                    const key = p.getIndex(p.index - 1);
                    try p.expect(.equal);
                    const string = try p.get(.string);
                    if (mem.eql(u8, "file", key)) {
                        if (is_file) return error.MultipleTargets;
                        is_file = true;
                        // TODO
                    }
                },
                .hash => {
                    const name = try p.get(.identifier);
                    // TODO
                },
                .space => {},
                .r_brace => break,
                else => return error.InvalidMetaBlock,
            }
        }
    }

    const Block = union(enum) {
        inline_block: usize,
        fenced_block,
    };

    /// Find the start of a fenced or inline code block
    fn findStartOfBlock(self: *Parser) ?Block {
        const tokens = self.tokens.items(.tag);
        const starts = self.tokens.items(.start);

        while (self.index < self.tokens.len) {
            // search for a multi-line/inline code block `{.z
            const block = mem.indexOfPos(Token.Tag, tokens, self.index, &.{
                .fence,
                .l_brace,
                .dot,
                .identifier,
            }) orelse return null;

            // figure out of this the real start
            const newline = mem.lastIndexOfScalar(Token.Tag, tokens[0..block], .newline) orelse 0;

            if (newline + 1 == block or newline == block) {
                // found fenced block

                var tokenizer: Tokenizer = .{ .text = self.text, .index = starts[block] };
                const token = tokenizer.next();
                assert(token.tag == .fence);
                if (token.data.end - token.data.start >= 3) {
                    self.index = block;
                    return .fenced_block;
                } else {
                    // not a passable codeblock, skip it and keep searching
                    self.index = block + 1;
                }
            } else if (mem.indexOfScalarPos(Token.Tag, tokens[0..block], newline, .fence)) |start| {
                // found inline block TODO: fix for `` ` ``{.zig}

                if (start < block) {
                    // by the time we've verified the current block to be inline we've also
                    // found the start of the block thus we return the start to avoid
                    // searcing for it again
                    self.index = block;
                    return Block{ .inline_block = start };
                } else {
                    // not a passable codeblock, skip it and keep searching
                    self.index = block + 1;
                }
            }
        } else return null;
    }
};

test "parse simple" {
    var p = try Parser.init(std.testing.allocator,
        \\This is an example file with some text that will
        \\cause the tokenizer to fill the token slice with
        \\garbage until the block below is reached.
        \\
        \\To make sure sequences with strings that "span
        \\multiple lines" are handled it's placed here.
        \\
        \\```{.this file="is.ok"}
        \\code follows which will again generage garbage
        \\however! <<this-block-is-not>> and some of the
        \\<<code-that-follows-like-this>> will be spliced
        \\in later.
        \\```
        \\
        \\The rest of the file isn't really interesting
        \\other than `one`{.inline #block} that shows up.
        \\
        \\```
        \\this is a block the parser won't will pick up
        \\```
    );
    defer p.deinit();
    try p.resolve();
}
