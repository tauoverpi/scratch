const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;
const meta = std.meta;
const math = std.math;
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const EntityStoreType = union(enum) {
    dynamic,
    static: usize,
    // TODO: slice
};

pub fn EntityStore(options: EntityStoreType, comptime T: type) type {
    const info = @typeInfo(T).Struct;
    const static: ?usize = if (options == .static) options.static else null;

    var entity_fields: [info.fields.len]TypeInfo.StructField = undefined;
    var used_fields: u16 = 0;

    for (info.fields) |field, i| {
        if (field.field_type != void) {
            entity_fields[used_fields] = .{
                .is_comptime = false,
                .name = field.name,
                .field_type = if (static) |size| [size]field.field_type else []field.field_type,
                .alignment = 0,
                .default_value = null,
            };
            used_fields += 1;
        }
    }

    return struct {
        entities: Entities = undefined,
        allocator: if (options == .dynamic) *Allocator else void,
        tags: if (static) |size| [size]Tag else []Tag = undefined,
        generations: if (static) |size| [size]Gen else []Gen = undefined,
        stack: if (static) |size| [size]u16 else []u16 = undefined,
        index: usize = 0,

        pub const Entities = @Type(.{
            .Struct = .{
                .layout = info.layout,
                .fields = entity_fields[0..used_fields],
                .decls = &.{},
                .is_tuple = false,
            },
        });

        pub const Fields = meta.FieldEnum(Entities);
        pub const TagEnum = meta.FieldEnum(T);
        pub const Entity = extern struct {
            token: u16,
            generation: Gen,
        };

        pub const Self = @This();

        pub const Gen = u16;
        pub const Tag = meta.Int(.unsigned, math.ceilPowerOfTwoAssert(usize, entity_fields.len + 1));
        pub const dead_bit = @as(Tag, 1) << entity_fields.len;

        pub usingnamespace switch (options) {
            .static => struct {
                pub fn init() Self {
                    var self: Self = undefined;
                    self.reset();
                    return self;
                }
            },
            .dynamic => struct {
                pub fn init(allocator: *Allocator, capacity: usize) !Self {
                    @panic("TODO");
                }
            },
        };

        pub fn create(self: *Self) !Entity {
            if (self.index == 0) return error.OutOfMemory;
            self.index -= 1;
            const token = self.stack[self.index];
            self.generations[token] += 1;
            self.tags[token] = 0;
            return Entity{ .token = token, .generation = self.generations[token] };
        }

        pub fn destroy(self: *Self, entity: Entity) void {
            assert(entity.generation == self.generations[entity.token]);
            assert(self.index != self.stack.len);
            self.tags[entity.token] = dead_bit;
            self.stack[self.index] = entity.token;
            self.index += 1;
        }

        pub fn reset(self: *Self) void {
            mem.set(Tag, self.tags[0..self.tags.len], dead_bit);
            mem.set(Gen, self.generations[0..self.generations.len], 0);
            for (self.stack) |*n, i| n.* = @intCast(u16, i);
            self.index = self.stack.len;
        }

        pub fn mark(self: *Self, entity: Entity, comptime tags: anytype) void {
            assert(entity.generation == self.generations[entity.token]);
            comptime var tag: Tag = 0;
            comptime for (meta.fields(@TypeOf(tags))) |field| {
                const offset = @enumToInt(@field(TagEnum, @tagName(@field(tags, field.name))));
                tag |= @as(Tag, 1) << offset;
            };
            self.tags[entity.token] |= tag;
        }

        pub fn unmark(self: *Self, entity: Entity, comptime tags: anytype) void {
            assert(entity.generation == self.generations[entity.token]);
            comptime var tag: Tag = 0;
            comptime for (meta.fields(@TypeOf(tags))) |field| {
                const offset = @enumToInt(@field(TagEnum, @tagName(@field(tags, field.name))));
                tag |= @as(Tag, 1) << offset;
            };
            self.tags[entity.token] &= ~tag;
        }

        pub fn update(self: *Self, entity: Entity, fields: anytype) void {
            assert(entity.generation == self.generations[entity.token]);
            inline for (meta.fields(@TypeOf(fields))) |field| {
                @field(self.entities, field.name)[entity.token] = @field(fields, field.name);
            }
        }

        const Sub = enum { none, ptr, slice };
        fn SubtypeWith(comptime mod: Sub, comptime fset: anytype) type {
            if (comptime meta.trait.isContainer(@TypeOf(fset))) {
                const args = meta.fields(@TypeOf(fset));
                var fields: [args.len]TypeInfo.StructField = undefined;
                for (args) |field, i| {
                    const name: []const u8 = @tagName(@field(fset, field.name));
                    const there = meta.fieldInfo(T, @field(fset, field.name)).field_type;
                    const typ = if (there == void) bool else there;
                    const given = switch (mod) {
                        .ptr => *typ,
                        .none => typ,
                        .slice => []typ,
                    };
                    fields[i] = .{
                        .name = name,
                        .field_type = if (there == void) typ else given,
                        .alignment = @alignOf(given),
                        .is_comptime = false,
                        .default_value = null,
                    };
                }

                return @Type(.{
                    .Struct = .{
                        .layout = info.layout,
                        .fields = &fields,
                        .decls = &.{},
                        .is_tuple = false,
                    },
                });
            } else {
                const typ = meta.fieldInfo(T, fset).field_type;
                switch (mod) {
                    .ptr => return *typ,
                    .none => return typ,
                    .slice => return []typ,
                }
            }
        }

        pub fn get(self: *Self, entity: Entity, comptime fields: anytype) SubtypeWith(.none, fields) {
            assert(entity.generation == self.generations[entity.token]);
            if (comptime meta.trait.isContainer(@TypeOf(fields))) {
                const FT = SubtypeWith(.none, fields);
                var ft: FT = undefined;
                inline for (meta.fields(FT)) |field| {
                    if (!@hasField(Entities, field.name) and @hasField(T, field.name)) {
                        const offset = @enumToInt(@field(TagEnum, field.name));
                        @field(ft, field.name) = self.tags[entity.token] & (@as(Tag, 1) << offset) != 0;
                    } else {
                        @field(ft, field.name) = @field(self.entities, field.name)[entity.token];
                    }
                }
                return ft;
            } else return @field(self.entities, @tagName(fields))[entity.token];
        }

        pub fn at(self: *Self, entity: Entity, comptime fields: anytype) SubtypeWith(.ptr, fields) {
            assert(entity.generation == self.generations[entity.token]);
            if (comptime meta.trait.isContainer(@TypeOf(fields))) {
                const FT = SubtypeWith(.ptr, fields);
                var ft: FT = undefined;
                inline for (meta.fields(FT)) |field| {
                    if (!@hasField(Entities, field.name) and @hasField(T, field.name)) {
                        const offset = @enumToInt(@field(TagEnum, field.name));
                        @field(ft, field.name) = self.tags[entity.token] & (@as(Tag, 1) << offset) != 0;
                    } else {
                        @field(ft, field.name) = &@field(self.entities, field.name)[entity.token];
                    }
                }
                return ft;
            } else return &@field(self.entities, @tagName(fields))[entity.token];
        }

        pub fn iterator(self: *Self, comptime filter: Iterator.Filter) Iterator {
            comptime var match: Tag = 0;
            comptime var ignore: Tag = 0;
            comptime for (meta.fields(Iterator.Filter)) |field| {
                const offset = @enumToInt(@field(TagEnum, field.name));
                switch (@field(filter, field.name)) {
                    .match => match |= @as(Tag, 1) << offset,
                    .ignore => ignore |= @as(Tag, 1) << offset,
                    else => {},
                }
            };

            return .{ .self = self, .match = match, .ignore = ignore | dead_bit };
        }

        pub const Iterator = struct {
            self: *Self,
            match: Tag,
            ignore: Tag,
            index: usize = 0,

            const Config = enum { ignore, match, none };

            pub fn next(it: *Iterator) ?Entity {
                while (it.index < it.self.tags.len) {
                    defer it.index += 1;
                    const tags = it.self.tags[it.index];
                    if (it.ignore & tags == 0 and it.match & tags == it.match) {
                        const gen = it.self.generations[it.index];
                        return Entity{
                            .token = @intCast(u16, it.index),
                            .generation = gen,
                        };
                    }
                } else return null;
            }

            pub const Filter = blk: {
                var filter_fields: [info.fields.len]TypeInfo.StructField = undefined;
                for (info.fields) |field, i| {
                    filter_fields[i] = .{
                        .name = field.name,
                        .field_type = Config,
                        .alignment = @alignOf(Config),
                        .is_comptime = false,
                        .default_value = Config.none,
                    };
                }

                break :blk @Type(.{
                    .Struct = .{
                        .layout = .Auto,
                        .fields = &filter_fields,
                        .decls = &.{},
                        .is_tuple = false,
                    },
                });
            };
        };
    };
}

test "" {
    const T = EntityStore(.{ .static = 256 }, struct {
        int: i32,
        uint: u32,
        flag: void,
        slice: []const u8,
        pointer: *u8,
        set: enum { one, two },
        structure: struct { one: u32, two: u32 },
        sum: union(enum) { one, two },
    });

    var int: [256]i32 = undefined;
    var gen: [256]u16 = undefined;
    var tag: [256]T.Tag = undefined;
    var uint: [256]u32 = undefined;
    var stack: [256]u16 = undefined;

    var t: T = undefined;

    t.reset();

    const ent = try t.create();

    const at = t.at(ent, .{ .int, .uint });
    at.int.* = 1;
    at.uint.* = 2;
    testing.expectEqual(@as(i32, 1), t.get(ent, .{ .int, .flag }).int);

    t.update(ent, .{ .int = 2 });
    testing.expectEqual(@as(i32, 2), t.get(ent, .int));

    var it = t.iterator(.{ .int = .match });
    testing.expectEqual(@as(?T.Entity, null), it.next());

    t.mark(ent, .{.int});

    it = t.iterator(.{ .int = .match });

    testing.expectEqual(@as(?T.Entity, ent), it.next());
    testing.expectEqual(@as(?T.Entity, null), it.next());
    testing.expectEqual(@as(?T.Entity, null), it.next());

    it = t.iterator(.{ .int = .match });
    t.unmark(ent, .{.int});
    testing.expectEqual(@as(?T.Entity, null), it.next());

    it = t.iterator(.{ .int = .match });
    t.mark(ent, .{.int});
    testing.expectEqual(@as(?T.Entity, ent), it.next());

    t.destroy(ent);
    it = t.iterator(.{ .int = .match });
    testing.expectEqual(@as(?T.Entity, null), it.next());
}

test "" {
    const Store = EntityStore(.{ .static = 256 }, struct {
        position: struct { x: f32, y: f32 },
        direction: struct { x: f32, y: f32 },
        health: u32,
        bullet: void,
        enemy: void,
    });

    var store = Store.init();
}
