const Cookie = @This();

const std = @import("std");
const http = @import("apple_pie");

name: []const u8,
value: []const u8,
path: ?[]const u8 = null,
domain: ?[]const u8 = null,
max_age: u32 = 0,
secure: bool = false,
http_only: bool = false,

pub fn format(
    self: Cookie,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    // TODO sanitize

    try writer.print("{s}={s}", .{ self.name, self.value });

    if (self.path) |path| {
        try writer.print("; Path={s}", .{path});
    }

    if (self.domain) |domain| {
        try writer.print("; Domain={s}", .{domain});
    }

    if (self.http_only) {
        try writer.writeAll("; HttpOnly");
    }

    if (self.secure) {
        try writer.writeAll("; Secure");
    }
}

pub fn readCookies(
    allocator: *std.mem.Allocator,
    request: http.Request,
    filter: ?[]const u8,
) ![]Cookie {
    var iterator = request.iterator();
    const header = while (iterator.next()) |header| {
        if (std.mem.eql(u8, header.key, "Cookie")) {
            break try allocator.dupe(u8, header.value);
        }
    } else return &[_]Cookie{};

    var cookies = std.ArrayList(Cookie).init(allocator);
    var iter = std.mem.split(u8, header, ";");
    while (iter.next()) |item| {
        var parts = std.mem.split(u8, item, "=");
        const name = parts.next() orelse continue;
        const value = parts.next() orelse continue;

        if (filter) |filter_name| {
            if (!std.mem.eql(u8, name, filter_name)) continue;
        }

        try cookies.append(Cookie{ .name = name, .value = value });
    }

    return cookies.toOwnedSlice();
}
