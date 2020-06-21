const std = @import("std");

const Example = struct {
    num: usize,
    text: []const u8,
    boolean: bool,
};

pub fn swap(a: var, b: @TypeOf(a)) void {
    switch (@typeInfo(@TypeOf(a.*))) {
        .Struct => |info| {
            var tmp: @TypeOf(a.*) = undefined;
            inline for (info.fields) |field| {
                @field(tmp, field.name) = @field(a.*, field.name);
                @field(a.*, field.name) = @field(b.*, field.name);
                @field(b.*, field.name) = @field(tmp, field.name);
            }
        },
        else => @compileError("not implemented"),
    }
}

test "" {
    var a: Example = .{ .text = &[1]u8{0}, .num = 2, .boolean = false };
    var b: Example = .{ .text = &[1]u8{1}, .num = 9, .boolean = true };
    std.debug.warn("a: {}\n", .{a});
    std.debug.warn("b: {}\n", .{b});
    var tmp: Example = undefined;
    inline for (@typeInfo(Example).Struct.fields) |field| {
        @field(tmp, field.name) = @field(a, field.name);
        @field(a, field.name) = @field(b, field.name);
        @field(b, field.name) = @field(tmp, field.name);
    }
    std.debug.warn("a: {}\n", .{a});
    std.debug.warn("b: {}\n", .{b});
    swap(&a, &b);
    std.debug.warn("a: {}\n", .{a});
    std.debug.warn("b: {}\n", .{b});
}
