const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

test "" {
    const E = @Type(TypeInfo{ .ErrorSet = &[_]TypeInfo.Error{.{ .name = "a" }} });
    std.debug.assert(@field(E, "a") == error.a);
}
