const std = @import("std");
const mem = std.mem;
const os = std.os;
const c = @cImport({
    @cInclude("linux/hidraw.h");
    @cInclude("libudev.h");
    @cInclude("sys/ioctl.h");
});

pub fn main() anyerror!void {
    const context = c.udev_new() orelse return error.@"Failed to create udev context";
    defer _ = c.udev_unref(context);

    const devices = c.udev_enumerate_new(context) orelse return error.@"Failed to create enumerator";
    defer _ = c.udev_enumerate_unref(devices);

    if (c.udev_enumerate_add_match_subsystem(devices, "hidraw") < 0) {
        return error.@"No hidraw devices available";
    }

    if (c.udev_enumerate_scan_devices(devices) < 0) {
        return error.@"Scan failed";
    }

    var entry = c.udev_enumerate_get_list_entry(devices);

    while (entry) |node| : (entry = c.udev_list_entry_get_next(node)) {
        const name = mem.sliceTo(c.udev_list_entry_get_name(node), 0);
        std.log.debug("{s}", .{name});
        if (mem.indexOf(u8, name, "i2c-UNIW0001:00") != null) {
            std.log.debug("found", .{});

            const dev = c.udev_device_new_from_syspath(context, c.udev_list_entry_get_name(node)) orelse
                return error.@"wat";

            const nomen = c.udev_device_get_devnode(dev);

            const fd = try os.open(mem.sliceTo(nomen, 0), os.O_WRONLY, 0);
            defer os.close(fd);

            var buffer = [_]u8{ 0x07, 0x00 }; // lock the touchpad... doesn't work with 0x03 so can't enable again ; -;

            if (c.ioctl(fd, HIDIOCSFEATURE(2), &buffer) < 0) {
                std.log.err("failed to set LED settings to off", .{});
            }

            break;
        }
    }
}

pub inline fn _IOC(dir: c_uint, type_1: c_uint, nr: c_uint, size: c_uint) c_ulong {
    return (((dir << @bitCast(c_uint, c._IOC_DIRSHIFT)) |
        (type_1 << @bitCast(c_uint, c._IOC_TYPESHIFT))) |
        (nr << @bitCast(c_uint, c._IOC_NRSHIFT))) |
        (size << @bitCast(c_uint, c._IOC_SIZESHIFT));
}

pub inline fn HIDIOCSFEATURE(len: c_uint) c_ulong {
    return _IOC(@bitCast(c_uint, c._IOC_WRITE) | @bitCast(c_uint, c._IOC_READ), 'H', @as(c_uint, 0x06), len);
}
