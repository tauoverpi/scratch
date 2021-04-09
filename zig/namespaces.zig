const std = @import("std");
const meta = std.meta;
const TypeInfo = std.builtin.TypeInfo;

fn @"usingnamespace"(comptime Dst: type, comptime Src: type) type {
    const di = meta.fields(Dst);
    const si = meta.fields(Src);
    const info = @typeInfo(Dst).Struct;
    var fields: []const TypeInfo.StructField = &[_]TypeInfo.StructField{};
    for (di) |field| {
        fields = fields ++ &[_]TypeInfo.StructField{.{
            .name = field.name,
            .field_type = field.field_type,
            .alignment = field.alignment,
            .is_comptime = true,
            .default_value = field.default_value,
        }};
    }
    return @Type(.{ .Struct = .{
        .layout = info.layout,
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

test "" {
    const T = @Type(.{ .Fn = .{
        .calling_convention = .C,
        .alignment = 4,
        .is_generic = false,
        .is_var_args = false,
        .return_type = void,
        .args = &.{.{
            .is_generic = false,
            .is_noalias = false,
            .arg_type = bool,
        }},
    } });

    const f: T = (struct {
        pub fn f(b: bool) align(4) callconv(.C) void {}
    }).f;

    const F = @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = &.{
            .{
                .name = "f",
                .field_type = T,
                .default_value = f,
                .is_comptime = true,
                .alignment = 4,
            },
        },
        .decls = &.{},
        .is_tuple = false,
    } });

    const ns: F = undefined;

    const P = @"usingnamespace"(F, struct {});

    ns.f(true);
    @as(P, undefined).f(true);
}
