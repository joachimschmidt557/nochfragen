const Cookie = @This();

const std = @import("std");
const http = @import("apple_pie");

const Options = @import("Options.zig");

name: []const u8,
value: []const u8,
path: ?[]const u8 = null,
domain: ?[]const u8 = null,
max_age: ?u32 = null,
/// Only send cookies over HTTPS
secure: bool = false,
/// If true, don't make this cookie available to the Document.cookie
/// JavaScript API
http_only: bool = false,
/// SameSite option
same_site: SameSiteOption = .lax,

pub const SameSiteOption = enum {
    none,
    lax,
    strict,
};

pub fn fmtCookie(cookie: Cookie) std.fmt.Formatter(fmtCookieImpl) {
    return .{ .data = cookie };
}

pub fn fmtCookieImpl(
    cookie: Cookie,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    try writeSetCookie(cookie, writer);
}

pub fn writeSetCookie(cookie: Cookie, writer: anytype) !void {
    try writeCookieName(cookie.name, writer);
    try writer.writeAll("=");
    try writeCookieValue(cookie.value, writer);

    if (cookie.path) |path| {
        try writer.writeAll("; Path=");
        try writeCookiePath(path, writer);
    }

    if (cookie.domain) |domain| {
        try writer.writeAll("; Domain=");
        try writeCookieDomain(domain, writer);
    }

    if (cookie.max_age) |max_age| {
        try writer.print("; Max-Age={}", .{max_age});
    }

    if (cookie.http_only) {
        try writer.writeAll("; HttpOnly");
    }

    if (cookie.secure) {
        try writer.writeAll("; Secure");
    }

    switch (cookie.same_site) {
        .none => try writer.writeAll("; SameSite=None"),
        .lax => try writer.writeAll("; SameSite=Lax"),
        .strict => try writer.writeAll("; SameSite=Strict"),
    }
}

fn writeCookieName(name: []const u8, writer: anytype) !void {
    // TODO sanitize
    try writer.writeAll(name);
}

fn writeCookieValue(value: []const u8, writer: anytype) !void {
    // TODO sanitize
    try writer.writeAll(value);
}

fn writeCookiePath(path: []const u8, writer: anytype) !void {
    // TODO sanitize
    try writer.writeAll(path);
}

fn writeCookieDomain(domain: []const u8, writer: anytype) !void {
    // TODO sanitize
    try writer.writeAll(domain);
}

pub fn readRequestCookies(
    allocator: std.mem.Allocator,
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
    var iter = std.mem.split(u8, header, "; ");
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

// CHAR           = <any US-ASCII character (octets 0 - 127)>
fn isChar(c: u8) bool {
    return switch (c) {
        0...127 => true,
        else => false,
    };
}

// CTL            = <any US-ASCII control character
//                  (octets 0 - 31) and DEL (127)>
fn isCtl(c: u8) bool {
    return switch (c) {
        0...31 => true,
        127 => true,
        else => false,
    };
}

// separators     = "(" | ")" | "<" | ">" | "@"
//                | "," | ";" | ":" | "\" | <">
//                | "/" | "[" | "]" | "?" | "="
//                | "{" | "}" | SP | HT
fn isSeparator(c: u8) bool {
    return switch (c) {
        '(', ')', '<', '>', '@', ',', ';', ':', '\\', '"', '/', '[', ']', '?', '=', '{', '}', '\t' => true,
        else => false,
    };
}

// token          = 1*<any CHAR except CTLs or separators>
fn isToken(s: []const u8) bool {
    if (s.len < 1) return false;
    for (s) |c| {
        const is_char = isChar(c);
        const is_ctl = isCtl(c);
        const is_separator = isSeparator(c);
        if (!(is_char and !(is_ctl or is_separator))) return false;
    }
    return true;
}

// path-value        = <any CHAR except CTLs or ";">
fn isPathValue(s: []const u8) bool {
    for (s) |c| {
        const is_char = isChar(c);
        const is_ctl = isCtl(c);
        if (!(is_char and !(is_ctl or c == ';'))) return false;
    }
    return true;
}
