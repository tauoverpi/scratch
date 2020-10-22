const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    const app = b.option(enum {
        cli,
        rocket,
        @"sdl-rocket",
        gtk,
    }, "app", "application to compile") orelse @panic("no app");

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    switch (app) {
        .cli => {
            const exe = b.addExecutable("cli", "cli.zig");
            exe.setTarget(target);
            exe.setBuildMode(mode);
            exe.strip = true;
            exe.install();

            const run_cmd = exe.run();
            run_cmd.step.dependOn(b.getInstallStep());

            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        },
        .@"sdl-rocket" => {
            const exe = b.addExecutable("sdl-rocket", "sdl-rocket.zig");
            exe.setTarget(target);
            exe.setBuildMode(mode);
            exe.linkSystemLibrary("c");
            exe.linkSystemLibrary("sdl2");
            exe.install();

            const run_cmd = exe.run();
            run_cmd.step.dependOn(b.getInstallStep());

            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        },
        .rocket => {
            const exe = b.addExecutable("rocket", "rocket.zig");
            exe.setTarget(target);
            exe.setBuildMode(mode);
            exe.linkSystemLibrary("c");
            exe.linkSystemLibrary("vulkan");
            exe.linkSystemLibrary("glfw3");
            exe.install();

            const run_cmd = exe.run();
            run_cmd.step.dependOn(b.getInstallStep());

            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        },
        .gtk => {
            const exe = b.addExecutable("gtk", "gtk.zig");
            exe.setTarget(target);
            exe.setBuildMode(mode);
            exe.linkSystemLibrary("c");
            exe.linkSystemLibrary("gtk+-3.0");
            exe.install();

            const run_cmd = exe.run();
            run_cmd.step.dependOn(b.getInstallStep());

            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        },
    }
}
