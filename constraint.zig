const std = @import("std");
const fnv = std.hash.Fnv1a_32;

const Token = union(enum) {
    Name: struct { name: u32, count: usize, spaces: usize },
    Type: struct { name: u32, count: usize, spaces: usize },
};

// cat typename;
// item name: category = ingredient, ingredient, ... ;
// solve category /\ category /\ category;

const StreamingParser = struct {
    count: usize,
    state: State,
    hash: fnv,
    spaces: usize,

    const State = enum {
        Start,
        Item,
        TypeBegin,
        Type,
        Bind,
    };

    pub fn init() StreamingParser {
        var p: StreamingParser = undefined;
        p.reset();
        return p;
    }

    pub fn reset(self: *StreamingParser) void {
        self.count = 0;
        self.state = .Start;
        self.hash = fnv.init();
        self.spaces = 0;
    }

    pub fn feed(self: *StreamingParser, c: u8) !?Token {
        self.count += 1;
        switch (self.state) {
            .Start => switch (c) {
                ' ' => switch (self.hash.final()) {
                    fnv.hash("item") => {
                        self.state = .Item;
                        self.count = 0;
                        self.spaces = 0;
                    },
                    fnv.hash("rule") => return error.NotImplemented,
                    fnv.hash("solve") => return error.NotImplemented,
                    fnv.hash("type") => return error.NotImplemented,
                    else => return error.UnknownIdentifier,
                },
                else => self.hash.update((&[_]u8{c})),
            },
            .Item => switch (c) {
                ' ' => self.spaces += 1,
                ':' => {
                    const token = Token{
                        .Name = .{
                            .name = self.hash.final(),
                            .count = self.count,
                            .spaces = self.spaces,
                        },
                    };
                    self.hash = fnv.init();
                    self.state = .TypeBegin;
                    return token;
                },
                else => {},
            },
            .TypeBegin => switch (c) {
                ' ' => {},
                else => {
                    self.state = .Type;
                    self.spaces = 0;
                    self.count = 0;
                },
            },
            .Type => switch (c) {
                '=' => {
                    const token = Token{
                        .Type = .{
                            .name = self.hash.final(),
                            .count = self.count,
                            .spaces = self.spaces,
                        },
                    };
                    self.state = .Bind;
                    self.spaces = 0;
                    self.count = 0;
                    return token;
                },
                ' ' => {},
                else => self.hash.update(&[_]u8{c}),
            },
            .Bind => switch (c) {
                ' ' => {},
                else => return error.Invalid,
            },
            //.Bind => return error.NotImplemented,
        }
        return null;
    }
};

test "" {
    var p = StreamingParser.init();
    for (
        \\item example: @ = example, category;
        \\rule @.example != kitten;
        \\solve @;
    ) |byte| {
        if (try p.feed(byte)) |item| {
            std.debug.print("{}\n", .{item});
        }
    }
}
