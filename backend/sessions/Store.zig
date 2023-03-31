const Store = @This();

const std = @import("std");
const http = @import("apple_pie");
const okredis = @import("okredis");

const Session = @import("Session.zig");
const Options = @import("Options.zig");
const Cookie = @import("Cookie.zig");

redis_client: *okredis.BufferedClient,
options: Options = .{},

pub const redis_key_prefix = "nochfragen:sessions:";
pub const session_indicator = "__session";

const Encoder = std.base64.url_safe_no_pad.Encoder;
const encoded_size = Encoder.calcSize(64);

/// Retrieve a session associated with this request. If the session
/// does not exist on the server, a new session is generated. If any
/// other error occurs, we fall back on a new session.
pub fn get(
    self: *Store,
    allocator: std.mem.Allocator,
    request: http.Request,
    name: []const u8,
) Session {
    const Decoder = std.base64.url_safe_no_pad.Decoder;

    // retrieve request cookies
    const cookies = Cookie.readRequestCookies(allocator, request, name) catch return self.generateNew(name);
    if (cookies.len != 1) return self.generateNew(name);

    // retrieve and decode session id
    var buf: [64]u8 = undefined;
    const encoded = cookies[0].value;
    const size = Decoder.calcSizeForSlice(encoded) catch return self.generateNew(name);
    if (size != 64) return self.generateNew(name);
    Decoder.decode(&buf, encoded) catch return self.generateNew(name);

    // look up session id in redis
    var key_buf: [redis_key_prefix.len + encoded_size]u8 = (redis_key_prefix ++ [_]u8{undefined} ** encoded_size).*;
    _ = Encoder.encode(key_buf[redis_key_prefix.len..], &buf);

    const indicator = self.redis_client.send(?u32, .{ "HGET", &key_buf, session_indicator }) catch return self.generateNew(name);
    if (indicator) |value| {
        if (value != 1) return self.generateNew(name);
    } else return self.generateNew(name);

    return Session{
        .store = self,
        .id = buf,
        .is_new = false,
        .name = name,
    };
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
