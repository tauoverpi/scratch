const std = @import("std");
const unicode = std.unicode;

pub const EditBuffer = struct {
    buffer: []u32,
    cursor: usize = 0,
    mirror: usize = 0,

    pub fn capacity(e: EditBuffer) usize {
        return e.buffer.len - (e.cursor + e.mirror);
    }

    pub fn insert(e: *EditBuffer, c: u21) !void {
        if (e.capacity() == 0 or e.cursor == e.buffer.len - e.mirror) return error.BufferFull;
        e.buffer[e.cursor] = (e.buffer[e.cursor] & 0xffe00000) | c;
        e.cursor += 1;
    }

    pub fn get(e: EditBuffer) u21 {
        return @truncate(u21, e.buffer[e.cursor - 1]);
    }

    pub fn paste(e: *EditBuffer, text: []const u8) !void {
        var utf8 = unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (utf8.nextCodepoint()) |c| try e.insert(c);
    }

    pub fn remove(e: *EditBuffer) !void {
        if (e.cursor == 0) return error.StartOfBuffer;
        e.cursor -= 1;
    }

    pub fn cut(e: *EditBuffer, amount: usize) !void {
        if (e.cursor < amount) {
            e.cursor = 0;
            return error.StartOfBuffer;
        }
        e.cursor -= amount;
    }

    pub fn next(e: *EditBuffer) !void {
        if (e.mirror == 0) return error.EndOfBuffer;
        e.buffer[e.cursor] = e.buffer[e.buffer.len - e.mirror];
        e.cursor += 1;
        e.mirror -= 1;
    }

    pub fn prev(e: *EditBuffer) !void {
        if (e.cursor == 0) return error.StartOfBuffer;
        e.buffer[e.buffer.len - (e.mirror + 1)] = e.buffer[e.cursor - 1];
        e.cursor -= 1;
        e.mirror += 1;
    }

    pub fn scroll(e: *EditBuffer, steps: isize) !void {
        var remains = std.math.absCast(steps);
        switch (std.math.order(steps, 0)) {
            .eq => {},
            .gt => while (remains > 0) : (remains -= 1) try e.next(),
            .lt => while (remains > 0) : (remains -= 1) try e.prev(),
        }
    }

    pub fn scrollStart(e: *EditBuffer) void {
        // TODO: fix this bug
        e.scroll(-@intCast(isize, e.cursor)) catch unreachable;
    }

    pub fn scrollEnd(e: *EditBuffer) void {
        // TODO: fix this bug
        e.scroll(@intCast(isize, e.mirror)) catch unreachable;
    }

    pub const Script = union(enum) {
        Insert: u21,
        Paste: []const u8,
        Remove,
        Cut: usize,
        Next,
        Prev,
        Scroll: isize,
        ScrollStart,
        ScrollEnd,
        Get,
    };

    pub fn dispatch(e: *EditBuffer, program: Script) !?u21 {
        switch (program) {
            .Insert => |c| try e.insert(c),
            .Paste => |text| try e.paste(text),
            .Remove => try e.remove(),
            .Cut => |amount| try e.cut(amount),
            .Next => try e.next(),
            .Prev => try e.prev(),
            .Scroll => |steps| try e.scroll(steps),
            .ScrollStart => e.scrollStart(),
            .ScrollEnd => e.scrollEnd(),
            .Get => return e.get(),
        }
        return null;
    }
};

test "" {
    var buffer: [256]u32 = undefined;
    var e = EditBuffer{ .buffer = &buffer };

    for ([_]EditBuffer.Script{
        .{ .Insert = 'A' },
        .{ .Insert = 'A' },
        .{ .Insert = 'A' },
        .Prev,
        .Next,
        .{ .Scroll = -2 },
        .{ .Insert = 'b' },
        .{ .Insert = 'b' },
        .{ .Scroll = 2 },
        .Remove,
        .{ .Paste = "hello" },
        .{ .Scroll = -5 },
        .{ .Cut = 4 },
        .{ .Scroll = 5 },
        .ScrollStart,
        .ScrollEnd,
    }) |p| _ = try e.dispatch(p);

    for (e.buffer[0..e.cursor]) |c| {
        var buff: [4]u8 = undefined;
        std.debug.print("{}", .{buff[0..try unicode.utf8Encode(@truncate(u21, c), &buff)]});
    }
}
