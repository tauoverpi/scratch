const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

// through type erasure
pub fn Iso(comptime T: type) type {
    return struct {
        getFn: fn (*Self, usize) T,
        putFn: fn (*Self, T, usize) void,

        const Self = @This();

        pub fn get(self: *Self, i: usize) T {
            return self.getFn(self, i);
        }

        pub fn put(self: *Self, value: T, i: usize) void {
            self.putFn(self, value, i);
        }
    };
}

pub fn AoS(comptime T: type, comptime size: usize) type {
    return struct {
        iso: Iso(T) = .{ .getFn = get, .putFn = put },
        data: [size]T = undefined,

        pub fn get(iso: *Iso(T), i: usize) T {
            return @fieldParentPtr(AoS(T, size), "iso", iso).data[i];
        }

        pub fn put(iso: *Iso(T), value: T, i: usize) void {
            @fieldParentPtr(AoS(T, size), "iso", iso).data[i] = value;
        }
    };
}

pub fn SoA(comptime T: type, comptime size: usize) type {
    comptime var fields: []const TypeInfo.StructField = &[_]TypeInfo.StructField{};
    inline for (std.meta.fields(T)) |field| {
        fields = fields ++ &[_]TypeInfo.StructField{.{
            .default_value = null, // TODO: field.default_value,
            .name = field.name,
            .field_type = [size]field.field_type,
        }};
    }

    return struct {
        iso: Iso(T) = .{ .getFn = get, .putFn = put },
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

        pub fn get(iso: *Iso(T), i: usize) T {
            const self = @fieldParentPtr(SoA(T, size), "iso", iso);
            var r: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                @field(r, field.name) = @field(self.data, field.name)[i];
            }
            return r;
        }

        pub fn put(iso: *Iso(T), value: T, i: usize) void {
            const self = @fieldParentPtr(SoA(T, size), "iso", iso);
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

test "erasure-array-of-structures" {
    const K = struct { a: u32, b: u8 };
    const T = AoS(K, 12);
    var b: T = .{};
    var t: Iso(K) = b.iso;
    t.put(.{ .a = 2, .b = 5 }, 2);
    std.debug.print("{}\n", .{t.get(2)});
}

test "erasure-structures-of-arrays" {
    const K = struct { a: u32, b: u8 };
    const T = SoA(K, 12);
    var b: T = .{};
    var t: Iso(K) = b.iso;
    t.put(.{ .a = 2, .b = 5 }, 2);
    std.debug.print("{}\n", .{t.get(2)});
}
