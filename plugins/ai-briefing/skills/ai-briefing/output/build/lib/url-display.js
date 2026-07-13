// Shared URL display formatter — used by build-html.js (anchor text) and
// validate.js (PDF text-layer URL coverage gate). Keep both in sync by
// importing from this single module.

/** Format URL for display — strip scheme, drop trailing slash, drop www.
 *  Truncate long paths to host + first segment + "…". Preserves
 *  x.com/{user}/status/{id} pattern by keeping host + user + "status" form. */
export function formatUrlDisplay(url) {
  try {
    const u = new URL(url);
    const host = u.hostname.replace(/^www\./, "");
    const path = u.pathname.replace(/\/$/, "");
    if (!path || path === "/") return host;
    // x.com/{user}/status/{id} → x.com/{user}/status
    if (/^(x\.com|twitter\.com)$/.test(host) && /^\/[^/]+\/status\/\d+/.test(path)) {
      const user = path.split("/")[1];
      return `${host}/${user}/status`;
    }
    // Short paths (≤32 chars) → show in full
    if (path.length <= 32) return host + path;
    // Long paths → host + first segment + ellipsis
    const segments = path.split("/").filter(Boolean);
    return `${host}/${segments[0]}/…`;
  } catch {
    return url;
  }
}
