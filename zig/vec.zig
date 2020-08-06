const std = @import("std");
test "" {
    const Vu8 = std.meta.Vector(16, u8);
    const route: Vu8 = .{ '/', 'o', 'p', 't', '/', 'r', 'o', 'u', 't', 'e', '.', '.', '.', '.', '.', '.' };
    const val: Vu8 = .{ '/', 0, 0, 0, '/', 0, 0, 0, 0, 0, 0, 0, 0 };
    const bar: [16]u8 = route;
    std.debug.print("{} {}\n", .{ val == route, bar });
}
