const std = @import("std");
const testing = std.testing;

const WasmToken = union(enum) {
    @"unreachable",
    nop,
    block_begin,
    loop_begin,
    if_begin,
    i32,
    i64,
    f32,
    f64,
};

const WasmValidator = struct {
    index: usize = 0,
    bitstack: u128 = 0,
    state: State = .top,

    const State = enum {
        top,
        block,
    };

    fn enterBlock(vm: *WasmValidator, t: enum { block, loop, iff }) WasmToken {
        switch (t) {
            .block => {
                vm.index += 1;
                vm.bitstack <<= 2;
                vm.bitstack |= 1;
                vm.state = .block;
                return .block_begin;
            },
            .loop => {
                vm.index += 1;
                vm.bitstack <<= 2;
                vm.bitstack |= 2;
                vm.state = .block;
                return .loop_begin;
            },
            .iff => {
                vm.index += 1;
                vm.bitstack <<= 2;
                vm.bitstack |= 3;
                vm.state = .block;
                return .if_begin;
            },
        }
    }

    const wi32 = 0x7f;
    const wi64 = 0x7e;
    const wf32 = 0x7d;
    const wf64 = 0x7c;

    fn emitType(vm: *WasmValidator, comptime T: type, st: State) WasmToken {
        vm.state = st;
        switch (T) {
            i32 => return .i32,
            i64 => return .i64,
            f32 => return .f32,
            f64 => return .f64,
            else => @compileError("not a valid wasm type"),
        }
    }

    pub fn step(vm: *WasmValidator, c: u8) !WasmToken {
        switch (vm.state) {
            .top => switch (c) {
                0x00 => return .@"unreachable",
                0x01 => return .nop,
                0x02 => return vm.enterBlock(.block),
                0x03 => return vm.enterBlock(.loop),
                0x04 => return vm.enterBlock(.iff),
                0x0b => std.debug.panic("TODO POP", .{}),
                //0x0c => return vm.
                else => std.debug.panic("TODO", .{}),
            },
            .block => switch (c) {
                wi32 => return vm.emitType(i32, .top),
                wi64 => return vm.emitType(i64, .top),
                wf32 => return vm.emitType(f32, .top),
                wf64 => return vm.emitType(f64, .top),
                else => return error.InvalidBlockType,
            },
        }
    }
};

test "" {
    var w = WasmValidator{};
    const script = .{
        .{ 0, .@"unreachable" },
        .{ 1, .nop },
        .{ 2, .block_begin },
        .{ 0x7f, .i32 },
    };
    inline for (script) |item| {
        testing.expect((try w.step(item.@"0")) == @field(WasmToken, @tagName(item.@"1")));
    }
}
