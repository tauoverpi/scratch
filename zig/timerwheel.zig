const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;
const math = std.math;
const Timer = std.time.Timer;

const Wheel = struct {
    timer: Timer,
    wheels: [6][64]List = [_][64]List{[_]List{.{}} ** 64} ** 6,
    indices: [6]u8 = [_]u8{0} ** 6,

    const log = std.log.scoped(.wheel);
    const ms = std.time.ns_per_ms;

    pub const List = std.SinglyLinkedList(Entry);

    pub const Entry = struct {
        frame: anyframe,
        due: u64,

        pub fn format(
            entry: Entry,
            comptime _: []const u8,
            options: fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            try writer.print("{}", .{fmt.fmtDuration(entry.due)});
        }
    };

    pub fn sleep(self: *Wheel, due: u64) void {
        suspend {
            var entry: List.Node = .{
                .next = undefined,
                .data = .{
                    .frame = @frame(),
                    .due = due,
                },
            };

            const p = position(due);
            const slot = (p.slot + self.indices[p.level]) & 63;

            log.debug(
                "placing entry on wheel {} slot {} due {}",
                .{ p.level, slot, fmt.fmtDuration(due) },
            );

            self.wheels[p.level][slot].prepend(&entry);
        }
    }

    pub fn peek(self: *Wheel) ?u64 {
        for (self.indices) |index, wheel| {
            var slot = index + 1;

            if (self.wheels[wheel][index].first) |node| {
                return node.data.due;
            }

            while (slot != index) : (slot = (slot + 1) & 63) {
                if (self.wheels[wheel][slot].first) |node| {
                    return node.data.due;
                }
            }
        }

        return null;
    }

    fn position(due: u64) struct { level: u8, slot: u8 } {
        const level = if (due < ms) 0 else math.log(u64, 64, due / ms);
        const slot = (due / ms / math.pow(u64, 64, level)) - 1;
        return .{
            .level = @intCast(u8, level),
            .slot = @intCast(u8, slot),
        };
    }

    fn tick(self: *Wheel) List {
        const list = self.wheels[0][self.indices[0]];
        self.wheels[0][self.indices[0]] = .{};

        self.indices[0] += 1;
        self.indices[0] &= 63;

        if (self.indices[0] == 0) for (self.indices[1..]) |*index, lower| {
            const wheel = lower + 1;
            log.debug("turning wheel {}", .{wheel});

            var old = self.wheels[wheel][index.*];
            self.wheels[wheel][index.*] = .{};

            while (old.popFirst()) |node| {
                node.data.due /= 64;
                const p = position(node.data.due);
                log.debug(
                    "moving entry from wheel {} to wheel {} slot {} due {}",
                    .{ wheel, lower, p.slot, fmt.fmtDuration(node.data.due) },
                );
                self.wheels[lower][(self.indices[lower] + p.slot) % 64].prepend(node);
            }

            index.* += 1;
            index.* &= 63;

            if (self.indices[wheel] != 0) break;
        };

        return list;
    }
};

const example = struct {
    pub fn e(w: *Wheel) void {
        w.sleep(std.time.ns_per_ms * 64);
    }

    pub fn v(w: *Wheel) void {
        w.sleep(std.time.ns_per_ms);
    }

    pub fn t(w: *Wheel) void {
        w.sleep(std.time.ns_per_ms * 63 + std.time.ns_per_ms * math.pow(u64, 64, 5));
    }
};

test {
    testing.log_level = .debug;

    var w: Wheel = .{ .timer = try Timer.start() };
    _ = async example.e(&w);
    _ = async example.v(&w);
    _ = async example.t(&w);

    var i: u32 = 0;
    std.log.debug("{}", .{fmt.fmtDuration(w.peek().?)});
    std.log.debug("{}", .{w.tick()});
    std.log.debug("{}", .{fmt.fmtDuration(w.peek().?)});
    while (i < 62) : (i += 1) _ = w.tick();

    std.log.debug("{}", .{w.tick()});
    std.log.debug("{}", .{w.tick()});
    std.log.debug("{}", .{fmt.fmtDuration(w.peek().?)});
}
