const std = @import("std");

fn foo() void {
    const strings = &[_][]const u8{
        "del", "alba", "alosa", "bert", "ben", "bener", "bat", "cat", "can't", "conor",
    };

    comptime var buff: [strings.len][]const u8 = undefined;
    inline for (strings) |str, i| {
        buff[i] = str;
    }

    comptime var len: usize = 12;

    comptime {
        std.sort.sort([]const u8, &buff, {}, (struct {
            pub fn f(l: void, a: []const u8, b: []const u8) bool {
                const min = std.math.min(a.len, b.len);
                for (a[0..min]) |_, i| {
                    if (a[i] != b[i]) return a[i] < b[i];
                } else return a.len < b.len;
            }
        }).f);
    }

    std.debug.print("\n", .{});
    render(1024, &buff);
}

const Result = struct { c: u8, leaf: bool = false, next: ?usize = null };
fn render(comptime depth: usize, strings: [][]const u8) void {
    const Context = struct { base: usize, len: usize, pos: usize };
    var stack: [depth]Context = undefined;
    var output: [depth]Result = undefined;
    var length: usize = 0;
    var index: usize = 0;
    stack[0] = .{ .base = 0, .len = strings.len, .pos = 0 };
    var seen: ?u8 = null;
    for (strings) |string, i| {
        // ignore empty strings
        if (string.len == 0) continue;
        if (seen == null or seen.? != string[0]) {
            output[length] = .{ .c = string[0] };
            length += 1;
            seen = string[0];
            std.debug.print("{c}", .{string[0]});
        }
    }

    var limit: usize = 100; // TODO: remove
    seen = null;
    var i: usize = 0;
    var start: usize = 0;
    index = 1;
    while (stack[0].pos != stack[0].len and limit > 0) {
        if (i == strings.len) break;
        if (strings[i].len == index) {
            i += 1;
            continue;
        }
        if (seen) |c| {
            if (strings[i][index] != c) {
                stack[index] = .{ .base = start, .pos = 0, .len = i - start };
                index += 1;
                i = 0;
                std.debug.print("{c}", .{strings[i][index]});
            }
        } else {
            std.debug.print("{c}", .{strings[i][index]});
            seen = strings[i][index];
        }
        i += 1;
        limit -= 1;
    }

    std.debug.print("\n", .{}); // TODO:remove
    for (output[0..length]) |byte| {
        std.debug.print("{c}", .{byte.c});
    }
}

test "" {
    foo();
}
