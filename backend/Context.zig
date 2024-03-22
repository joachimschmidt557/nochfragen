const okredis = @import("okredis");
const sqlite = @import("sqlite");

redis_client: okredis.BufferedClient,
db: sqlite.Db,
root_dir: []const u8,

imprint_url: []const u8,
privacy_policy_url: []const u8,
