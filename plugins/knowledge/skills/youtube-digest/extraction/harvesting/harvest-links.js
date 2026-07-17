/**
 * Harvest reference links from YouTube metadata (description, chapters, pinned comment).
 *
 * On-screen URLs are captured during skill-side frame reads and merged separately.
 * Heatmap is null-tolerant — optional context only, never required.
 */

import { findPinnedComment } from "../acquisition/video-metadata.js";

/** @typedef {import('../acquisition/video-metadata.js').VideoMetadata} VideoMetadata */
/** @typedef {import('./models.js').HarvestedLink} HarvestedLink */
/** @typedef {import('./models.js').HarvestSource} HarvestSource */

const URL_PATTERN =
  /https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z]{2,}\b(?:[-a-zA-Z0-9@:%._+~#?&/=]*)/gi;
const TRAILING_URL_PUNCTUATION_PATTERN = /[),.;]+$/;

/**
 * Extract unique URLs from free text.
 *
 * @param {string} text
 * @returns {string[]}
 */
export function extractUrlsFromText(text) {
  if (!text) return [];
  const matches = text.match(URL_PATTERN) ?? [];
  return [...new Set(matches.map((url) => url.replace(TRAILING_URL_PUNCTUATION_PATTERN, "")))];
}

/**
 * Build HarvestedLink entries from a text block.
 *
 * @param {string} text
 * @param {HarvestSource} source
 * @param {object} [meta]
 * @param {string} [meta.context]
 * @param {number|null} [meta.timestampSec]
 * @returns {HarvestedLink[]}
 */
export function linksFromText(text, source, { context = "", timestampSec = null } = {}) {
  return extractUrlsFromText(text).map((url) => {
    /** @type {HarvestedLink} */
    const link = { url, source, timestampSec };
    if (context) {
      link.context = context;
    }
    return link;
  });
}

/**
 * Harvest links from description, chapters, and pinned comment.
 *
 * @param {VideoMetadata} metadata
 * @returns {HarvestedLink[]}
 */
export function harvestMetadataLinks(metadata) {
  /** @type {HarvestedLink[]} */
  const links = [];

  links.push(...linksFromText(metadata.description, "description"));

  for (const chapter of metadata.chapters) {
    links.push(
      ...linksFromText(chapter.title, "chapter", {
        context: chapter.title,
        timestampSec: chapter.startSec,
      }),
    );
  }

  const pinned = findPinnedComment(metadata.comments);
  if (pinned) {
    links.push(...linksFromText(pinned, "pinned-comment", { context: pinned }));
  }

  return deduplicateHarvestedLinks(links);
}

/**
 * Optional heatmap context — null-tolerant, returns empty when absent.
 *
 * @param {object|null} heatmap
 * @returns {{ present: boolean, peakCount: number }}
 */
export function summarizeHeatmap(heatmap) {
  if (!heatmap || typeof heatmap !== "object") {
    return { present: false, peakCount: 0 };
  }

  const record = /** @type {Record<string, unknown>} */ (heatmap);
  const values = Array.isArray(record.values) ? record.values : [];
  return { present: true, peakCount: values.length };
}

/**
 * Deduplicate harvested links by normalized URL, keeping first occurrence.
 *
 * @param {HarvestedLink[]} links
 * @returns {HarvestedLink[]}
 */
export function deduplicateHarvestedLinks(links) {
  const seen = new Set();
  /** @type {HarvestedLink[]} */
  const unique = [];

  for (const link of links) {
    const key = link.url.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(link);
  }

  return unique;
}

/**
 * Merge metadata-harvested links with on-screen URLs from vision reads.
 *
 * @param {HarvestedLink[]} metadataLinks
 * @param {HarvestedLink[]} onScreenLinks
 * @returns {HarvestedLink[]}
 */
export function mergeHarvestedLinks(metadataLinks, onScreenLinks) {
  return deduplicateHarvestedLinks([...metadataLinks, ...onScreenLinks]);
}
