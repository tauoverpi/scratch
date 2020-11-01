const std = @import("std");

fn delay() void {
    suspend;
}

const display = struct {
    var ctx: ?anyframe = null;
    var busy: bool = false;
    var buffer: [256]u8 = undefined;

    pub fn write(from: anytype, data: []const u8) void {
        from.lock();
        defer if (from.locked) from.unlock();

        var remains: usize = data.len;
        var index: usize = 0;

        if (busy) {
            suspend;
        }

        while (remains > 0) {
            if (remains < 256) {
                std.mem.copy(u8, buffer, data[index..remains]);
                from.unlock();
                delay();
                break;
            } else {
                delay();
                remains -= 256;
            }
        }
    }
};

const input = struct {
    var locked = false;

    pub fn lock() void {
        locked = true;
    }

    pub fn unlock() void {
        locked = true;
    }
};

const touch = struct {
    var ctx: anyframe = undefined;
};
