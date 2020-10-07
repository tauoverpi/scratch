const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;
const StructField = TypeInfo.StructField;

const Currency = enum { EUR, CAD, CHF, GBP, SEK, USD, RUB };

const Conversion = struct {
    base: Currency,
    date: []const u8,
    rates: []Rate,

    const Rate = struct {
        EUR: f64,
        CAD: f64,
        CHF: f64,
        GBP: f64,
        SEK: f64,
        USD: f64,
        RUB: f64,
        PHP: f64,
    };
};
