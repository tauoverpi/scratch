const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const TailQueue = std.TailQueue;
const Timer = std.time.Timer;

const Loop = struct {
    timer: Timer,
    queue: TailQueue(anyframe),

    pub const Node = TailQueue(anyframe).Node;

    pub const Entry = struct {
        node: Node,
        expires: u64,
    };

    pub fn init() !Loop {
        return Loop{
            .timer = try Timer.start(),
            .queue = TailQueue(anyframe){},
        };
    }

    pub fn sleep(self: *Loop, ns: u64) void {
        suspend {
            const now = self.timer.read();
            var frame = @frame();
            var entry: Entry = .{ .node = .{
                .prev = undefined,
                .next = undefined,
                .data = frame,
            }, .expires = now + ns };

            self.queue.prepend(&entry.node);
            std.log.info("scheduled frame at {} for {}", .{ now, now + ns });
        }
    }

    pub fn yield(self: *Loop) void {
        self.sleep(0);
    }

    fn popExpired(self: *Loop) ?*Entry {
        const now = self.timer.read();
        const entry = self.peekExpiringNext() orelse return null;
        if (entry.expires > now) return null;
        std.log.info("expired {}", .{now});
        self.queue.remove(&entry.node);
        return entry;
    }

    fn nextExpires(self: *Loop) ?u64 {
        const entry = self.peekExpiringNext() orelse return null;
        return entry.expires;
    }

    fn peekExpiringNext(self: *Loop) ?*Entry {
        var head = self.queue.first orelse return null;
        var min = head;
        while (head.next) |node| {
            const min_entry = @fieldParentPtr(Entry, "node", min);
            const node_entry = @fieldParentPtr(Entry, "node", node);
            if (node_entry.expires < min_entry.expires) {
                min = node;
            }
            head = node;
        }
        return @fieldParentPtr(Entry, "node", min);
    }
};

test "" {
    var loop = try Loop.init();
    var day = async loop.sleep(std.time.ns_per_day);
    var week = async loop.sleep(std.time.ns_per_week);
    var hour = async loop.sleep(std.time.ns_per_hour);
    testing.expect(loop.popExpired() == null);
    var now = async loop.sleep(0);
    std.time.sleep(1);
    const ready = loop.popExpired() orelse unreachable;
    resume ready.node.data;
}

fn worker(ctx: *Loop) !void {
    std.log.info("suspending third", .{});
    var three = async ctx.sleep(std.time.ns_per_s * 6);
    std.log.info("suspending first", .{});
    var one = async ctx.sleep(std.time.ns_per_s);
    std.log.info("suspending second", .{});
    var two = async ctx.sleep(std.time.ns_per_s * 3);

    await one;
    std.log.info("one resumed", .{});
    await two;
    std.log.info("two resumed", .{});
    await three;
    std.log.info("three resumed", .{});
    std.log.info("done", .{});
}

pub fn main() !void {
    var loop = try Loop.init();
    var backing = async worker(&loop);
    while (loop.queue.first != null) {
        if (loop.popExpired()) |entry| {
            resume entry.node.data;
        }
    }
}
