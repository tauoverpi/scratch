const std = @import("std");

const Context = @Type(.Opaque);
fn Mailbox(comptime T: type) type {
    const StructField = std.builtin.TypeInfo.StructField;
    const Struct = std.builtin.TypeInfo.Struct;

    comptime var fields: []const StructField = &[_]StructField{};

    inline for (std.meta.declarations(T)) |decl| {
        switch (decl.data) {
            .Fn => |fun| {
                const info = @typeInfo(fun.fn_type).Fn;
                if (info.args.len != 3) continue;
                if (info.args[0].arg_type.? != *T) continue;
                if (info.args[1].arg_type.? != Context) continue;
                fields = fields ++ &[_]StructField{.{
                    .name = decl.name,
                    .default_value = null,
                    .field_type = struct {
                        pending: usize,
                        queue: std.TailQueue(info.args[2].arg_type.?),
                    },
                }};
            },
            else => {},
        }
    }

    return @Type(.{
        .Struct = .{
            .fields = fields,
            .decls = &[_]std.builtin.TypeInfo.Declaration{},
            .is_tuple = false,
            .layout = .Auto,
        },
    });
}

const Example = struct {
    mailbox: Mailbox(Example),
    allocator: *Allocator,

    pub fn example(self: *Example, ctx: Context, mail: u32) void {}
};
