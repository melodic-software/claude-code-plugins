/**
 * VideoMetadata domain model parsed from yt-dlp info JSON.
 */

/**
 * @typedef {Object} VideoChapter
 * @property {number} startSec
 * @property {string} title
 */

/**
 * @typedef {Object} VideoComment
 * @property {string} text
 * @property {boolean} is_pinned
 */

/**
 * @typedef {Object} VideoMetadata
 * @property {string} id
 * @property {string} title
 * @property {string} description
 * @property {VideoChapter[]} chapters
 * @property {object|null} heatmap
 * @property {VideoComment[]} comments
 */

/**
 * @param {unknown} value
 * @returns {number}
 */
function toSeconds(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}

/**
 * Map a raw yt-dlp array field through a per-entry parser, dropping non-object
 * entries and the ones the parser rejects.
 *
 * @template T
 * @param {unknown} rawEntries
 * @param {(record: Record<string, unknown>) => T | null} parseEntry
 * @returns {T[]}
 */
function parseEntries(rawEntries, parseEntry) {
  if (!Array.isArray(rawEntries)) return [];

  return rawEntries
    .map((entry) => (entry && typeof entry === "object" ? parseEntry(entry) : null))
    .filter((parsed) => parsed !== null);
}

/**
 * Parse chapters from yt-dlp info JSON.
 *
 * @param {unknown} rawChapters
 * @returns {VideoChapter[]}
 */
export function parseChapters(rawChapters) {
  return parseEntries(rawChapters, (record) => {
    const title = typeof record.title === "string" ? record.title.trim() : "";
    if (!title) return null;
    return {
      startSec: toSeconds(record.start_time ?? record.startTime),
      title,
    };
  });
}

/**
 * Parse comments from yt-dlp info JSON.
 *
 * @param {unknown} rawComments
 * @returns {VideoComment[]}
 */
export function parseComments(rawComments) {
  return parseEntries(rawComments, (record) => {
    const text = typeof record.text === "string" ? record.text.trim() : "";
    if (!text) return null;
    return {
      text,
      is_pinned: record.is_pinned === true,
    };
  });
}

/**
 * Parse yt-dlp info JSON into VideoMetadata.
 *
 * @param {unknown} infoJson
 * @returns {VideoMetadata}
 */
export function parseVideoMetadata(infoJson) {
  const record =
    infoJson && typeof infoJson === "object"
      ? /** @type {Record<string, unknown>} */ (infoJson)
      : {};

  const id = typeof record.id === "string" ? record.id : "";
  const title = typeof record.title === "string" ? record.title : "";
  const description = typeof record.description === "string" ? record.description : "";
  const heatmap =
    record.heatmap && typeof record.heatmap === "object"
      ? /** @type {object} */ (record.heatmap)
      : null;

  return {
    id,
    title,
    description,
    chapters: parseChapters(record.chapters),
    heatmap,
    comments: parseComments(record.comments),
  };
}

/**
 * Find pinned comment text when present.
 *
 * @param {VideoComment[]} comments
 * @returns {string|null}
 */
export function findPinnedComment(comments) {
  const pinned = comments.find((comment) => comment.is_pinned);
  return pinned?.text ?? null;
}
