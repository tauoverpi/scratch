//! copyright (c) 2020 Simon A. Nielsen Knights <tauoverpi@yandex.com>
//! license: MIT

const std = @import("std");
const Random = std.rand.Random;
const TypeInfo = std.builtin.TypeInfo;
const StructField = TypeInfo.StructField;
const Declaration = TypeInfo.Declaration;

fn Arguments(comptime T: type) type {
    comptime {
        comptime var fields: []const StructField = &[_]StructField{};
        for (@typeInfo(T).Fn.args) |arg, i| {
            if (arg.arg_type) |typ| {
                fields = fields ++ &[_]StructField{.{
                    .name = std.fmt.comptimePrint("{}", .{i}),
                    .field_type = typ,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = if (typ == void) 0 else @alignOf(typ),
                }};
            } else @compileError("argument type required");
        }
        return @Type(TypeInfo{
            .Struct = .{ .layout = .Auto, .fields = fields, .decls = &[_]Declaration{}, .is_tuple = true },
        });
    }
}

fn fill(comptime T: type, rng: *Random, r: *T) void {
    var i: usize = 0;
    switch (@typeInfo(T)) {
        .Int => r.* = rng.int(T),
        .Bool => r.* = rng.int(u1) == 1,
        .Void => r.* = {},
        .Float => r.* = rng.float(T),
        .Optional => |info| if (rng.int(u1)) {
            fill(info.child, rng, r);
        } else {
            r.* = null;
        },
        .Array => |info| {
            while (i < info.len) : (i += 1) fill(info.child, rng, &r[i]);
        },
        .Vector => |info| {
            var vec: [info.len]info.child = undefined;
            while (i < info.len) : (i += 1) fill(info.child, rng, &vec[i]);
            r.* = vec;
        },
        .ErrorSet => |info| if (info) |set| {
            const chosen = rng.intRangeAtMost(usize, 0, set.len - 1);
            inline for (set) |field, n| if (n == chosen) {
                r.* = @field(T, field.name);
            };
        },
        .Pointer => |info| switch (info.size) {
            .One => fill(info.child, rng, r.*),
            .Slice => while (i < r.*.len) : (i += 1) {
                var tmp: info.child = undefined;
                fill(info.child, rng, &tmp);
                r.*[i] = tmp;
            },
            .Many => @compileError("many pointers not fuzzable"),
            .C => @compileError("c pointers not fuzzable"),
        },
        .Enum => |info| {
            const chosen = rng.intRangeAtMost(usize, 0, info.fields.len - 1);
            inline for (info.fields) |field, n| if (n == chosen) {
                r.* = @field(T, field.name);
            };
        },
        .Union => |info| {
            const chosen = rng.intRangeAtMost(usize, 0, info.fields.len - 1);
            inline for (info.fields) |field, n| if (n == chosen) {
                var inside: field.field_type = undefined;
                fill(field.field_type, rng, &inside);
                r.* = @unionInit(T, field.name, inside);
            };
        },
        .Struct => |info| inline for (info.fields) |field| {
            fill(field.field_type, rng, &@field(r, field.name));
        },
        else => @compileError("unable to fuzz type " ++ @typeName(T)),
    }
}

pub fn fuzz(
    rng: *Random,
    function: anytype,
    arguments: anytype,
    context: anytype,
    predicate: anytype,
) !void {
    const T = Arguments(@TypeOf(function));
    var r: T = undefined;
    const A = @TypeOf(arguments);
    inline for (std.meta.fields(T)) |field, i| {
        if (comptime @hasField(A, field.name)) {
            if (comptime std.meta.trait.is(.Pointer)(field.field_type) and
                comptime !std.meta.trait.isConstPtr(field.field_type))
            {
                @field(r, field.name) = @field(arguments, field.name);
                fill(std.meta.fields(A)[i].field_type, rng, &@field(r, field.name));
            }
            @field(r, field.name) = @field(arguments, field.name);
        } else if (comptime std.meta.trait.is(.Pointer)(field.field_type)) {
            @compileError("pointers must be passed as explicit arguments");
        } else fill(field.field_type, rng, &@field(r, field.name));
    }
    const result = @call(.{}, function, r);
    try predicate(result, context, r);
}

test "" {
    var buf: [8]u8 = undefined;
    try std.crypto.randomBytes(buf[0..]);
    const seed = std.mem.readIntLittle(u64, buf[0..8]);
    var r = std.rand.DefaultPrng.init(seed);
    var rng = r.random;

    @setEvalBranchQuota(8000);
    const example = struct {
        pub fn foo(
            s: []u8,
            x: u32,
            y: u32,
            z: [2]u8,
            w: std.meta.Vector(8, u8),
            a: bool,
            b: enum { one, two, three },
            c: struct { x: u8, y: bool },
            d: union(enum) { a: u32, b: bool, c },
            e: error{ A, B },
            f: void,
            g: u0,
        ) u32 {
            return x +% y;
        }
    };
    var buffer: [256]u8 = undefined;
    try fuzz(&rng, example.foo, .{ .@"0" = @as([]u8, &buffer) }, .{}, (struct {
        pub fn f(result: anytype, context: anytype, arguments: anytype) !void {
            std.debug.print("{} {} {}\n", .{ result, context, arguments });
        }
    }).f);
}
