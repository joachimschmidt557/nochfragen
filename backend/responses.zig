const http = @import("apple_pie");

pub fn badRequest(response: *http.Response, message: []const u8) !void {
    response.status_code = .bad_request;
    try response.body.print("{s}\n", .{message});
}

pub fn forbidden(response: *http.Response, message: []const u8) !void {
    response.status_code = .forbidden;
    try response.body.print("{s}\n", .{message});
}
