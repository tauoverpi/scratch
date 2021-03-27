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

                    '<', '{' => |ch| {
                        token.tag = .l_chevron;
                        state = .chevron;
                        fence = ch;
                    },

                    '>', '}' => |ch| {
                        token.tag = .r_chevron;
                        state = .chevron;
                        fence = ch;
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
                    switch (fence) {
                        '{' => {
                            token.tag = .l_brace;
                            break;
                        },

                        '}' => {
                            token.tag = .r_brace;
                            break;
                        },

                        else => {
                            token.tag = .text;
                            state = .ignore;
                        },
                    }
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

            // handle braces at the end
            .r_chevron => if (fence == '}') {
                token.tag = .r_brace;
            },

            .l_chevron => if (fence == '{') {
                token.tag = .l_brace;
            },
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

        .newline,

        .identifier,
        // The sequence which terminates the block follows.
        .newline,

        .fence,
    });
}

const NodeList = std.MultiArrayList(Node);
const Node = struct {
    tag: Tag,
    token: Index,

    pub const Tag = enum(u8) {
        tag,
        filename,
        file,
        block,
        inline_block,
        placeholder,
    };
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
        };
    }

    pub fn deinit(p: *Parser) void {
        p.tokens.deinit(p.allocator);
        p.nodes.deinit(p.allocator);
        p.* = undefined;
    }

    fn getToken(p: *Parser, index: usize) !Token {
        const starts = p.tokens.items(.start);
        var tokenizer: Tokenizer = .{ .text = p.text, .index = starts[index] };
        return tokenizer.next();
    }

    fn expect(p: *Parser, tag: Token.Tag) !void {
        defer p.index += 1;
        if (p.peek() != tag) {
            log.debug("expected {s} found {s}", .{ @tagName(tag), @tagName(p.peek().?) });
            return error.UnexpectedToken;
        }
        log.debug("expect  | {s}", .{@tagName(tag)});
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
        defer p.index += 1;
        if (p.peek() != tag) {
            log.debug("expected {s} found {s}", .{ @tagName(tag), @tagName(p.peek().?) });
            return error.UnexpectedToken;
        }
        log.debug("get     | {s}", .{@tagName(tag)});
        const slice = p.getTokenSlice(p.index);
        return slice;
    }

    fn getTokenSlice(p: *Parser, index: usize) []const u8 {
        const token = try p.getToken(index);
        return p.text[token.data.start..token.data.end];
    }

    fn consume(p: *Parser) !Token.Tag {
        const token = p.peek() orelse return error.OutOfBounds;
        log.debug("consume | {s}", .{@tagName(token)});
        p.index += 1;
        return token;
    }

    fn peek(p: *Parser) ?Token.Tag {
        const tokens = p.tokens.items(.tag);
        return if (p.index < p.tokens.len) tokens[p.index] else null;
    }

    pub fn resolve(p: *Parser) !void {
        std.testing.log_level = .debug;
        while (p.findStartOfBlock()) |tag| {
            switch (tag) {
                .inline_block => |start| try p.parseInlineBlock(start),
                .fenced_block => try p.parseFencedBlock(),
            }
        }

        for (p.nodes.items(.tag)) |tag| log.debug("node {s}", .{@tagName(tag)});
    }

    fn parseFencedBlock(p: *Parser) !void {
        const tokens = p.tokens.items(.tag);
        const fence = (p.get(.fence) catch unreachable).len;
        log.debug("<< fenced block meta >>", .{});

        const reset = p.nodes.len;
        errdefer p.nodes.shrinkRetainingCapacity(reset);

        const filename = try p.parseMetaBlock();
        try p.expect(.newline);
        log.debug("<< fenced block start >>", .{});

        const block_start = p.index;

        // find the closing fence
        while (mem.indexOfPos(Token.Tag, tokens, p.index, &.{ .newline, .fence })) |found| {
            if (p.getTokenSlice(found + 1).len == fence) {
                p.index = found + 2;
                break;
            } else {
                p.index = found + 2;
            }
        } else return error.FenceNotClosed;

        const block_end = p.index - 2;

        if (filename) |file| {
            try p.nodes.append(p.allocator, .{
                .tag = .filename,
                .token = file,
            });
            try p.nodes.append(p.allocator, .{
                .tag = .file,
                .token = @intCast(Node.Index, block_start),
            });
        } else {
            try p.nodes.append(p.allocator, .{
                .tag = .block,
                .token = @intCast(Node.Index, block_start),
            });
        }

        try p.parsePlaceholders(block_start, block_end);

        p.index = block_end + 2;

        log.debug("<< fenced block end >>", .{});
    }

    fn parsePlaceholders(p: *Parser, start: usize, end: usize) !void {
        const tokens = p.tokens.items(.tag);
        p.index = start;
        while (mem.indexOfPos(Token.Tag, tokens[0..end], p.index, &.{.l_chevron})) |found| {
            p.index = found + 1;
            log.debug("search  | {s}", .{@tagName(tokens[found])});
            const name = p.get(.identifier) catch continue;
            p.expect(.r_chevron) catch continue;

            try p.nodes.append(p.allocator, .{
                .tag = .placeholder,
                .token = @intCast(Node.Index, found),
            });
        }
    }

    fn parseInlineBlock(p: *Parser, start: usize) !void {
        const block_end = p.index;
        p.expect(.fence) catch unreachable;
        log.debug("<< inline block meta >>", .{});

        const reset = p.nodes.len;
        errdefer p.nodes.shrinkRetainingCapacity(reset);

        if ((try p.parseMetaBlock()) != null) return error.InlineFileBlock;
        log.debug("<< inline block start >>", .{});

        try p.nodes.append(p.allocator, .{
            .tag = .inline_block,
            .token = @intCast(Node.Index, block_end),
        });

        const end = p.index;
        defer p.index = end;

        try p.parsePlaceholders(start, block_end);
        log.debug("<< inline block end >>", .{});
    }

    /// Parse the metau data block which follows a fence and
    /// allocate nodes for each tag found.
    fn parseMetaBlock(p: *Parser) !?Node.Index {
        p.expect(.l_brace) catch unreachable;
        var file: ?Node.Index = null;

        try p.expect(.dot);
        const language = try p.get(.identifier);
        try p.expect(.space);

        const before = p.nodes.len;
        errdefer p.nodes.shrinkRetainingCapacity(before);

        while (true) {
            switch (try p.consume()) {
                .identifier => {
                    const key = p.getTokenSlice(p.index - 1);
                    try p.expect(.equal);
                    const string = try p.get(.string);
                    if (mem.eql(u8, "file", key)) {
                        if (file != null) return error.MultipleTargets;
                        file = @intCast(Node.Index, p.index - 3);
                    }
                },
                .hash => {
                    const name = try p.get(.identifier);
                    try p.nodes.append(p.allocator, .{
                        .tag = .tag,
                        .token = @intCast(Node.Index, p.index - 1),
                    });
                },
                .space => {},
                .r_brace => break,
                else => return error.InvalidMetaBlock,
            }
        }

        return file;
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
        \\other than ``one `<<inline>>``{.block #that}
        \\shows up.
        \\
        \\```
        \\this is a block the parser won't will pick up
        \\```
        \\
        \\```{.while #this}
        \\will be picked up
        \\```
    );
    defer p.deinit();
    try p.resolve();
}
