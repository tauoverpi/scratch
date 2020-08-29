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

// TODO: csv parser
// TODO: csv row type inference
//       assumption: CSV files are not trees...
//                   CSV files have the same type for every row...
//                   CSV files have equal length rows

fn infer(comptime text: []const u8) type {
    comptime var row: []const Guess = &[_]Guess{};
    inline while (it.next()) |cell| {
        switch (cell) {
            .Nil => {},
            .Item => {},
            .End => break,
        }
    }
}
