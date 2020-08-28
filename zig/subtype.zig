const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

fn Subtype(comptime A: type, comptime B: type) type {
    comptime var fields: []const TypeInfo.StructField = &[_]TypeInfo.StructField{};
    inline for (std.meta.fields(A)) |field| {
        if (@hasField(B, field.name) and @TypeOf(@field(@as(B, undefined), field.name)) == field.field_type) {
            fields = fields ++ &[_]TypeInfo.StructField{.{
                .name = field.name,
                .default_value = null,
                .field_type = field.field_type,
            }};
        }
    }

    return @Type(TypeInfo{
        .Struct = .{
            .is_tuple = false,
            .decls = &[_]TypeInfo.Declaration{},
            .fields = fields,
            .layout = .Auto,
        },
    });
}

pub fn subtype(comptime A: type, comptime B: type, value: anytype) Subtype(A, B) {
    if (@TypeOf(value) != A and @TypeOf(value) != B) @compileError("value must be one of the supertypes");
    const T = Subtype(A, B);
    var r: T = undefined;
    inline for (std.meta.fields(T)) |field| {
        @field(r, field.name) = @field(value, field.name);
    }
    return r;
}

test "" {
    const A = struct { a: u32, b: bool, c: []const u8, d: u4 = 9 };
    const B = struct { b: bool, d: u4, f: i23, k: A };

    var a: A = .{ .a = 32, .b = true, .c = "jijf" };

    std.debug.print("{}\n", .{subtype(A, B, a)});
    // struct:16:26{ .b = true, .d = 3 }
}
