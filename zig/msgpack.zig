const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const Token = union(enum) {
    Object: struct {},
    Array: struct {},
    String: struct {},
    Number: struct { bits: u16, signed: bool },
    True,
    False,
    Nil,
};

const StreamingParser = struct {
    count: usize,
    state: State,

    const State = enum { Start, U8, U16, U32, U64 };

    pub fn init() StreamingParser {
        return .{ .count = 0, .state = .Start };
    }

    pub fn feed(p: *StreamingParser, c: u8) !?Token {
        switch (p.state) {
            .Start => switch (c) {
                0xc0 => return .Nil,
                0xc2 => return .False,
                0xc3 => return .True,
                0x00...0x7f => return Token{ .Number = .{ .bits = 7, .signed = false } },
                0xe0...0xff => return Token{ .Number = .{ .bits = 5, .signed = true } },

                0xcc => p.state = .U8,
                0xcd => {
                    p.count = 1;
                    p.state = .U16;
                },
                0xce => {
                    p.count = 3;
                    p.state = .U32;
                },
                0xcf => {
                    p.count = 7;
                    p.state = .U64;
                },
                else => return error.NotImplemented,
            },

            .U8 => {
                p.state = .Start;
                return Token{ .Number = .{ .bits = 8, .signed = false } };
            },
            .U16 => if (p.count == 0) {
                p.state = .Start;
                return Token{ .Number = .{ .bits = 16, .signed = false } };
            } else {
                p.count -= 1;
            },
            .U32 => if (p.count == 0) {
                p.state = .Start;
                return Token{ .Number = .{ .bits = 32, .signed = false } };
            } else {
                p.count -= 1;
            },
            .U64 => if (p.count == 0) {
                p.state = .Start;
                return Token{ .Number = .{ .bits = 64, .signed = false } };
            } else {
                p.count -= 1;
            },
        }
        return null;
    }
};

// zig fmt: off
const example_message = &[_]u8{
        0xc0, // nil
        0xc2, // false
        0xc3, // true
        0x05, // positive fixint
        0xff, // negative fixint
        0xcc,  0xff, // u8
        0xcd, 0x00, 0xff, // u16
        0xce, 0x00, 0x00, 0x00, 0xff, // u32
        0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, // u64
};
// zig fmt: on

test "streaming parser" {
    var p = StreamingParser.init();
    for (example_message) |byte| {
        if (try p.feed(byte)) |item| {
            std.debug.print("{}\n", .{item});
        }
    }
}

const old = struct {
    const Token = union(enum) {
        Nil, // 0xc0
        False, // 0xc2
        True, // 0xc3
        PositiveFixint: u7, // 0x00 - 0x7f
        NegativeFixint: u5, // 0xe0 - 0xff
        Int: struct { size: u8, signed: bool },
        Float: u8,
        Str: usize,
    };

    const StreamingParser = struct {
        count: usize,
        state: State,
        tmp: union { length: u64 },

        const State = enum {
            Start,
            Uint8,
            Uint16,
            Uint32,
            Uint64,
            Int8,
            Int16,
            Int32,
            Int64,
            Float32,
            Float64,
            FixStr,
            Str8,
            Str16,
            Str16Len,
            Str32,
            Str32Len1,
            Str32Len2,
            Str32Len3,
            StrLoop,
        };

        pub fn init() StreamingParser {
            var p: StreamingParser = undefined;
            p.reset();
            return p;
        }

        pub fn reset(self: *StreamingParser) void {
            self.count = 0;
            self.state = .Start;
        }

        pub fn feed(self: *StreamingParser, c: u8) !?Token {
            std.debug.print("{}\n", .{self.state});
            self.count += 1;
            switch (self.state) {
                .Start => {
                    self.count = 0;
                    switch (c) {
                        0xc0 => return .Nil,
                        0xc2 => return .False,
                        0xc3 => return .True,
                        0x00...0x7f => return Token{ .PositiveFixint = @truncate(u7, c) },
                        0xe0...0xff => return Token{ .NegativeFixint = @truncate(u5, c) },
                        0xcc => self.state = .Uint8,
                        0xcd => self.state = .Uint16,
                        0xce => self.state = .Uint32,
                        0xcf => self.state = .Uint64,
                        0xd0 => self.state = .Int8,
                        0xd1 => self.state = .Int16,
                        0xd2 => self.state = .Int32,
                        0xd3 => self.state = .Int64,
                        0xca => self.state = .Float32,
                        0xcb => self.state = .Float64,
                        0xa0...0xbf => {
                            self.tmp.length = c & 0b00011111;
                            self.state = .FixStr;
                        },
                        0xd9 => self.state = .Str8,
                        0xda => self.state = .Str16,
                        0xdb => self.state = .Str32,
                        else => return error.NotImplemented,
                    }
                },

                .Uint8 => {
                    self.state = .Start;
                    return Token{ .Int = .{ .size = 1, .signed = false } };
                },
                .Uint16 => if (self.count == 2) {
                    self.state = .Start;
                    return Token{ .Int = .{ .size = 2, .signed = false } };
                },
                .Uint32 => if (self.count == 4) {
                    self.state = .Start;
                    return Token{ .Int = .{ .size = 4, .signed = false } };
                },
                .Uint64 => if (self.count == 8) {
                    self.state = .Start;
                    return Token{ .Int = .{ .size = 8, .signed = false } };
                },

                .Int8 => {
                    self.state = .Start;
                    return Token{ .Int = .{ .size = 1, .signed = true } };
                },
                .Int16 => if (self.count == 2) {
                    self.state = .Start;
                    return Token{ .Int = .{ .size = 2, .signed = true } };
                },
                .Int32 => if (self.count == 4) {
                    self.state = .Start;
                    return Token{ .Int = .{ .size = 4, .signed = true } };
                },
                .Int64 => if (self.count == 8) {
                    self.state = .Start;
                    return Token{ .Int = .{ .size = 8, .signed = true } };
                },

                .Float32 => if (self.count == 4) {
                    self.state = .Start;
                    return Token{ .Float = 4 };
                },
                .Float64 => if (self.count == 8) {
                    self.state = .Start;
                    return Token{ .Float = 8 };
                },

                .FixStr => if (self.count == self.tmp.length) {
                    self.state = .Start;
                    return Token{ .Str = self.tmp.length };
                },
                .Str8 => {
                    self.tmp.length = c;
                    self.state = .StrLoop;
                    self.count = 0;
                },
                .Str16 => {
                    self.tmp.length = @as(u64, c) << 8;
                    self.state = .Str16Len;
                },
                .Str16Len => {
                    self.tmp.length |= c;
                    self.count = 0;
                    self.state = .StrLoop;
                },
                .Str32 => {
                    self.tmp.length = @as(u64, c) << 8;
                    self.state = .Str32Len1;
                },
                .Str32Len1 => {
                    self.tmp.length = @as(u64, c) << 8;
                    self.state = .Str32Len2;
                },
                .Str32Len2 => {
                    self.tmp.length = @as(u64, c) << 8;
                    self.state = .Str32Len3;
                },
                .Str32Len3 => {
                    self.tmp.length = @as(u64, c) << 8;
                    self.count = 0;
                    self.state = .StrLoop;
                },
                .StrLoop => if (self.count == self.tmp.length) {
                    self.state = .Start;
                    return Token{ .Str = self.tmp.length };
                },
            }
            return null;
        }
    };

    pub const TokenStream = struct {
        sp: StreamingParser,
        bytes: []const u8,
        index: usize,

        pub fn init(bytes: []const u8) TokenStream {
            var p: TokenStream = undefined;
            p.bytes = bytes;
            p.reset();
            return p;
        }

        pub fn reset(self: *TokenStream) void {
            self.index = 0;
            self.sp.reset();
        }

        pub fn next(self: *TokenStream) !?Token {
            if (self.index >= self.bytes.len) return null;
            for (self.bytes[self.index..]) |byte, i| {
                if (try self.sp.feed(byte)) |item| {
                    self.index += i + 1;
                    return item;
                }
            } else return null;
        }
    };

    // zig fmt: off
    const test_input = &[_]u8{
        0xc0, // nil
        0xc2, // false
        0xc3, // true
        0x05, // positive fixint
        0xff, // negative fixint
        0xcc,
        0xff, // u8
        0xcd,
        0x00,
        0xff, // u16
        0xce,
        0x00,
        0x00,
        0x00,
        0xff, // u32
        0xcf,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xff, // u64
        0xd0,
        0xff, // i8
        0xd1,
        0x00,
        0xff, // i16
        0xd2,
        0x00,
        0x00,
        0x00,
        0xff, // i32
        0xd3,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xff, // i64
        0xca,
        0x00,
        0x00,
        0x00,
        0xff, // float32
        0xcb,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xff, // float64
        0xa2,
        0x00,
        0x00, // fixstr(2)
        0xd9,
        0x01,
        0x00, // str8(1)
        0xda,
        0x00,
        0x03,
        0x00,
        0x00,
        0x00, // str16(3)
        0xdb,
        0x00,
        0x00,
        0x00,
        0x02,
        0x00,
        0x00, // str32(2)
    };
    // zig fmt: on

    test "" {
        var p = TokenStream.init(test_input);
        testing.expect((try p.next()).? == .Nil);
        testing.expect((try p.next()).? == .False);
        testing.expect((try p.next()).? == .True);
        testing.expect((try p.next()).? == .PositiveFixint);
        testing.expect((try p.next()).? == .NegativeFixint);
        testing.expectEqual((try p.next()).?, Token{ .Int = .{ .size = 1, .signed = false } });
        testing.expectEqual((try p.next()).?, Token{ .Int = .{ .size = 2, .signed = false } });
        testing.expectEqual((try p.next()).?, Token{ .Int = .{ .size = 4, .signed = false } });
        testing.expectEqual((try p.next()).?, Token{ .Int = .{ .size = 8, .signed = false } });
        testing.expectEqual((try p.next()).?, Token{ .Int = .{ .size = 1, .signed = true } });
        testing.expectEqual((try p.next()).?, Token{ .Int = .{ .size = 2, .signed = true } });
        testing.expectEqual((try p.next()).?, Token{ .Int = .{ .size = 4, .signed = true } });
        testing.expectEqual((try p.next()).?, Token{ .Int = .{ .size = 8, .signed = true } });
        testing.expectEqual((try p.next()).?, Token{ .Float = 4 });
        testing.expectEqual((try p.next()).?, Token{ .Float = 8 });
        testing.expectEqual((try p.next()).?, Token{ .Str = 2 });
        testing.expectEqual((try p.next()).?, Token{ .Str = 1 });
        testing.expectEqual((try p.next()).?, Token{ .Str = 3 });
        testing.expectEqual((try p.next()).?, Token{ .Str = 1 });

        testing.expect((try p.next()) == null);
    }

    pub const ParseOptions = struct {
        allocator: ?*Allocator = null,
    };

    pub fn parseInternal(comptime T: type, token: Token, tokens: *TokenStream, options: ParseOptions) !T {
        switch (@typeInfo(T)) {
            .Int => |info| {
                switch (info.bits) {
                    7 => if (token == .PositiveFixint) {
                        return token.PositiveFixint;
                    } else {
                        return error.InvalidType;
                    },
                    else => @compileError("not supported"),
                }
            },
            else => @compileError("not implemented " ++ @typeName(T)),
        }
    }

    pub fn parse(comptime T: type, tokens: *TokenStream, options: ParseOptions) !T {
        const token = (try tokens.next()) orelse return error.UnexpectedEndOfMsgpack;
        return parseInternal(T, token, tokens, options);
    }

    //test "parse from type" {
    //var ts = TokenStream.init(&[_]u8{0x7});
    //testing.expectEqual(try parse(u8, &ts, .{}), 7);
    //}
};
