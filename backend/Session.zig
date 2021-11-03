const Session = @This();

const std = @import("std");
const http = @import("apple_pie");
const okredis = @import("okredis");

const Store = @import("Store.zig");
const Cookie = @import("Cookie.zig");

store: *Store,
id: [64]u8,
is_new: bool,
name: []const u8,

// pub fn set(self: *Session, comptime T: type, key: []const u8, value: T) !void {}

// pub fn get(self: *Session, comptime T: type, key: []const u8) !T {}

pub fn save(
    self: Session,
    allocator: *std.mem.Allocator,
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
