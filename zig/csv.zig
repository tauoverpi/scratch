// Copyright (c) 2020 Simon A. Nielsen Knights <tauoverpi@yandex.com>
// License: MIT

const std = @import("std");
const mem = std.mem;

pub const Token = union(enum) {
    Item: struct {
        offset: usize,
        len: usize,

        pub fn slice(t: @This(), text: []const u8, index: usize) []const u8 {
            return text[index - (t.len + 1) .. (index - 1) - t.offset];
        }
    },
    Empty,
    End,
};

pub const ParserOptions = struct {
    delimiter: u8 = ',',
    comment: ?u8 = null,
    trim: bool = false,
};

pub const StreamingParser = struct {
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

pub const TokenStream = struct {
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
        } else if (p.index > p.text.len) return null;

        for (p.text[p.index..]) |byte, i| {
            if (try p.sp.feed(byte, &p.token)) |item| {
                p.index += i + 1;
                return item;
            }
        } else p.index += i + 1;

        if (p.sp.state == .Item or p.sp.state == .Skip) {
            return try p.sp.feed('\n', &p.token);
        }
        return null;
    }
};

test "token stream" {
    const text =
        \\one,two,,
        \\three,four,
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
    std.testing.expectEqual(Token.Empty, (try p.next()).?);
    std.testing.expectEqual(Token.End, (try p.next()).?);
    std.testing.expectEqual(@as(?Token, null), try p.next());
}

fn parseColumnInternal(comptime T: type, token: Token, text: []const u8, i: usize) !T {
    switch (@typeInfo(T)) {
        .Enum => |info| switch (token) {
            .Item => |item| {
                const slice = item.slice(text, i);
                return std.meta.stringToEnum(T, item.slice(text, i)) orelse {
                    if (@typeInfo(info.tag_type).Int.bits == 0) {
                        // TODO: if this is u0 it produces invalid LLVM IR
                        const num = std.fmt.parseInt(u1, slice, 10) catch return error.InvaludEnum;
                        return std.meta.intToEnum(T, num) catch return error.InvalidEnum;
                    } else {
                        const num = std.fmt.parseInt(info.tag_type, slice, 10) catch return error.InvalidEnum;
                        return std.meta.intToEnum(T, num) catch return error.InvalidEnum;
                    }
                };
            },
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
            .Item => return try parseColumnInternal(info.child, token, text, i),
            .Empty => return null,
            else => {
                std.debug.print("{}\n", .{text[i .. i + 100]});
                return error.ExpectedItemOrNull;
            },
        },

        else => @compileError(@typeName(T) ++ " not supported"),
    }
}

pub fn parseColumn(comptime T: type, stream: *TokenStream) !T {
    const token = (try stream.next()) orelse
        return error.UnexpectedEndOfColumns;
    return try parseColumnInternal(T, token, stream.text, stream.index);
}

test "column parser" {
    var p = TokenStream.init("0", .{});
    const T = enum { only };
    std.testing.expectEqual(T.only, try parseColumn(T, &p));
}

pub const ParserComptimeOptions = struct {
    allow_missing_fields: bool = false,
    allow_superflous_fields: bool = false,
};

pub fn parseLine(
    comptime T: type,
    stream: *TokenStream,
    comptime options: ParserComptimeOptions,
) !T {
    switch (@typeInfo(T)) {
        .Struct => |info| {

            // initialize all null fields in case of configured early return
            // while calculating the number of fields we can safely skip
            comptime const computed = comptime blk: {
                var lim: usize = 0;
                var cr: T = undefined;
                for (info.fields) |field, i| {
                    const ti = @typeInfo(field.field_type);
                    if (ti == .Optional) @field(cr, field.name) = null;
                    if (ti != .Void or ti != .Optional) lim = i;
                }
                break :blk .{ .result = cr, .required = lim };
            };

            var r: T = computed.result;
            var count: usize = 0;

            inline for (info.fields) |field, i| {
                // TODO: must be written like this otherwise the compiler segfaults
                const token = (try stream.next()) orelse {
                    if (i == 0) {
                        return error.EmptyLine;
                    } else return error.UnexpectedEndOfColumns;
                };

                // allow skipping optional fields
                if (options.allow_missing_fields) {
                    count += 1;
                    if (token == .End and count >= computed.required) {
                        return r;
                    }
                } else {
                    if (token == .End) return error.ColumnTooShort;
                }

                // set the field if it's not void
                if (@typeInfo(field.field_type) != .Void) {
                    @field(r, field.name) = try parseColumnInternal(
                        field.field_type,
                        token,
                        stream.text,
                        stream.index,
                    );
                }
            }

            // skip superflous fields
            if (options.allow_superflous_fields) {
                while (try stream.next()) |item| {
                    if (item == .End) return r;
                } else return r;
            } else {
                if (try stream.next()) |item| {
                    if (item == .End) return r;
                }
                return error.ColumnTooLong;
            }
        },
        else => |info| @compileError(@typeName(T) ++ " not supported, only structs"),
    }
}
test "line parser" {
    {
        var p = TokenStream.init("1,ok,4.5,", .{});
        const T = struct { i: usize, e: enum { ok }, f: f32, n: ?u1 };
        const expected: T = .{ .i = 1, .e = .ok, .f = 4.5, .n = null };
        std.testing.expectEqual(expected, try parseLine(T, &p, .{}));
    }

    {
        var p = TokenStream.init("more,fields,which,can,be,ignored", .{});
        const T = struct { text: []const u8 };
        std.testing.expect(std.mem.eql(
            u8,
            "more",
            (try parseLine(T, &p, .{ .allow_superflous_fields = true })).text,
        ));
    }

    {
        var p = TokenStream.init("missing,ok", .{});
        const T = struct { f: enum { missing }, s: enum { ok }, n: ?usize, v: void };
        const expected: T = .{ .f = .missing, .s = .ok, .n = null, .v = {} };
        std.testing.expectEqual(
            expected,
            try parseLine(T, &p, .{ .allow_missing_fields = true }),
        );
    }
}

fn stringifyColumn(
    comptime T: type,
    value: anytype,
    out_stream: anytype,
) @TypeOf(out_stream).Error!void {
    switch (@typeInfo(T)) {
        .Float, .ComptimeFloat => try std.fmt.formatFloatScientific(value, std.fmt.FormatOptions{}, out_stream),
        .Int, .ComptimeInt => try std.fmt.formatIntValue(value, "", std.fmt.FormatOptions{}, out_stream),
        .Enum => |info| {
            inline for (info.fields) |field| {
                if (value == std.meta.stringToEnum(T, field.name).?) {
                    try out_stream.writeAll(field.name);
                    return;
                }
            }
        },
        .Pointer => |info| {
            if (!info.is_const or info.child != u8) @compileError("only []const u8 supported");
            try out_stream.writeAll(value);
        },
        else => @compileLog(T),
    }
}

pub const StringifyOptions = struct {
    delimiter: u8 = ',',
};

pub fn stringifyLine(
    value: anytype,
    options: StringifyOptions,
    out_stream: anytype,
) @TypeOf(out_stream).Error!void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Struct => |info| {
            comptime var comma = false;
            inline for (info.fields) |field, i| {
                if (comma and info.fields.len - 1 != i) try out_stream.writeAll(",");
                switch (@typeInfo(field.field_type)) {
                    .Optional => |optional| if (@field(value, field.name)) |opt| {
                        try stringifyColumn(optional.child, opt, out_Stream);
                    } else
                        try out_stream.writeAll(","),
                    .Void => try out_stream.writeAll(","),
                    else => try stringifyColumn(
                        field.field_type,
                        @field(value, field.name),
                        out_stream,
                    ),
                }
                comma = true;
            }
        },
        else => @compileError("unsupported type " ++ @typeName(T)),
    }
}

test "stringify" {
    const out = std.io.getStdOut().writer();
    const T = enum { ok };
    try stringifyLine(.{ .f = 4.4, .i = 4, .e = T.ok, .s = @as([]const u8, "a thing"), .k = {} }, .{}, out);
    try out.writeAll("\n");
}
