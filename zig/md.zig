const std = @import("std");

const StreamingParser = struct {
    count: usize = 0,
    state: State = .Code,

    const State = enum { Code, Text };

    pub fn feed(p: *StreamingParser, c: u8) !?Token {
        switch (p.state) {
            .Code => switch (c) {
                '\n' => {
                    const count = p.count;
                    p.count = 0;
                    return Token{ .Code = count };
                },
                else => p.count += 1,
            },
            .Text => switch (c) {
                '\n' => {
                    const count = p.count;
                    p.count = 0;
                    return Token{ .Text = count };
                },
                else => p.count += 1,
            },
        }
        return null;
    }
};
