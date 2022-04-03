const Store = @This();

const std = @import("std");
const okredis = @import("okredis");
const http = @import("apple_pie");

const Session = @import("Session.zig");
const Options = @import("Options.zig");
const Cookie = @import("Cookie.zig");

redis_client: *okredis.Client,
options: Options = .{},

pub fn get(
    self: *Store,
    allocator: std.mem.Allocator,
    request: http.Request,
    name: []const u8,
) !Session {
    const Decoder = std.base64.url_safe_no_pad.Decoder;

    const cookies = try Cookie.readCookies(allocator, request, name);

    if (cookies.len > 0) {
        var buf: [64]u8 = undefined;
        const encoded = cookies[0].value;
        const size = Decoder.calcSizeForSlice(encoded) catch return self.generateNew(name);
        if (size != 64) return self.generateNew(name);
        Decoder.decode(&buf, encoded) catch return self.generateNew(name);

        return Session{
            .store = self,
            .id = buf,
            .is_new = false,
            .name = name,
        };
    } else return self.generateNew(name);
}

fn generateNew(self: *Store, name: []const u8) Session {
    return Session{
        .store = self,
        .id = generateRandomId(),
        .is_new = true,
        .name = name,
    };
}

fn generateRandomId() [64]u8 {
    var buf: [64]u8 = undefined;
    // TODO https://github.com/ziglang/zig/issues/7593
    // std.crypto.random.bytes(&buf);
    std.os.getrandom(&buf) catch @panic("getrandom() failed to provide entropy");
    return buf;
}
