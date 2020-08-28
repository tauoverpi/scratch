const std = @import("std");

//test "" {
//    var sock = std.net.connectUnixSocket("/tmp/.X11-unix/X0") catch unreachable;
//    defer sock.close();
//}

const Token = union(enum) {
    Family: u16,
    Address: usize,
    Display: usize,
    Name: usize,
    Data: usize,

    pub fn slice(t: Token, text: []const u8, i: usize) []const u8 {
        return switch (t) {
            .Family => "",
            .Address, .Display, .Name, .Data => |n| text[i - n .. i],
        };
    }
};

const StreamingParser = struct {
    count: usize = 1,
    state: State = .Family,
    tmp: u16 = 0,

    const State = enum { Family, AddrLen, Address, DispLen, Display, NameLen, Name, DataLen, Data };

    pub fn feed(p: *StreamingParser, c: u8) ?Token {
        switch (p.state) {
            .Family, .AddrLen, .DispLen, .NameLen, .DataLen => if (p.count == 0) {
                p.tmp <<= 8;
                p.tmp |= c;
                if (p.state == .Family) {
                    p.state = .AddrLen;
                    p.count = 1;
                    return Token{ .Family = p.tmp };
                }
                p.count = p.tmp - 1;
                p.state = switch (p.state) {
                    .Family => .AddrLen,
                    .AddrLen => .Address,
                    .DispLen => .Display,
                    .NameLen => .Name,
                    .DataLen => .Data,
                    else => unreachable,
                };
            } else {
                p.count -= 1;
                p.tmp <<= 8;
                p.tmp |= c;
            },

            .Address, .Display, .Name, .Data => if (p.count == 0) {
                defer p.state = switch (p.state) {
                    .Address => .DispLen,
                    .Display => .NameLen,
                    .Name => .DataLen,
                    .Data => .Family,
                    else => unreachable,
                };
                const count = p.tmp;
                p.count = 1;
                p.tmp = 0;
                return switch (p.state) {
                    .Address => Token{ .Address = count },
                    .Display => Token{ .Display = count },
                    .Name => Token{ .Name = count },
                    .Data => Token{ .Data = count },
                    else => unreachable,
                };
            } else {
                p.count -= 1;
            },
        }
        return null;
    }
};

const TokenStream = struct {
    i: usize,
    buffer: []const u8,
    sp: StreamingParser,

    pub fn init(text: []const u8) TokenStream {
        return .{ .buffer = text, .i = 0, .sp = StreamingParser{} };
    }

    pub fn next(t: *TokenStream) ?Token {
        if (t.i >= t.buffer.len) return null;
        while (t.i < t.buffer.len) : (t.i += 1) {
            if (t.sp.feed(t.buffer[t.i])) |item| {
                t.i += 1;
                return item;
            }
        } else return null;
    }
};

const XAuthIterator = struct {
    ts: TokenStream,

    pub fn next(a: *XAuthIterator) !XAuth {
        return XAuth{
            .family = ts.next() orelse return error.MissingFamily,
            .address = ts.next() orelse return error.MissingFamily,
            .display = ts.next() orelse return error.MissingFamily,
            .name = ts.next() orelse return error.MissingFamily,
            .data = ts.next() orelse return error.MissingFamily,
        };
    }
};

test "" {
    const auth = @embedFile("/home/tau/.Xauthority");
    var ts = TokenStream.init(auth);
    const family = ts.next().?.Family;
    const address = ts.next().?.slice(ts.buffer, ts.i);
    const display = ts.next().?.slice(ts.buffer, ts.i);
    const name = ts.next().?.slice(ts.buffer, ts.i);
    const data = ts.next().?.slice(ts.buffer, ts.i);

    var sock = try std.net.connectUnixSocket("/tmp/.X11-unix/X0");
    defer sock.close();
}
