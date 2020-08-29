const std = @import("std");
const os = std.os;

pub fn waitForThing(name: [*:0]const u8) !void {
    const fd = try os.inotify_init1(os.linux.IN_CLOEXEC);
    defer os.close(fd);
    const watch = try os.inotify_add_watchZ(fd, name, os.linux.IN_CLOSE_WRITE | os.linux.IN_ONLYDIR);
    var buffer: [4096]u8 align(@alignOf(os.linux.inotify_event)) = undefined;
    _ = os.linux.read(fd, &buffer, buffer.len);
}

pub fn main() !void {
    if (os.argv.len != 2) return error.NeedArgument;
    try waitForThing(os.argv[1]);
}
