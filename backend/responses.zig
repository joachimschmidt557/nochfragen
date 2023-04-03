const http = @import("apple_pie");

pub fn badRequest(response: *http.Response, message: []const u8) !void {
    response.status_code = .bad_request;
    response.close = true;
    try response.writer().print("{s}\n", .{message});
}

pub fn forbidden(response: *http.Response, message: []const u8) !void {
    response.status_code = .forbidden;
    response.close = true;
    try response.writer().print("{s}\n", .{message});
}

pub fn ok(response: *http.Response) !void {
    response.close = true;
    try response.writer().print("OK", .{});
}
