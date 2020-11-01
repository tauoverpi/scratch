const std = @import("std");

const ItemList = struct {
    next: ?*ItemList,
    data: [256]u8,
    slice: []const u8,
};

const Node = struct {
    address: u64,
    count: usize,
    items: *?ItemList,
    left: *?Node,
    right: *?Node,
};

var tree: ?Node = null;
