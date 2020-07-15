const std = @import("std");
const mem = std.mem;

const Token = union(enum) {
    Item: struct {
        offset: usize,
        len: usize,
        pub fn slice(t: @This(), text: []const u8, index: usize) []const u8 {
            return text[index - (t.len + 1) .. (index - 1) - t.offset];
        }
    },
    End,
    Empty,
};

const ParserOptions = struct {
    delimiter: u8 = ',',
    comment: ?u8 = null,
    trim: bool = false,
};

const StreamingParser = struct {
    count: usize,
    spaces: usize,
    comment: ?u8,
    trim: bool,
    state: State,
    delimiter: u8,

    const State = enum { Item, Skip, Crlf, Comment };

    pub fn init(options: ParserOptions) StreamingParser {
        var p: StreamingParser = undefined;
        p.reset();
        p.comment = options.comment;
        p.trim = options.trim;
        p.delimiter = options.delimiter;
        return p;
    }

    pub fn reset(p: *StreamingParser) void {
        p.count = 0;
        p.spaces = 0;
        p.state = if (p.comment) |_| .Comment else .Item;
    }

    pub fn feed(p: *StreamingParser, c: u8, token: *?Token) !?Token {
        switch (p.state) {
            .Comment => switch (c) {
                '\n' => {
                    p.state = if (p.trim) .Skip else .Item;
                    p.count = 0;
                },
                else => p.count += 1,
            },
            .Skip => switch (c) {
                '\n' => {
                    p.count = 0;
                    p.state = .Item;
                },
                '\r' => {
                    p.state = .Crlf;
                    token.* = .End;
                    return .Empty;
                },
                ' ' => {},
                else => {
                    p.count = 0;
                },
            },
            .Crlf => if (c != '\n') {
                return error.MissingLineFeed;
            } else {
                p.state = .Item;
                p.count = 0;
            },
            .Item => if (c == p.delimiter or c == '\r' or c == '\n') {
                var tok: Token = undefined;
                if (p.count == 0) {
                    tok = .Empty;
                } else {
                    tok = Token{ .Item = .{ .len = p.count, .offset = p.spaces } };
                }
                if (c == '\r') {
                    p.state = .Crlf;
                    token.* = .End;
                } else if (c == '\n') {
                    token.* = .End;
                }
                p.count = 0;
                return tok;
            } else {
                if (p.trim) {
                    if (c == ' ') {
                        p.spaces += 1;
                    } else {
                        p.spaces = 0;
                        p.count += 1;
                    }
                } else {
                    p.count += 1;
                }
            },
        }
        return null;
    }
};

test "streaming parser" {
    var p = StreamingParser.init(.{});
    const text = "abc,de,f,g,-\r\n123,45,6,7,8\n+,-,=,,,";
    for (text) |byte, i| {
        var token: ?Token = null;
        _ = try p.feed(byte, &token);
    }
}

const TokenStream = struct {
    sp: StreamingParser,
    text: []const u8,
    index: usize,
    token: ?Token,

    pub fn init(text: []const u8, options: ParserOptions) TokenStream {
        var p: TokenStream = undefined;
        p.sp = StreamingParser.init(options);
        p.text = text;
        p.reset();
        return p;
    }

    pub fn reset(p: *TokenStream) void {
        p.index = 0;
        p.token = null;
    }

    pub fn next(p: *TokenStream) !?Token {
        if (p.token) |tok| {
            p.token = null;
            return tok;
        }
        if (p.index >= p.text.len) return null;
        for (p.text[p.index..]) |byte, i| {
            if (try p.sp.feed(byte, &p.token)) |item| {
                p.index += i + 1;
                return item;
            }
        } else p.index += i;
        if (p.sp.state == .Item or p.sp.state == .Skip) {
            return try p.sp.feed('\n', &p.token);
        }
        return null;
    }
};

test "token stream" {
    const text =
        \\one,two,,
        \\three,four
    ;
    var p = TokenStream.init(text, .{});
    var token: ?Token = null;
    std.testing.expectEqual(
        Token{ .Item = .{ .offset = 0, .len = 3 } },
        (try p.next()).?,
    );
    std.testing.expectEqual(
        Token{ .Item = .{ .offset = 0, .len = 3 } },
        (try p.next()).?,
    );
    std.testing.expectEqual(Token.Empty, (try p.next()).?);
    std.testing.expectEqual(Token.Empty, (try p.next()).?);
    std.testing.expectEqual(Token.End, (try p.next()).?);
    std.testing.expectEqual(
        Token{ .Item = .{ .offset = 0, .len = 5 } },
        (try p.next()).?,
    );
    std.testing.expectEqual(
        Token{ .Item = .{ .offset = 0, .len = 4 } },
        (try p.next()).?,
    );
    std.testing.expectEqual(Token.End, (try p.next()).?);
    std.testing.expectEqual(@as(?Token, null), try p.next());
}

fn parseColumn(comptime T: type, token: Token, text: []const u8, i: usize) !T {
    switch (@typeInfo(T)) {
        .Enum => |info| switch (token) {
            .Item => |item| return std.meta.stringToEnum(T, item.slice(text, i)) orelse error.InvalidEnum,
            else => return error.ExpectedEnum,
        },
        .Int => |info| switch (token) {
            .Item => |item| return try std.fmt.parseInt(T, item.slice(text, i), 10),
            else => return error.ExpectedInt,
        },
        .Float => |info| switch (token) {
            .Item => |item| return try std.fmt.parseFloat(T, item.slice(text, i)),
            else => return error.ExpectedFloat,
        },
        .Pointer => |info| {
            if (!info.is_const or info.child != u8) @compileError("only []const u8 supported");
            return switch (token) {
                .Item => |item| item.slice(text, i),
                .Empty => &[_]u8{},
                else => error.ExpectedString,
            };
        },
        .Optional => |info| switch (token) {
            .Item => return try parseColumn(info.child, token, text, i),
            .Empty => return null,
            else => return error.ExpectedItemOrNull,
        },
        else => @compileError(@typeName(T) ++ " not supported"),
    }
}

pub fn parseLine(comptime T: type, stream: *TokenStream) !T {
    switch (@typeInfo(T)) {
        .Struct => |info| {
            var r: T = undefined;
            inline for (info.fields) |field| {
                const token = (try stream.next()) orelse
                    return error.UnexpectedEndOfColumn;
                @field(r, field.name) = try parseColumn(
                    field.field_type,
                    token,
                    stream.text,
                    stream.index,
                );
            }
            if (try stream.next()) |item| {
                if (item == .End) return r;
            }
            return error.ColumnTooLong;
        },
        else => |info| @compileError(@typeName(T) ++ " not supported, only structs"),
    }
}

test "line parser" {
    var p = TokenStream.init("1,ok,4.5,\n", .{});
    const T = struct { i: usize, e: enum { ok }, f: f32, n: ?u1 };
    const expected: T = .{ .i = 1, .e = .ok, .f = 4.5, .n = null };
    std.testing.expectEqual(expected, try parseLine(T, &p));
}
