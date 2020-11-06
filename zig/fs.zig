const Filesystem = packed struct {
    // file records
    files: [255]File = undefined,
    // file chunks
    chunks: [255]Chunk,

    // maximum of 255 files
    entries: u8,

    pub const File = packed struct {
        // hash of the filename
        hash: u16,
        // location in the file list
        location: u8,
        // unused meta
        unused: u8,
    };
};

const Chunk = packed struct {
    // if 0 then we've reached the end of the chunk list, offset is calculated as
    // base address + 128 * next
    next: u8,

    // size of the file entry (note: top two bytes are used for this header)
    size: u7 = undefined,

    // if the chunk is free to use
    active: bool = false,

    // content
    data: [126]u8 = undefined,
};

const filesystem: Filesystem = .{
    .files = [_]File{.{ .hash = 0, .location = 0, .unused = 0 }} ** 255,
    .entries = 0,
    .chunks = comptime blk: {
        comptime var chunks: []const Chunk = [_]Chunk{};
        var i: usize = 0;
        while (i < 255) : (i += 1) chunks = chunks ++ [_]Chunk{.{ .next = i +% 1 }};
        break :blk chunks;
    },
};

pub fn findEmptyChunk() ?*u8 {
    for (filesystem.chunks) |*chunk, i| {
        if (chunk.active) continue;
        return i;
    }
    return null; // no free chunks found, filesystem is full
}
