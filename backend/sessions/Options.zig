const Cookie = @import("Cookie.zig");

secure: bool = true,
http_only: bool = false,
same_site: SameSiteOption = .lax,

const SameSiteOption = Cookie.SameSiteOption;
