const std = @import("std");

fn Unit(comptime T: type) type {
    const Hack = struct {
        var runtime: T = undefined;
    };
    return @TypeOf(.{Hack.runtime});
}

fn Actor(comptime T: type) type {
    const H = struct { typ: anytype };
    var empty = .{};
    comptime var names: []const []const u8 = &[_][]const u8{};
    comptime var box = H{ .typ = empty };

    inline for (@typeInfo(T).Struct.decls) |decl| {
        switch (decl.data) {
            else => {},
            .Fn => |fun| {
                const info = @typeInfo(fun.fn_type).Fn;
                if (info.args.len != 3) continue;
                if (info.args[0].arg_type.? != *T) continue;
                if (info.args[1].arg_type.? != *Context(T)) continue;
                const A = info.args[2].arg_type.?;
                const B = struct { pending: usize, mail: std.TailQueue(A) };
                names = names ++ [_][]const u8{decl.name};
                box.typ = box.typ ++ Unit(B){ .@"0" = undefined };
            },
        }
    }

    const Mailbox = @TypeOf(box.typ);

    return struct {
        mailbox: Mailbox,
        context: Context(T),

        const Self = @This();

        pub fn init() Self {
            var r: Self = undefined;
            inline for (names) |_, i| {
                r.mailbox[i].pending = 0;
                r.mailbox[i].mail = @TypeOf(r.mailbox[i].mail).init();
            }
            r.context = .{};
            return r;
        }
    };
}

fn Context(comptime T: type) type {
    return struct {};
}

fn Address(comptime T: type) type {
    return struct {
        pid: usize,
        const actor = T;
    };
}

test "basic-actor" {
    const T = Actor(struct {
        const T = @This();
        pub fn unit(storage: *T, context: *Context(T), mail: void) !void {}
    });
    var t: T = T.init();
}
