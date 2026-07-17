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
 * Build the per-video work slice slug: kebab-case title (40-char cap) + video id suffix.
 *
 * @param {string} title
 * @param {string} videoId
 * @returns {string}
 */
export function deriveVideoSlug(title, videoId) {
  const base = slugifyTitle(title).slice(0, MAX_TITLE_CHARS).replace(/-+$/g, "");
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
