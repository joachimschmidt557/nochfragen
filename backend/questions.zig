const std = @import("std");
const http = @import("apple_pie");
const okredis = @import("okredis");
const Client = okredis.BufferedClient;
const json = std.json;

const Store = @import("sessions/Store.zig");
const Context = @import("Context.zig");
const printTime = @import("time.zig").printTime;

const responses = @import("responses.zig");
const forbidden = responses.forbidden;
const badRequest = responses.badRequest;

const max_question_len = 500;

const QuestionState = enum(u32) {
    hidden,
    unanswered,
    deleted,
    answering,
    answered,

    fn toString(self: QuestionState) []const u8 {
        return switch (self) {
            .hidden => "hidden",
            .unanswered => "unanswered",
            .deleted => "deleted",
            .answering => "answering",
            .answered => "answered",
        };
    }
};

const Question = struct {
    text: []const u8,
    upvotes: u32 = 0,
    state: QuestionState = .unanswered,
    created_at: i64,
    modified_at: i64,
    answering_at: i64,
    answered_at: i64,
};
const QuestionInternal = struct {
    text: []const u8,
    upvotes: u32 = 0,
    state: u32 = @enumToInt(QuestionState.unanswered),
    created_at: i64,
    modified_at: i64 = -1,
    answering_at: i64 = -1,
    answered_at: i64 = -1,
};

const HSETQuestion = okredis.commands.hashes.HSET.forStruct(QuestionInternal);
const HMGETQuestion = okredis.commands.hashes.HMGET.forStruct(QuestionInternal);

const QuestionIterator = struct {
    allocator: std.mem.Allocator,
    redis_client: *Client,
    end: u32,
    id: u32,

    pub fn init(allocator: std.mem.Allocator, redis_client: *Client) !QuestionIterator {
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

        const question_internal = try self.redis_client.sendAlloc(QuestionInternal, self.allocator, HMGETQuestion.init(key));

        return Question{
            .text = question_internal.text,
            .upvotes = question_internal.upvotes,
            .state = std.meta.intToEnum(QuestionState, question_internal.state) catch .deleted,
            .created_at = question_internal.created_at,
            .modified_at = question_internal.modified_at,
            .answering_at = question_internal.answering_at,
            .answered_at = question_internal.answered_at,
        };
    }
};

pub fn listQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;

    var iter = try QuestionIterator.init(allocator, &ctx.redis_client);

    var json_write_stream = std.json.writeStream(response.writer(), 4);
    try json_write_stream.beginArray();

    while (try iter.next()) |question| {
        if (question.state == .deleted) continue;
        if (!logged_in and question.state == .hidden) continue;

        const str_id = try std.fmt.allocPrint(allocator, "question:{}", .{iter.id - 1});
        const upvoted = (try session.get(bool, str_id)) orelse false;

        try json_write_stream.arrayElem();
        try json_write_stream.beginObject();

        try json_write_stream.objectField("id");
        try json_write_stream.emitNumber(iter.id - 1);

        try json_write_stream.objectField("text");
        try json_write_stream.emitString(question.text);

        try json_write_stream.objectField("upvotes");
        try json_write_stream.emitNumber(question.upvotes);

        try json_write_stream.objectField("state");
        try json_write_stream.emitNumber(@enumToInt(question.state));

        try json_write_stream.objectField("upvoted");
        try json_write_stream.emitBool(upvoted);

        try json_write_stream.endObject();
    }

    try json_write_stream.endArray();
}

pub fn exportQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;
    if (!logged_in) return forbidden(response, "Forbidden");

    var iter = try QuestionIterator.init(allocator, &ctx.redis_client);

    try response.headers.put(
        "Content-Disposition",
        "attachment; filename=\"questions.csv\"",
    );

    try response.writer().print(
        "text,upvotes,state,created_at,modified_at,answering_at,answered_at\n",
        .{},
    );

    while (try iter.next()) |question| {
        if (question.state == .deleted) continue;

        try std.json.encodeJsonString(question.text, .{}, response.writer());
        try response.writer().print(",{},{s},", .{
            question.upvotes,
            question.state.toString(),
        });
        try printTime(question.created_at, response.writer());
        try response.writer().writeAll(",");
        try printTime(question.modified_at, response.writer());
        try response.writer().writeAll(",");
        try printTime(question.answering_at, response.writer());
        try response.writer().writeAll(",");
        try printTime(question.answered_at, response.writer());
        try response.writer().writeAll("\n");
    }
}

pub fn addQuestion(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var token_stream = json.TokenStream.init(request.body());
    const request_data = json.parse(
        struct { text: []const u8 },
        &token_stream,
        .{ .allocator = allocator },
    ) catch return badRequest(response, "Invalid JSON");

    if (request_data.text.len == 0) return badRequest(response, "Empty question");
    if (request_data.text.len > max_question_len) return badRequest(response, "Maximum question length exceeded");

    const new_end = try ctx.redis_client.send(i64, .{ "INCR", "nochfragen:questions-end" });
    const id = new_end - 1;

    const key = try std.fmt.allocPrint(allocator, "nochfragen:questions:{}", .{id});
    try ctx.redis_client.send(void, HSETQuestion.init(key, .{
        .text = request_data.text,
        .created_at = std.time.timestamp(),
    }));

    try response.writer().print("OK", .{});
}

pub fn modifyQuestion(ctx: *Context, response: *http.Response, request: http.Request, raw_id: []const u8) !void {
    const allocator = request.arena;

    const id = std.fmt.parseInt(u32, raw_id, 10) catch return badRequest(response, "Invalid ID");

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    if (session.is_new) return forbidden(response, "Access denied");

    const iter = try QuestionIterator.init(allocator, &ctx.redis_client);
    if (id < iter.id or id >= iter.end) return badRequest(response, "Invalid ID");

    var token_stream = json.TokenStream.init(request.body());
    const request_data = json.parse(
        struct {
            upvote: bool,
            state: u32,
        },
        &token_stream,
        .{ .allocator = allocator },
    ) catch return badRequest(response, "Invalid JSON");

    const key = try std.fmt.allocPrint(allocator, "nochfragen:questions:{}", .{id});
    if (request_data.upvote) {
        const str_id = try std.fmt.allocPrint(allocator, "question:{}", .{id});

        const upvoted = (try session.get(bool, str_id)) orelse false;
        if (upvoted) return forbidden(response, "Already upvoted");

        try ctx.redis_client.send(void, .{ "HINCRBY", key, "upvotes", 1 });
        try session.set(bool, str_id, true);
    } else {
        const logged_in = (try session.get(bool, "authenticated")) orelse false;
        if (!logged_in) return forbidden(response, "Forbidden");

        const state = std.meta.intToEnum(QuestionState, request_data.state) catch return badRequest(response, "Invalid state");
        const modified_at = switch (state) {
            // don't track these separately
            .hidden => "modified_at",
            .unanswered => "modified_at",
            .deleted => "modified_at",

            .answering => "answering_at",
            .answered => "answered_at",
        };

        try ctx.redis_client.send(void, .{
            "HSET",
            key,
            "state",
            request_data.state,
            modified_at,
            std.time.timestamp(),
        });
    }

    try response.writer().print("OK", .{});
}

pub fn deleteAllQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;
    if (!logged_in) return forbidden(response, "Forbidden");

    try ctx.redis_client.send(void, .{ "COPY", "nochfragen:questions-end", "nochfragen:questions-start", "REPLACE" });

    try response.writer().print("OK", .{});
}
