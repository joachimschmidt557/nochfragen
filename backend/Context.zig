const okredis = @import("okredis");
const Client = okredis.BufferedClient;

redis_client: Client,
root_dir: []const u8,
