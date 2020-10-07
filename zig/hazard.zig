const std = @import("std");

fn HazardPointerRecord(comptime T: type) type {
    return struct {
        next: ?*HazardPointerRecord,
        node: *T,
        active: bool,
    };
}

/// Hazard table keeping track of all references currently in a reading state
var global_hazard_table: ?HazardPointerRecord(usize) = null;
threadlocal var hazard_table: ?HazardPointerRecord(usize) = null;
