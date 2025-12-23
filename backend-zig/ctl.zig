const std = @import("std");
const okredis = @import("okredis");
const clap = @import("clap");
const Client = okredis.BufferedClient;
const scrypt = std.crypto.pwhash.scrypt;

const log = std.log.scoped(.nochfragenctl);

const ParsedAddress = @import("ParsedAddress.zig");
const parseAddress = ParsedAddress.parse;

const default_redis_address = ParsedAddress{ .ip = "127.0.0.1", .port = 6379 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help                     Display this help and exit.") catch unreachable,
        clap.parseParam("--set-password <PASS>          Set a new password and exit") catch unreachable,
        clap.parseParam("--redis-address <IP:PORT>      Address to connect to redis") catch unreachable,
    };

    const parsers = comptime .{
        .PASS = clap.parsers.string,
        .@"IP:PORT" = parseAddress,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{ .diagnostic = &diag }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        std.process.exit(1);
    };
    defer res.deinit();

    if (res.args.help) {
        const stderr = std.io.getStdErr().writer();

        try stderr.writeAll("Usage: nochfragenctl ");
        try clap.usage(stderr, clap.Help, &params);
        try stderr.writeAll("\n\nOptions:\n\n");

        try clap.help(stderr, clap.Help, &params, .{});
        try stderr.writeAll("\n");
    } else if (res.args.@"set-password") |pass| {
        const redis_address = res.args.@"redis-address" orelse default_redis_address;

        setPassword(allocator, redis_address, pass) catch |err| {
            log.err("Error during password setting: {}", .{err});
            std.process.exit(1);
        };
    } else {
        log.err("No command given", .{});
        std.process.exit(1);
    }
}

fn setPassword(allocator: std.mem.Allocator, redis_address: ParsedAddress, password: []const u8) !void {
    const addr = try std.net.Address.parseIp4(redis_address.ip, redis_address.port);
    var connection = std.net.tcpConnectToAddress(addr) catch return error.RedisConnectionError;

    var redis_client: Client = undefined;
    try redis_client.init(connection);
    defer redis_client.close();

    var buf: [128]u8 = undefined;
    const hashed_password = try scrypt.strHash(password, .{
        .allocator = allocator,
        .params = scrypt.Params.interactive,
        .encoding = .crypt,
    }, &buf);

    try redis_client.send(void, .{ "SET", "nochfragen:password", hashed_password });
}
