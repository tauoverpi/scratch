//| Proposal:
//|
//| Allow restricted views of structs of the form `struct { baud: usize | _ }`
//| where only the mentioned fields can be reached (`_` represents the rest of
//| the struct that's not accessible) and only the subset in the view is passed
//| to the callee.
//|
//| Should the callee return the same struct `fn(struct{x:u8|r}) struct{x:u8|r}`
//| the full struct with the fields given upon calling is placed in the result
//| location and updated with the returned fields.
//|
//| Implicit casts:
//|
//| - for the caller of the function taking a view of a struct the return is of
//|   the same struct passed to the callee
//|   `struct { f0: t0, ..., fN: tN | rest } == struct { f0: t0, ..., fN: tN, rest }`
//| - for the callee the view is equivalent to any struct of the same shape as
//|   the subset
//|   `struct { f0: t0, ..., fN: tN | _} == struct { f0: t0, ..., fN: tN }`
//|
//| comptime copy implementation:

const std = @import("std");

pub fn subset(comptime T: type, value: anytype) T {
    // while this works it does incurr overhead for keeping type safety without
    // extra magic
    var r: T = undefined;

    inline for (std.meta.fields(T)) |field| {
        @field(r, field.name) = @field(value, field.name);
    }

    return r;
}

pub fn merge(comptime T: type, set: anytype, value: T) void {
    // used for merging back into the original set
    var r = set;

    inline for (std.meta.fields(T)) |field| {
        @field(set, field.name) = @field(value, field.name);
    }
}

//| Related footgun it prevents (but doesn't solve):
//|
//| Currently `anytype` hides footguns in the form of any type which can use the
//| `x.f` notation since it relies on the field having the right name and type
//| rather than any kind of sanity check if it's even possible to reach the
//| field.

test "footgun" {
    const Projectile = union(enum) { x: u32, y: u32 };

    var foot: Projectile = .{ .x = 5 };

    const shoot = (struct {
        pub fn gun(x: anytype) void {
            // this should be a compile error since it's impossible for a union
            // to change here for this expression to be correct
            _ = x.x + x.y;
        }
    }).gun;

    shoot(foot);
}

//| The proposal on constraining to a subset of fields in structs (or just
//| constraining to be a struct) would allow for avoiding this in cases where
//| analysis can't catch it.
//|
//| Motivation:

test "subset-equivalence" {

    //| Say you have a configuration for talking to Modbus meters or similar
    const SecondaryAddress = struct { id: u32, medium: u8, version: u8, manufacturer: u16 };
    const ComType = enum { RS232, RS485 };
    const Parity = enum { even, odd };
    const Telegram = *@Type(.Opaque); // imagine an M-Bus meter telegram

    //| Communication is usually serial thus give the following
    const SerialDevice = struct {
        comport: usize,
        com: ComType,
        bits: u4 = 8,
        parity: Parity = .even,
        stopbit: u2 = 1,
        baud: usize,
        primary: u8,
        secondary: SecondaryAddress,
        telegrams: []const Telegram,
    };

    //| However it can be over a network where each meter differs in
    //| configuration of at least one of the serial parameters
    const NetDevice = struct {
        address: struct { ip: []const u8, port: u16 },
        com: ComType,
        bits: u4 = 8,
        parity: Parity = .even,
        stopbit: u2 = 1,
        baud: usize,
        primary: u8,
        secondary: SecondaryAddress,
        telegrams: []const Telegram,
    };

    //| Both structures overlap as they're the exact same structure apart from
    //| the first field
    const EqualSubset = struct {
        com: ComType,
        bits: u4,
        parity: Parity,
        stopbit: u2,
        baud: usize,
        primary: u8,
        secondary: SecondaryAddress,
        telegrams: []const Telegram,
    };

    //| and in the case where one must select between them
    const Device = union(enum) {
        Serial: SerialDevice,
        Net: NetDevice,
    };

    //| where only one is active
    var device = Device{
        .Serial = .{
            .comport = 4,
            .com = .RS485,
            .baud = 2400,
            .primary = 0,
            .secondary = .{ .id = 0x12345678, .version = 0, .medium = 0, .manufacturer = 0x7f },
            .telegrams = &[_]Telegram{},
        },
    };

    //| you would currently have to duplicate code, make a copy of the subset, or use anytype
    var sub = switch (device) {
        .Net => |net| subset(EqualSubset, net),
        .Serial => |ser| subset(EqualSubset, ser),
    };

    //| this works with anytype but now the type signature doesn't say anything about
    //| the type it works on and the only other option I'm aware of is a new
    //| type + copy to constrain it to the subset. However, with the proposal it
    //| would explicitly specify what it takes as follows:
    //|
    //| struct {
    //|    com: ComType,
    //|    bits: u4,
    //|    parity: Parity,
    //|    stopbit: u2,
    //|    baud: usize,
    //|    primary: u8,
    //|    secondary: SecondaryAddress,
    //|    telegrams: []const Telegram,
    //|    | _
    //| }
    //|
    //| Which only cares that the fields and type exists (like anytype use) but
    //| explicit in the type signature.
    const modifySomehow = (struct {
        pub fn modifySomehow(set: *EqualSubset) void {
            set.baud = 9600;
        }
    }).modifySomehow;

    modifySomehow(&sub);

    //| which results in an awkward inteface
    switch (device) {
        .Net => |*net| merge(EqualSubset, net, sub),
        .Serial => |*ser| merge(EqualSubset, ser, sub),
    }

    std.debug.print("{}\n", .{device});
}
