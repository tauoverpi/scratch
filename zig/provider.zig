const std = @import("std");

// The Plan
//       ,-------------------------------------> ?unknown
//       |                                         |
//       |,---> usize -,-------> ?usize <----------|
//       ||      |     v         |    v            |
// unknown ---------> f64 --------> ?f64 <---------|
//       ||      v    v          v    v            |
//       |`---> []const u8 --> ?[]const u8 <-------|
//       |        ^                 ^              |
//       `----> bool -----------> ?bool <----------`
//
// struct{ section: T } ---> struct { section: ?T } -------> nest
//                       `-> struct { section: []T } --`

const Token = union(enum) {};

const TokenParser = struct {
    index: usize = 0,
    text: []const u8,

    pub fn next(p: *TokenParser) !?Token {}
};
