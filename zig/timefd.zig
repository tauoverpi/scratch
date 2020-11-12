const std = @import("std");
const linux = std.os.linux;

pub fn main() !void {
    const epoll = linux.epoll_create1(linux.EPOLL_CLOEXEC);
    if (linux.getErrno(epoll) != 0) return error.Epoll;

    const timer = linux.timerfd_create(linux.CLOCK_MONOTONIC, linux.TFD_CLOEXEC);
    if (linux.getErrno(timer) != 0) return error.Timer;

    const interval: linux.timespec = .{ .tv_sec = 4, .tv_nsec = 0 };
    const spec: linux.itimerspec = .{ .it_interval = interval, .it_value = interval };

    if (linux.timerfd_settime(@intCast(i32, timer), 0, &spec, null) != 0) return error.SetTimer;

    var event: linux.epoll_event = .{
        .events = linux.EPOLLIN | linux.EPOLLOUT | linux.EPOLLET,
        .data = .{ .ptr = 0 },
    };

    if (linux.epoll_ctl(@intCast(i32, epoll), linux.EPOLL_CTL_ADD, @intCast(i32, timer), &event) != 0) {
        return error.Ctl;
    }

    var events = [_]linux.epoll_event{.{ .events = 0, .data = undefined }} ** 8;

    _ = linux.epoll_wait(@intCast(i32, epoll), @ptrCast([*]linux.epoll_event, &events), 8, -1);
    for (events) |item| std.debug.print("{}\n", .{item});

    if (linux.timerfd_settime(@intCast(i32, timer), 0, &spec, null) != 0) return error.SetTimer;

    _ = linux.epoll_wait(@intCast(i32, epoll), @ptrCast([*]linux.epoll_event, &events), 8, -1);
    for (events) |item| std.debug.print("{}\n", .{item});
}
