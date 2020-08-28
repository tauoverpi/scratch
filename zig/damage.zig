const std = @import("std");

var box: [layers.len]struct { x: usize, y: usize, w: usize, h: usize } = undefined;
var layers: [16][]u16 = undefined;

//  _ _ _ _ _ _
//  O...O.. _ _
//  .O....o _ _
//  ....||||| _
//  _ _ ||||| _

// + + + + -,
// + + + +  |
// - - - -  |
// - - - - -`

// = = = = -,
// = = = =  |
// + + + +  |
// + + + + -`

// - - - -
// - - - -

const Writer = struct {
    pub fn writeSlice(pix: []const u16) !void {}
    pub fn writeMatrix(mat: []const []const u16) !void {}
};
