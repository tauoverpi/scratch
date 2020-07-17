const std = @import("std");

test "rot13" {
    var last: u8 = undefined;
    // define an array of characters
    var msg = [_]u8{ 'h', 'e', 'l', 'l', 'o' };
    std.debug.print("initial: {}\nhex: ", .{&msg});

    // print in hex
    for (&msg) |c| {
        std.debug.print("{d} ", .{c});
    } else std.debug.print("\n", .{});

    // rotate every character by 13 places
    for (&msg) |_, i| {
        msg[i] += 13;
    }

    std.debug.print("\nrotated: {} (c+13)\nhex: ", .{&msg});

    for (&msg) |c| {
        std.debug.print("{d} ", .{c});
    } else std.debug.print("\n", .{});

    // rotate every character back by 13 places
    for (&msg) |_, i| {
        msg[i] -= 13;
    }

    std.debug.print("\nrestored: {} (c-13)\nhex: ", .{&msg});

    for (&msg) |c| {
        std.debug.print("{d} ", .{c});
    } else std.debug.print("\n", .{});
}
