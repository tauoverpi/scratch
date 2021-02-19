const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;
const meta = std.meta;
const math = std.math;

pub fn EntityStore(comptime T: type) type {
    const info = @typeInfo(T).Struct;

    var entity_fields: [info.fields.len]TypeInfo.StructField = undefined;
    var used_fields: u16 = 0;

    for (info.fields) |field, i| {
        if (field.field_type != void) {
            entity_fields[used_fields] = .{
                .is_comptime = false,
                .name = field.name,
                .field_type = []field.field_type,
                .alignment = 0,
                .default_value = null,
            };
            used_fields += 1;
        }
    }

    return struct {
        entities: Entities,
        memory: [*]u8 = undefined,
        tags: []Tags,
        generations: []u16,

        pub const Entities = @Type(.{
            .Struct = .{
                .layout = info.layout,
                .fields = entity_fields[0..used_fields],
                .decls = &.{},
                .is_tuple = false,
            },
        });

        pub const Fields = meta.FieldEnum(Entities);
        pub const FlagEnum = meta.FieldEnum(T);
        pub const Entity = extern struct {
            token: u16,
            generation: u16,
        };

        pub const Self = @This();

        pub const Tags = meta.Int(.unsigned, entity_fields.len);

        pub fn init(bytes: []u8) Self {}

        pub fn set(self: *Self, entity: Entity, comptime flags: anytype) void {}

        pub fn update(self: *Self, entity: Entity, fields: anytype) void {
            inline for (meta.fields(@TypeOf(fields))) |field| {
                @field(self.entities, field.name)[entity.token] = @field(fields, field.name);
            }
        }

        const Sub = enum { none, ptr, slice };
        fn SubtypeWith(comptime mod: Sub, comptime fset: anytype) type {
            const args = meta.fields(@TypeOf(fset));
            var fields: [args.len]TypeInfo.StructField = undefined;
            for (args) |field, i| {
                const name: []const u8 = @tagName(@field(fset, field.name));
                const typ = meta.fieldInfo(T, @field(fset, field.name)).field_type;
                const given = switch (mod) {
                    .ptr => *typ,
                    .none => typ,
                    .slice => []typ,
                };
                fields[i] = .{
                    .name = name,
                    .field_type = given,
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
        }

        pub fn get(self: *Self, entity: Entity, comptime fields: anytype) SubtypeWith(.none, fields) {
            const FT = SubtypeWith(.none, fields);
            var ft: FT = undefined;
            inline for (fields) |field| {
                @field(ft, @tagName(field)) = @field(self.entities, @tagName(field))[entity.token];
            }
            return ft;
        }

        pub fn at(self: *Self, entity: Entity, comptime fields: anytype) SubtypeWith(.ptr, fields) {
            const FT = SubtypeWith(.ptr, fields);
            var ft: FT = undefined;
            inline for (fields) |field| {
                @field(ft, @tagName(field)) = &@field(self.entities, @tagName(field))[entity.token];
            }
            return ft;
        }

        pub fn iterator(self: *Self, comptime filter: Iterator.Filter) Iterator {
            comptime var tags: Tags = 0;
            comptime for (meta.fields(Iterator.Filter)) |field| {
                const offset = @enumToInt(@field(FlagEnum, field.name));
                tags |= @as(Tags, 1) << offset;
            };

            return .{ .self = self, .tags = tags };
        }

        pub const Iterator = struct {
            self: *Self,
            tags: Tags,
            index: usize = 0,

            const Config = enum { ignore, match, filter };

            pub const Filter = blk: {
                var filter_fields: [info.fields.len]TypeInfo.StructField = undefined;
                for (info.fields) |field, i| {
                    filter_fields[i] = .{
                        .name = field.name,
                        .field_type = Config,
                        .alignment = @alignOf(Config),
                        .is_comptime = false,
                        .default_value = Config.ignore,
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
    const T = EntityStore(struct {
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

    var t: T = undefined;
    t.entities.int = &int;
    const at = t.at(T.Entity{ .token = 0, .generation = 0 }, .{ .int, .uint, .sum, .slice });
    //const get = t.get(T.Entity{ .token = 0, .generation = 0 }, .{.int});
    var it = t.iterator(.{ .int = .match });
    //while (it.next()) |_| {}
}
