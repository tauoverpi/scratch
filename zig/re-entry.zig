const std = @import("std");

pub fn panic(_: []const u8, x: ?*std.builtin.StackTrace) noreturn {
    std.log.info("panic", .{});
    _ = x;
    var k: u32 = undefined;
    std.log.info("{}", .{&k});
    @call(.{ .stack = &the_stack }, indirect, .{true});
    unreachable;
}

fn runner() void {
    var x: u32 = 1;
    const f = 1 / (x - 1);
    _ = f;
}

var the_stack: [1024 * 1024 * 8]u8 align(std.Target.stack_align) = undefined;

fn indirect(crashed: bool) void {
    std.log.info("crashed {}", .{crashed});

    if (!crashed) {
        runner();
    }

    std.os.exit(0);
}

pub fn main() void {
    @call(.{ .stack = &the_stack }, indirect, .{false});
}
