const std = @import("std");

test "" {
    var alpha = [_][257]usize{[_]usize{0} ** 257} ** 256;
    var position: usize = 0;
    for (@embedFile(@src().file)) |byte| {
        alpha[position][byte] += 1;
        alpha[position][256] += 1;
        position = byte;
    }

    position = 0;
    var rng = &std.rand.DefaultPrng.init(@intCast(u64, std.time.timestamp())).random;
    var limit: usize = 500;

    while (limit > 0) : (limit -= 1) {
        const chosen = rng.uintLessThan(usize, alpha[position][256] + 1);
        var count: usize = 0;
        for (alpha[position][0 .. alpha[position].len - 1]) |freq, i| {
            count += alpha[position][i];
            if (count >= chosen) {
                position = i;
                std.debug.print("{c}", .{@truncate(u8, i)});
                break;
            }
        }
    }
}
