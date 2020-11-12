const std = @import("std");
const linux = std.os.linux;
const File = std.fs.File;

const FdTimer = struct {
    timer: usize,

    pub fn init() !FdTimer {
        const timer = linux.timerfd_create(linux.CLOCK_MONOTONIC, linux.TFD_CLOEXEC);
        if (linux.getErrno(timer) != 0) return error.FailedToCreateTimer;
        return FdTimer{ .timer = timer };
    }

    pub fn setNanoseconds(self: FdTimer, nsec: isize) !void {
        const interval: linux.timespec = .{ .tv_sec = 0, .tv_nsec = nsec };
        const spec: linux.itimerspec = .{ .it_interval = interval, .it_value = interval };
        if (linux.timerfd_settime(@intCast(i32, self.timer), 0, &spec, null) != 0)
            return error.FailedToSetTime;
    }

    pub fn setSeconds(self: FdTimer, sec: isize) !void {
        const interval: linux.timespec = .{ .tv_sec = sec, .tv_nsec = 0 };
        const spec: linux.itimerspec = .{ .it_interval = interval, .it_value = interval };
        if (linux.timerfd_settime(@intCast(i32, self.timer), 0, &spec, null) != 0)
            return error.FailedToSetTime;
    }
};

const Epoll = struct {
    epoll: usize,

    pub fn init() !Epoll {
        const epoll = linux.epoll_create1(0);
        if (linux.getErrno(epoll) != 0) return error.FailedToCreateEpollInstance;
        return Epoll{ .epoll = epoll };
    }

    pub fn wait(self: Epoll, events: []linux.epoll_event, timeout: i32) usize {
        const len = linux.epoll_wait(@intCast(i32, self.epoll), events.ptr, @intCast(u32, events.len), timeout);
        std.debug.print("got event {}\n", .{events[0].data.ptr});
        return len;
    }

    pub const EventConfig = struct {
        read: bool = false,
        write: bool = false,
        edge: bool = false,
        oneshot: bool = false,
    };

    pub fn addTimerEvent(self: Epoll, timer: FdTimer, value: usize, cfg: EventConfig) !void {
        try self.addFdEvent(timer.timer, value, cfg);
    }

    pub fn addFileEvent(self: Epoll, file: File, value: usize, cfg: EventConfig) !void {
        try self.addFdEvent(file.handle, value, cfg);
    }

    pub fn addFdEvent(self: Epoll, fd: usize, value: usize, cfg: EventConfig) !void {
        var flags: u32 = 0;
        if (cfg.read) flags |= linux.EPOLLIN;
        if (cfg.write) flags |= linux.EPOLLOUT;
        if (cfg.edge) flags |= linux.EPOLLET;
        if (cfg.oneshot) flags |= linux.EPOLLONESHOT;

        var event: linux.epoll_event = .{
            .events = flags,
            .data = .{ .ptr = value },
        };

        if (linux.epoll_ctl(@intCast(i32, self.epoll), linux.EPOLL_CTL_ADD, @intCast(i32, fd), &event) != 0) {
            return error.FailedToSetEvent;
        }
    }
};

fn masterFn() void {
    while (true) {
        suspend {
            master = @frame();
        }
    }
}

// plan:
// - suspend master upon trying to blocking write
// - resume master when possible
// - suspend udp when trying to blocking write

pub fn main() !void {
    const master = try FdTimer.init();
    const udp = try FdTimer.init();
    const unix = try FdTimer.init();
    const epoll = try Epoll.init();

    try master.setSeconds(1);
    try udp.setSeconds(10);
    try unix.setSeconds(6);
    try epoll.addTimerEvent(master, 1, .{ .edge = true, .read = true });
    try epoll.addTimerEvent(udp, 2, .{ .edge = true, .read = true });
    try epoll.addTimerEvent(unix, 3, .{ .edge = true, .read = true });

    var buffer: [3]linux.epoll_event = undefined;

    while (true) for (buffer[0..epoll.wait(&buffer, -1)]) |item| switch (item.data.ptr) {
        1 => try master.setSeconds(1),
        2 => try udp.setSeconds(2),
        3 => try unix.setSeconds(4),
        else => unreachable,
    };
}
