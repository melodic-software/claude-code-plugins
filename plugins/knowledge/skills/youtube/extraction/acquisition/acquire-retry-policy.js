/**
 * Retry policy for yt-dlp acquisition — HTTP 429 and transient failures.
 */

export const DEFAULT_MAX_ACQUIRE_ATTEMPTS = 5;
export const DEFAULT_BACKOFF_BASE_MS = 2000;
export const DEFAULT_BACKOFF_MAX_MS = 60_000;
export const CAPTION_ONLY_SLEEP_SUBTITLES_SEC = 10;

/** @type {readonly RegExp[]} */
export const RETRYABLE_ACQUIRE_PATTERNS = [
  /HTTP Error 429/i,
  /Too Many Requests/i,
  /HTTP Error 503/i,
  /Service Unavailable/i,
  /Connection reset/i,
  /ECONNRESET/i,
  /ETIMEDOUT/i,
  /timed out/i,
];

/**
 * @param {string} detail
 * @returns {boolean}
 */
export function isRetryableAcquireError(detail) {
  if (!detail) return false;
  return RETRYABLE_ACQUIRE_PATTERNS.some((pattern) => pattern.test(detail));
}

/**
 * @param {number} attempt - zero-based attempt index
 * @param {object} [options]
 * @param {number} [options.baseMs]
 * @param {number} [options.maxMs]
 * @returns {number}
 */
export function computeAcquireBackoffMs(
  attempt,
  { baseMs = DEFAULT_BACKOFF_BASE_MS, maxMs = DEFAULT_BACKOFF_MAX_MS } = {},
) {
  const exponential = baseMs * 2 ** attempt;
  const capped = Math.min(exponential, maxMs);
  const jitter = Math.floor(Math.random() * Math.min(1000, capped * 0.1));
  return capped + jitter;
}

/**
 * @param {number} ms
 * @returns {Promise<void>}
 */
export function sleepMs(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}
