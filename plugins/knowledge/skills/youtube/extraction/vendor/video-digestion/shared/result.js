/**
 * Result type for video-digestion pipeline operations.
 *
 * Every stage returns a Result - explicit success/failure with timing,
 * operation name, and context. No silent catches, no null returns.
 *
 * @typedef {Object} ResultContext
 * @property {string} [label]
 */

/**
 * @typedef {Object} Result
 * @property {boolean} success
 * @property {*} data - the extracted value (null on failure)
 * @property {string|null} error - human-readable error message (null on success)
 * @property {string} operation - what was attempted (e.g., "extract-transcript")
 * @property {number} durationMs - how long the operation took
 * @property {ResultContext|null} [context] - additional context (lesson, module, URL)
 */

/**
 * Create a success result.
 * @template T
 * @param {T} data
 * @param {string} operation
 * @param {ResultContext|null} context
 * @param {number} durationMs
 * @returns {Result}
 */
export function ok(data, operation, context, durationMs) {
  return { success: true, data, error: null, operation, durationMs, context };
}

/**
 * Create a failure result.
 * @param {string} error
 * @param {string} operation
 * @param {ResultContext|null} context
 * @param {number} durationMs
 * @returns {Result}
 */
export function fail(error, operation, context, durationMs) {
  return { success: false, data: null, error, operation, durationMs, context };
}

/**
 * Wrap an async function with timing and automatic result creation.
 * Returns ok() on success, fail() on error - never throws.
 * @template T
 * @param {string} operation
 * @param {ResultContext|null} context
 * @param {() => Promise<T>} fn
 * @returns {Promise<Result>}
 */
export async function timed(operation, context, fn) {
  const start = performance.now();
  try {
    const data = await fn();
    return ok(data, operation, context, performance.now() - start);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return fail(msg, operation, context, performance.now() - start);
  }
}
