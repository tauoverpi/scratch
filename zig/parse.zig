const std = @import("std");

const Token = struct {
    len: usize,

    pub fn slice(t: @This(), text: []const u8, index: usize) []const u8 {
        return text[(index + 1) - t.len .. index - 1];
    }
};

const SP = struct {
    count: usize,
    state: State,

    const State = enum { Reading, Crlf };

    pub fn init() SP {
        return .{
            .count = 0,
            .state = .Reading,
        };
    }

    pub fn feed(p: *SP, c: u8) !?Token {
        switch (p.state) {
            .Reading => switch (c) {
                '\t' => p.count += 1,

                '\n', '\r' => {
                    if (c == '\r') {
                        p.state = .Crlf;
                    }
                    defer p.count = 0;
                    return .{ .len = p.count };
                },

                else => p.count += 1,
            },

            .Crlf => if (c == '\n') {
                p.state = .Reading;
                p.count = 0;
            } else {
                return error.NewlineExpected;
            },
        }
        return null;
    }
};

test "" {
    var p = SP.init();
    const text =
        \\jwfoiwejfoiwjfoijweifjwe
        \\kgoerjgoiwejgoiejrgoijwe
        \\wofjoeijgroijgoirejgiorjg
        \\
    ;
    for (text) |byte, i| {
        if (try p.feed(byte)) |item| {
            std.debug.print("{}\n", .{item.slice(text, i)});
        }
    }

    var t = TS.init(text);
    while (try t.next()) |item| {
        std.debug.print("{}\n", .{item});
    }
}

const TS = struct {
    sp: SP,
    index: usize,
    text: []const u8,

    pub fn init(text: []const u8) TS {
        return .{ .sp = SP.init(), .index = 0, .text = text };
    }

    pub fn next(p: *TS) !?Token {
        if (p.text.len < p.index) return null;
        for (p.text[p.index..]) |byte, i| {
            if (try p.sp.feed(byte)) |item| {
                p.index += i + 1;
                return item;
            }
        } else p.index += i + 1;
        return null;
    }
};
