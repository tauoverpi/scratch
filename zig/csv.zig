// Copyright (c) 2020 Simon A. Nielsen Knights <tauoverpi@yandex.com>
// License: MIT

const std = @import("std");
const testing = std.testing;
const parser = @import("utf8-parser.zig");
const ParserOptions = parser.ParserOptions;
const P = parser.P;

fn item(comptime T: type, text: []const u8) !T {
    if (comptime std.meta.trait.isContainer(T) and @hasField(T, "parse")) {
        return T.parse(text);
    } else switch (@typeInfo(T)) {
        .Int => return try std.fmt.parseInt(T, text, 10),
        .Float => return try std.fmt.parseFloat(T, text),
        .Enum => |info| return std.meta.stringToEnum(T, text) orelse error.UnknownEnumValue,
        .Pointer => |info| if (T == []const u8) {
            return text;
        } else @compileError("only []const u8"),
        //.Optional => |info| return if (text.len == 0) null else item(info.child, text),
        else => @compileError(@typeName(T) ++ " is not supported as an item type"),
    }
}

test "parse-item" {
    testing.expect((try item(u32, "12345")) == 12345);
    testing.expect((try item(f32, "1.0")) == 1.0);
    testing.expect((try item(enum { SEK, GBP }, "SEK")) == .SEK);
    //testing.expect((try item(?f32, "")) == null);
}

fn row(comptime T: type, p: *P) !T {
    if (comptime std.meta.trait.isContainer(T) and @hasField(T, "parse")) {
        return T.parse(text);
    }

    const comma = (struct {
        pub fn pass(x: *P) !void {
            _ = try x.not(',');
        }
    }).pass;

    const newline = (struct {
        pub fn pass(x: *P) !void {
            _ = try x.not('\n');
        }
    }).pass;

    var r: T = undefined;

    if (comptime !std.meta.trait.is(.Struct)(T)) @compileError("only structs may represent rows");
    const fields = std.meta.fields(T);
    inline for (fields) |field, i| {
        if (i + 1 == fields.len) {
            @field(r, field.name) = try item(field.field_type, try p.string(newline));
        } else {
            @field(r, field.name) = try item(field.field_type, try p.string(comma));
            try p.expect(',');
        }
    }
    return r;
}

const Currency = enum { SEK, GBP, PHP, USD };

const Date = struct {
    year: usize,
    month: usize,
    day: usize,

    pub fn parse(text: []const u8) !Date {
        var p = P{ .text = text };
        var r: Date = undefined;
        r.year = try item(usize, try p.string1(P.dec));
        try p.expect('-');
        r.month = try item(usize, try p.string1(P.dec));
        try p.expect('-');
        r.day = try item(usize, try p.string1(P.dec));
        return r;
    }
};

const Transaction = struct {
    row: usize,
    clearing: usize,
    account: usize,
    product: []const u8,
    currency: Currency,
    booking_day: Date,
    transaction_day: Date,
    currency_day: Date,
    reference: []const u8,
    description: []const u8,
    sum: f64, // <- never do this for money
};

test "parse-transaction" {

    // Radnummer,Clearingnummer,Kontonummer,Produkt,Valuta,Bokföringsdag,Transaktionsdag,Valutadag,Referens,Beskrivning,Belopp
    var p = P{
        .text =
        \\1,10101,1234567890,"name",SEK,2020-09-28,2020-09-28,2020-09-28,"SHOP","SHOP",-10.43
    };
    const result = try row(Transaction, &p); // this should work
    std.debug.print("{}\n", .{result});
}
