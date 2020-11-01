pub fn Process(comptime process: fn (*usize) callconv(.Async) void) type {
    return struct {
        var frame: @Frame(process) = undefined;
        var state: usize = undefined;

        pub fn init() void {
            frame = async process(&state);
        }

        pub fn run() void {
            resume frame;
        }
    };
}

const display = Process((struct {
    pub fn run(state: *usize) callconv(.Async) void {
        state.* = 0;
        while (true) {
            state.* += 1;
            suspend;
        }
    }
}).run);

test "" {
    display.init();
    display.run();
    display.run();
    display.run();
}
