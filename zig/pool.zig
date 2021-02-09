const std = @import("std");
const os = std.os;
const time = std.time;
const net = std.net;
const assert = std.debug.assert;

const Pool = struct {
    connections: [1024]Connection = undefined,
    index: usize = 0,

    const Connection = struct {
        start: i64,
        stream: net.Stream,
    };

    const Token = enum { _ };

    pub fn add(self: *Pool, fd: os.fd_t) Token {
        defer self.index += 1;
        self.fd[self.index] = .{
            .start = time.milliTimestamp(),
            .stream = Stream{ .handle = fd },
            .address = net.Address,
        };
        return @intToEnum(Token, self.index);
    }

    pub fn get(self: Pool, token: Token) Connection {
        return self.connections[@enumToInt(token)];
    }

    pub fn remove(self: *Pool, token: Token) void {
        assert(self.index != 0);
        const index = @enumToInt(token);
        self.connections[index].stream.close();
        self.connections[index] = undefined;
        if (self.index - 1 == index) {
            self.index -= 1;
        } else {
            self.connections[index] = self.connections[self.index - 1];
            self.index -= 1;
        }
    }
};

pub fn main() !void {
    var http = net.StreamServer.init();
    try http.listen(net.Address.parseIp("0.0.0.0", 8080));

    const epoll = try Epoll(enum { http, client }).init(.{});
    try epoll.add(http, server.sockfd.?, .{ .in = true, .et = true });

    while (epoll.next()) |event| switch (event.tag) {
        .http => {
            const welcome = "hi";
            var con = try http.accept();
            errdefer con.stream.close();
            con.stream.writer().writeAll( // index.html
                "HTTP/1.1 200 OK\r\n" ++
                "Server: example\r\n" ++
                "Content-Type: text/plain\r\n" ++
                std.fmt.comptimePrint("Content-Length: {}\r\n", .{welcome.len}) ++
                "\r\n" ++
                welcome);
            pool.add(con.stream.handle);
        },
        .client => {
            errdefer pool.remove(event.fd);
        },
        .timeout => {
            const now = time.milliTimestamp();
            for (pool.connections) |con| {
                if (now < con.start + 60 * time.ms_per_s) {
                    pool.remove(i);
                    epoll.del(con.stream.fd);
                }
            }
        },
    };
}
