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
        stack: [size]Entity.Token,
        index: Entity.Token = size,
        alive: Entity.Token = 0,

        const Self = @This();

        const Tag = meta.Int(
            .unsigned,
            math.ceilPowerOfTwoAssert(usize, math.max(8, info.fields.len + 1)),
        );

        const live_bit = @as(Tag, 1) << info.fields.len;

        pub fn init() Self {
            var self: Self = .{ .stack = undefined };
            for (&self.stack) |*n, i| n.* = @truncate(Entity.Token, (size - 1) - i);
            mem.set(Tag, &self.tags, 0);
            return self;
        }

        pub fn reset(self: *Self) void {
            for (self.stack) |*n, i| n.* = @truncate(Entity.Token, (size - 1) - i);
            mem.set(Tag, &self.tags, 0);
            self.index = size;
        }

        pub const Entity = extern struct {
            token: Token,

            pub const Token = u32;
        };

        const TagEnum = meta.FieldEnum(T);

        pub const Components = blk: {
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
                    .fields = fields[0..used],
                    .decls = &.{},
                    .is_tuple = false,
                },
            });
        };

        const info = @typeInfo(T).Struct;

        pub fn new(self: *Self) !Entity {
            if (self.index == 0) return error.OutOfMemory;
            self.index -= 1;
            const token = self.stack[self.index];
            self.tags[token] = live_bit;
            self.alive += 1;
            return Entity{ .token = token };
        }

        pub fn delete(self: *Self, entity: Entity) void {
            assert(self.tags[entity.token] & live_bit != 0);
            self.tags[entity.token] = 0;
            self.stack[self.index] = entity.token;
            self.alive -= 1;
        }

        fn Subtype(comptime subset: anytype) type {
            if (comptime meta.trait.isContainer(@TypeOf(subset))) {
                var fields: [subset.len]TypeInfo.StructField = undefined;
                for (subset) |n, i| {
                    var field = info.fields[@enumToInt(@field(TagEnum, @tagName(n)))];
                    if (field.field_type == void) {
                        field.field_type = bool;
                        field.alignment = 1;
                        field.default_value = null;
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
            assert(self.tags[entity.token] & live_bit != 0);
            const ST = Subtype(fields);
            var r: ST = undefined;
            if (comptime meta.trait.isContainer(@TypeOf(fields))) {
                inline for (meta.fields(ST)) |field| {
                    if (!@hasField(Components, field.name) and @hasField(T, field.name)) {
                        const bit = @as(Tag, 1) << @enumToInt(@field(TagEnum, field.name));
                        @field(r, field.name) = self.tags[entity.token] & bit != 0;
                    } else {
                        @field(r, field.name) = @field(self.components, field.name)[entity.token];
                    }
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
            return Iterator{ .self = self, .match = match | live_bit, .ignore = ignore };
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
                        return Entity{ .token = @intCast(Entity.Token, it.index) };
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

    var t = T.init();
    const entity = try t.new();
    t.tag(entity, .{.i});

    t.set(entity, .{ .i = 1, .u = 2 });
    testing.expectEqual(@as(i32, 1), t.get(entity, .i));
    testing.expectEqual(@as(u32, 2), t.get(entity, .{ .i, .u }).u);

    var it = t.iterator(.{ .i = .match });
    var l: usize = 0;
    while (it.next()) |e| {
        testing.expectEqual(@as(i32, 1), t.get(e, .i));
        l += 1;
    }
    testing.expectEqual(@as(usize, 1), l);

    t.untag(entity, .{.i});

    while (it.next()) |e| l += 1;
    testing.expectEqual(@as(usize, 1), l);
}
