const Session = @This();

const std = @import("std");
const http = @import("apple_pie");
const okredis = @import("okredis");
const OrErr = okredis.types.OrErr;

const Store = @import("Store.zig");
const Cookie = @import("Cookie.zig");

store: *Store,
id: [64]u8,
is_new: bool,
name: []const u8,

pub fn set(
    self: *Session,
    comptime T: type,
    key: []const u8,
    value: T,
) !void {
    const Encoder = std.base64.url_safe_no_pad.Encoder;
    const size = comptime Encoder.calcSize(64);

    const prefix = "nochfragen:sessions:";
    var buf: [prefix.len + size]u8 = (prefix ++ [_]u8{undefined} ** size).*;
    _ = Encoder.encode(buf[prefix.len..], &self.id);

    const fixed_up_value = switch (T) {
        bool => @boolToInt(value),
        else => value,
    };

    try self.store.redis_client.send(void, .{ "HSET", &buf, key, fixed_up_value });
}

pub fn get(
    self: *Session,
    comptime T: type,
    key: []const u8,
) !?T {
    const Encoder = std.base64.url_safe_no_pad.Encoder;
    const size = comptime Encoder.calcSize(64);

    const prefix = "nochfragen:sessions:";
    var buf: [prefix.len + size]u8 = (prefix ++ [_]u8{undefined} ** size).*;
    _ = Encoder.encode(buf[prefix.len..], &self.id);

    const FixedUpT = switch (T) {
        bool => u1,
        else => T,
    };

    const value = switch (try self.store.redis_client.send(OrErr(FixedUpT), .{ "HGET", &buf, key })) {
        .Ok => |x| x,
        .Nil => return null,
        .Err => return error.RedisError,
    };

    return switch (T) {
        bool => value == 1,
        else => value,
    };
}

pub fn save(
    self: Session,
    allocator: std.mem.Allocator,
    request: http.Request,
    response: *http.Response,
) !void {
    _ = request;
    const Encoder = std.base64.url_safe_no_pad.Encoder;
    const size = comptime Encoder.calcSize(64);
    var buf: [size]u8 = undefined;

    const cookie = Cookie{
        .name = self.name,
        .value = Encoder.encode(&buf, &self.id),
        .secure = self.store.options.secure,
        .http_only = self.store.options.http_only,
    };

    const value = try std.fmt.allocPrint(allocator, "{}", .{cookie});
    try response.headers.put("Set-Cookie", value);
}
