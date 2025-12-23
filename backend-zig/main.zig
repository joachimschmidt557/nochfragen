const std = @import("std");
const http = @import("apple_pie");
const okredis = @import("okredis");
const clap = @import("clap");
const sqlite = @import("sqlite");

const fs = http.FileServer;
const router = http.router;
const json = std.json;
const scrypt = std.crypto.pwhash.scrypt;

const Store = @import("sessions/Store.zig");
const Context = @import("Context.zig");

const responses = @import("responses.zig");
const forbidden = responses.forbidden;
const badRequest = responses.badRequest;
const ok = responses.ok;

const surveys = @import("surveys.zig");
const questions = @import("questions.zig");

// TODO https://github.com/ziglang/zig/issues/7593
pub const io_mode = .evented;

const log = std.log.scoped(.nochfragen);

const ParsedAddress = @import("ParsedAddress.zig");
const parseAddress = ParsedAddress.parse;

const default_redis_address = ParsedAddress{ .ip = "127.0.0.1", .port = 6379 };
const default_listen_address = ParsedAddress{ .ip = "127.0.0.1", .port = 8080 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help                     Display this help and exit.") catch unreachable,
        clap.parseParam("--listen-address <IP:PORT>     Address to listen for connections") catch unreachable,
        clap.parseParam("--redis-address <IP:PORT>      Address to connect to redis") catch unreachable,
        clap.parseParam("--sqlite-db <PATH>             Path to the SQLite database") catch unreachable,
        clap.parseParam("--root-dir <PATH>              Path to the static HTML, CSS and JS content") catch unreachable,
    };

    const parsers = comptime .{
        .PATH = clap.parsers.string,
        .URL = clap.parsers.string,
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

        try stderr.writeAll("Usage: nochfragen ");
        try clap.usage(stderr, clap.Help, &params);
        try stderr.writeAll("\n\nOptions:\n\n");

        try clap.help(stderr, clap.Help, &params, .{});
        try stderr.writeAll("\n");
    } else {
        const listen_address = res.args.@"listen-address" orelse default_listen_address;
        const redis_address = res.args.@"redis-address" orelse default_redis_address;
        const root_dir = res.args.@"root-dir" orelse "build/";
        const db_file = res.args.@"sqlite-db" orelse "db.sqlite";

        startServer(
            allocator,
            listen_address,
            redis_address,
            db_file,
            root_dir,
        ) catch |err| {
            log.err("Error during server execution: {}", .{err});
            std.process.exit(1);
        };
    }
}

fn startServer(
    allocator: std.mem.Allocator,
    listen_address: ParsedAddress,
    redis_address: ParsedAddress,
    db_file: []const u8,
    root_dir: []const u8,
) !void {
    var context: Context = .{
        .redis_client = undefined,
        .db = undefined,
        .root_dir = try allocator.dupe(u8, root_dir),
    };
    const builder = router.Builder(*Context);

    const addr = try std.net.Address.parseIp4(redis_address.ip, redis_address.port);
    var connection = std.net.tcpConnectToAddress(addr) catch return error.RedisConnectionError;

    try context.redis_client.init(connection);
    defer context.redis_client.close();

    context.db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = try allocator.dupeZ(u8, db_file) },
        .open_flags = .{ .write = true, .create = true },
    });
    defer context.db.deinit();
    try questions.initializeDatabase(&context.db);
    try surveys.initializeDatabase(&context.db);

    fs.init(allocator, .{
        .dir_path = try std.fs.path.join(allocator, &.{ root_dir, "_app" }),
        .base_path = "_app",
    }) catch |err| {
        log.err("Error initializing filesystem serve: {}", .{err});
        std.process.exit(1);
    };
    defer fs.deinit();

    @setEvalBranchQuota(10000);
    try http.listenAndServe(
        allocator,
        try std.net.Address.parseIp(listen_address.ip, listen_address.port),
        &context,
        comptime router.Router(*Context, &.{
            builder.get("/", index),
            builder.get("/_app/*", serveFs),

            builder.get("/api/login", loginStatus),
            builder.post("/api/login", login),
            builder.post("/api/logout", logout),

            builder.get("/api/questions", questions.listQuestions),
            builder.post("/api/questions", questions.addQuestion),
            builder.delete("/api/questions", questions.deleteAllQuestions),
            builder.put("/api/question/:id", questions.modifyQuestion),
            builder.delete("/api/question/:id", questions.deleteQuestion),

            builder.get("/api/export", questions.exportQuestions),

            builder.get("/api/surveys", surveys.listSurveys),
            builder.post("/api/surveys", surveys.addSurvey),
            builder.put("/api/survey/:id", surveys.modifySurvey),
            builder.delete("/api/survey/:id", surveys.deleteSurvey),
        }),
    );
}

fn index(ctx: *Context, response: *http.Response, request: http.Request) !void {
    var store = Store{ .redis_client = &ctx.redis_client };
    const session = store.get(request.arena, request, "nochfragen_session");

    const file_path = try std.fs.path.join(request.arena, &.{ ctx.root_dir, "index.html" });
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return response.notFound(),
        else => |e| return e,
    };
    defer file.close();

    try session.save(request.arena, request, response);

    fs.serveFile(response, "index.html", file) catch |err| switch (err) {
        error.NotAFile => return response.notFound(),
        else => return err,
    };
}

/// Serves static content
fn serveFs(ctx: *Context, response: *http.Response, request: http.Request) !void {
    _ = ctx;
    try fs.serve({}, response, request);
}

fn loginStatus(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;

    try std.json.stringify(.{ .loggedIn = logged_in }, .{}, response.writer());
    response.close = true;
}

fn login(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var token_stream = json.TokenStream.init(request.body());
    const request_data = json.parse(
        struct { password: []const u8 },
        &token_stream,
        .{ .allocator = allocator },
    ) catch return badRequest(response, "Invalid JSON");

    const maybe_hashed_password = try ctx.redis_client.sendAlloc(?[]const u8, allocator, .{ "GET", "nochfragen:password" });
    const hashed_password = maybe_hashed_password orelse return forbidden(response, "Access denied");
    scrypt.strVerify(hashed_password, request_data.password, .{ .allocator = allocator }) catch return forbidden(response, "Access denied");

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    try session.set(bool, "authenticated", true);

    try ok(response);
}

fn logout(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    try session.set(bool, "authenticated", false);

    try ok(response);
}
