const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

fn AoS(comptime T: type, comptime size: usize) type {
    return struct {
        data: [size]T = undefined,

        const Self = @This();

        pub fn get(self: Self, i: usize) T {
            return self.data[i];
        }

        pub fn put(self: *Self, value: T, i: usize) void {
            self.data[i] = value;
        }
    };
}

fn SoA(comptime T: type, comptime size: usize) type {
    comptime var fields: []const TypeInfo.StructField = &[_]TypeInfo.StructField{};

    inline for (std.meta.fields(T)) |field| {
        const default = if (field.default_value) |value| {
            break value ** size;
        } else null;

        fields = fields ++ &[_]TypeInfo.StructField{.{
            .default_value = default,
            .name = field.name,
            .field_type = [size]field.field_type,
        }};
    }

    return struct {
        data: K = undefined,

        const K = @Type(TypeInfo{
            .Struct = .{
                .is_tuple = false,
                .fields = fields,
                .decls = &[_]TypeInfo.Declaration{},
                .layout = .Auto,
            },
        });

        const Self = @This();

        pub fn get(self: Self, i: usize) T {
            var r: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                @field(r, field.name) = @field(self.data, field.name)[i];
            }
            return r;
        }

        pub fn put(self: *Self, value: T, i: usize) void {
            inline for (std.meta.fields(T)) |field| {
                @field(self.data, field.name)[i] = @field(value, field.name);
            }
        }

        pub const Iterator = struct {
            index: usize = 0,
            self: *Self,

            pub fn next(it: *Iterator) ?T {
                if (it.index >= @field(it.self, std.meta.fields(T)[0].name)) {
                    return null;
                } else {
                    defer it.index += 1;
                    return it.self.get(it.index);
                }
            }
        };
    };
}

const Kind = enum { SoA, AoS };
pub fn AoSSoA(comptime kind: Kind, comptime T: type, comptime size: usize) type {
    return switch (kind) {
        .SoA => SoA(T, size),
        .AoS => AoS(T, size),
    };
}

test "array-of-structures" {
    const T = AoSSoA(.AoS, struct { a: u32, b: u8 }, 12);
    var t: T = .{};
    t.put(.{ .a = 2, .b = 5 }, 2);
    std.debug.print("{}\n", .{t.get(2)});
}

test "structures-of-arrays" {
    const T = AoSSoA(.SoA, struct { a: u32, b: u8 }, 12);
    var t: T = .{};
    t.put(.{ .a = 2, .b = 5 }, 2);
    std.debug.print("{}\n", .{t.get(2)});
}
