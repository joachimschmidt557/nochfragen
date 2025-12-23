const Cookie = @import("Cookie.zig");
const SameSiteOption = Cookie.SameSiteOption;

secure: bool = true,
http_only: bool = false,
same_site: SameSiteOption = .lax,
