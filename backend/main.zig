const std = @import("std");
const http = @import("apple_pie");
const okredis = @import("okredis");
const fs = http.FileServer;
const router = http.router;
const Client = okredis.Client;
const json = std.json;

const Store = @import("Store.zig");

// https://github.com/ziglang/zig/issues/7593
// pub const io_mode = .evented;

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
    redis_client: Client,
};

const HSETQuestion = okredis.commands.hashes.HSET.forStruct(Question);
const HMGETQuestion = okredis.commands.hashes.HMGET.forStruct(Question);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    var context: Context = .{
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
            router.get("/api/export", exportQuestions),
            router.get("/api/exportall", exportAllQuestions),
            // router.put("/api/question/:id", modifyQuestion),
        }),
    );
}

fn index(ctx: *Context, response: *http.Response, request: http.Request) !void {
    var store = Store{
        .redis_client = &ctx.redis_client,
        .options = .{},
    };
    const session = try store.get(request.arena, request, "nochfragen_session");

    const file = std.fs.cwd().openFile("public/index.html", .{}) catch |err| switch (err) {
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
fn serveFs(_: *Context, response: *http.Response, request: http.Request) !void {
    try fs.serve({}, response, request);
}

fn badRequest(response: *http.Response, message: []const u8) !void {
    response.status_code = .bad_request;
    try response.body.print("{s}\n", .{message});
}

const QuestionIterator = struct {
    allocator: *std.mem.Allocator,
    redis_client: *Client,
    end: u32,
    id: u32,

    pub fn init(allocator: *std.mem.Allocator, redis_client: *Client) !QuestionIterator {
        const question_range = try redis_client.send([2]?u32, .{
            "MGET",
            "nochfragen:questions-start",
            "nochfragen:questions-end",
        });
        const start = question_range[0] orelse 0;
        const end = question_range[1] orelse 0;

        return QuestionIterator{
            .allocator = allocator,
            .redis_client = redis_client,
            .end = end,
            .id = start,
        };
    }

    pub fn next(self: *QuestionIterator) !?Question {
        if (self.id >= self.end) return null;

        const key = try std.fmt.allocPrint(self.allocator, "nochfragen:questions:{}", .{self.id});
        self.id += 1;

        return try self.redis_client.sendAlloc(Question, self.allocator, HMGETQuestion.init(key));
    }
};

fn listQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    var iter = try QuestionIterator.init(request.arena, &ctx.redis_client);

    var json_write_stream = std.json.writeStream(response.writer(), 4);
    try json_write_stream.beginArray();

    while (try iter.next()) |question| {
        if (question.visibility != @enumToInt(Visibility.deleted)) {
            try json_write_stream.arrayElem();
            try json_write_stream.beginObject();

            try json_write_stream.objectField("id");
            try json_write_stream.emitNumber(iter.id - 1);

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

fn exportQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    try exportQuestionsHidden(ctx, response, request, false);
}

fn exportAllQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    try exportQuestionsHidden(ctx, response, request, true);
}

fn exportQuestionsHidden(
    ctx: *Context,
    response: *http.Response,
    request: http.Request,
    include_hidden: bool,
) !void {
    var iter = try QuestionIterator.init(request.arena, &ctx.redis_client);

    try response.headers.put("Content-Disposition", "attachment; filename=\"questions.txt\"");

    while (try iter.next()) |question| {
        if (question.visibility != @enumToInt(Visibility.deleted) and
            (include_hidden or question.visibility == @enumToInt(Visibility.visible)))
        {
            try response.writer().print("{s}\n", .{question.text});
        }
    }
}

fn addQuestion(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

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
