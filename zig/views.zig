//| Proposal:
//|
//| Allow restricted views of structs of the form `struct { baud: usize | _ }`
//| where only the mentioned fields can be reached (`_` represents the rest of
//| the struct that's not accessible) and only the subset in the view is passed
//| to the callee. Should the callee return the same struct `fn(struct{x:u8|r}) struct{x:u8|r}`
//| the full struct with the fields given upon calling is placed in the result
//| location and updated with the returned fields.
//|
//| Storing the in data structures view retains the rest of the fields since
//| the view is no different than the original struct in representation.
//|
//| Example:
//|
//| ```zig
//| /// Adjusts baudrate until a response can be read from the configured meter
//| pub fn searchBaud(cfg: *struct { baud: usize | _ }, timeout: usize) !void {
//|     // some logic providing an adjusted baud
//|     cfg.baud = adjusted;
//| }
//| ```
//|
//| ```zig
//| /// When passing back the same view the `_` is replaced by a name
//| /// representing information needed to reconstruct the struct from
//| /// the view. Omitting this returns an anonymous struct (as it's today)
//| /// rather than a view of the same as the input.
//| pub fn function(x: struct { k: u32 | r }) struct { k: u32 | r } {
//|     return x;
//| }
//| ```
//|
//| Conversion:
//|
//| - The view casts back into the type with `const t: Original = @fromView(view)` when
//|   the underlying struct of the view matches the result type. (can be implicit)
//|   `struct { f0: t0, ..., fN: tN | rest } ==> struct { f0: t0, ..., fN: tN, rest }`
//| - When passed to a procedure taking a view of a subset of the struct a view
//|   is passed `struct { f0: t0, ..., fN: tN } ==> struct { ... | _ }`
//|
//| Comptime implementation:

const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

// split the fields we care about from the struct
pub fn subset(comptime T: type, value: anytype) T {
    var r: T = undefined;

    inline for (std.meta.fields(T)) |field| {
        @field(r, field.name) = @field(value, field.name);
    }

    return r;
}

// merge them back at the end when we're done with it
pub fn merge(comptime T: type, set: anytype, value: T) void {
    var r = set;

    inline for (std.meta.fields(T)) |field| {
        @field(set, field.name) = @field(value, field.name);
    }
}

// return the common subset of fields both structs agree upon (not part of the proposal)
pub fn Subset(comptime A: type, comptime B: type) type {
    comptime var fields: []const TypeInfo.StructField = &[_]TypeInfo.StructField{};
    inline for (std.meta.fields(A)) |field| {
        if (@hasField(B, field.name) and @TypeOf(@field(@as(B, undefined), field.name)) == field.field_type) {
            fields = fields ++ &[_]TypeInfo.StructField{
                .{
                    .name = field.name,
                    .default_value = null,
                    .field_type = field.field_type,
                },
            };
        }
    }

    return @Type(TypeInfo{
        .Struct = .{
            .is_tuple = false,
            .fields = fields,
            .decls = &[_]TypeInfo.Declaration{},
            .layout = .Auto,
        },
    });
}

//| Motivation:
//|
//| Say you have a configuration for talking to Modbus meters or similar
const SecondaryAddress = struct { id: u32, medium: u8, version: u8, manufacturer: u15 };
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
    slaveaddress: u16,
    secondary: SecondaryAddress,
    telegrams: []const Telegram,
};

//| However it can be over a network where each meter may differ in
//| configuration of the serial parameters
const NetDevice = struct {
    address: struct { ip: []const u8, port: u16 },
    com: ComType,
    bits: u4 = 8,
    parity: Parity = .even,
    stopbit: u2 = 1,
    baud: usize,
    primary: u8,
    slaveaddress: u16,
    secondary: SecondaryAddress,
    telegrams: []const Telegram,
};

//| Both structures overlap as they're the exact same structure apart from
//| the first field thus we could construct a view of the overlap
const EqualSubset = Subset(NetDevice, SerialDevice);

//| and in the case where one must perform some operation over one of them
const Device = union(enum) {
    Serial: SerialDevice,
    Net: NetDevice,
};

test "at runtime" {

    //| where only one is active
    var device = Device{
        .Serial = .{
            .comport = 4,
            .com = .RS485,
            .baud = 2400,
            .primary = 0,
            .slaveaddress = 0,
            .secondary = .{ .id = 0x12345678, .version = 0, .medium = 0, .manufacturer = 0x7f },
            .telegrams = &[_]Telegram{},
        },
    };

    //| you would currently have to duplicate code
    //| const sub = ... TODO remove ptr
    var sub = switch (device) {
        .Net => |net| subset(EqualSubset, net),
        .Serial => |ser| subset(EqualSubset, ser),
    };

    //| and use a function which is either of type `anytype` and have comptime code
    //| to typecheck it with no restriction on what you access or a manually
    //| specialized procedure for each case
    modifySomehow(&sub);

    //| where with this proposal you could return a pointer restricted by the
    //| view of the original struct and modify it directly to remove the need to
    //| merge the subset back manually. This makes it purely a type-level restriction
    //| and doesn't bleed into runtime.
    switch (device) {
        .Net => |*net| merge(EqualSubset, net, sub),
        .Serial => |*ser| merge(EqualSubset, ser, sub),
    }

    std.debug.print("{}\n", .{device});
}

//| if views were supported one could instead provide a direct pointer to the
//| struct with a restricted view declaring exactly what may be modified/read
//| without constraining to one particular instance of a shape.
//|
//| const EqualSubset = struct {
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
//| thus the following would be generic over all structs the same size or larger
//| which contain the specified fields while being less powerful than `anytype`.
pub fn modifySomehow(set: *EqualSubset) void {
    set.baud = if (set.com == .RS232) 2400 else 9600;
    set.stopbit = 1;
    // and so on...
}
