const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

test "void-does-not-support-struct-initialization-syntax" {
    _ = TypeInfo.StructField{
        .name = "this should work",
        .field_type = u32,
        .default_value = null,
    };
}
