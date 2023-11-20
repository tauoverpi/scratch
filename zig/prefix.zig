head: [16]Node = .{.{}} ** 16,
nodes: Array([16]Node) = .{},
len: u16,

const Node = packed struct(u16) {
    index: u8 = 0,
    zero: u6 = 0,
    type: Type = .empty,

    pub const Type = enum(u2) { empty, leaf, branch, branch_with_leaf };
};

const Iterator = struct {
    bytes: []const u8,
    index: u16 = 0,

    pub fn next(it: *Iterator) ?u4 {
        if (it.index >> 1 >= it.bytes.len) return null;
        defer it.index += 1;
        const byte = it.bytes[it.index >> 1];
        return @truncate(byte >> @intCast((it.index & 1) * 4));
    }

    pub fn zero(it: *Iterator) u6 {
        return @intCast(for (0..63) |n| {
            if ((it.next() orelse break n) != 0) {
                it.index -= 1;
                break n;
            }
        } else 63);
    }

    pub inline fn len(it: Iterator) usize {
        return it.bytes.len * 2 - it.index;
    }
};

pub fn append(trie: *Trie, gpa: Allocator, bytes: []const u8) error{OutOfMemory}!bool {
    assert(bytes.len == trie.len);
    var curr: *[16]Node = &trie.head;
    var it: Iterator = .{ .bytes = bytes };

    while (it.next()) |nibble| {
        const node = &curr[nibble];
        const zero = it.zero();

        switch (node.type) {
            .empty => {
                node.zero = zero;
                if (it.len() == 0) {
                    node.type = .leaf;
                    return false;
                } else {
                    const index: u8 = @intCast(trie.nodes.items.len);
                    node.type = .branch;
                    node.index = index;
                    try trie.nodes.append(gpa, .{.{}} ** 16);
                    curr = &trie.nodes.items[index];
                }
            },

            .leaf => if (zero == node.zero) {
                if (it.len() == 0) return true;
                node.type = .branch_with_leaf;
                try trie.nodes.append(gpa, .{.{}} ** 16);
            } else {
                node.type = .branch_with_leaf;
                try trie.nodes.append(gpa, .{.{}} ** 16);
            },

            .branch => if (zero == node.zero) {
                curr = &trie.nodes.items[node.index];
            } else if (zero < node.zero) {
                const new: u8 = @intCast(trie.nodes.items.len);
                try trie.nodes.append(gpa, .{.{}} ** 16);
                curr = &trie.nodes.items[new];
                curr[it.next().?] = .{
                    .type = .branch,
                    .index = node.index,
                    .zero = 0,
                };
                node.index = new;
            } else {
                it.index -= zero - node.zero;
                curr = &trie.nodes.items[node.index];
            },

            .branch_with_leaf => if (zero == node.zero) {
                curr = &trie.nodes.items[node.index];
            } else if (it.len() == 0) {
                return true; // already inserted
            } else if (zero < node.zero) {
                const new: u8 = @intCast(trie.nodes.items.len);
                try trie.nodes.append(gpa, [_]Node{.{}} ** 16);
                curr = &trie.nodes.items[new];
                curr[it.next().?] = .{
                    .type = .branch,
                    .index = node.index,
                    .zero = 0,
                };
                node.index = new;
            } else {
                it.index -= zero - node.zero;
                curr = &trie.nodes.items[node.index];
            },
        }
    }
    return false;
}

test append {
    var trie: Trie = .{ .len = 8 };
    defer trie.nodes.deinit(testing.allocator);

    const table = [_]struct { usize, []const u8 }{
        .{ 0, "\x00" ** 8 },
        .{ 15, "cafebabe" },
        .{ 22, "cafedead" },
        .{ 35, "configur" },
        .{ 49, "archetyp" },
        .{ 56, "archlinu" },
        .{ 63, "architec" },
        .{ 78, "iusearch" },
        .{ 79, "cafebabf" },
        .{ 88, "cafababe" },
    };

    for (&table) |item| {
        const size, const string = item;

        try testing.expect(!try trie.append(testing.allocator, string));
        try testing.expectEqual(size, trie.nodes.items.len);
        try testing.expect(trie.contains(string));
    }

    for (&table) |item| {
        _, const string = item;
        try testing.expect(trie.contains(string));
    }
}

pub fn contains(trie: *Trie, bytes: []const u8) bool {
    assert(bytes.len == trie.len);
    var curr: *const [16]Node = &trie.head;
    var it: Iterator = .{ .bytes = bytes };

    while (it.next()) |nibble| {
        const node = &curr[nibble];
        const zero = it.zero();

        switch (node.type) {
            // false as the path is a dead end (can only happen in trie.head).
            .empty => return false,

            // false if trailing zero nibbles are not the same length (zero < node.zero).
            .leaf => return zero == node.zero,

            // false if paths diverge.
            .branch => if (zero == node.zero) {
                curr = &trie.nodes.items[node.index];
            } else return false,

            // special case, true if the remaining nibbles are all zero.
            .branch_with_leaf => if (zero == node.zero) {
                curr = &trie.nodes.items[node.index];
            } else return it.len() == 0,
        }
    } else unreachable; // end of the string can never be reached.
}

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Array = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const Trie = @This();
