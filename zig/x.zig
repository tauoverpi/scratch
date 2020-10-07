const std = @import("std");

const XAuth = struct {
    family: Family,
    address: []const u8,
    display: []const u8,
    name: []const u8,
    data: []const u8,

    pub const Family = u16;
};

const XAuthIterator = struct {
    cookies: []const u8,
    i: usize = 0,

    fn item(it: *XAuthIterator) ![]const u8 {
        if (it.cookies[it.i..].len < 2) return error.MalformedCookie;
        const len = std.mem.readIntSliceBig(u16, it.cookies[it.i .. it.i + 2]);
        it.i += 2;
        if (it.cookies[it.i..].len < len) return error.MalformedCookie;
        defer it.i += len;
        return it.cookies[it.i .. it.i + len];
    }

    pub fn next(it: *XAuthIterator) !?XAuth {
        if (it.i == it.cookies.len) return null;

        var r: XAuth = undefined;
        r.family = std.mem.readIntSliceNative(u16, it.cookies[it.i..2]);
        it.i += 2;
        r.address = try it.item();
        r.display = try it.item();
        r.name = try it.item();
        r.data = try it.item();

        return r;
    }
};

const XConnectHeader = packed struct {
    order: u8 = 'l',
    unused: u8 = 0,
    major: u16 = 11,
    minor: u16 = 0,
    name: u16,
    data: u16,
    unused2: u16 = 0,
};

test "" {
    const cookie_text = @embedFile("/home/tau/.Xauthority");
    var it = XAuthIterator{ .cookies = cookie_text };
    var xauth: XAuth = (try it.next()).?;

    var buffer: [1024]u8 = [_]u8{0} ** 1024;
    const header: XConnectHeader = .{ .name = @intCast(u16, xauth.name.len), .data = @intCast(u16, xauth.data.len) };
    std.mem.copy(u8, &buffer, std.mem.asBytes(&header));
    std.mem.copy(u8, buffer[@sizeOf(XConnectHeader)..], xauth.name);
    std.mem.copy(u8, buffer[@sizeOf(XConnectHeader) + xauth.data.len + 1 ..], xauth.data);
    const message = buffer[0 .. @sizeOf(XConnectHeader) + xauth.data.len + 1 + xauth.name.len + 1];

    std.debug.print("\n{}\n", .{xauth});
    std.debug.print("\nout {e}\n", .{message});
    var sock = try std.net.connectUnixSocket("/tmp/.X11-unix/X0");
    _ = try sock.write(message);
    const len = try sock.read(&buffer);
    std.debug.print("in  {} {e}\n", .{ len, buffer[0..len] });
    defer sock.close();
}
