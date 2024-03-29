//! Absolutely terrible password manager

const std = @import("std");
const os = std.os;
const fmt = std.fmt;
const mem = std.mem;
const scrypt = std.crypto.pwhash.scrypt;
const hmac = std.crypto.auth.hmac.sha2.HmacSha512;
const base64 = std.base64.standard_no_pad;

const writer = std.io.getStdOut().writer();
const err = std.io.getStdErr().writer();

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const gpa = arena.allocator();

    if (os.argv.len != 5) {
        try err.writeAll(
            \\usage: pass name password site counter
            \\
            \\  name          Name of the user
            \\  password      Master password
            \\  site          Website which the password is scoped to
            \\  counter       Iteration of the password
            \\
        );
        return 1;
    }
    const name = mem.span(os.argv[1]);
    const secret = mem.span(os.argv[2]);
    const site = mem.span(os.argv[3]);
    const count = try std.fmt.parseInt(u8, mem.span(os.argv[4]), 10);

    var key: [64]u8 = undefined;

    try scrypt.kdf(gpa, &key, secret, name, .{ .ln = 20, .r = 8, .p = 1 });

    const m_seed = try fmt.allocPrint(gpa, "{s}.{d}", .{ site, count });

    var mac: [hmac.mac_length]u8 = undefined;
    hmac.create(&mac, m_seed, &key);

    inline for (@typeInfo(@TypeOf(template)).Struct.fields) |field| {
        const tmpl = blk: {
            const tmp = @field(template, field.name);
            break :blk tmp[mac[0] % tmp.len];
        };

        try writer.writeAll(field.name ++ ": ");

        for (tmpl, mac[1 .. 1 + tmpl.len]) |c, x| try writer.writeByte(get(c, x));

        try writer.writeByte('\n');
    }

    return 0;
}

fn get(c: u8, x: u8) u8 {
    switch (c) {
        inline 'V', 'C', 'v', 'c', 'A', 'a', 'n', 'o', 'x', 'X' => |m| {
            const cls = @field(class, &.{m});

            return cls[x % cls.len];
        },
        ' ' => return ' ',
        else => std.debug.print("oops: {c}\n", .{c}),
    }

    unreachable;
}

const class = .{
    .V = "AEIOU",
    .C = "BCDFGHJKLMNPQRSTVWXYZ",
    .v = "aeiou",
    .c = "bcdfghjklmnpqrstvwxyz",
    .A = "AEIOUBCDFGHJKLMNPQRSTVWXYZ",
    .a = "AEIOUaeiouBCDFGHJKLMNPQRSTVWXYZbcdfghjklmnpqrstvwxyz",
    .n = "123456789",
    .o = "@&%?,=[]_:-+*$#!'^~;()/.",
    .x = "AEIOUaeiouBCDFGHJKLMNPQRSTVWXYZbcdfghjklmnpqrstvwxyz0123456789!@#$%^&*()",
    .X = "AEIOUaeiouBCDFGHJKLMNPQRSTVWXYZbcdfghjklmnpqrstvwxyz0123456789!@#$%^&*()_-+={[}]:;\"'\\|<,>.?/~` ",
};

const template = .{
    .@"64" = &[_][]const u8{"xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXx"},
    .@"32" = &[_][]const u8{"xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXx"},
    .max = &[_][]const u8{
        "anoxxxxxxxxxxxxxxxxx",
        "axxxxxxxxxxxxxxxxxno",
    },
    .long = &[_][]const u8{
        "CvcvnoCvcvCvcv",
        "CvcvCvcvCvccno",
        "CvcvCvcvnoCvcv",
        "CvccnoCvccCvcv",
        "CvcvCvcvCvcvno",
        "CvccCvccnoCvcv",
        "CvccnoCvcvCvcv",
        "CvccCvccCvcvno",
        "CvccCvcvnoCvcv",
        "CvcvnoCvccCvcc",
        "CvccCvcvCvcvno",
        "CvcvCvccnoCvcc",
        "CvcvnoCvccCvcv",
        "CvcvCvccCvccno",
        "CvcvCvccnoCvcv",
        "CvccnoCvcvCvcc",
        "CvcvCvccCvcvno",
        "CvccCvcvnoCvcc",
        "CvcvnoCvcvCvcc",
        "CvccCvcvCvccno",
        "CvcvCvcvnoCvcc",
    },
    .medium = &[_][]const u8{
        "CvcnoCvc",
        "CvcCvcno",
    },
    .short = &[_][]const u8{"Cvcn"},
    .basic = &[_][]const u8{
        "aaanaaan",
        "aannaaan" ++ "aaannaaa",
    },
    .pin = &[_][]const u8{"nnnn"},
    .name = &[_][]const u8{"cvccvcvcv"},
    .phrase = &[_][]const u8{
        "cvcc cvc cvccvcv cvc",
        "cvc cvccvcvcv cvcv",
        "cv cvccv cvc cvcvccv",
    },
};
