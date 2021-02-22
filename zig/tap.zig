const std = @import("std");
const os = std.os;
const mem = std.mem;
const c = @cImport({
    @cInclude("linux/ioctl.h");
    @cInclude("linux/if_tun.h");
});
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const Tap = struct {
    file: File,

    pub fn open() !Tap {
        var ifr: os.ifreq = undefined;
        const fd = try os.open("/dev/net/tun", os.O_RDWR, 0);
        errdefer os.close(fd);

        // TODO: contribute os.IFF_TAP | os.IFF_NO_PI;
        const device = "tap0" ++ [_]u8{0} ** 12;
        ifr.ifru.flags &= c.IFF_TUN;
        ifr.ifru.flags = c.IFF_TAP | c.IFF_NO_PI;
        mem.copy(u8, &ifr.ifrn.name, device);

        // TODO: contribute os.TUNSETIFF
        if (os.linux.ioctl(fd, c.TUNSETIFF, @ptrToInt(&ifr)) > 0) {
            return error.IoctlTunFailed;
        }

        return Tap{ .file = File{ .handle = fd } };
    }

    pub fn close(self: Tap) void {
        self.file.close();
    }
};

fn readEthHeader(reader: anytype) !EthHeader {
    const dmac = try reader.readBytesNoEof(6);
    std.log.info("dmac {x}", .{dmac});
    const smac = try reader.readBytesNoEof(6);
    std.log.info("smac {x}", .{dmac});
    const ethertype = @intToEnum(EthFrame.Type, try reader.readIntBig(u16));
    std.log.info("type {x}", .{dmac});
    var frame: EthHeader = .{
        .dmac = dmac,
        .smac = smac,
        .ethertype = ethertype,
    };

    return frame;
}

pub fn readArpHeader(reader: anytype) !ArpHeader {
    var frame: ArpHeader = undefined;
    frame.hwtype = @intToEnum(ArpFrame.HardwareType, try reader.readIntBig(u16));
    frame.protype = @intToEnum(ArpFrame.ProtocolType, try reader.readIntBig(u16));
    frame.hwsize = try reader.readByte();
    frame.prosize = try reader.readByte();
    frame.opcode = @intToEnum(ArpFrame.OpCode, try reader.readIntBig(u16));
    switch (frame.protype) {
        .ipv4 => {
            frame.data = .{
                .ipv4 = .{
                    .smac = try reader.readBytesNoEof(6),
                    .sip = try reader.readIntBig(u32),
                    .dmac = try reader.readBytesNoEof(6),
                    .dip = try reader.readIntBig(u32),
                },
            };
        },
        else => frame.data = .{ .other = {} },
    }
    return frame;
}

const EthHeader = struct {
    dmac: [6]u8,
    smac: [6]u8,
    ethertype: Type,

    pub const Type = enum(u16) {
        ipv4 = 0x0800,
        arp = 0x0806,
        ipv6 = 0x88dd,
        _,
    };
};

const ArpHeader = struct {
    hwtype: HardwareType,
    protype: ProtocolType,
    hwsize: u8,
    prosize: u8,
    opcode: OpCode,
    data: union(enum) {
        ipv4: struct {
            smac: [6]u8,
            sip: u32,
            dmac: [6]u8,
            dip: u32,
        },
        other,
    },

    pub const ProtocolType = enum(u16) { ipv4 = 0x0800, _ };
    pub const HardwareType = enum(u16) { eth = 0x0001, _ };
    pub const OpCode = enum(u16) {
        arp_request = 1,
        arp_reply = 2,
        rarp_request = 3,
        rarp_reply = 4,
        _,
    };
};

const Ipv4Header = struct {
    version: u4,
    ihl: u4,
    tos: u8,
    len: u16,
    id: u16,
    flags: u3,
    frag_offset: u13,
    ttl: u8,
    proto: Protocol,
    csum: u16,
    saddr: u32,
    daddr: u32,

    pub const Protocol = enum(u8) {
        tcp = 6,
        udp = 16,
        _,
    };
};

const Imcpv4Header = struct {};

pub fn main() !void {
    var tap = try Tap.open();
    defer tap.close();

    try tap.file.writeAll(arp_ask_all);
    const address = &.{ 0x42, 0x6d, 0x6b, 0xe0, 0x56, 0x53 };

    while (true) {
        var br = std.io.bufferedReader(tap.file.reader());
        var bw = std.io.bufferedWriter(tap.file.writer());
        const w = bw.writer();
        std.log.info("reading", .{});
        var eth = try readEthFrame(br.reader());
        std.log.info("{any}", .{eth});
        switch (eth.ethertype) {
            .arp => {
                var arp = try readArpFrame(br.reader());
                std.log.info("{any}", .{arp});
                switch (arp.data) {
                    .ipv4 => |data| {
                        try w.writeAll(&eth.smac);
                        try w.writeAll(address);
                        try w.writeIntBig(u16, @enumToInt(eth.ethertype));
                        try w.writeIntBig(u16, @enumToInt(arp.hwtype));
                        try w.writeIntBig(u16, @enumToInt(arp.protype));
                        try w.writeByte(arp.hwsize);
                        try w.writeByte(arp.prosize);
                        try w.writeIntBig(u16, @enumToInt(arp.opcode));
                        try w.writeAll(address);
                        try w.writeIntBig(u32, data.dip);
                        try w.writeAll(&data.smac);
                        try w.writeIntBig(u32, data.sip);
                        try bw.flush();
                    },
                    .other => {},
                }
            },
            else => std.log.warn("unsupported protocol", .{}),
        }
    }
}
