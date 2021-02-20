const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;
const meta = std.meta;
const math = std.math;
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

pub fn ComponentStore(comptime size: usize, comptime T: type) type {
    return struct {
        components: Components = undefined,
        tags: [size]Tag = undefined,
        stack: [size]Entity.Token = undefined,
        index: Entity.Token = size,

        const Self = @This();

        const Tag = meta.Int(
            .unsigned,
            math.ceilPowerOfTwoAssert(usize, math.max(8, info.fields.len + 1)),
        );

        const dead_bit = @as(Tag, 1) << info.fields.len;

        pub const Entity = extern struct {
            token: Token,

            pub const Token = u32;
        };

        const TagEnum = meta.FieldEnum(T);

        const Components = blk: {
            var fields: [info.fields.len]TypeInfo.StructField = undefined;
            var used: usize = 0;
            for (info.fields) |field, i| {
                if (field.field_type != void) {
                    fields[used] = .{
                        .is_comptime = false,
                        .name = field.name,
                        .field_type = [size]field.field_type,
                        .alignment = 0,
                        .default_value = null,
                    };
                    used += 1;
                }
            }

            break :blk @Type(.{
                .Struct = .{
                    .layout = .Auto,
                    .fields = &fields,
                    .decls = &.{},
                    .is_tuple = false,
                },
            });
        };

        const info = @typeInfo(T).Struct;

        pub fn new(self: *Self) !Entity {
            if (self.index == 0) return error.OutOfMemory;
            self.index -= 1;
            return Entity{ .token = self.stack[self.index] };
        }

        pub fn delete(self: *Self, entity: Entity) void {
            self.stack[self.index] = entity.token;
        }

        fn Subtype(comptime subset: anytype) type {
            if (comptime meta.trait.isContainer(@TypeOf(subset))) {
                var fields: [subset.len]TypeInfo.StructField = undefined;
                for (subset) |n, i| {
                    var field = info.fields[@enumToInt(@field(TagEnum, @tagName(n)))];
                    if (field.field_type == void) {
                        field.field_type = bool;
                        field.alignment = 1;
                    }
                    fields[i] = field;
                }

                return @Type(.{
                    .Struct = .{
                        .layout = info.layout,
                        .fields = &fields,
                        .decls = &.{},
                        .is_tuple = false,
                    },
                });
            } else return meta.fieldInfo(T, subset).field_type;
        }

        pub fn get(self: *Self, entity: Entity, comptime fields: anytype) Subtype(fields) {
            const ST = Subtype(fields);
            var r: ST = undefined;
            if (comptime meta.trait.isContainer(@TypeOf(fields))) {
                inline for (meta.fields(ST)) |field| {
                    @field(r, field.name) = @field(self.components, field.name)[entity.token];
                }
                return r;
            } else return @field(self.components, @tagName(fields))[entity.token];
        }

        pub fn set(self: *Self, entity: Entity, fields: anytype) void {
            inline for (meta.fields(@TypeOf(fields))) |field| {
                @field(self.components, field.name)[entity.token] = @field(fields, field.name);
            }
        }

        pub fn tag(self: *Self, entity: Entity, comptime tags: anytype) void {
            comptime var subset: Tag = 0;
            comptime for (tags) |field| {
                subset |= @as(Tag, 1) << @enumToInt(@field(TagEnum, @tagName(field)));
            };
            self.tags[entity.token] |= subset;
        }

        pub fn untag(self: *Self, entity: Entity, comptime tags: anytype) void {
            comptime var subset: Tag = 0;
            comptime for (tags) |field| {
                subset |= @as(Tag, 1) << @enumToInt(@field(TagEnum, @tagName(field)));
            };
            self.tags[entity.token] &= ~subset;
        }

        pub fn iterator(self: *Self, comptime items: Iterator.Filter) Iterator {
            comptime var match: Tag = 0;
            comptime var ignore: Tag = 0;
            comptime for (meta.fields(@TypeOf(items))) |field| {
                const offset = @enumToInt(@field(TagEnum, field.name));
                switch (@field(items, field.name)) {
                    .match => match |= @as(Tag, 1) << offset,
                    .ignore => ignore |= @as(Tag, 1) << offset,
                    else => {},
                }
            };
            return Iterator{ .self = self, .match = match, .ignore = ignore | dead_bit };
        }

        pub const Iterator = struct {
            self: *Self,
            match: Tag,
            ignore: Tag,
            index: usize = 0,

            pub fn next(it: *Iterator) ?Entity {
                while (it.index < size) {
                    defer it.index += 1;
                    const item = it.self.tags[it.index];
                    if (it.ignore & item == 0 and it.match & item == it.match) {
                        return Entity{ .token = @intCast(Tag, it.index) };
                    }
                } else return null;
            }

            pub const FilterOption = enum { ignore, match, allow };

            pub const Filter = blk: {
                var fields: [info.fields.len]TypeInfo.StructField = undefined;
                for (info.fields) |field, i| {
                    fields[i] = .{
                        .name = field.name,
                        .field_type = FilterOption,
                        .alignment = 0,
                        .is_comptime = false,
                        .default_value = FilterOption.allow,
                    };
                }

                break :blk @Type(.{
                    .Struct = .{
                        .layout = .Auto,
                        .fields = &fields,
                        .decls = &.{},
                        .is_tuple = false,
                    },
                });
            };
        };
    };
}

test "" {
    const T = ComponentStore(256, struct {
        i: i32,
        u: u32,
    });

    var t: T = .{};
    const entity = try t.new();
    t.tag(entity, .{.i});

    t.set(entity, .{ .i = 1, .u = 2 });
    testing.expectEqual(@as(i32, 1), t.get(entity, .i));
    testing.expectEqual(@as(u32, 2), t.get(entity, .{ .i, .u }).u);

    var it = t.iterator(.{ .i = .match });
    var l: usize = 0;
    while (it.next()) |_| l += 1;
    testing.expectEqual(@as(usize, l), 1);

    t.untag(entity, .{.i});
}
