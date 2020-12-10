const std = @import("std");
const os = std.os;
const mem = std.mem;
const parse = std.json.parse;

const TokenStream = std.json.TokenStream;
const ArrayList = std.ArrayList;

const http_header = "HTTP/2 200 OK\r\n" ++ "Server: recovery\r\n";
const text_html = "Content-Type: text/html\r\n";
const application_octet_stream = "Content-Type: application/octet-stream\r\n";
const application_json = "Content-Type: application/json\r\n";

const http_400 = "HTTP/2 400\r\n\r\n";
const index = http_header ++ text_html ++ "\r\n" ++ @embedFile("index.html");
const json_header = http_header ++ application_json;
const html_header = http_header ++ text_html;

const Msg = union(enum) {
    ping: struct {
        jsonrpc: []const u8,
        method: enum { ping },
        id: ?u32 = null,
    },
    quit: struct {
        jsonrpc: []const u8,
        method: enum { quit },
        id: ?u32 = null,
    },
};

const pong =
    \\{"jsonrpc":"2.0","method":"pong"}
;

pub fn main() !void {
    const stderr = std.io.getStdErr().writer();

    const efd = try os.epoll_create1(os.EPOLL_CLOEXEC);

    const address = std.net.Address.parseIp("0.0.0.0", 8888) catch unreachable;
    const tcp = try os.socket(os.AF_INET, os.SOCK_STREAM | os.SOCK_CLOEXEC, os.IPPROTO_TCP);
    try os.bind(tcp, &address.any, @sizeOf(os.sockaddr));
    try os.listen(tcp, 16);

    var events: [8]os.epoll_event = undefined;

    const TCP = 0;

    {
        var event: os.epoll_event = .{
            .events = os.EPOLLIN | os.EPOLLET,
            .data = .{ .u64 = TCP },
        };
        try os.epoll_ctl(efd, os.EPOLL_CTL_ADD, tcp, &event);
    }

    var stream: TokenStream = undefined;
    var buffer: [1500]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = &fba.allocator;

    while (true) for (events[0..os.epoll_wait(efd, &events, -1)]) |event| {
        defer fba.reset();
        var inbox: [4096]u8 = undefined;
        var out = ArrayList(u8).init(allocator);
        const writer = out.writer();

        switch (event.data.u64) {
            TCP => {
                const fd = try os.accept(tcp, null, null, os.SOCK_CLOEXEC);
                defer os.shutdown(fd, .both) catch os.exit(2);
                const res = inbox[0..try os.recv(fd, &inbox, os.MSG_CMSG_CLOEXEC)];

                try stderr.print("{e}\n", .{res});
                const msg = res[mem.indexOf(u8, res, "\r\n\r\n") orelse continue ..];

                if (mem.startsWith(u8, res, "GET / HTTP/1.1")) {
                    _ = try os.send(fd, index, 0);
                } else if (mem.startsWith(u8, res, "POST / HTTP/1.1")) {
                    stream = TokenStream.init(msg);

                    const request = parse(Msg, &stream, .{ .allocator = allocator }) catch {
                        _ = os.send(fd, http_400, 0) catch {};
                        continue;
                    };

                    switch (request) {
                        .ping => try writer.print(
                            "{}Content-Length: {}\r\n\r\n{}",
                            .{ json_header, pong.len, pong },
                        ),
                        .quit => std.os.exit(0),
                    }

                    _ = try os.send(fd, out.items, 0);
                } else {
                    writer.writeAll(http_400) catch unreachable;
                    _ = try os.send(fd, out.items, 0);
                    continue;
                }
            },
            else => unreachable,
        }
    };
}
