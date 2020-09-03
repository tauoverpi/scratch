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
            \\  -q --quiet
            \\
        );
        return error.HelpText;
    }

    pub fn notify() !void {
        const fd = try os.inotify_init1(os.linux.IN_CLOEXEC);
        defer os.close(fd);
        var buffer: [4096]u8 align(@alignOf(os.linux.inotify_event)) = undefined;
        const Watch = struct { wd: i32, arg: usize };
        var watch_buffer: [4096]Watch = undefined;
        var files: []const Watch = &[_]Watch{};
        var quiet = false;

        var options: u32 = 0;
        if (std.mem.len(os.argv) > 2) {
            for (os.argv[2..std.mem.len(os.argv)]) |flag| {
                const arg = flag[0..std.mem.len(flag)];
                if (arg.len == 2 and arg[0] == '-' and arg[1] == '-') break;
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
                            'q' => quiet = true,
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
                            hash("--quiet") => quiet = true,
                            else => try help(),
                        }
                    }
                }
            }
            if (options == 0) options |= os.linux.IN_ALL_EVENTS;
            var watching: bool = false;
            var number: usize = 0;
            var escaped = false;
            for (os.argv[2..std.mem.len(os.argv)]) |file, arg| {
                const name = file[0..std.mem.len(file) :0];
                if (name.len == 2 and name[0] == '-' and name[1] == '-') {
                    escaped = true;
                    continue;
                }
                if (name.len >= 1 and (name[0] != '-' or escaped)) {
                    if (!quiet) try stderr.print("watching {}\n", .{name});
                    const watch = try os.inotify_add_watchZ(fd, name, options);
                    watch_buffer[number] = .{ .wd = watch, .arg = arg + 2 };
                    number += 1;
                    watching = true;
                }
            } else files = watch_buffer[0..number];
            if (!watching) {
                if (!quiet) try stderr.writeAll("watching current directory\n");
                const watch = try os.inotify_add_watchZ(fd, ".", options);
            }
        } else {
            try stderr.writeAll("watching current directory\n");
            options |= os.linux.IN_ALL_EVENTS;
            const watch = try os.inotify_add_watchZ(fd, ".", options);
        }
        if (!quiet) {
            if (os.linux.IN_CLOSE_WRITE & options > 0) try stderr.writeAll("event IN_CLOSE_WRITE\n");
            if (os.linux.IN_CLOSE_NOWRITE & options > 0) try stderr.writeAll("event IN_CLOSE_NOWRITE\n");
            if (os.linux.IN_CREATE & options > 0) try stderr.writeAll("event IN_CREATE\n");
            if (os.linux.IN_MODIFY & options > 0) try stderr.writeAll("event IN_MODIFY\n");
            if (os.linux.IN_DELETE & options > 0) try stderr.writeAll("event IN_DELETE\n");
            if (os.linux.IN_DELETE_SELF & options > 0) try stderr.writeAll("event IN_DELETE_SELF\n");
            if (os.linux.IN_MOVE_SELF & options > 0) try stderr.writeAll("event IN_MOVE_SELF\n");
            if (os.linux.IN_MOVED_FROM & options > 0) try stderr.writeAll("event IN_MOVED_FROM\n");
            if (os.linux.IN_MOVED_TO & options > 0) try stderr.writeAll("event IN_MOVED_TO\n");
            if (os.linux.IN_ACCESS & options > 0) try stderr.writeAll("event IN_ACCESS\n");
            if (os.linux.IN_OPEN & options > 0) try stderr.writeAll("event IN_OPEN\n");
            if (os.linux.IN_ATTRIB & options > 0) try stderr.writeAll("event IN_ATTRIB\n");
            if (os.linux.IN_ONLYDIR & options > 0) try stderr.writeAll("event IN_ONLYDIR\n");
            if (os.linux.IN_DONT_FOLLOW & options > 0) try stderr.writeAll("event IN_DONT_FOLLOW\n");
        }

        _ = os.linux.read(fd, &buffer, buffer.len);
        const wd = std.mem.readIntSliceNative(i32, buffer[0..4]);
        if (files.len > 0) for (files) |file| {
            if (file.wd == wd) {
                try stdout.print("{}\n", .{os.argv[file.arg][0..std.mem.len(os.argv[file.arg])]});
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
