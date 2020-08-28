const std = @import("std");

fn Unit(comptime T: type) type {
    const Hack = struct {
        var runtime: T = undefined;
    };
    return @TypeOf(.{Hack.runtime});
}

fn Actor(comptime T: type) type {
    const F = std.builtin.TypeInfo.StructField;
    comptime var fields: []const F = &[_]F{};

    inline for (@typeInfo(T).Struct.decls) |decl| {
        switch (decl.data) {
            else => {},
            .Fn => |fun| {
                const info = @typeInfo(fun.fn_type).Fn;
                if (!decl.is_pub or info.args.len != 3) continue;
                if (info.args[0].arg_type.? != *T) continue;
                if (info.args[1].arg_type.? != *Context(T)) continue;
                fields = fields ++ [_]F{
                    .{
                        .name = decl.name,
                        .default_value = null,
                        .field_type = struct {
                            pending: usize,
                            mail: std.TailQueue(info.args[2].arg_type.?),
                        },
                    },
                };
            },
        }
    }

    const Mailbox = @Type(.{
        .Struct = .{
            .fields = fields,
            .decls = &[_]std.builtin.TypeInfo.Declaration{},
            .is_tuple = false,
            .layout = .Auto,
        },
    });

    return struct {
        mailbox: Mailbox,
        context: Context(T),

        const Self = @This();

        pub fn init() Self {
            var r: Self = undefined;
            inline for (std.meta.fields(Mailbox)) |field, i| {
                @field(r.mailbox, field.name).pending = 0;
                @field(r.mailbox, field.name).mail = .{};
            }
            r.context = .{};
            return r;
        }
    };
}

fn Context(comptime T: type) type {
    return struct {
        const Ctx = @This();
        pub fn send(ctx: Ctx, comptime method: []const u8, address: anytype, mail: anytype) void {
            if (!@hasDecl(address.kind, method)) @compileError("handler does not exist");
        }
    };
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
