const ST7789 = struct {
    framebuffer: [240 * 320]u16 = [_]u16{0} ** (240 * 320),
    visible: []const u8 = framebuffer[0..240],
};

test "" {
    var display: ST7789 = .{};
}
