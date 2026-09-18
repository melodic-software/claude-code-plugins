// URL predicates shared by the setup checkers: the WHATWG parse gate and the
// telemetry contract's normalized canonical item URL.

// Parses a value as a WHATWG URL. Anything that is not a nonempty,
// whitespace-free string the parser accepts yields null.
export function parseUrl(value) {
  if (typeof value !== "string" || /\s/.test(value) || value.length === 0) return null;
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

// A normalized canonical item URL must parse as a real URL, not merely match a
// shape: https protocol, a non-empty hostname, none of query, fragment, or
// trailing slash, and it must round-trip the WHATWG parser unchanged
// (url.href === value), which is what "normalized" means. Round-tripping
// rejects values the parser silently repairs (empty host `https:///items/101`
// becomes `https://items/101`) and parsing rejects outright malformed ones
// (non-numeric port `https://h:abc/items/101`). The literal `?` and `#` tests
// are not redundant with the parsed search and hash: a bare trailing `?` or
// `#` round-trips with both parsed parts empty.
export function isNormalizedCanonicalUrl(value) {
  const url = parseUrl(value);
  return (
    url !== null &&
    url.protocol === "https:" &&
    url.hostname.length > 0 &&
    url.search === "" &&
    url.hash === "" &&
    url.href === value &&
    !value.includes("?") &&
    !value.includes("#") &&
    !value.endsWith("/")
  );
}
