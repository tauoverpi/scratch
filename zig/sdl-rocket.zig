const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const io_mode = .evented;

pub fn main() !void {
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    defer c.SDL_Quit();

    await async mainLoop(0);
}

fn mainLoop(i: usize) void {
    if (i > 10) return;
    std.debug.print("{} ", .{i});
    mainLoop(i + 1);
}
