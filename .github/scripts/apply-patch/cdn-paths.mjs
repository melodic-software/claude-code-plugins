export const CDN_RECORD = "lib/cdn-pins/pins.json";
export const CDN_MANIFEST = "lib/cdn-pins/package.json";
export const CDN_SCRIPT = "lib/cdn-pins/sync.mjs";
export const CDN_LOCK = "lib/cdn-pins/package-lock.json";
export const CDN_BUMP_PATHS = new Set([CDN_MANIFEST, CDN_LOCK]);

export function cdnPaths(record) {
  const targets = record.targets.map(({ path }) => path);
  const paths = [CDN_RECORD, ...targets];
  if (new Set(paths).size !== paths.length || targets.some((path) =>
    typeof path !== "string" || !path.split("/").every((part) => /^[\w.-]+$/.test(part) && ![".", "..", ".git"].includes(part)) ||
    CDN_BUMP_PATHS.has(path) || path === CDN_SCRIPT)) {
    throw new Error("invalid CDN pin target paths");
  }
  return paths;
}
