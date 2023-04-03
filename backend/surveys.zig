const std = @import("std");
const http = @import("apple_pie");
const okredis = @import("okredis");
const Client = okredis.BufferedClient;
const json = std.json;

const Store = @import("sessions/Store.zig");
const Context = @import("Context.zig");

const responses = @import("responses.zig");
const forbidden = responses.forbidden;
const badRequest = responses.badRequest;
const ok = responses.ok;

const max_question_len = 500;

const SurveyState = enum(u32) {
    hidden,
    open,
    deleted,
};

const Survey = struct {
    text: []const u8,
    options_len: u32,
    state: SurveyState = .hidden,
};
const SurveyInternal = struct {
    text: []const u8,
    options_len: u32,
    state: u32 = @enumToInt(SurveyState.hidden),
};

const Option = struct {
    text: []const u8,
    votes: u32 = 0,
};

const HSETSurvey = okredis.commands.hashes.HSET.forStruct(SurveyInternal);
const HMGETSurvey = okredis.commands.hashes.HMGET.forStruct(SurveyInternal);

const HSETOption = okredis.commands.hashes.HSET.forStruct(Option);
const HMGETOption = okredis.commands.hashes.HMGET.forStruct(Option);

const SurveyIterator = struct {
    allocator: std.mem.Allocator,
    redis_client: *Client,
    end: u32,
    id: u32,

    pub fn init(allocator: std.mem.Allocator, redis_client: *Client) !SurveyIterator {
        const survey_range = try redis_client.send([2]?u32, .{
            "MGET",
            "nochfragen:surveys-start",
            "nochfragen:surveys-end",
        });
        const start = survey_range[0] orelse 0;
        const end = survey_range[1] orelse 0;

        return SurveyIterator{
            .allocator = allocator,
            .redis_client = redis_client,
            .end = end,
            .id = start,
        };
    }

    const IteratorResult = struct {
        survey: Survey,
        options: [*]Option,
    };

    pub fn next(self: *SurveyIterator) !?IteratorResult {
        if (self.id >= self.end) return null;

        const key = try std.fmt.allocPrint(self.allocator, "nochfragen:surveys:{}", .{self.id});
        const survey_internal = try self.redis_client.sendAlloc(SurveyInternal, self.allocator, HMGETSurvey.init(key));
        const survey = Survey{
            .text = survey_internal.text,
            .options_len = survey_internal.options_len,
            .state = std.meta.intToEnum(SurveyState, survey_internal.state) catch .deleted,
        };

        const options = try self.allocator.alloc(Option, survey.options_len);
        for (options) |*option, i| {
            const option_key = try std.fmt.allocPrint(self.allocator, "nochfragen:surveys:{}:options:{}", .{ self.id, i });
            option.* = try self.redis_client.sendAlloc(Option, self.allocator, HMGETOption.init(option_key));
        }

        self.id += 1;

        return IteratorResult{
            .survey = survey,
            .options = options.ptr,
        };
    }
};

pub fn listSurveys(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;

    var iter = try SurveyIterator.init(allocator, &ctx.redis_client);

    var json_write_stream = std.json.writeStream(response.writer(), 6);
    try json_write_stream.beginArray();

    while (try iter.next()) |result| {
        const survey = result.survey;
        const options = result.options[0..survey.options_len];

        if (survey.state == .deleted) continue;
        if (!logged_in and survey.state == .hidden) continue;

        const str_id = try std.fmt.allocPrint(allocator, "survey:{}", .{iter.id - 1});
        const voted = (try session.get(bool, str_id)) orelse false;

        try json_write_stream.arrayElem();
        try json_write_stream.beginObject();

        try json_write_stream.objectField("id");
        try json_write_stream.emitNumber(iter.id - 1);

        try json_write_stream.objectField("text");
        try json_write_stream.emitString(survey.text);

        try json_write_stream.objectField("state");
        try json_write_stream.emitNumber(@enumToInt(survey.state));

        try json_write_stream.objectField("voted");
        try json_write_stream.emitBool(voted);

        try json_write_stream.objectField("options");
        try json_write_stream.beginArray();
        for (options) |option| {
            try json_write_stream.arrayElem();
            try json_write_stream.beginObject();

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

    const new_end = try ctx.redis_client.send(i64, .{ "INCR", "nochfragen:surveys-end" });
    const id = new_end - 1;

    const survey_key = try std.fmt.allocPrint(allocator, "nochfragen:surveys:{}", .{id});
    try ctx.redis_client.send(void, HSETSurvey.init(survey_key, .{
        .text = request_data.text,
        .options_len = @intCast(u32, request_data.options.len),
    }));

    for (request_data.options) |option_text, i| {
        const option_key = try std.fmt.allocPrint(allocator, "nochfragen:surveys:{}:options:{}", .{ id, i });
        try ctx.redis_client.send(void, HSETOption.init(option_key, .{ .text = option_text }));
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

    const iter = try SurveyIterator.init(allocator, &ctx.redis_client);
    if (id < iter.id or id >= iter.end) return badRequest(response, "Invalid ID");

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
            const key = try std.fmt.allocPrint(allocator, "nochfragen:surveys:{}:options:{}", .{ id, vote });
            try ctx.redis_client.send(void, .{ "HINCRBY", key, "votes", 1 });
            try session.set(bool, str_id, true);
        },
        1 => {
            const logged_in = (try session.get(bool, "authenticated")) orelse false;
            if (!logged_in) return forbidden(response, "Forbidden");

            const key = try std.fmt.allocPrint(allocator, "nochfragen:surveys:{}", .{id});
            try ctx.redis_client.send(void, .{ "HSET", key, "state", request_data.state });
        },
        else => return badRequest(response, "Invalid mode"),
    }

    try ok(response);
}
