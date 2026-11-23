
export function parseUrl(value) {
  if (typeof value !== "string" || /\s/.test(value) || value.length === 0) return null;
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

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
