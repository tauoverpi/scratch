const std = @import("std");

// simple movements otherwise search
// syntax highlighting to a minimum

const E = struct {
    text: []u32,
    // position
    line: usize = 0,
    column: usize = 0,
    // stacks
    index: usize = 0,
    offset: usize = 0,
    // byte count to position
    byte: usize = 0,

    pub fn next(e: *E) !void {
        if (e.offset == 0) return error.EndOfFile;
    }

    pub fn prev(e: *E) !void {
        if (e.index == 0) return error.StartOfFile;
    }

    pub fn insert(e: *E, codepoint: u21) !void {
        if (e.index == e.text.len) return error.BufferFull;
    }

    pub fn delete(e: *E) !u21 {
        if (e.index == 0) return error.BufferEmpty;
    }

    pub fn search(e: *E, needle: []const u32) !Location {}

    pub fn iterator(e: E) Iterator {}

    const Iterator = struct {
        text: []const u32,
        line: usize,
        column: usize,
        byte: usize,
    };
};
