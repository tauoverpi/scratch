const std = @import("std");

//! This is by no means an efficient implementation and quite a bit of redundant
//! error checking is performed within the interpreter.

const Opcode = union(enum(u16)) {
    // special
    nop,
    next,
    docol,
    lit: u32,
    flit: f64,

    // stack
    dup,
    swap,
    drop,
    over,
    rot,
    @"-rot",
    dstore,

    // control-flow
    rpush,
    rpop,
    rstore,
    ipstore,
    jmp,
    jnz,

    // bit manipulation
    band,
    bor,
    bxor,
    clz,
    ctz,
    shl,
    ashr,
    shr,

    // atomics
    armw,
    astore,
    aload,
    cmpxchg_s,
    cmpxchg_w,
    fence,

    // arithmetic
    imul,
    idiv,
    mul,
    add,
    sub,
    divmod,
    rem,

    // vm memory
    @"align",
    fetch,
    cfetch,
    wfetch,
    store,
    cstore,
    wstore,
    comma,
    ccomma,
    wcomma,

    // hardware memory
    mmap,
    munmap,

    // i/o
    key,
    emit,
    @"type",

    // floating-point
    fsqrt,
    fsin,
    fcos,
    fexp,
    flog,
    flog10,
    fabs,
    ffloor,
    fceil,
    fround,

    // word
    create,
    does,
    tailcall,

    // meta
    see,
    @"[",
    @"]",
    imm,

    // special
    halt,
    // all values after this map to user defined opcodes
};

pub fn Forth(comptime image: []const u8, comptime kb: usize) type {
    var buffer: [image.len]u8 = undefined;
    std.mem.copy(u8, &buffer, image);
    return struct {
        ip: usize = 0,
        dp: usize = 0,
        rp: usize = 0,
        fp: usize = 0,
        dstk: [8]u32 = undefined,
        rstk: [16]u32 = undefined,
        fstk: [8]f64 = undefined,
        memory: [1024 * kb]u8 = buffer ++ [_]u8{0} ** (1024 * kb - image.len),

        const Self = @This();

        fn dpop(vm: *Self) !u32 {
            if (vm.dp == 0) return error.DataStackUnderflow;
            vm.dp -= 1;
            return vm.dstk[vm.dp];
        }

        fn rpop(vm: *Self) !u32 {
            if (vm.rp == 0) return error.ReturnStackUnderflow;
            vm.rp -= 1;
            return vm.rstk[vm.rp];
        }

        fn fpop(vm: *Self) !f32 {
            if (vm.fp == 0) return error.FloatingPointStackUnderflow;
            vm.fp -= 1;
            return vm.fstk[vm.fp];
        }

        fn dpush(vm: *Self, d: u32) !void {
            if (vm.dp == vm.dstk.len) return error.DataStackOverflow;
            vm.dstk[vm.dp] = d;
            std.debug.print("push {}\n", .{vm.dstk[vm.dp]});
            vm.dp += 1;
        }

        fn rpush(vm: *Self, r: u32) !void {
            if (vm.fp == vm.rstk.len) return error.ReturnStackOverflow;
            vm.rstk[vm.rp] = r;
            vm.rp += 1;
        }

        fn fpush(vm: *Self, f: f32) !void {
            if (vm.fp == vm.fstk.len) return error.FloatingPointStackOverflow;
            vm.fstk[vm.fp] = f;
            vm.fp += 1;
        }

        fn drequire(vm: *Self, size: usize) !void {
            if (vm.dp < size) return error.DataStackUnderflow;
        }

        fn rrequire(vm: *Self, size: usize) !void {
            if (vm.rp < size) return error.ReturnStackUnderflow;
        }

        fn frequire(vm: *Self, size: usize) !void {
            if (vm.fp < size) return error.FloatingPointStackUnderflow;
        }

        pub fn next(vm: *Self) !void {
            const inst = std.mem.readIntSliceBig(u16, vm.memory[vm.ip..]);
            const ip = vm.ip;
            vm.ip += 2;
            if (inst > @enumToInt(Opcode.halt)) {
                std.debug.print("inst {}\n", .{inst});
                // user defined words
            } else {
                const op = @intToEnum(@TagType(Opcode), inst);
                std.debug.print("inst {}\n", .{op});

                switch (op) {
                    // special
                    .nop => {},
                    .lit => {
                        try vm.dpush(std.mem.readIntSliceBig(u32, vm.memory[vm.ip..]));
                        vm.ip += 4;
                    },

                    // stack
                    .dup => {
                        const a = try vm.dpop();
                        try vm.dpush(a);
                    },

                    .swap => {
                        const a = try vm.dpop();
                        const b = try vm.dpop();
                        try vm.dpush(a);
                        try vm.dpush(b);
                    },
                    .drop => _ = try vm.dpop(),
                    .over => {
                        const a = try vm.dpop();
                        const b = try vm.dpop();
                        try vm.dpush(b);
                        try vm.dpush(a);
                        try vm.dpush(b);
                    },
                    .rot => {},

                    // arithmetic
                    .add => try vm.dpush((try vm.dpop()) +% (try vm.dpop())),
                    .sub => try vm.dpush((try vm.dpop()) +% (try vm.dpop())),
                    .mul => try vm.dpush((try vm.dpop()) *% (try vm.dpop())),
                    .imul => try vm.dpush(@bitCast(u32, @bitCast(i32, try vm.dpop()) *% @bitCast(i32, try vm.dpop()))),

                    // special
                    .halt => return error.Halt,
                    else => return error.Todo,
                }
            }
        }
    };
}

test "" {
    var vm = Forth(&[_]u8{ 0, 0 }, 8){};
    try vm.next();
}

test "add" {
    var vm = Forth(&[_]u8{
        0,
        @enumToInt(Opcode.lit),
        0,
        0,
        0,
        2,
        0,
        @enumToInt(Opcode.lit),
        0,
        0,
        0,
        2,
        0,
        @enumToInt(Opcode.add),
    }, 8){};

    try vm.next();
    try vm.next();
    try vm.next();
    std.testing.expectEqual(@as(u32, 4), vm.dstk[0]);
}
