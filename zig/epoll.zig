const std = @import("std");
const os = std.os;
const mem = std.mem;
const meta = std.meta;
const math = std.math;
const testing = std.testing;
const assert = std.debug.assert;

fn Epoll(comptime T: type) type {
    return struct {
        buffer: [16]os.epoll_event = undefined,
        index: usize = 0,
        timeout: i32 = -1,
        fd: os.fd_t,

        const Self = @This();

        pub const Config = struct {
            in: bool = false,
            out: bool = false,
            err: bool = false,
            et: bool = false,
            rdhup: bool = false,
            pri: bool = false,
            oneshot: bool = false,
            wakeup: bool = false,
            exclusive: bool = false,
        };

        fn configure(config: Config) u32 {
            var events: u32 = 0;
            if (config.in) events |= os.EPOLLIN;
            if (config.out) events |= os.EPOLLOUT;
            if (config.err) events |= os.EPOLLERR;
            if (config.et) events |= os.EPOLLET;
            if (config.rdhup) events |= os.EPOLLRDHUP;
            if (config.pri) events |= os.EPOLLPRI;
            if (config.oneshot) events |= os.EPOLLONESHOT;
            if (config.wakeup) events |= os.EPOLLWAKEUP;
            if (config.exclusive) events |= os.EPOLLEXCLUSIVE;
            return events;
        }

        pub fn add(self: *Self, data: T, fd: os.fd_t, cfg: Config) !void {
            var event: os.epoll_event = .{
                .events = configure(cfg),
                .data = .{ .u64 = pack(u64, data) },
            };
            try os.epoll_ctl(self.fd, os.EPOLL_CTL_ADD, fd, &event);
        }

        pub fn mod(self: *Self, data: T, fd: os.fd_t, cfg: Config) !void {
            var event: os.epoll_event = .{
                .events = configure(cfg),
                .data = .{ .u64 = pack(u64, data) },
            };
            try os.epoll_ctl(self.fd, os.EPOLL_CTL_MOD, fd, &event);
        }

        pub fn del(self: *Self, data: T, fd: os.fd_t) !void {
            try os.epoll_ctl(self.fd, os.EPOLL_CTL_DEL, fd, null);
        }

        const Pair = struct {
            in: bool, out: bool, err: bool, rdhup: bool, pri: bool, hup: bool, data: T
        };

        pub fn wait(self: *Self) ?Pair {
            while (true) {
                if (self.index == 0) {
                    self.index = os.epoll_wait(self.fd, &self.buffer, self.timeout);
                    if (self.index == 0) return null;
                } else {
                    self.index -= 1;
                    const e = self.buffer[self.index].events;
                    var event: Pair = undefined;
                    event.in = os.EPOLLIN & e > 0;
                    event.out = os.EPOLLOUT & e > 0;
                    event.pri = os.EPOLLPRI & e > 0;
                    event.err = os.EPOLLERR & e > 0;
                    event.rdhup = os.EPOLLRDHUP & e > 0;
                    event.hup = os.EPOLLHUP & e > 0;
                    event.data = unpack(T, self.buffer[self.index].data.u64);
                    return event;
                }
            }
        }
    };
}

pub fn pack(comptime T: type, data: anytype) T {
    return packInternal(@TypeOf(data), T, 0, data);
}

fn bitSizeOf(comptime T: type) comptime_int {
    switch (@typeInfo(T)) {
        .Bool => return 1,
        .Void => return 0,
        .Int => |info| return info.bits,
        .Float => |info| return info.bits,
        .Enum => |info| return @bitSizeOf(info.tag_type),
        .Union => |info| {
            var size: usize = 0;
            for (info.fields) |field| size += bitSizeOf(field.field_type);
            if (info.tag_type) |tag| size += @bitSizeOf(tag);
            return size;
        },
        .Struct => |info| {
            var size: usize = 0;
            for (info.fields) |field| size += bitSizeOf(field.field_type);
            return size;
        },
        else => @compileError("unimplemented: " ++ @typeName(T)),
    }
}

fn packInternal(comptime T: type, comptime R: type, comptime bit: usize, data: T) R {
    const max = bitSizeOf(R);
    switch (@typeInfo(T)) {
        .Bool => @boolToInt(data),
        .Void => return 0,
        .ComptimeInt => return data,
        .ComptimeFloat => @compileError("todo: what do I even set here?"),
        .Int => |info| return @bitCast(meta.Int(.unsigned, info.bits), data),
        .Float => switch (T) {
            f16 => return @bitCast(u16, data),
            f32 => return @bitCast(u32, data),
            f64 => return @bitCast(u64, data),
            f128 => return @bitCast(u128, data),
        },
        .Enum => return @enumToInt(data),
        .Union => |info| {
            comptime var limit = bit;
            var result: R = 0;
            comptime for (info.fields) |field| {
                limit = math.max(limit, bitSizeOf(field.field_type));
            };
            comptime assert(limit + @sizeOf(info.tag_type.?) <= max);
            inline for (info.fields) |field| if (data == @field(info.tag_type.?, field.name)) {
                result = packInternal(field.field_type, R, bit, @field(data, field.name));
            };
            result <<= bitSizeOf(info.tag_type.?);
            result |= @enumToInt(data);
            return result;
        },
        .Struct => |info| {
            comptime var limit = bit;
            var result: R = 0;
            inline for (info.fields) |field| {
                result <<= bitSizeOf(field.field_type);
                result |= packInternal(field.field_type, R, limit, @field(data, field.name));
                limit += bitSizeOf(field.field_type);
            }
            comptime assert(limit <= max);
            return result;
        },
        else => @compileError("unable to pack " ++ @typeName(T)),
    }
}

pub fn unpack(comptime T: type, data: anytype) T {
    return unpackInternal(@TypeOf(data), T, data);
}

fn unpackInternal(comptime T: type, comptime R: type, data: T) R {
    switch (@typeInfo(R)) {
        .Bool => return data == 1,
        .Void => {},
        .Int => |info| if (info.bits > bitSizeOf(T)) {
            @compileError("incorrect packing size");
        } else return @bitCast(R, @truncate(meta.Int(.unsigned, bitSizeOf(R)), data)),
        .Float => |info| if (info.bits > bitSizeOf(T)) {
            @compileError("incorrect packing size");
        } else switch (T) {
            f16 => return @bitCast(f16, @truncate(u16, data)),
            f32 => return @bitCast(f32, @truncate(u32, data)),
            f64 => return @bitCast(f64, @truncate(u64, data)),
            f128 => return @bitCast(f128, @truncate(u128, data)),
        },
        .Enum => |info| if (bitSizeOf(info.tag_type) > bitSizeOf(T)) {
            @compileError("incorrect packing size");
        } else return @intToEnum(R, @truncate(meta.Int(.unsigned, bitSizeOf(R)), data)),
        .Union => |info| {
            const tagbits = bitSizeOf(info.tag_type.?);
            const tag = @truncate(meta.Int(.unsigned, tagbits), data);
            inline for (info.fields) |field| if (tag == @enumToInt(@field(info.tag_type.?, field.name))) {
                return @unionInit(R, field.name, unpackInternal(T, field.field_type, data >> tagbits));
            };
            unreachable;
        },
        .Struct => |info| {
            var result: R = undefined;
            var tmp = data;
            inline for (info.fields) |_, i| {
                const field = info.fields[info.fields.len - (i + 1)];
                @field(result, field.name) = unpackInternal(T, field.field_type, tmp);
                tmp >>= bitSizeOf(field.field_type);
            }
            return result;
        },

        else => @compileError("unable to unpack " ++ @typeName(R)),
    }
}

test "pack unpack" {
    const Enum = enum { a, b, c };
    const Struct = struct { a: u32, b: u32 };
    const Union = union(enum) { a, b: u32 };
    const Complex = union(enum) {
        b,
        a: struct { b: u32, c: enum { k, j } },
    };
    const x: u64 = pack(u64, 1);
    const y = pack(u64, @as(Enum, .a));
    const z = pack(u64, @as(Struct, .{ .a = 1, .b = 2 }));
    const w = pack(u64, @as(Union, .{ .b = 3 }));
    const k = pack(u64, @as(Union, .a));
    const c = pack(u64, @as(Complex, .{ .a = .{ .b = 12, .c = .k } }));
    testing.expectEqual(x, unpack(u8, x));
    testing.expectEqual(Enum.a, unpack(Enum, y));
    testing.expectEqual(Struct{ .a = 1, .b = 2 }, unpack(Struct, z));
    testing.expectEqual(Union{ .b = 3 }, unpack(Union, w));
    testing.expectEqual(Union.a, unpack(Union, k));
    testing.expectEqual(Complex{ .a = .{ .b = 12, .c = .k } }, unpack(Complex, c));
}

const Event = union(enum) {
    stdin,
    net: os.fd_t,
};

pub fn main() !void {
    const stdin = std.io.getStdIn();
    var epoll = Epoll(Event){ .fd = try os.epoll_create1(os.EPOLL_CLOEXEC) };
    try epoll.add(.stdin, stdin.handle, .{ .in = true, .et = true });
    while (epoll.wait()) |event| switch (event.data) {
        .stdin => {
            const reader = stdin.reader();
            const writer = stdin.writer();
            var tmp: [1024 * 64]u8 = undefined;
            const line = tmp[0..try reader.read(&tmp)];
            try writer.writeAll(line);
        },
        .net => |fd| {},
    };
}
