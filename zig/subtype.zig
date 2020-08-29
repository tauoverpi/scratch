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
    if (@TypeOf(value) != A and @TypeOf(value) != B)
        @compileError("value must be either " ++
            @typeName(A) ++ " or " ++
            @typeName(B) ++ " but got " ++
            @typeName(@TypeOf(value)));

    const T = Subtype(A, B);

    var r: T = undefined;

    inline for (std.meta.fields(T)) |field| {
        @field(r, field.name) = @field(value, field.name);
    }

    return r;
}

pub fn merge(dst: anytype, src: anytype) void {
    const ti = @typeInfo(@TypeOf(dst));
    if (ti != .Pointer or ti.Pointer.is_const or @typeInfo(ti.Pointer.child) != .Struct)
        @compileError("must be a pointer to a struct");
    const D = ti.Pointer.child;
    const S = @TypeOf(src);
    inline for (std.meta.fields(S)) |field| {
        @field(dst, field.name) = @field(src, field.name);
    }
}

test "" {
    const A = struct { a: u32, b: bool, c: []const u8, d: u4 = 9 };
    const B = struct { b: bool, d: u4, f: i23, k: A };

    var a: A = .{ .a = 32, .b = true, .c = "jijf" };
    var st = subtype(A, B, a);

    std.debug.print("{}\n", .{a});
    std.debug.print("{}\n", .{st});
    st.d = 4;
    std.debug.print("{}\n", .{st});
    merge(&a, st);
    std.debug.print("{}\n", .{a});
    // struct:16:26{ .b = true, .d = 3 }
}
