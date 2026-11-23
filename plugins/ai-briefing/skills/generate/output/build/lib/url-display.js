/** Format URL for display — strip scheme, drop trailing slash, drop www.
 *  Truncate long paths to host + first segment + "…". Preserves
 *  x.com/{user}/status/{id} pattern by keeping host + user + "status" form. */
export function formatUrlDisplay(url) {
  try {
    const u = new URL(url);
    const host = u.hostname.replace(/^www\./, "");
    const path = u.pathname.replace(/\/$/, "");
    if (!path || path === "/") return host;
    if (/^(x\.com|twitter\.com)$/.test(host) && /^\/[^/]+\/status\/\d+/.test(path)) {
      const user = path.split("/")[1];
      return `${host}/${user}/status`;
    }
    if (path.length <= 32) return host + path;
    const segments = path.split("/").filter(Boolean);
    return `${host}/${segments[0]}/…`;
  } catch {
    return url;
  }
}
