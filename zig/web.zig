const std = @import("std");

const Writer = struct {
    pub const Node = union(enum) {
        Div: Div,
    };

    pub const Element = struct {
        pub fn parentNode(self: anytype) ?Node {}
    };

    pub const Div = struct {
        pub usingnamespace Element;
    };

    pub fn write(element: Node) void {}
};
