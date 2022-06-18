/// Only send cookies over HTTPS
secure: bool = true,
/// If true, don't make this cookie available to the Document.cookie
/// JavaScript API
http_only: bool = false,
/// SameSite option
same_site: SameSiteOption = .lax,

pub const SameSiteOption = enum {
    none,
    lax,
    strict,
};
