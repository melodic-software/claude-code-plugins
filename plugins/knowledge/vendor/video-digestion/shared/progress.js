/**
 * Progress tracker for long-running video-digestion pipeline runs.
 *
 * Provides per-item progress lines with elapsed time and ETA,
 * plus a structured run report for post-run diagnostics.
 */

import { writeStdout } from "./terminal.js";

/** @type {ProgressLogger} */
const defaultProgressLogger = { info: (...args) => writeStdout(...args) };

/**
 * @typedef {Object} ProgressItemResult
 * @property {boolean} success
 * @property {number} [chars]
 * @property {string} [error]
 * @property {number} durationMs
 */

/**
 * @typedef {Object} ProgressItemRecord
 * @property {number} index
 * @property {string} label
 * @property {'success' | 'failed'} status
 * @property {number} durationMs
 * @property {number|null} chars
 * @property {string|null} error
 */

/**
 * @typedef {Object} ProgressRunReport
 * @property {string} timestamp
 * @property {number} totalItems
 * @property {number} processed
 * @property {number} succeeded
 * @property {number} failed
 * @property {number} skipped
 * @property {number} totalDurationMs
 * @property {number} averageItemMs
 * @property {Record<string, unknown>} [environment]
 * @property {Record<string, unknown>} [phases]
 * @property {Record<string, number>} [errorCategories]
 * @property {ProgressItemRecord[]} items
 */

/**
 * @typedef {Object} ProgressLogger
 * @property {(...args: unknown[]) => void} info
 */

/**
 * @typedef {Object} ProgressTrackerOptions
 * @property {ProgressLogger} [logger]
 */

/**
 * @typedef {Object} ProgressFinishOptions
 * @property {Record<string, unknown>} [environment]
 * @property {Record<string, unknown>} [phases]
 */

/**
 * @typedef {Object} ProgressTracker
 * @property {() => void} start
 * @property {(index: number, label: string, result: ProgressItemResult) => void} item
 * @property {(options?: ProgressFinishOptions) => ProgressRunReport} finish
 * @property {() => ProgressRunReport | null} report
 */

/**
 * Format milliseconds as human-readable duration (e.g., "3m 12s").
 * @param {number} ms
 * @returns {string}
 */
function formatDuration(ms) {
  const sec = Math.round(ms / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  const rem = sec % 60;
  if (min < 60) return `${min}m ${rem}s`;
  const hr = Math.floor(min / 60);
  return `${hr}h ${min % 60}m`;
}

/**
 * Create a progress tracker for a batch operation.
 *
 * @param {number} totalItems - total number of items to process
 * @param {ProgressTrackerOptions} [options]
 * @returns {ProgressTracker}
 */
export function createTracker(totalItems, { logger } = {}) {
  const out = logger ?? defaultProgressLogger;
  let startTime = 0;
  /** @type {ProgressItemRecord[]} */
  const items = [];
  /** @type {number[]} */
  const recentDurations = [];
  const ETA_WINDOW = 10;
  /** @type {ProgressRunReport | null} */
  let finishedReport = null;

  return {
    start() {
      startTime = performance.now();
    },

    /**
     * Record a processed item and log a progress line.
     * @param {number} index - 1-based item index
     * @param {string} label - item name/title
     * @param {ProgressItemResult} result
     */
    item(index, label, result) {
      const elapsed = performance.now() - startTime;
      const status = result.success ? "OK" : "FAIL";
      let detail = "";
      if (!result.success) {
        detail = result.error || "error";
      } else if (result.chars) {
        detail = `${result.chars} chars`;
      }

      recentDurations.push(result.durationMs);
      if (recentDurations.length > ETA_WINDOW) recentDurations.shift();

      const avgMs = recentDurations.reduce((a, b) => a + b, 0) / recentDurations.length;
      const remaining = totalItems - index;
      const etaMs = avgMs * remaining;

      const parts = [`  [${index}/${totalItems}]`, `"${label.substring(0, 40)}"`, `— ${status}`];
      if (detail) parts.push(`(${detail}, ${formatDuration(result.durationMs)})`);
      else parts.push(`(${formatDuration(result.durationMs)})`);
      parts.push(`| Elapsed: ${formatDuration(elapsed)}`);
      if (remaining > 0 && items.length >= 2) {
        parts.push(`| ETA: ~${formatDuration(etaMs)}`);
      }

      out.info(parts.join(" "));

      items.push({
        index,
        label,
        status: result.success ? "success" : "failed",
        durationMs: Math.round(result.durationMs),
        chars: result.chars ?? null,
        error: result.error ?? null,
      });
    },

    /**
     * Finalize tracking and return the report.
     * Accepts optional environment and phase timing for enriched diagnostics.
     *
     * @param {ProgressFinishOptions} [options]
     * @returns {ProgressRunReport}
     */
    finish(options = {}) {
      const totalDurationMs = performance.now() - startTime;
      const succeeded = items.filter((i) => i.status === "success").length;
      const failed = items.filter((i) => i.status === "failed").length;

      /** @type {Record<string, number>} */
      const errorCategories = {};
      for (const item of items) {
        if (item.error) {
          errorCategories[item.error] = (errorCategories[item.error] || 0) + 1;
        }
      }

      const totalItemMs = items.reduce((sum, i) => sum + i.durationMs, 0);
      const averageItemMs = items.length > 0 ? Math.round(totalItemMs / items.length) : 0;

      finishedReport = {
        timestamp: new Date().toISOString(),
        totalItems,
        processed: items.length,
        succeeded,
        failed,
        skipped: totalItems - items.length,
        totalDurationMs: Math.round(totalDurationMs),
        averageItemMs,
        ...(options.environment && { environment: options.environment }),
        ...(options.phases && { phases: options.phases }),
        ...(Object.keys(errorCategories).length > 0 && { errorCategories }),
        items,
      };

      return finishedReport;
    },

    /**
     * Get the report (call after finish()).
     * @returns {ProgressRunReport | null}
     */
    report() {
      return finishedReport;
    },
  };
}
