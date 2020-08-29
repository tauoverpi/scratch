//! A collection of the worst code I've written to replace bash scripts (at least it "works")

const std = @import("std");
const os = std.os;
const hash = std.hash.Fnv1a_64.hash;

const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

const Notify = struct {
    fn help() !void {
        try stderr.writeAll(
            \\usage: cli notify [arguments]
            \\
            \\  -w --close-write
            \\  -W --close-nowrite
            \\  -c --create
            \\  -m --modify
            \\  -d --delete
            \\  -S --delete-self
            \\  -s --move-self
            \\  -f --moved-from
            \\  -t --moved-to
            \\  -a --access
            \\  -o --open
            \\  -A --attrib
            \\  -e --all-events
            \\  -O --onlydir
            \\  -D --dont-follow
            \\
        );
        std.os.exit(1);
    }

    pub fn notify() !void {
        const fd = try os.inotify_init1(os.linux.IN_CLOEXEC);
        defer os.close(fd);
        var buffer: [1]u8 align(@alignOf(os.linux.inotify_event)) = undefined;
        const Watch = struct { wd: i32, arg: usize };
        var watch_buffer: [4096]Watch = undefined;
        var files: []const Watch = &[_]Watch{};

        var options: u32 = 0;
        if (std.mem.len(os.argv) > 2) {
            for (os.argv[3..std.mem.len(os.argv)]) |flag| {
                const arg = flag[0..std.mem.len(flag)];
                if (arg.len >= 2 and arg[0] == '-' and arg[1] != '-') {
                    for (arg[1..]) |c| {
                        switch (c) {
                            'w' => options |= os.linux.IN_CLOSE_WRITE,
                            'W' => options |= os.linux.IN_CLOSE_NOWRITE,
                            'c' => options |= os.linux.IN_CREATE,
                            'm' => options |= os.linux.IN_MODIFY,
                            'd' => options |= os.linux.IN_DELETE,
                            'S' => options |= os.linux.IN_DELETE_SELF,
                            's' => options |= os.linux.IN_MOVE_SELF,
                            'f' => options |= os.linux.IN_MOVED_FROM,
                            't' => options |= os.linux.IN_MOVED_TO,
                            'a' => options |= os.linux.IN_ACCESS,
                            'o' => options |= os.linux.IN_OPEN,
                            'A' => options |= os.linux.IN_ATTRIB,
                            'e' => options |= os.linux.IN_ALL_EVENTS,
                            'O' => options |= os.linux.IN_ONLYDIR,
                            'D' => options |= os.linux.IN_DONT_FOLLOW,
                            else => try help(),
                        }
                    }
                } else {
                    if (arg[0] == '-' and arg[1] == '-') {
                        switch (hash(arg)) {
                            hash("--close-write") => options |= os.linux.IN_CLOSE_WRITE,
                            hash("--close-nowrite") => options |= os.linux.IN_CLOSE_NOWRITE,
                            hash("--create") => options |= os.linux.IN_CREATE,
                            hash("--modify") => options |= os.linux.IN_MODIFY,
                            hash("--delete") => options |= os.linux.IN_DELETE,
                            hash("--delete-self") => options |= os.linux.IN_DELETE_SELF,
                            hash("--move-self") => options |= os.linux.IN_MOVE_SELF,
                            hash("--moved-from") => options |= os.linux.IN_MOVED_FROM,
                            hash("--moved-to") => options |= os.linux.IN_MOVED_TO,
                            hash("--access") => options |= os.linux.IN_ACCESS,
                            hash("--open") => options |= os.linux.IN_OPEN,
                            hash("--attrib") => options |= os.linux.IN_ATTRIB,
                            hash("--all-events") => options |= os.linux.IN_ALL_EVENTS,
                            hash("--onlydir") => options |= os.linux.IN_ONLYDIR,
                            hash("--dont-follow") => options |= os.linux.IN_DONT_FOLLOW,
                            else => try help(),
                        }
                    }
                }
            }
            if (options == 0) options |= os.linux.IN_ALL_EVENTS;
            var watching: bool = false;
            var number: usize = 0;
            for (os.argv[2..std.mem.len(os.argv)]) |file, arg| {
                const name = file[0..std.mem.len(file) :0];
                if (name.len >= 1 and name[0] != '-') {
                    try stderr.print("watching {}\n", .{name});
                    const watch = try os.inotify_add_watchZ(fd, name, options);
                    watch_buffer[number] = .{ .wd = watch, .arg = arg };
                    number += 1;
                    watching = true;
                }
            } else files = watch_buffer[0..number];
            if (!watching) {
                try stderr.writeAll("watching current directory\n");
                const watch = try os.inotify_add_watchZ(fd, ".", options);
            }
        } else {
            try stderr.writeAll("watching current directory\n");
            options |= os.linux.IN_ALL_EVENTS;
            const watch = try os.inotify_add_watchZ(fd, ".", options);
        }

        _ = os.linux.read(fd, &buffer, buffer.len);
        if (files.len > 0) for (files) |file| {
            if (file.wd == watch_buffer[0].wd) {
                try stdout.print("{}\n", .{os.argv[file.arg + 2][0..std.mem.len(os.argv[file.arg + 2])]});
                break;
            }
        };
    }
};

pub fn main() !void {
    if (os.argv.len < 2) return error.NeedArgument;
    switch (hash(os.argv[1][0..std.mem.len(os.argv[1])])) {
        hash("notify") => try Notify.notify(),
        hash("help") => try stderr.writeAll(
            \\usage: cli command [args]
            \\
            \\  notify - inotify interface
            \\
        ),
        else => try stderr.writeAll("need argument\n"),
    }
}
