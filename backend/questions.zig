const std = @import("std");
const http = @import("apple_pie");
const sqlite = @import("sqlite");

const json = std.json;

const Store = @import("sessions/Store.zig");
const Context = @import("Context.zig");
const printTime = @import("time.zig").printTime;

const responses = @import("responses.zig");
const forbidden = responses.forbidden;
const badRequest = responses.badRequest;
const ok = responses.ok;

const max_question_len = 500;

const create_table_questions_query =
    \\CREATE TABLE IF NOT EXISTS "questions" (
    \\  "id"  INTEGER NOT NULL UNIQUE,
    \\  "text"  TEXT NOT NULL,
    \\  "upvotes"  INTEGER NOT NULL,
    \\  "state"  INTEGER NOT NULL,
    \\  "created_at"  INTEGER NOT NULL,
    \\  "modified_at"  INTEGER NOT NULL,
    \\  "answering_at"  INTEGER NOT NULL,
    \\  "answered_at"  INTEGER NOT NULL,
    \\  PRIMARY KEY("id" AUTOINCREMENT)
    \\);
;

const insert_question_query =
    \\INSERT INTO questions(
    \\  "text",
    \\  "upvotes",
    \\  "state",
    \\  "created_at",
    \\  "modified_at",
    \\  "answering_at",
    \\  "answered_at"
    \\) VALUES(
    \\  @text,
    \\  @upvotes,
    \\  @state,
    \\  @created_at,
    \\  @modified_at,
    \\  @answering_at,
    \\  @answered_at
    \\);
;

const list_questions_visible_query = std.fmt.comptimePrint(
    \\SELECT
    \\  "id",
    \\  "text",
    \\  "upvotes",
    \\  "state",
    \\  "created_at",
    \\  "modified_at",
    \\  "answering_at",
    \\  "answered_at"
    \\FROM questions
    \\WHERE
    \\  state = {} OR
    \\  state = {} OR
    \\  state = {}
, .{
    @enumToInt(QuestionState.unanswered),
    @enumToInt(QuestionState.answering),
    @enumToInt(QuestionState.answered),
});

const list_questions_all_query =
    \\SELECT
    \\  "id",
    \\  "text",
    \\  "upvotes",
    \\  "state",
    \\  "created_at",
    \\  "modified_at",
    \\  "answering_at",
    \\  "answered_at"
    \\FROM questions
;

const increment_upvotes_query =
    \\UPDATE questions SET upvotes = upvotes + 1 WHERE id = @id;
;

const modify_question_query =
    \\UPDATE questions SET
    \\  state = @state,
    \\  modified_at = @modified_at
    \\WHERE id = @id;
;

const answering_question_query = std.fmt.comptimePrint(
    \\UPDATE questions SET
    \\  state = {},
    \\  answering_at = @answering_at
    \\WHERE id = @id;
, .{
    @enumToInt(QuestionState.answering),
});

const answered_question_query = std.fmt.comptimePrint(
    \\UPDATE questions SET
    \\  state = {},
    \\  answered_at = @answered_at
    \\WHERE id = @id;
, .{
    @enumToInt(QuestionState.answered),
});

const delete_all_questions_query =
    \\DELETE FROM questions;
;

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
    id: u64 = 0, // TODO remove default value
    text: []const u8,
    upvotes: u32 = 0,
    state: QuestionState = .unanswered,
    created_at: i64,
    modified_at: i64,
    answering_at: i64,
    answered_at: i64,
};
// TODO remove
const QuestionInternal = struct {
    text: []const u8,
    upvotes: u32 = 0,
    state: u32 = @enumToInt(QuestionState.unanswered),
    created_at: i64,
    modified_at: i64 = -1,
    answering_at: i64 = -1,
    answered_at: i64 = -1,
};
const QuestionInternalWithoutId = struct {
    text: sqlite.Text,
    upvotes: u32 = 0,
    state: u32 = @enumToInt(QuestionState.unanswered),
    created_at: i64,
    modified_at: i64 = -1,
    answering_at: i64 = -1,
    answered_at: i64 = -1,
};
// TODO rename to `QuestionInternal`
const QuestionInternalSqlite = struct {
    id: u64,
    text: sqlite.Text,
    upvotes: u32 = 0,
    state: u32 = @enumToInt(QuestionState.unanswered),
    created_at: i64,
    modified_at: i64 = -1,
    answering_at: i64 = -1,
    answered_at: i64 = -1,
};

const QuestionIterator = struct {
    allocator: std.mem.Allocator,
    statement: sqlite.DynamicStatement,
    iterator: sqlite.Iterator(QuestionInternalSqlite),

    fn init(allocator: std.mem.Allocator, db: *sqlite.Db, include_hidden: bool) !QuestionIterator {
        const query = if (include_hidden)
            list_questions_all_query
        else
            list_questions_visible_query;

        var statement = try db.prepareDynamic(query);

        return QuestionIterator{
            .allocator = allocator,
            .statement = statement,
            .iterator = try statement.iterator(QuestionInternalSqlite, .{}),
        };
    }

    fn deinit(self: *QuestionIterator) void {
        self.statement.deinit();
    }

    fn next(self: *QuestionIterator) !?Question {
        const question_internal_maybe = try self.iterator.nextAlloc(self.allocator, .{});
        const question_internal = question_internal_maybe orelse return null;

        return Question{
            .id = question_internal.id,
            .text = question_internal.text.data,
            .upvotes = question_internal.upvotes,
            .state = std.meta.intToEnum(QuestionState, question_internal.state) catch .deleted,
            .created_at = question_internal.created_at,
            .modified_at = question_internal.modified_at,
            .answering_at = question_internal.answering_at,
            .answered_at = question_internal.answered_at,
        };
    }
};

pub fn initializeDatabase(db: *sqlite.Db) !void {
    try db.exec(create_table_questions_query, .{}, .{});
}

pub fn listQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;

    var iter = try QuestionIterator.init(allocator, &ctx.db, logged_in);
    defer iter.deinit();

    var json_write_stream = std.json.writeStream(response.writer(), 4);
    try json_write_stream.beginArray();

    while (try iter.next()) |question| {
        if (question.state == .deleted) continue;

        const str_id = try std.fmt.allocPrint(allocator, "question:{}", .{question.id});
        const upvoted = (try session.get(bool, str_id)) orelse false;

        try json_write_stream.arrayElem();
        try json_write_stream.beginObject();

        try json_write_stream.objectField("id");
        try json_write_stream.emitNumber(question.id);

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
    response.close = true;
}

pub fn exportQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;
    if (!logged_in) return forbidden(response, "Forbidden");

    var iter = try QuestionIterator.init(allocator, &ctx.db, true);
    defer iter.deinit();

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

    try ctx.db.exec(insert_question_query, .{}, QuestionInternalWithoutId{
        .text = sqlite.Text{ .data = request_data.text },
        .created_at = std.time.timestamp(),
    });

    try ok(response);
}

pub fn modifyQuestion(ctx: *Context, response: *http.Response, request: http.Request, raw_id: []const u8) !void {
    const allocator = request.arena;

    const id = std.fmt.parseInt(u32, raw_id, 10) catch return badRequest(response, "Invalid ID");

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    if (session.is_new) return forbidden(response, "Access denied");

    var token_stream = json.TokenStream.init(request.body());
    const request_data = json.parse(
        struct {
            upvote: bool,
            state: u32,
        },
        &token_stream,
        .{ .allocator = allocator },
    ) catch return badRequest(response, "Invalid JSON");

    if (request_data.upvote) {
        const str_id = try std.fmt.allocPrint(allocator, "question:{}", .{id});

        const upvoted = (try session.get(bool, str_id)) orelse false;
        if (upvoted) return forbidden(response, "Already upvoted");

        try ctx.db.exec(increment_upvotes_query, .{}, .{ .id = id });

        try session.set(bool, str_id, true);
    } else {
        const logged_in = (try session.get(bool, "authenticated")) orelse false;
        if (!logged_in) return forbidden(response, "Forbidden");

        const state = std.meta.intToEnum(QuestionState, request_data.state) catch
            return badRequest(response, "Invalid state");
        switch (state) {
            // don't track these separately
            .hidden,
            .unanswered,
            .deleted,
            => try ctx.db.exec(modify_question_query, .{}, .{
                .state = request_data.state,
                .modified_at = std.time.timestamp(),
                .id = id,
            }),

            .answering => try ctx.db.exec(answering_question_query, .{}, .{
                .answering_at = std.time.timestamp(),
                .id = id,
            }),

            .answered => try ctx.db.exec(answered_question_query, .{}, .{
                .answered_at = std.time.timestamp(),
                .id = id,
            }),
        }
    }

    try ok(response);
}

pub fn deleteAllQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;
    if (!logged_in) return forbidden(response, "Forbidden");

    try ctx.db.exec(delete_all_questions_query, .{}, .{});

    try ok(response);
}
