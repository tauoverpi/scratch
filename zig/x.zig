const std = @import("std");

const XAuth = struct {
    family: Family,
    address: []const u8,
    display: []const u8,
    name: []const u8,
    data: []const u8,

    pub const Family = u16;
};

const XConnectHeader = struct {
    order: Order,
    major: u16 = 11,
    minor: u16 = 0,
    name: []const u8,
    data: []const u8,

    pub const Order = enum(u8) { little = 'l', big = 'B' };

    pub fn serialize(self: @This(), serializer: anytype) !void {
        try serializer.serialize(@enumToInt(self.order));
        try serializer.serialize(@as(u8, 0));
        try serializer.serialize(self.major);
        try serializer.serialize(self.minor);
        try serializer.serialize(@intCast(u16, self.name.len));
        try serializer.serialize(@intCast(u16, self.data.len));
        try serializer.serialize(@as(u16, 0));
        try serializer.serialize(self.name);
        try serializer.serialize(@as(u16, 0));
        try serializer.serialize(self.data);
        try serializer.serialize(@as(u16, 0));
    }
};

const XConnectReply = struct {
    success: u8,
    pad: u8,
    major: u16,
    minor: u16,
    length: u16,
};

const XConnectSetup = struct {
    release: u32,
    id_base: u32,
    id_mask: u32,
    motion_buffer_size: u32,
    vendor_length: u16,
    request_max: u16,
    roots: u8,
    formats: u8,
    image_order: u8,
    bitmap_order: u8,
    scanline_unit: u8,
    scanline_pad: u8,
    keycode_min: u8,
    keycode_max: u8,
    pad: u32,
};

const XPixmapFormat = struct {
    depth: u8,
    bits_per_pixel: u8,
    scanline_pad: u8,
    pad: u48,
};

const XRootWindow = struct {
    id: u32,
    colormap: u32,
    white: u32,
    black: u32,
    input_mask: u32,
    width: u16,
    height: u16,
    width_mm: u16,
    height_mm: u16,
    maps_min: u16,
    maps_max: u16,
    root_visual_id: u32,
    backing_store: u8,
    save_unders: u8,
    depth: u8,
    depths: u8,
};

const XDepth = struct {
    depth: u8,
    pad: u8,
    visuals: u16,
    padd: u32,
};

const XVisual = struct {
    group: u8,
    bits: u8,
    colormap_entries: u16,
    mask_red: u32,
    mask_green: u32,
    mask_blue: u32,
    pad: u32,
};

test "" {
    const text = @embedFile("/home/tau/.Xauthority");
    var sock = try std.net.connectUnixSocket("/tmp/.X11-unix/X0");
    defer sock.close();

    var buffer: [1024 * 1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    var ser = std.io.serializer(.Little, .Byte, fbs.writer());

    _ = std.mem.readIntSliceBig(u16, text[0..]);
    const x = std.mem.readIntSliceBig(u16, text[2..]);
    const address = text[4 .. 4 + x];
    const y = std.mem.readIntSliceBig(u16, text[4 + x ..]);
    const display = text[6 + x .. 6 + x + y];
    const z = std.mem.readIntSliceBig(u16, text[6 + x + y ..]);
    const name = text[8 + x + y .. 8 + x + y + z];
    const w = std.mem.readIntSliceBig(u16, text[8 + x + y + z ..]);
    const data = text[10 + x + y + z .. 10 + x + y + z + w];

    const header: XConnectHeader = .{
        .order = .little,
        .name = name,
        .data = data,
    };

    try ser.serialize(header);

    _ = try sock.write(fbs.getWritten());
    const len = try sock.read(&buffer);

    fbs = std.io.fixedBufferStream(&buffer);
    var dser = std.io.deserializer(.Little, .Byte, fbs.reader());
    const reply = try dser.deserialize(XConnectReply);
    const setup = try dser.deserialize(XConnectSetup);

    std.debug.print(
        \\
        \\address  : {}
        \\display  : {}
        \\name     : {}
        \\data     : {x}
        \\sending
        \\response : {x}
        \\reply    : {}
        \\setup    : {}
        \\
    , .{
        address,
        display,
        name,
        data,
        buffer[0..len],
        reply,
        setup,
    });

    var length = reply.length * 4;
}
