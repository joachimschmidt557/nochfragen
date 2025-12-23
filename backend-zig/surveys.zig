const std = @import("std");
const http = @import("apple_pie");
const sqlite = @import("sqlite");
const json = std.json;

const Store = @import("sessions/Store.zig");
const Context = @import("Context.zig");

const responses = @import("responses.zig");
const forbidden = responses.forbidden;
const badRequest = responses.badRequest;
const ok = responses.ok;

const max_question_len = 500;

const create_table_surveys_query =
    \\CREATE TABLE IF NOT EXISTS "surveys" (
    \\  "id" INTEGER NOT NULL UNIQUE,
    \\  "text" TEXT NOT NULL,
    \\  "state" INTEGER NOT NULL,
    \\  PRIMARY KEY("id" AUTOINCREMENT)
    \\);
;

const create_table_survey_options_query =
    \\CREATE TABLE IF NOT EXISTS "survey_options" (
    \\  "id" INTEGER NOT NULL UNIQUE,
    \\  "survey" INTEGER NOT NULL,
    \\  "text" TEXT NOT NULL,
    \\  "votes" INTEGER NOT NULL,
    \\  PRIMARY KEY("id" AUTOINCREMENT),
    \\  FOREIGN KEY("survey") REFERENCES "surveys"("id") ON DELETE CASCADE ON UPDATE CASCADE
    \\);
;

const insert_survey_query =
    \\INSERT INTO surveys(
    \\  "text",
    \\  "state"
    \\) VALUES(
    \\  @text,
    \\  @state
    \\) RETURNING "id";
;

const insert_survey_option_query =
    \\INSERT INTO survey_options(
    \\  "survey",
    \\  "text",
    \\  "votes"
    \\) VALUES(
    \\  @survey,
    \\  @text,
    \\  @votes
    \\);
;

const list_surveys_visible_query = std.fmt.comptimePrint(
    \\SELECT
    \\  "id",
    \\  "text",
    \\  "state"
    \\FROM surveys
    \\WHERE state = {}
, .{
    @enumToInt(SurveyState.open),
});

const list_surveys_all_query =
    \\SELECT
    \\  "id",
    \\  "text",
    \\  "state"
    \\FROM surveys
;

const list_survey_options_query =
    \\SELECT
    \\  "id",
    \\  "text",
    \\  "votes"
    \\FROM survey_options
    \\WHERE survey = @survey
;

const increment_votes_query =
    \\UPDATE survey_options SET
    \\  votes = votes + 1
    \\WHERE id = @id AND survey = @survey;
;

const modify_survey_query =
    \\UPDATE surveys SET
    \\  state = @state
    \\WHERE id = @id;
;

const delete_survey_query =
    \\DELETE FROM surveys WHERE id = @id;
;

const SurveyState = enum(u32) {
    hidden,
    open,
};

const Survey = struct {
    id: u64,
    text: []const u8,
    state: SurveyState,
    options: []const Option,
};

const SurveyInternalWithoutId = struct {
    text: sqlite.Text,
    state: u32 = @enumToInt(SurveyState.hidden),
};
const SurveyInternal = struct {
    id: u64,
    text: sqlite.Text,
    state: u32 = @enumToInt(SurveyState.hidden),
};

const Option = struct {
    id: u64,
    text: []const u8,
    votes: u32 = 0,
};

const OptionInternalWithoutId = struct {
    text: sqlite.Text,
    survey: u64,
    votes: u32 = 0,
};
const OptionInternalWithoutSurvey = struct {
    id: u64,
    text: sqlite.Text,
    votes: u32 = 0,
};

const SurveyIterator = struct {
    allocator: std.mem.Allocator,
    db: *sqlite.Db,
    statement: sqlite.DynamicStatement,
    iterator: sqlite.Iterator(SurveyInternal),

    pub fn init(allocator: std.mem.Allocator, db: *sqlite.Db, include_hidden: bool) !SurveyIterator {
        const query = if (include_hidden)
            list_surveys_all_query
        else
            list_surveys_visible_query;

        var statement = try db.prepareDynamic(query);

        return SurveyIterator{
            .allocator = allocator,
            .db = db,
            .statement = statement,
            .iterator = try statement.iterator(SurveyInternal, .{}),
        };
    }

    fn deinit(self: *SurveyIterator) void {
        self.statement.deinit();
    }

    pub fn next(self: *SurveyIterator) !?Survey {
        const survey_internal_maybe = try self.iterator.nextAlloc(self.allocator, .{});
        const survey_internal = survey_internal_maybe orelse return null;

        var options = std.ArrayList(Option).init(self.allocator);

        var statement = try self.db.prepareDynamic(list_survey_options_query);
        defer statement.deinit();

        var iterator = try statement.iterator(OptionInternalWithoutSurvey, .{ .survey = survey_internal.id });
        while (try iterator.nextAlloc(self.allocator, .{})) |option_internal| {
            try options.append(.{
                .id = option_internal.id,
                .text = option_internal.text.data,
                .votes = option_internal.votes,
            });
        }

        return Survey{
            .id = survey_internal.id,
            .text = survey_internal.text.data,
            .state = std.meta.intToEnum(SurveyState, survey_internal.state) catch .open,
            .options = options.items,
        };
    }
};

pub fn initializeDatabase(db: *sqlite.Db) !void {
    _ = try db.pragma(void, .{}, "foreign_keys", "1");
    try db.exec(create_table_surveys_query, .{}, .{});
    try db.exec(create_table_survey_options_query, .{}, .{});
}

pub fn listSurveys(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;

    var iter = try SurveyIterator.init(allocator, &ctx.db, logged_in);

    var json_write_stream = std.json.writeStream(response.writer(), 6);
    try json_write_stream.beginArray();

    while (try iter.next()) |survey| {
        const str_id = try std.fmt.allocPrint(allocator, "survey:{}", .{survey.id});
        const voted = (try session.get(bool, str_id)) orelse false;

        try json_write_stream.arrayElem();
        try json_write_stream.beginObject();

        try json_write_stream.objectField("id");
        try json_write_stream.emitNumber(survey.id);

        try json_write_stream.objectField("text");
        try json_write_stream.emitString(survey.text);

        try json_write_stream.objectField("state");
        try json_write_stream.emitNumber(@enumToInt(survey.state));

        try json_write_stream.objectField("voted");
        try json_write_stream.emitBool(voted);

        try json_write_stream.objectField("options");
        try json_write_stream.beginArray();
        for (survey.options) |option| {
            try json_write_stream.arrayElem();
            try json_write_stream.beginObject();

            try json_write_stream.objectField("id");
            try json_write_stream.emitNumber(option.id);

            try json_write_stream.objectField("text");
            try json_write_stream.emitString(option.text);

            try json_write_stream.objectField("votes");
            try json_write_stream.emitNumber(option.votes);

            try json_write_stream.endObject();
        }
        try json_write_stream.endArray();

        try json_write_stream.endObject();
    }

    try json_write_stream.endArray();
    response.close = true;
}

pub fn addSurvey(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    if (session.is_new) return forbidden(response, "Access denied");

    const logged_in = (try session.get(bool, "authenticated")) orelse false;
    if (!logged_in) return forbidden(response, "Forbidden");

    var token_stream = json.TokenStream.init(request.body());
    const request_data = json.parse(
        struct { text: []const u8, options: []const []const u8 },
        &token_stream,
        .{ .allocator = allocator },
    ) catch return badRequest(response, "Invalid JSON");

    if (request_data.text.len == 0) return badRequest(response, "Empty question");
    if (request_data.text.len > max_question_len) return badRequest(response, "Maximum question length exceeded");
    if (request_data.options.len == 0) return badRequest(response, "No options provided");

    const survey_id = (try ctx.db.one(u64, insert_survey_query, .{}, SurveyInternalWithoutId{
        .text = sqlite.Text{ .data = request_data.text },
    })) orelse return error.InsertSurveyFailed;

    for (request_data.options) |option_text| {
        try ctx.db.exec(insert_survey_option_query, .{}, OptionInternalWithoutId{
            .survey = survey_id,
            .text = sqlite.Text{ .data = option_text },
        });
    }

    try ok(response);
}

pub fn modifySurvey(
    ctx: *Context,
    response: *http.Response,
    request: http.Request,
    raw_id: []const u8,
) !void {
    const allocator = request.arena;

    const id = std.fmt.parseInt(u32, raw_id, 10) catch return badRequest(response, "Invalid ID");

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    if (session.is_new) return forbidden(response, "Access denied");

    var token_stream = json.TokenStream.init(request.body());
    const request_data = json.parse(
        struct {
            mode: u32,
            vote: u32,
            state: u32,
        },
        &token_stream,
        .{ .allocator = allocator },
    ) catch return badRequest(response, "Invalid JSON");

    switch (request_data.mode) {
        0 => {
            const str_id = try std.fmt.allocPrint(allocator, "survey:{}", .{id});
            const voted = (try session.get(bool, str_id)) orelse false;
            if (voted) return forbidden(response, "Already voted");

            const vote = request_data.vote;

            try ctx.db.exec(increment_votes_query, .{}, .{
                .id = vote,
                .survey = id,
            });

            try session.set(bool, str_id, true);
        },
        1 => {
            const logged_in = (try session.get(bool, "authenticated")) orelse false;
            if (!logged_in) return forbidden(response, "Forbidden");

            _ = std.meta.intToEnum(SurveyState, request_data.state) catch
                return badRequest(response, "Invalid state");

            try ctx.db.exec(modify_survey_query, .{}, .{
                .state = request_data.state,
                .id = id,
            });
        },
        else => return badRequest(response, "Invalid mode"),
    }

    try ok(response);
}

pub fn deleteSurvey(
    ctx: *Context,
    response: *http.Response,
    request: http.Request,
    raw_id: []const u8,
) !void {
    const allocator = request.arena;

    const id = std.fmt.parseInt(u32, raw_id, 10) catch return badRequest(response, "Invalid ID");

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;
    if (!logged_in) return forbidden(response, "Forbidden");

    try ctx.db.exec(delete_survey_query, .{}, .{.id = id});

    try ok(response);
}
