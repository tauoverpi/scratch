const std = @import("std");

const Token = struct {
    access_token: []const u8,
    device_id: []const u8,
    home_server: []const u8,
    user_id: []const u8,
    well_known: struct {
        @"m.homeserver": struct {
            base_url: []const u8,
        },
    },
};

test "" {
    const token = @embedFile("/tmp/mat");
    std.debug.print("{}", .{std.json.parse(Token, &std.json.TokenStream.init(token), .{ .allocator = std.heap.page_allocator })});
}
