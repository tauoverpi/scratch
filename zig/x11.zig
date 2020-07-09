const std = @import("std");

const X11ConnReq = packed struct {
    order: u8,
    pad: u8,
    major: u16,
    minor: u16,
    proto: u16,
    data: u16,
    pad2: u16,
};

test "" {
    var sock = std.net.connectUnixSocket("/tmp/.X11-unix/X0") catch unreachable;
    defer sock.close();
}
