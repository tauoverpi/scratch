const std = @import("std");
const log = std.log.scoped(.rocket);
const math = std.math;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

pub fn main() !void {
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    _ = c.IMG_Init(c.IMG_INIT_PNG);
    defer c.SDL_Quit();
    const window = c.SDL_CreateWindow(
        "title",
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        600,
        600,
        c.SDL_WINDOW_SHOWN,
    ) orelse return error.Window;

    const renderer = c.SDL_CreateRenderer(
        window,
        -1,
        c.SDL_RENDERER_ACCELERATED,
    ) orelse return error.Rendered;

    const texture = c.IMG_LoadTexture(
        renderer,
        "rocket.png",
    ) orelse return error.Rocket;

    const projectile = c.IMG_LoadTexture(
        renderer,
        "bullet.png",
    ) orelse return error.Bullet;

    const fiend = c.IMG_LoadTexture(
        renderer,
        "enemy.png",
    ) orelse return error.Enemy;

    const Rocket = struct {
        x: f64 = 300,
        y: f64 = 500,
        left: bool = false,
        right: bool = false,
        down: bool = false,
        up: bool = false,
        hp: i32 = 100,

        var w: i32 = undefined;
        var h: i32 = undefined;
    };

    const Enemy = struct {
        x: f64,
        y: f64,
        dy: f64 = 0.05,
        dx: f64 = 0,
        hp: i32 = 100,

        var w: i32 = undefined;
        var h: i32 = undefined;
    };

    const Bullet = struct {
        x: f64,
        y: f64,
        dy: f64,
        dx: f64 = 0,

        var w: i32 = undefined;
        var h: i32 = undefined;
    };

    _ = c.SDL_QueryTexture(texture, null, null, &Rocket.w, &Rocket.h);
    _ = c.SDL_QueryTexture(projectile, null, null, &Bullet.w, &Bullet.h);
    _ = c.SDL_QueryTexture(fiend, null, null, &Enemy.w, &Enemy.h);

    var rocket: Rocket = .{};
    var bullets = [_]?Bullet{null} ** 256;
    var boltz = [_]?Bullet{null} ** 256;
    var enemies = [_]?Enemy{null} ** 16;

    var kills: u64 = 0;

    var last_spawn = std.time.timestamp();
    var rand = std.rand.Xoroshiro128.init(@intCast(u64, last_spawn));
    const rng = &rand.random;
    exit: while (true) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_MOUSEMOTION => {},
                c.SDL_MOUSEBUTTONDOWN => {},
                c.SDL_MOUSEBUTTONUP => {},
                c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    c.SDLK_LEFT => rocket.left = true,
                    c.SDLK_RIGHT => rocket.right = true,
                    c.SDLK_DOWN => rocket.down = true,
                    c.SDLK_UP => rocket.up = true,
                    c.SDLK_ESCAPE => break :exit,
                    // animate
                    c.SDLK_SPACE => {},
                    else => {},
                },
                c.SDL_KEYUP => switch (event.key.keysym.sym) {
                    c.SDLK_LEFT => rocket.left = false,
                    c.SDLK_RIGHT => rocket.right = false,
                    c.SDLK_DOWN => rocket.down = false,
                    c.SDLK_UP => rocket.up = false,
                    c.SDLK_SPACE => for (bullets) |slot, i| if (slot == null) {
                        bullets[i] = .{
                            .x = rocket.x +
                                @intToFloat(f64, @divFloor(Rocket.w, 2)) -
                                @intToFloat(f64, @divFloor(Bullet.w, 2)),
                            .y = rocket.y,
                            .dy = 0.5,
                        };
                        break;
                    },
                    else => {},
                },
                c.SDL_QUIT => break :exit,
                else => {},
            }
        }

        if (rocket.right) rocket.x = math.clamp(rocket.x + 0.2, 25, 575);
        if (rocket.left) rocket.x = math.clamp(rocket.x - 0.2, 25, 575);
        if (rocket.down) rocket.y = math.clamp(rocket.y + 0.2, 25, 500);
        if (rocket.up) rocket.y = math.clamp(rocket.y - 0.2, 25, 500);

        {
            const now = std.time.timestamp();
            if (last_spawn + 1 < now) {
                last_spawn = now;
                for (enemies) |slot, i| if (slot == null) {
                    const dx = @intToFloat(f64, rng.int(u3)) / 100;
                    enemies[i] = .{
                        .x = @rem(rocket.x + @intToFloat(f64, rng.int(u16)), 550) + 25,
                        .y = 20,
                        .dx = dx,
                        .dy = @intToFloat(f64, rng.int(u3) | 1) / 100,
                    };
                    if (rng.boolean()) enemies[i].?.dx = -dx;
                    break;
                } else {
                    if (rng.boolean()) enemies[i].?.dy = @intToFloat(f64, rng.int(u3) | 1) / 100;
                    if (rng.boolean()) enemies[i].?.dx = -enemies[i].?.dx;
                    if (rng.int(u5) > 1) for (boltz) |bslot, k| if (bslot == null) {
                        boltz[k] = .{
                            .x = slot.?.x,
                            .y = slot.?.y,
                            .dy = 0.2,
                            .dx = @intToFloat(f64, rng.int(i2)) / 10,
                        };
                        break;
                    };
                };
            }
        }

        _ = c.SDL_SetRenderDrawColor(renderer, 30, 40, 70, 255);
        _ = c.SDL_RenderClear(renderer);

        var dest: c.SDL_Rect = undefined;

        for (enemies) |slot, i| {
            if (slot) |enemy| {
                if ((enemy.x > rocket.x - @intToFloat(f64, Enemy.w) and
                    enemy.y > rocket.y - @intToFloat(f64, Enemy.h) and
                    enemy.x < rocket.x + @intToFloat(f64, Enemy.w) and
                    enemy.y < rocket.y + @intToFloat(f64, Enemy.h)) or
                    enemy.y > 600)
                {
                    enemies[i] = null;
                    rocket.hp -= 10;
                } else if (enemy.hp < 1 or enemy.y > 600) {
                    enemies[i] = null;
                } else {
                    if (enemy.x > 600) enemies[i].?.x = 0;
                    if (enemy.x < 0) enemies[i].?.x = 600;
                    enemies[i].?.y += enemy.dy;
                    enemies[i].?.x += enemy.dx;
                    dest.x = @floatToInt(c_int, enemy.x);
                    dest.y = @floatToInt(c_int, enemy.y);
                    dest.h = Enemy.h;
                    dest.w = Enemy.w;
                    _ = c.SDL_RenderCopy(renderer, fiend, null, &dest);
                }
            }
        }

        for (bullets) |slot, i| {
            if (slot) |bullet| {
                for (enemies) |eslot, j| {
                    if (eslot) |enemy| {
                        if (bullet.y < enemy.y + @intToFloat(f64, Enemy.h) and
                            bullet.y > enemy.y and
                            bullet.x > enemy.x and
                            bullet.x < enemy.x + @intToFloat(f64, Enemy.w))
                        {
                            bullets[i] = null;
                            enemies[j].?.hp -= 110;
                            if (enemy.hp <= 0) enemies[i] = null;
                            kills += 1;
                            break;
                        }
                    }
                } else if (bullet.y < 0) {
                    bullets[i] = null;
                } else {
                    bullets[i].?.y -= bullet.dy;
                    dest.x = @floatToInt(c_int, bullet.x);
                    dest.y = @floatToInt(c_int, bullet.y);
                    dest.h = Bullet.h;
                    dest.w = Bullet.w;
                    _ = c.SDL_RenderCopy(renderer, projectile, null, &dest);
                }
            }
        }

        for (boltz) |slot, i| {
            if (slot) |bullet| {
                if (bullet.y < rocket.y + @intToFloat(f64, Rocket.h) and
                    bullet.y > rocket.y and
                    bullet.x > rocket.x and
                    bullet.x < rocket.x + @intToFloat(f64, Rocket.h))
                {
                    boltz[i] = null;
                    rocket.hp -= 5;
                } else if (bullet.y > 600) {
                    boltz[i] = null;
                } else {
                    boltz[i].?.y += bullet.dy;
                    boltz[i].?.x += bullet.dx;
                    dest.x = @floatToInt(c_int, bullet.x);
                    dest.y = @floatToInt(c_int, bullet.y);
                    dest.h = Bullet.h;
                    dest.w = Bullet.w;
                    _ = c.SDL_RenderCopy(renderer, projectile, null, &dest);
                }
            }
        }

        dest.x = @floatToInt(c_int, rocket.x);
        dest.y = @floatToInt(c_int, rocket.y);
        dest.h = Rocket.h;
        dest.w = Rocket.w;
        _ = c.SDL_RenderCopy(renderer, texture, null, &dest);

        _ = c.SDL_RenderPresent(renderer);

        if (rocket.hp <= 0) break :exit;

        std.debug.print(
            "\rkills {: <5} hp {: <5} x {: <3} y {: <3}",
            .{ kills, rocket.hp, @floatToInt(u64, rocket.x), @floatToInt(u64, rocket.y) },
        );
    }
    std.debug.print(
        \\
        \\You lost!
        \\score: {}
        \\
    , .{kills});
}
