pub fn compress(backing: *Allocator, reader: anytype, writer: anytype) !void {
    var buffer: [4096]u8 = undefined;
    //While not end of file
    while (true) {
        //   Read next block of data into buffer and
        const len = try reader.readAll(&buffer);
        const slice = buffer[0..len];
        var arena = std.heap.ArenaAllocator.init(backing);
        defer arena.deinit();
        const allocator = &arena.allocator;

        //      enter all pairs in hash table with counts of their occurrence
        //   While compression possible
        //      Find most frequent byte pair
        //      Replace pair with an unused byte
        //      If substitution deletes a pair from buffer,
        //         decrease its count in the hash table
        //      If substitution adds a new pair to the buffer,
        //         increase its count in the hash table
        //      Add pair to pair table
        //   End while
        //   Write pair table and packed data
        if (len < buffer.len) break;
    }
    //End while
}

pub fn expand() void {
    //While not end of file
    //   Read pair table from input
    //   While more data in block
    //      If stack empty, read byte from input
    //      Else pop byte from stack
    //      If byte in table, push pair on stack
    //      Else write byte to output
    //   End while
    //
    //End while
}
