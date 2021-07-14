const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const math = std.math;

pub fn Wheel(comptime res: comptime_int, comptime wheels: u3) type {
    return struct {
        wheel: [wheels][64]List = [_][64]List{[_]List{.{}} ** 64} ** wheels,
        index: [wheels]u8 = [_]u8{0} ** wheels,

        fn getLevel(ticks: u64) u3 {
            return @intCast(u3, (63 - @clz(u64, ticks | 63)) / 6);
        }

        const log = std.log.scoped(.wheel);

        pub const List = std.SinglyLinkedList(Entry);
        pub const Entry = struct {
            ns: u64,
            frame: anyframe,

            pub fn format(
                value: Entry,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                _ = options;
                try writer.print("[ns: {d}]", .{value.ns});
            }
        };

        pub const Self = @This();

        pub const resolution = res;

        pub fn sleep(self: *Self, nanoseconds: u64) void {
            suspend {
                var ticks = nanoseconds / resolution;
                var level: u6 = getLevel(ticks);
                var slot = ticks >> (level * 6);

                var entry: List.Node = .{
                    .next = undefined,
                    .data = .{
                        .ns = nanoseconds,
                        .frame = @frame(),
                    },
                };

                const position = (slot + self.index[level]) & 63;

                self.wheel[level][position].prepend(&entry);
            }
        }

        pub fn tick(self: *Self) List {
            var list: List = .{};

            for (self.index) |*index, wheel| {
                while (self.wheel[wheel][index.*].popFirst()) |node| {
                    const old = node.data.ns;
                    const ticks = (old >> 6) / resolution;
                    node.data.ns >>= 6;
                    if (ticks == 0) {
                        list.prepend(node);
                    } else {
                        var level: u6 = getLevel(ticks);
                        var slot = ticks >> (level * 6);

                        const position = (slot + self.index[level]) & 63;

                        self.wheel[level][position].prepend(node);
                    }
                }

                index.* = (index.* +% 1) & 63;

                if (index.* != 0) break;
            }

            return list;
        }
    };
}

const W = Wheel(std.time.ns_per_ms, 6);
pub fn delay(w: *W) void {
    var tim = std.time.Timer.start() catch unreachable;
    var m: u64 = 0;
    const out = std.io.getStdOut().writer();
    out.writeAll("expected,gotten,difference,tick\n") catch unreachable;
    while (true) : (m += 50) {
        const n = W.resolution * m;
        w.sleep(n);
        const l = tim.lap();
        const d = @intCast(i64, l) - @intCast(i64, n);

        std.log.debug("wanted {} got {} diff {}", .{
            std.fmt.fmtDuration(n),
            std.fmt.fmtDuration(l),
            std.fmt.fmtDurationSigned(d),
        });

        out.print("{},{},{},{}\n", .{ n, l, d, m }) catch unreachable;
    }
}

test {
    testing.log_level = .debug;
    var w: W = .{};
    _ = async delay(&w);

    const os = std.os;
    const linux = os.linux;
    const timerfd = blk: {
        const tmp = linux.timerfd_create(os.linux.CLOCK_MONOTONIC, linux.TFD_CLOEXEC);
        if (linux.getErrno(tmp) != 0) return error.CannotCreateTimer;
        const fd = @intCast(os.fd_t, tmp);

        const spec: linux.itimerspec = .{
            .it_interval = .{ .tv_sec = 0, .tv_nsec = W.resolution },
            .it_value = .{ .tv_sec = 0, .tv_nsec = W.resolution },
        };

        const ret = linux.timerfd_settime(fd, 0, &spec, null);
        if (ret != 0) return error.CannotStartTimer;

        break :blk fd;
    };
    defer os.close(timerfd);

    while (true) {
        var l: u64 = 0;
        _ = try os.read(timerfd, std.mem.asBytes(&l));
        var list = w.tick();
        while (list.popFirst()) |node| resume node.data.frame;
    }
}
