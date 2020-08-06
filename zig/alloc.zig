test "" {
    const thing = comptime blk: {
        const str = ".......11111";
        var i: usize = 0;
        while (str[i] != '1') : (i += 1) {}
        var mem: [i]u8 = undefined;
        for (&mem) |*x| {
            x.* = '4';
        }
        break :blk mem;
    };
    @import("std").debug.print("{}\n", .{thing});
}
