const std = @import("std");

ip: []const u8,
port: u16,

const ParsedAddress = @This();

pub fn parse(address: []const u8) !ParsedAddress {
    var iter = std.mem.split(u8, address, ":");

    const ip = iter.next() orelse return error.AddressParseError;
    const port_raw = iter.next() orelse return error.AddressParseError;
    if (iter.next() != null) return error.AddressParseError;
    const port = std.fmt.parseInt(u16, port_raw, 10) catch return error.AddressParseError;

    return ParsedAddress{ .ip = ip, .port = port };
}
