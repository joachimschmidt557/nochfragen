const std = @import("std");
const http = @import("apple_pie");
const okredis = @import("okredis");
const fs = http.FileServer;
const router = http.router;
const Client = okredis.Client;
const json = std.json;

pub const io_mode = .evented;

const log = std.log.scoped(.nochfragen);
const max_question_len = 500;

const Visibility = enum(u32) {
    hidden,
    visible,
    deleted,
};

const Question = struct {
    text: []const u8,
    upvotes: u32 = 0,
    visibility: u32 = 0,
};

const Context = struct {
    allocator: *std.mem.Allocator,
    redis_client: Client,
};

const HSETQuestion = okredis.commands.hashes.HSET.forStruct(Question);
const HMGETQuestion = okredis.commands.hashes.HMGET.forStruct(Question);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    var context: Context = .{
        .allocator = allocator,
        .redis_client = undefined,
    };

    const addr = try std.net.Address.parseIp4("127.0.0.1", 6379);
    var connection = std.net.tcpConnectToAddress(addr) catch |err| {
        return log.crit("Error connecting to redis: {}", .{err});
    };

    try context.redis_client.init(connection);
    defer context.redis_client.close();

    try fs.init(allocator, .{ .dir_path = "public/build", .base_path = "build" });
    defer fs.deinit();

    try http.listenAndServe(
        allocator,
        try std.net.Address.parseIp("127.0.0.1", 8080),
        &context,
        comptime router.Router(*Context, &.{
            router.get("/", index),
            router.get("/build/*", serveFs),
            router.get("/api/questions", listQuestions),
            router.post("/api/questions", addQuestion),
            // router.put("/api/question/:id", modifyQuestion),
        }),
    );
}

fn index(ctx: *Context, response: *http.Response, request: http.Request) !void {
    _ = ctx;
    _ = request;

    const file = std.fs.cwd().openFile("public/index.html", .{}) catch |err| switch (err) {
        error.FileNotFound => return response.notFound(),
        else => |e| return e,
    };
    defer file.close();

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

fn badRequest(response: *http.Response, message: []const u8) !void {
    response.status_code = .bad_request;
    try response.body.print("{s}\n", .{message});
}

fn listQuestions(ctx: *Context, response: *http.Response, _: http.Request) !void {
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const question_range = try ctx.redis_client.send([2]?u32, .{
        "MGET",
        "nochfragen:questions-start",
        "nochfragen:questions-end",
    });
    const start = question_range[0] orelse 0;
    const end = question_range[1] orelse 0;

    var json_write_stream = std.json.writeStream(response.writer(), 4);
    try json_write_stream.beginArray();

    var id = start;
    while (id < end) : (id += 1) {
        const key = try std.fmt.allocPrint(allocator, "nochfragen:questions:{}", .{id});
        const question = try ctx.redis_client.sendAlloc(Question, allocator, HMGETQuestion.init(key));

        if (question.visibility != @enumToInt(Visibility.deleted)) {
            try json_write_stream.arrayElem();
            try json_write_stream.beginObject();

            try json_write_stream.objectField("id");
            try json_write_stream.emitNumber(id);

            try json_write_stream.objectField("text");
            try json_write_stream.emitString(question.text);

            try json_write_stream.objectField("upvotes");
            try json_write_stream.emitNumber(question.upvotes);

            try json_write_stream.objectField("visibility");
            try json_write_stream.emitNumber(question.visibility);

            try json_write_stream.objectField("upvoted");
            try json_write_stream.emitBool(false);

            try json_write_stream.endObject();
        }
    }

    try json_write_stream.endArray();
}

fn addQuestion(ctx: *Context, response: *http.Response, request: http.Request) !void {
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var token_stream = json.TokenStream.init(request.body());
    const request_data = try json.parse(
        struct { text: []const u8 },
        &token_stream,
        .{ .allocator = allocator },
    );

    if (request_data.text.len == 0) return badRequest(response, "Empty question");
    if (request_data.text.len > max_question_len) return badRequest(response, "Maximum question length exceeded");

    const new_end = try ctx.redis_client.send(i64, .{ "INCR", "nochfragen:questions-end" });
    const id = new_end - 1;

    const key = try std.fmt.allocPrint(allocator, "nochfragen:questions:{}", .{id});
    try ctx.redis_client.send(void, HSETQuestion.init(key, .{ .text = request_data.text }));

    try response.writer().print("OK", .{});
}
