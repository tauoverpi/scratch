const std = @import("std");
const ComptimeStringMap = std.ComptimeStringMap;

const HttpRequestHeader = union(enum) {
    @"A-IM",
    Accept,
    @"Accept-Charset",
    @"Accept-Datetime",
    @"Accept-Encoding",
    @"Accept-Language",
    @"Accept-Control-Request-Method",
    @"Accept-Control-Request-Headers",
    Authorization,
    @"Cache-Control",
    Connection,
    @"Content-Encoding",
    @"Content-Length",
    @"Content-MD5",
    @"Content-Type",
    Cookie,
    Date,
    Expect,
    Forwarded,
    From,
    Host,
    @"HTTP2-Settings",
    @"If-Match",
    @"If-Modified-Since",
    @"If-None-Match",
    @"If-Range",
    @"If-Unmodified-Since",
    @"Max-Forwards",
    Origin,
    Pragma,
    @"Proxy-Authorization",
    Range,
    Referer,
    TE,
    Trailer,
    @"Transfer-Encoding",
    @"User-Agent",
    Upgrade,
    Via,
    Warning,
};

const HttpResponseHeader = union(enum) {
    @"Access-Control-Allow-Origin",
    @"Access-Control-Allow-Credentials",
    @"Access-Control-Expose-Headers",
    @"Access-Control-Max-Age",
    @"Access-Control-Allow-Methods",
    @"Access-Control-Allow-Headers",
    @"Accept-Patch",
    @"Accept-Ranges",
    Age,
    Allow,
    @"Alt-Svc",
    @"Cache-Control",
    Connection,
    @"Content-Disposition",
    @"Content-Encoding",
    @"Content-Language",
    @"Content-Length",
    @"Content-Location",
    @"Content-MD5",
    @"Content-Range",
    @"Content-Type",
    Date,
    @"Delta-Base",
    ETag,
    Expires,
    IM,
    @"Last-Modified",
    Link,
    Location,
    P3P,
    Pragma,
    @"Proxy-Authenticate",
    @"Public-Key-Pins",
    @"Retry-After",
    Server,
    @"Set-Cookie",
    @"Strict-Transport-Security",
    Trailer,
    @"Transfer-Encoding",
    Tk,
    Upgrade,
    Vary,
    Via,
    Warning,
    @"WWW-Authenticate",
    @"X-Frame-Options",
};

const StreamingTagParser = struct {
    count: u8,

    pub fn init() StreamingTagParser {
        return .{ .count = 0 };
    }

    pub fn feed(p: *StreamingTagParser, c: u8) !?usize {
        switch (c) {
            0x1f => return error.InvalidCharacter,
            ':' => {
                p.count = 0;
                return p.count;
            },
            else => {},
        }
    }
};

fn TokenStream(comptime T: type) type {
    return struct {
        text: []const u8,
        index: usize,

        const Self = @This();

        pub fn init(text: []const u8) Self {
            return .{ .text = text, .index = index };
        }
    };
}
