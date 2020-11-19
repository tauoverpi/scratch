const std = @import("std");
const testing = std.testing;
const meta = std.meta;
const TypeInfo = std.builtin.TypeInfo;

fn unionFromStruct(comptime T: type) type {
    comptime {
        const UnionField = TypeInfo.UnionField;
        const EnumField = TypeInfo.EnumField;
        var fields: []const UnionField = &[_]UnionField{};
        var tags: []const EnumField = &[_]EnumField{};
        for (meta.fields(T)) |field, i| {
            fields = fields ++ &[_]UnionField{.{
                .name = field.name,
                .field_type = field.field_type,
                .alignment = field.alignment,
            }};
            tags = tags ++ &[_]EnumField{.{ .name = field.name, .value = i }};
        }
        const bits = @clz(u128, std.math.ceilPowerOfTwoPromote(u128, tags.len));
        const enum_type = @Type(TypeInfo{
            .Enum = .{
                .layout = .Auto,
                .tag_type = meta.Int(.unsigned, bits),
                .fields = tags,
                .is_exhaustive = false,
                .decls = &[_]TypeInfo.Declaration{},
            },
        });
        return @Type(TypeInfo{
            .Union = .{
                .layout = .Auto,
                .tag_type = enum_type,
                .fields = fields,
                .decls = &[_]TypeInfo.Declaration{},
            },
        });
    }
}
