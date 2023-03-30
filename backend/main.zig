const std = @import("std");
const http = @import("apple_pie");
const okredis = @import("okredis");
const clap = @import("clap");
const fs = http.FileServer;
const router = http.router;
const Client = okredis.BufferedClient;
const json = std.json;
const scrypt = std.crypto.pwhash.scrypt;

const Store = @import("Store.zig");

// TODO https://github.com/ziglang/zig/issues/7593
// pub const io_mode = .evented;

const log = std.log.scoped(.nochfragen);
const max_question_len = 500;

const State = enum(u32) {
    hidden,
    visible,
    deleted,
};

const Question = struct {
    text: []const u8,
    upvotes: u32 = 0,
    state: u32 = 1,
};

const Survey = struct {
    text: []const u8,
    options_len: u32,
    state: u32 = 0,
};

const Option = struct {
    text: []const u8,
    votes: u32 = 0,
};

const Context = struct {
    redis_client: Client,
    root_dir: []const u8,
};

const HSETQuestion = okredis.commands.hashes.HSET.forStruct(Question);
const HMGETQuestion = okredis.commands.hashes.HMGET.forStruct(Question);

const HSETSurvey = okredis.commands.hashes.HSET.forStruct(Survey);
const HMGETSurvey = okredis.commands.hashes.HMGET.forStruct(Survey);

const HSETOption = okredis.commands.hashes.HSET.forStruct(Option);
const HMGETOption = okredis.commands.hashes.HMGET.forStruct(Option);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help                     Display this help and exit.") catch unreachable,
        clap.parseParam("--set-password <PASS>          Set a new password and exit") catch unreachable,
        clap.parseParam("--listen-address <IP:PORT>     Address to listen for connections") catch unreachable,
        clap.parseParam("--redis-address <IP:PORT>      Address to connect to redis") catch unreachable,
        clap.parseParam("--root-dir <PATH>              Path to the static HTML, CSS and JS content") catch unreachable,
    };

    const parsers = comptime .{
        .PASS = clap.parsers.string,
        .PATH = clap.parsers.string,
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
    } else if (res.args.@"set-password") |pass| {
        const redis_address = res.args.@"redis-address" orelse default_redis_address;

        setPassword(allocator, redis_address, pass) catch |err| {
            log.err("Error during password setting: {}", .{err});
            std.process.exit(1);
        };
    } else {
        const listen_address = res.args.@"listen-address" orelse default_listen_address;
        const redis_address = res.args.@"redis-address" orelse default_redis_address;
        const root_dir = res.args.@"root-dir" orelse "public/";

        startServer(allocator, listen_address, redis_address, root_dir) catch |err| {
            log.err("Error during server execution: {}", .{err});
            std.process.exit(1);
        };
    }
}

const ParsedAddress = struct { ip: []const u8, port: u16 };
const default_redis_address = ParsedAddress{ .ip = "127.0.0.1", .port = 6379 };
const default_listen_address = ParsedAddress{ .ip = "127.0.0.1", .port = 8080 };

fn parseAddress(address: []const u8) !ParsedAddress {
    var iter = std.mem.split(u8, address, ":");

    const ip = iter.next() orelse return error.AddressParseError;
    const port_raw = iter.next() orelse return error.AddressParseError;
    if (iter.next() != null) return error.AddressParseError;
    const port = std.fmt.parseInt(u16, port_raw, 10) catch return error.AddressParseError;

    return ParsedAddress{ .ip = ip, .port = port };
}

fn startServer(
    allocator: std.mem.Allocator,
    listen_address: ParsedAddress,
    redis_address: ParsedAddress,
    root_dir: []const u8,
) !void {
    var context: Context = .{
        .redis_client = undefined,
        .root_dir = try allocator.dupe(u8, root_dir),
    };
    const builder = router.Builder(*Context);

    const addr = try std.net.Address.parseIp4(redis_address.ip, redis_address.port);
    var connection = std.net.tcpConnectToAddress(addr) catch return error.RedisConnectionError;

    try context.redis_client.init(connection);
    defer context.redis_client.close();

    try fs.init(allocator, .{
        .dir_path = try std.fs.path.join(allocator, &.{ root_dir, "build" }),
        .base_path = "build",
    });
    defer fs.deinit();

    @setEvalBranchQuota(10000);
    try http.listenAndServe(
        allocator,
        try std.net.Address.parseIp(listen_address.ip, listen_address.port),
        &context,
        comptime router.Router(*Context, &.{
            builder.get("/", index),
            builder.get("/build/*", serveFs),

            builder.get("/api/login", loginStatus),
            builder.post("/api/login", login),
            builder.post("/api/logout", logout),

            builder.get("/api/questions", listQuestions),
            builder.post("/api/questions", addQuestion),
            builder.delete("/api/questions", deleteAllQuestions),
            builder.put("/api/question/:id", modifyQuestion),

            builder.get("/api/export", exportQuestions),
            builder.get("/api/exportall", exportAllQuestions),

            builder.get("/api/surveys", listSurveys),
            builder.post("/api/surveys", addSurvey),
            builder.put("/api/survey/:id", modifySurvey),
        }),
    );
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

fn index(ctx: *Context, response: *http.Response, request: http.Request) !void {
    var store = Store{ .redis_client = &ctx.redis_client };
    const session = try store.get(request.arena, request, "nochfragen_session");

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

fn badRequest(response: *http.Response, message: []const u8) !void {
    response.status_code = .bad_request;
    try response.body.print("{s}\n", .{message});
}

fn forbidden(response: *http.Response, message: []const u8) !void {
    response.status_code = .forbidden;
    try response.body.print("{s}\n", .{message});
}

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

        return try self.redis_client.sendAlloc(Question, self.allocator, HMGETQuestion.init(key));
    }
};

fn listQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;

    var iter = try QuestionIterator.init(allocator, &ctx.redis_client);

    var json_write_stream = std.json.writeStream(response.writer(), 4);
    try json_write_stream.beginArray();

    while (try iter.next()) |question| {
        if (question.state != @enumToInt(State.deleted) and
            (logged_in or question.state == @enumToInt(State.visible)))
        {
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
            try json_write_stream.emitNumber(question.state);

            try json_write_stream.objectField("upvoted");
            try json_write_stream.emitBool(upvoted);

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
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;
    if (!logged_in) return forbidden(response, "Forbidden");

    var iter = try QuestionIterator.init(allocator, &ctx.redis_client);

    try response.headers.put("Content-Disposition", "attachment; filename=\"questions.txt\"");

    while (try iter.next()) |question| {
        if (question.state != @enumToInt(State.deleted) and
            (include_hidden or question.state == @enumToInt(State.visible)))
        {
            try response.writer().print("{s}\n", .{question.text});
        }
    }
}

fn addQuestion(ctx: *Context, response: *http.Response, request: http.Request) !void {
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
    try ctx.redis_client.send(void, HSETQuestion.init(key, .{ .text = request_data.text }));

    try response.writer().print("OK", .{});
}

fn modifyQuestion(ctx: *Context, response: *http.Response, request: http.Request, raw_id: []const u8) !void {
    const allocator = request.arena;

    const id = std.fmt.parseInt(u32, raw_id, 10) catch return badRequest(response, "Invalid ID");

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
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

        try ctx.redis_client.send(void, .{ "HSET", key, "state", request_data.state });
    }

    try response.writer().print("OK", .{});
}

fn loginStatus(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;

    try std.json.stringify(.{ .loggedIn = logged_in }, .{}, response.writer());
}

fn login(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var token_stream = json.TokenStream.init(request.body());
    const request_data = json.parse(
        struct { password: []const u8 },
        &token_stream,
        .{ .allocator = allocator },
    ) catch return badRequest(response, "Invalid JSON");

    const hashed_password = try ctx.redis_client.sendAlloc([]const u8, allocator, .{ "GET", "nochfragen:password" });
    scrypt.strVerify(hashed_password, request_data.password, .{ .allocator = allocator }) catch return forbidden(response, "Access denied");

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
    try session.set(bool, "authenticated", true);

    try response.writer().print("OK", .{});
}

fn logout(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
    try session.set(bool, "authenticated", false);

    try response.writer().print("OK", .{});
}

fn deleteAllQuestions(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;
    if (!logged_in) return forbidden(response, "Forbidden");

    try ctx.redis_client.send(void, .{ "COPY", "nochfragen:questions-end", "nochfragen:questions-start", "REPLACE" });

    try response.writer().print("OK", .{});
}

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
        const survey = try self.redis_client.sendAlloc(Survey, self.allocator, HMGETSurvey.init(key));

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

fn listSurveys(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
    const logged_in = (try session.get(bool, "authenticated")) orelse false;

    var iter = try SurveyIterator.init(allocator, &ctx.redis_client);

    var json_write_stream = std.json.writeStream(response.writer(), 6);
    try json_write_stream.beginArray();

    while (try iter.next()) |result| {
        const survey = result.survey;
        const options = result.options[0..survey.options_len];

        if (survey.state != @enumToInt(State.deleted) and
            (logged_in or survey.state == @enumToInt(State.visible)))
        {
            const str_id = try std.fmt.allocPrint(allocator, "survey:{}", .{iter.id - 1});
            const voted = (try session.get(bool, str_id)) orelse false;

            try json_write_stream.arrayElem();
            try json_write_stream.beginObject();

            try json_write_stream.objectField("id");
            try json_write_stream.emitNumber(iter.id - 1);

            try json_write_stream.objectField("text");
            try json_write_stream.emitString(survey.text);

            try json_write_stream.objectField("state");
            try json_write_stream.emitNumber(survey.state);

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
    }

    try json_write_stream.endArray();
}

fn addSurvey(ctx: *Context, response: *http.Response, request: http.Request) !void {
    const allocator = request.arena;

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
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

    try response.writer().print("OK", .{});
}

fn modifySurvey(ctx: *Context, response: *http.Response, request: http.Request, raw_id: []const u8) !void {
    const allocator = request.arena;

    const id = std.fmt.parseInt(u32, raw_id, 10) catch return badRequest(response, "Invalid ID");

    var store = Store{ .redis_client = &ctx.redis_client };
    var session = try store.get(allocator, request, "nochfragen_session");
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

    try response.writer().print("OK", .{});
}
