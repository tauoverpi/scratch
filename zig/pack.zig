const std = @import("std");
const fnv = std.hash.Fnv1a_32;
const meta = std.meta;
const mem = std.mem;

const spec = .{
    .@"/tmp/csv.zig" = @embedFile("csv.zig"),
    .@"/tmp/pack.zig" = @embedFile("pack.zig"),
};

pub fn unpack(ar: anytype) !void {
    switch (@typeInfo(@TypeOf(ar))) {
        .Struct => |info| {
            inline for (info.fields) |field| {
                var os = (try std.fs.createFileAbsolute(field.name, .{})).writer();
                try os.writeAll(@field(ar, field.name));
            }
        },
        else => @compileError("can only unpack structs"),
    }
}

const help =
    \\usage: pkg [options]
    \\
    \\  -h/--help          display this message
    \\  -p/--prefix        use the given prefix path
    \\  -i/--install       install package
    \\  -u/--uninstall     restore last version (must have installed prior)
    \\  -l/--log [topic]   produce logs from the given topic
    \\  -f/--force         proceed regardless of errors
    \\  -o/--optimize      hardlink duplicates
    \\  -g/--graph         produce a graph of the system
;

const LogOptions = struct {};

const ArgParser = struct {
    prefix: ?[]const u8,
    log: LogOptions,
    install: bool,
    force: bool,
    optimize: bool,
    graph: bool,
    state: State,

    const State = enum { Option, LogTopic, Prefix };

    pub fn feed(p: *ArgParser, arg: []const u8) !void {
        switch (p.state) {
            .Option => switch (fnv.hash(arg)) {
                fnv.hash("-h"), fnv.hash("--help") => {},
                fnv.hash("-p"), fnv.hash("--prefix") => {
                    p.state = .Prefix;
                },
                fnv.hash("-i"), fnv.hash("--install") => {},
                fnv.hash("-u"), fnv.hash("--uninstall") => {},
                fnv.hash("-l"), fnv.hash("--log") => {
                    p.state = .LogTopic;
                },
                fnv.hash("-f"), fnv.hash("--force") => {},
                fnv.hash("-o"), fnv.hash("--optimize") => {},
                fnv.hash("-g"), fnv.hash("--graph") => {},
                else => return error.InvalidArgument,
            },

            .Prefix => {
                if (p.prefix) |_| return error.MultiPrefixNotValid;
                p.prefix = arg;
            },

            .LogTopic => {
                p.state = .Option;
                // set log options based on type
                inline for (meta.fields(LogOptions)) |field| {
                    if (mem.eql(u8, arg, field.name)) {
                        @field(p.log, field.name) = true;
                        return;
                    }
                }
            },
        }
        return;
    }
};
