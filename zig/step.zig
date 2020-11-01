const std = @import("std");

fn Steppable(comptime f: anytype) type {
    return struct {
        state: @Frame(f),

        pub fn init() @This() {
            return .{ .state = async f() };
        }

        pub fn next(self: *@This()) void {
            resume self.state;
        }
    };
}

fn foo() void {
    while (true) {
        std.debug.print("hi\n", .{});
        suspend;
    }
}

pub fn main() !void {
    var frame = Steppable(foo).init();
    const reader = std.io.getStdIn().reader();
    while (true) {
        _ = try reader.skipUntilDelimiterOrEof('\n');
        frame.next();
        std.debug.print("there\n", .{});
    }
}
