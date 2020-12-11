const Meter = struct {
    slaveSelectFn: fn (*Meter) void,
    sndnkeFn: fn (*Meter) void,
    requd2Fn: fn (*Meter) void,
};

const Virtual = struct {
    meter: Meter = .{ .slaveSelectFn = slaveselect, .sndnkeFn = sndnke, .requd2Fn = requd2 },
    toggle: ?u1 = null,
    access: u8 = 0,

    pub fn slaveSelect(meter: *Meter) !void {
        const self = @fieldParentPtr(Virtual, "meter", meter);
        return error.NoReply;
    }

    pub fn sndnke(meter: *Virtual) !void {
        const self = @fieldParentPtr(Virtual, "meter", meter);
        self.toggle = null;
    }

    pub fn requd2(meter: *Virtual, toggle: u1) !void {
        const self = @fieldParentPtr(Virtual, "meter", meter);
        self.access +%= 1;
        if (self.toggle != null and self.toggle.? == toggle) {
            return {};
        } else {
            return {};
        }
    }
};
