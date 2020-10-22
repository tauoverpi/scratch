const std = @import("std");
const testing = std.testing;

const Message = union(enum) {
    user: struct { nick: []const u8, mask: u8, realname: []const u8 },
    join: struct { channel: []const u8, rest: []const []const u8 },
    nick: []const u8,
    topic: struct { target: []const u8, text: ?[]const u8 },
    names: []const []const u8,
    part: struct { channel: []const u8, message: ?[]const u8 },
    ping: []const u8,
    pong: []const u8,
    privmsg: struct { nick: []const u8, message: []const u8 },
    quit: ?[]const u8,
    motd,
    version,
    admin,
    connect: struct { server: []const u8, optional: ?struct { port: ?u16, remote: ?[]const u8 = null } = null },
    time: ?[]const u8,
    stats: enum { c, h, i, k, l, m, o, u, y },
    info: ?[]const u8,
    mode: struct { nick: []const u8 },
    notice: struct { server: []const u8, message: []const u8 },
    userost: []const u8,

    pub fn render(msg: Message, writer: anytype) !void {
        switch (msg) {
            .user => |user| try writer.print("USER {} {} * :{}\r\n", .{ user.nick, user.mask, user.realname }),
            .join => |join| {
                try writer.print("JOIN {}", .{join.channel});
                for (join.rest) |channel| try writer.print(",{}", .{channel});
                try writer.writeAll("\r\n");
            },
            .nick => |nick| try writer.print("NICK {}\r\n", .{nick}),
            //.topic => |topic| if (topic.message
            //.names
            //.part
            .ping => |ping| try writer.print("PING :{}\r\n", .{ping}),
            .pong => |pong| try writer.print("PONG :{}\r\n", .{pong}),
            .privmsg => |privmsg| try writer.print("PRIVMSG {} :{}\r\n", .{ privmsg.nick, privmsg.message }),
            .quit => |quit| if (quit) |text| {
                try writer.print("QUIT :{}\r\n", .{quit});
            } else {
                try writer.writeAll("QUIT\r\n");
            },
            .motd => try writer.writeAll("MOTD\r\n"),
            .version => try writer.writeAll("VERSION\r\n"),
            .admin => try writer.writeAll("ADMIN\r\n"),
            .connect => |connect| {
                try writer.print("CONNECT {}", .{connect.server});
                if (connect.optional) |optional| {
                    try writer.print(" {}", .{optional.port});
                    if (optional.remote) |remote| try writer.print(" {}", .{remote});
                }
                try writer.writeAll("\r\n");
            },
            else => std.debug.panic("todo {}", .{msg}),
        }
    }
};

fn testRender(expected: []const u8, msg: Message) !void {
    var buf: [255]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try msg.render(writer);
    testing.expectEqualStrings(expected, fbs.getWritten());
}

test "message-user" {
    try testRender(
        "USER levy 0 * :tauoverpi\r\n",
        .{ .user = .{ .nick = "levy", .mask = 0, .realname = "tauoverpi" } },
    );
}

test "message-join" {
    const text = "JOIN :#programming\r\n";
}

test "message-nick" {
    const text = "NICK levy\r\n";
}

test "message-topic" {
    {
        // set topic
        const text = "TOPIC #programming :zig\r\n";
    }
    {
        // clear topic
        const text = "TOPIC #programming :\r\n";
    }
    {
        // check topic
        const text = "TOPIC #programming\r\n";
    }
}

test "message-names" {
    {
        // list users on channel
        const text = "NAMES #programming\r\n";
    }
    {
        // list users on server
        const text = "NAMES\r\n";
    }
}

test "message-part" {
    {
        const text = "PART #programming\r\n";
    }
    {
        const text = "PART #programming :leaving\r\n";
    }
}

test "message-ping" {
    try testRender("PING :irc.lainchan.org\r\n", .{ .ping = "irc.lainchan.org" });
}

test "message-pong" {
    try testRender("PONG :irc.lainchan.org\r\n", .{ .pong = "irc.lainchan.org" });
}

test "message-privmsg" {
    try testRender("PRIVMSG levy :message\r\n", .{ .privmsg = .{ .nick = "levy", .message = "message" } });
}

test "message-quit" {
    try testRender("QUIT\r\n", .{ .quit = null });
    try testRender("QUIT :walking the cat\r\n", .{ .quit = "walking the cat" });
}

test "message-motd" {
    try testRender("MOTD\r\n", .motd);
}

test "message-version" {
    try testRender("VERSION\r\n", .version);
}

test "message-admin" {
    try testRender("ADMIN\r\n", .admin);
}

test "message-connect" {
    try testRender("CONNECT irc.lainchan.org\r\n", .{ .connect = .{ .server = "irc.lainchan.org" } });
    try testRender(
        "CONNECT irc.lainchan.org 6667\r\n",
        .{ .connect = .{ .server = "irc.lainchan.org", .optional = .{ .port = 6667 } } },
    );
    try testRender(
        "CONNECT irc.lainchan.org 6667 irc.freenode.net\r\n",
        .{ .connect = .{ .server = "irc.lainchan.org", .optional = .{ .port = 6667, .remote = "irc.freenode.net" } } },
    );
}

test "message-time" {
    {
        const text = "TIME\r\n";
    }
    {
        const text = "TIME irc.lainchan.org\r\n";
    }
}

test "message-stats" {
    const query = "chiklmouy";
    const text = "STATS {c}\r\n";
}

test "message-info" {
    {
        const text = "INFO\r\n";
    }
    {
        const text = "INFO irc.lainchan.org\r\n";
    }
}

test "message-mode" {
    {
        // get mode
        const text = "MODE levy\r\n";
    }
}

test "message-notice" {
    const text = "NOTICE irc.lainchan.org hi\r\n";
}

test "message-userhost" {
    const text = "USERHOST levy\r\n";
}
