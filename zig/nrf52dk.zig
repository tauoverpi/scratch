const std = @import("std");
usingnamespace @cImport({
    @cInclude("SDL2/SDL.h");
});

pub fn main() !void {
    _ = SDL_Init(SDL_INIT_VIDEO);
    defer SDL_Quit();
    const win = SDL_CreateWindow(
        "nrf52",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        240,
        240,
        SDL_WINDOW_SHOWN,
    ) orelse return error.UnableToOpenWindow;
    defer SDL_DestroyWindow(win);

    var server = std.net.StreamServer.init(.{});
    try server.listen(try std.net.Address.initUnix("/tmp/nrf52"));
    defer server.deinit();

    const emu: Interpreter = .{ .window = win, .server = server };

    var running = true;
    while (running) {
        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                SDL_QUIT => running = false,
                else => {}, // ignore
            }
        }
    }
}

const Interpreter = struct {
    window: *SDL_Window,
    server: std.net.StreamServer,
};

test "main" {
    _ = main;
}
