/**
 * Domain models for the harvesting capability slice.
 */

/**
 * @typedef {'description'|'chapter'|'pinned-comment'|'on-screen'|'heatmap'} HarvestSource
 */

/**
 * Link harvested from video metadata or vision reads.
 *
 * @typedef {Object} HarvestedLink
 * @property {string} url - Normalized URL
 * @property {HarvestSource} source
 * @property {string} [context] - Surrounding text or chapter title
 * @property {number|null} [timestampSec] - Chapter start or on-screen capture time
 */

export {};
