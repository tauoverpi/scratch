const StreamingParser = struct {
    count: usize = 0,
    state: State,

    const State = enum {};

    pub fn feed(p: *StreamingParser, c: u8) !?Token {
        switch (p.state) {}
    }
};
