const std = @import("std");
const epoch = std.time.epoch;

/// Prints a UNIX timestamp in ISO 8601 format
/// (e.g. 2023-03-31T16:23:07Z). Timezone is UTC.
///
/// negative values are treated as no timestamp and instead '-' is
/// printed.
pub fn printTime(timestamp: i64, writer: anytype) !void {
    if (timestamp < 0) {
        try writer.writeAll("-");
        return;
    }

    // seconds since unix epoch UTC
    const epoch_seconds: epoch.EpochSeconds = .{ .secs = @intCast(u64, timestamp) };

    // days since epoch
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1;

    // time since day start
    const day_seconds = epoch_seconds.getDaySeconds();
    const hours = day_seconds.getHoursIntoDay();
    const minutes = day_seconds.getMinutesIntoHour();
    const seconds = day_seconds.getSecondsIntoMinute();

    try writer.print(
        "{:0>4}-{:0>2}-{:0>2}T{:0>2}:{:0>2}:{:0>2}Z",
        .{ year, month, day, hours, minutes, seconds },
    );
}
