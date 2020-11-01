const std = @import("std");

const Timer = struct {
    count: usize = 0,

    pub fn delay(t: Timer, x: usize) void {
        t.count = x;
        suspend;
    }

    pub fn check(t: Timer) bool {
        return t.count == 0;
    }

    pub fn tick(t: Timer) void {
        if (t.count != 0) t.count -= 1;
    }
};

const ms = 1;

var timer0 = Timer{};
var timer1 = Timer{};
var timer2 = Timer{};
var timer3 = Timer{};
var timer4 = Timer{};

const Display = struct {
    pub fn init() void {
        timer0.delay(50 * ms);
    }

    pub fn reset() void {
        timer0.delay(15 * ms);
        timer0.delay(5 * ms);
    }

    pub fn write(byte: u8) void {
        timer0.delay(1 * ms);
    }
};

test "" {
    while (true) {
        timer0.tick();
    }
}
