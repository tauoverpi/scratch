const std = @import("std");
const atomic = std.atomic;

const Ring = struct {
    jobs: [256]u8,
    bottom: u8,
    top: u8,

    pub fn push(self: *Ring, job: u8) void {
        self.jobs[self.bottom] = job;

        // Update must happen before incrementing bottom otherwise another
        // thread could end up reading garbage.

        atomic.compilerFence(.SeqCst);

        self.bottom += 1;
    }

    pub fn steal(self: *Ring) ?u8 {
        const top = self.top;

        atomic.compilerFence(.SeqCst);

        const bottom = self.bottom;

        if (top < bottom) {
            const job = self.jobs[top];

            if (@cmpxchgWeak(u8, &self.top, top + 1, top, .Monotonic, .Monotonic) != top) {
                return null; // failed transaction
            }

            return job;
        } else {
            return null;
        }
    }

    pub fn pop(self: *Ring) ?u8 {
        const bottom = self.bottom - 1; // pretend this is ok

        // Since `pop` won't run concurrently it only needs a memory barrier here
        // to ensure `bottom` is read before `top` in-case there's a concurrent
        // update to `top`.

        _ = @atomicRmw(u8, &self.bottom, .Xchg, bottom, .SeqCst);

        const top = self.top;

        if (top <= bottom) {
            const job = self.jobs[bottom];

            // more than one item left so it's fine to return
            if (top != bottom) return job;

            // If we won the race or we lost, need to increment regardless as this item
            // was taken.
            defer self.bottom += 1;

            if (@cmpxchgWeak(u8, &top, top + 1, top, .Monotonic, .Monotonic) != top) {
                return null; // failed transaction
            }

            return job;
        } else {
            return null;
        }
    }
};
