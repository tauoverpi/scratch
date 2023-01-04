const std = @import("std");
const mem = std.mem;
const is_test = @import("builtin").is_test;

const App = @This();

const Pixel = packed struct(u32) {
    red: u8,
    blue: u8,
    green: u8,
    alpha: u8,
};

framebuffer: [480][720]Pixel = undefined,
time: f64 = undefined,

fn step(self: *App, time: f64) error{}!void {
    const dt = time - self.time;
    _ = dt;

    for (self.framebuffer) |*line| {
        for (line) |*cell| {
            cell.red +%= 1;
            cell.green +%= cell.red >> 7;
            cell.blue +%= cell.green >> 7;
        }
    }
}

// boilerplate

var app: if (is_test) struct {} else @This() = .{};

const js = struct {
    extern fn blit() void;
};

comptime {
    if (!is_test) {
        @export(wasmInit, .{ .name = "init" });
        @export(wasmStep, .{ .name = "step" });
        @export(wasmGetFramebuffer, .{ .name = "getFramebuffer" });
    }
}

fn wasmInit(time: f64) callconv(.C) void {
    app.time = time;
    mem.set(u8, mem.asBytes(&app.framebuffer), 0xff);
}

fn wasmStep(time: f64) callconv(.C) i32 {
    app.step(time) catch return 1;
    app.time = time;

    js.blit();

    return 0;
}

fn wasmGetFramebuffer() callconv(.C) *[480][720]Pixel {
    return &app.framebuffer;
}
