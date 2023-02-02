const std = @import("std");
const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("string.h");
    @cInclude("linux/kvm.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/mman.h");
});

// zig fmt: off
const code = [_]u8{
    0xba, 0xf8, 0x03, // mov $0x3f8, %dx
    0x00, 0xd8,       // add %bl, %al
    0x04, '0',        // add $'0', %al
    0xee,             // out %al, (%dx)
    0xb0, '\n',       // mov $'\n', %al
    0xee,             // out %al, (%dx)
    0xf4,             // hlt
};
// zig fmt: on

pub fn main() void {
    const kvm = c.open("/dev/kvm", c.O_RDWR | c.O_CLOEXEC);
    var ret: c_int = undefined;

    ret = c.ioctl(kvm, c.KVM_GET_API_VERSION, @as(usize, 0));
    if (ret < 0) @panic("ioctl kvm version");
    if (ret != 12) @panic("not 12");

    ret = c.ioctl(kvm, c.KVM_CHECK_EXTENSION, c.KVM_CAP_USER_MEMORY);
    if (ret < 0) @panic("ioctl kvm extension");
    if (ret == 0) @panic("require cap user mem");

    const vm = c.ioctl(kvm, c.KVM_CREATE_VM, @as(usize, 0));

    const memory = @ptrCast([*]u8, @alignCast(4096, c.mmap(
        null,
        0x1000,
        c.PROT_READ | c.PROT_WRITE,
        c.MAP_SHARED | c.MAP_ANONYMOUS,
        -1,
        0,
    )));

    _ = c.memcpy(memory, &code, code.len);

    var region = std.mem.zeroes(c.kvm_userspace_memory_region);
    region.slot = 0;
    region.guest_phys_addr = 0x1000;
    region.memory_size = 0x1000;
    region.userspace_addr = @ptrToInt(memory);

    ret = c.ioctl(vm, c.KVM_SET_USER_MEMORY_REGION, &region);
    if (ret < 0) @panic("ioctl region");

    const vcpu = c.ioctl(vm, c.KVM_CREATE_VCPU, @as(usize, 0));
    if (vcpu < 0) @panic("vcpu");

    const mmap_size = c.ioctl(kvm, c.KVM_GET_VCPU_MMAP_SIZE, @as(usize, 0));

    const run = @ptrCast(*c.kvm_run, @alignCast(@alignOf(c.kvm_run), c.mmap(
        null,
        @intCast(usize, mmap_size),
        c.PROT_READ | c.PROT_WRITE,
        c.MAP_SHARED,
        vcpu,
        0,
    )));

    var sregs = std.mem.zeroes(c.kvm_sregs);

    _ = c.ioctl(vcpu, c.KVM_GET_SREGS, &sregs);
    sregs.cs.base = 0;
    sregs.cs.selector = 0;
    _ = c.ioctl(vcpu, c.KVM_SET_SREGS, &sregs);

    var regs = std.mem.zeroes(c.kvm_regs);
    regs.rip = 0x1000;
    regs.rax = 2;
    regs.rbx = 2;
    regs.rflags = 0x2;
    _ = c.ioctl(vcpu, c.KVM_SET_REGS, &regs);

    var fuel: u32 = 100;
    while (fuel != 0) : (fuel -= 1) {
        _ = c.ioctl(vcpu, c.KVM_RUN, @as(usize, 0));
        switch (run.exit_reason) {
            c.KVM_EXIT_HLT => {
                _ = c.puts("halted");
                break;
            },

            c.KVM_EXIT_IO => _ = c.puts("io"),
            c.KVM_EXIT_SHUTDOWN => @panic("shutdown"),
            c.KVM_EXIT_IO_IN => @panic("in"),
            c.KVM_EXIT_IO_OUT => @panic("in"),
            c.KVM_EXIT_FAIL_ENTRY => @panic("hardware"),
            c.KVM_EXIT_INTERNAL_ERROR => @panic("internal"),

            else => |err| {
                _ = c.printf("unknown: 0x%x\n", err);
                @panic("unknown");
            },
        }
    }
}
