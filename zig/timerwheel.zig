const std = @import("std");
const math = std.math;
const fmt = std.fmt;
const testing = std.testing;

pub fn TimerWheel(
    comptime res: comptime_int,
    comptime wheels: comptime_int,
) type {
    return struct {
        wheel: [wheels][64]List = [_][64]List{[_]List{.{}} ** 64} ** wheels,
        index: [wheels]u8 = [_]u8{0} ** wheels,

        const log = std.log.scoped(.wheel);

        pub const List = std.TailQueue(Entry);

        pub const resolution = res;

        const Self = @This();

        pub const Entry = struct {
            ticks: u64,
            frame: anyframe,

            pub fn format(
                entry: Entry,
                comptime _: []const u8,
                options: fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = options;
                try writer.print("[ticks: {}]", .{entry.ticks});
            }
        };

        const power = blk: {
            var table: [wheels]u64 = undefined;
            for (table) |*level, i| level.* = math.pow(u64, 64, i);
            break :blk table;
        };

        fn getLevel(ticks: u64) u8 {
            for (power) |_, i| {
                const p = ((wheels - 1) - i);
                if (ticks >= power[p] - 1) return @intCast(u8, p);
            }
            unreachable;
        }

        fn getSlot(level: u8, ticks: u64) u8 {
            if (level == 0) {
                return @intCast(u8, ticks);
            } else {
                const slot = (ticks / power[level]);
                return @intCast(u8, slot);
            }
        }

        pub fn sleep(self: *Self, offset: u64) void {
            self.sleepTicks(offset / resolution);
        }

        pub fn sleepTicks(self: *Self, ticks: u64) void {
            suspend {
                const level = getLevel(ticks);
                const slot = getSlot(level, ticks);
                const w_slot = (slot + self.index[level]) & 63;
                var entry: List.Node = .{
                    .next = undefined,
                    .data = .{
                        .ticks = ticks,
                        .frame = @frame(),
                    },
                };

                log.debug("new entry level:{} slot:{} ticks:{} ({})", .{
                    level,
                    slot,
                    ticks,
                    fmt.fmtDuration(ticks * resolution),
                });

                self.wheel[level][w_slot].append(&entry);
            }
        }

        pub fn tick(self: *Self) List {
            var list: List = self.wheel[0][self.index[0]];
            self.wheel[0][self.index[0]] = .{};

            for (self.index) |*index, wheel| {
                while (self.wheel[wheel][index.*].popFirst()) |node| {
                    const ticks = node.data.ticks;
                    if (ticks == 0) {
                        list.append(node);
                    } else {
                        // reschedule

                        const level = getLevel(ticks);
                        const slot = getSlot(level, ticks);

                        const reduction = power[level] * (slot + 1);
                        const n_ticks = math.sub(u64, ticks, reduction) catch 0;
                        log.debug("{} <- {} ({})", .{ n_ticks, ticks, reduction });
                        const n_level = getLevel(n_ticks);
                        const n_slot = getSlot(n_level, n_ticks);
                        const w_slot = (n_slot + self.index[n_level]) & 63;

                        node.data.ticks = n_ticks;

                        log.debug("moved entry " ++
                            "level:{} slot:{} ticks:{} -> " ++
                            "level:{} slot:{} ticks:{} ({}:{})", .{
                            level,               slot,   ticks,
                            n_level,             n_slot, n_ticks,
                            self.index[n_level], w_slot,
                        });

                        self.wheel[n_level][w_slot].prepend(node);
                    }
                }

                index.* += 1;
                index.* &= 63;

                if (index.* != 0) break;
            }

            return list;
        }
    };
}

test {
    testing.log_level = .debug;
    const W = TimerWheel(std.time.ns_per_ms, 6);
    const example = struct {
        pub fn ms(w: *W, n: u64, p: u64, r: u64) void {
            w.sleep(std.time.ns_per_ms * n * math.pow(u64, 64, p) + r);
        }
    };

    var wheel: W = .{};
    const ms = std.time.ns_per_ms;

    _ = async example.ms(&wheel, 3, 0, 0);
    _ = async example.ms(&wheel, 3, 1, 0);
    _ = async example.ms(&wheel, 3, 2, ms * 3);
    _ = async example.ms(&wheel, 1, 2, 0);

    std.log.debug("{}", .{wheel.tick()});
    std.log.debug("{}", .{wheel.tick()});
    std.log.debug("{}", .{wheel.tick()});
    std.log.debug("{}", .{wheel.tick()});
    std.log.debug("{}", .{wheel.tick()});

    for (W.power) |p| {
        var i: u64 = 0;
        while (i < 64) : (i += 1) {
            const level = W.getLevel((i + 1) * p);
            const slot = W.getSlot(level, (i + 1) * p);
            std.log.debug("{}:{} {}", .{
                level,
                slot,
                fmt.fmtDuration((i + 1) * p * ms),
            });
        }
    }
}
