const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

//                        The Plan
//
//     ,--> Optional Unknown ---,-----------------,
//     |                        v                 |
//     |,-> Number --> Optional Number --,        v
// Unknown                               |---> Optional String
//      `-> String ----------------------`
//

const Token = union(enum) {
    Cell: []const u8,
    Nil,
    End,
};

const TokenParser = struct {
    index: usize = 0,
    text: []const u8,
    delimiter: u8 = ',',
    last: ?Token = null,

    pub fn next(p: *TokenParser) ?Token {
        var count: usize = 0;
        if (p.last) |last| {
            p.last = null;
            return last;
        }
        if (p.index >= p.text.len) return null;
        while (p.index < p.text.len) : ({
            p.index += 1;
            count += 1;
        }) {
            const c = p.text[p.index];
            if (c == p.delimiter or c == '\n') {
                if (c == '\n') p.last = .End;
                defer p.index += 1;
                if (count == 0) {
                    return .Nil;
                } else
                    return Token{ .Cell = p.text[p.index - count .. p.index] };
            }
        } else if (count == 0) {
            return .End;
        } else {
            p.last = .End;
            defer p.index += 1;
            return Token{ .Cell = p.text[p.index - count .. p.index] };
        }
        return null;
    }
};

test "tokenize-csv" {
    var p = TokenParser{ .text = "a,,b,c,d\na,b,c" };
    while (p.next()) |item| {
        std.debug.print("{}\n", .{item});
    }
}

fn inferType(comptime text: []const u8) type {
    const Guess = enum { String, Number, OptString, OptNumber, OptUnknown };
    var it = TokenParser{ .text = text };
    comptime var column_names: []const []const u8 = &[_][]const u8{};
    if (text[0] == '#') {
        it.index = 1;
        inline while (it.next()) |cell| {
            switch (cell) {
                .Cell => |name| {
                    column_names = column_names ++ &[_][]const u8{name};
                },
                .Nil => @compileError("column names must not be empty"),
                .End => break,
            }
        }
    }
    comptime var first_row: []const Guess = &[_]Guess{};
    inline while (it.next()) |cell| {
        switch (cell) {
            .Nil => first_row = first_row ++ &[_]Guess{.OptUnknown},
            .Cell => |slice| {
                if (std.fmt.parseFloat(f64, slice)) |_| {
                    first_row = first_row ++ &[_]Guess{.Number};
                } else |err| {
                    first_row = first_row ++ &[_]Guess{.String};
                }
            },
            .End => break,
        }
    }
    var row: [first_row.len]Guess = undefined;
    for (first_row) |item, i| row[i] = item;
    var i: usize = 0;
    while (it.next()) |cell| : (i += 1) {
        if (i == row.len) {
            _ = it.next();
            i = 0;
        } else switch (cell) {
            .Nil => row[i] = switch (row[i]) {
                .String => .OptString,
                .Number => .OptNumber,
                else => row[i],
            },
            .Cell => |slice| {
                if (std.fmt.parseFloat(f64, slice)) |_| {
                    switch (row[i]) {
                        .Number => {},
                        .OptUnknown => row[i] = .OptNumber,
                        else => {},
                    }
                } else |err| {
                    switch (row[i]) {
                        .Number => row[i] = .String,
                        .OptNumber => row[i] = .OptString,
                        .OptUnknown => row[i] = .OptString,
                        else => {},
                    }
                }
            },
            .End => @compileError("row too short"),
        }
    }

    comptime var fields: []const TypeInfo.StructField = &[_]TypeInfo.StructField{};
    inline for (row) |cell, n| {
        var buffer: [100]u8 = undefined;
        const number = switch (column_names.len > 0) {
            false => std.fmt.bufPrint(&buffer, "{}", .{n}) catch @compileError("buffer too small"),
            true => for (column_names[n]) |c, j| {
                buffer[j] = c;
            } else buffer[0..j],
        };
        //const name = column_names[0];
        fields = fields ++ &[_]TypeInfo.StructField{.{
            .field_type = switch (cell) {
                .String => []const u8,
                .Number => f64,
                .OptString => ?[]const u8,
                .OptNumber => ?f64,
                else => @compileError("unknown type"),
            },
            .name = number,
            .default_value = null,
        }};
    }
    return @Type(TypeInfo{
        .Struct = .{
            .is_tuple = column_names.len == 0,
            .fields = fields,
            .decls = &[_]TypeInfo.Declaration{},
            .layout = .Auto,
        },
    });
}

test "infer-csv-type" {
    @setEvalBranchQuota(1500);
    const T = inferType(
        \\#name,number,optname,optnumber
        \\string,123445,,
        \\string,123456,optional string,54
    );

    var t: T = T{ .name = "iejfiej", .number = 123, .optname = null, .optnumber = null };
}
