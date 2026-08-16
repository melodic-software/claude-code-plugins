/**
 * Derive durable `.work/<watch-epic>/<video-slug>/` directory names from video metadata.
 */

import path from "node:path";

export const YOUTUBE_WATCH_EPIC_DIR = "youtube-watch";

const MAX_TITLE_CHARS = 40;

/**
 * @param {string} text
 * @returns {string}
 */
export function slugifyTitle(text) {
  return text
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/**
 * Slugify, cap at `maxChars`, then re-trim the trailing `-` the cut can expose.
 *
 * @param {string} text
 * @param {number} maxChars
 * @returns {string}
 */
export function capSlug(text, maxChars) {
  return slugifyTitle(text).slice(0, maxChars).replace(/-+$/g, "");
}

/**
 * Slice keys become on-disk directory segments under `.work/`, so the shared
 * slug derivation fails closed on anything that could traverse or terminate a
 * path (separators, dots, empty). Mirrors the adapter contract's
 * `extractSliceKey` invariant — a non-conforming key is an adapter bug.
 */
const SAFE_SLICE_KEY_PATTERN = /^[A-Za-z0-9_-]+$/;

/**
 * Build the per-video work slice slug: kebab-case title (40-char cap) + slice key suffix.
 *
 * @param {string} title
 * @param {string} videoId - the source adapter's slice key; must match `[A-Za-z0-9_-]+`
 * @returns {string}
 */
export function deriveVideoSlug(title, videoId) {
  if (!SAFE_SLICE_KEY_PATTERN.test(videoId)) {
    throw new Error(
      `Unsafe slice key ${JSON.stringify(videoId)}: must match [A-Za-z0-9_-]+ (it becomes a directory segment under .work/)`,
    );
  }
  const base = capSlug(title, MAX_TITLE_CHARS);
  const prefix = base || "video";
  return `${prefix}-${videoId}`;
}

/**
 * Resolve the `.work/<watch-epic>/<video-slug>/` directory under the repo root.
 *
 * @param {string} repoRoot
 * @param {string} videoSlug
 * @returns {string}
 */
export function resolveWorkSliceDir(repoRoot, videoSlug) {
  return path.join(repoRoot, ".work", YOUTUBE_WATCH_EPIC_DIR, videoSlug);
}
