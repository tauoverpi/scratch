const std = @import("std");

const offsets = .{ .r = 7, .g = 11, .b = 15 };
const fullblock = "\x1b[48;2;000;000;000m\x1b[38;2;000;000;000m▄";
const display = blk: {
    const line = fullblock ** 160 ++ "\n";
    var buffer: [line.len * (144 / 2)]u8 = undefined;
    var i :usize=0;
    while (i < (144/2)) : (i += 1) {
       std.mem.copy(u8, buffer[
    }
};
