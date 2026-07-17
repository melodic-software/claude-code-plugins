/**
 * yt-dlp spawn wrapper with exponential backoff on rate-limit errors.
 */

import {
  computeAcquireBackoffMs,
  DEFAULT_MAX_ACQUIRE_ATTEMPTS,
  isRetryableAcquireError,
  sleepMs,
} from "./acquire-retry-policy.js";

/**
 * @typedef {import('@melodic/video-digestion/shared/process.js').SpawnResult} SpawnResult
 */

/**
 * @param {SpawnResult} result
 * @returns {string}
 */
export function spawnFailureDetail(result) {
  return (result.stderr ?? "").trim() || (result.error ?? "") || "spawn failed";
}

/**
 * Invoke spawn with retries on transient / rate-limit failures.
 *
 * @param {(command: string, args: string[], options?: object) => Promise<SpawnResult>} spawn
 * @param {string} command
 * @param {string[]} args
 * @param {object} [options]
 * @param {number} [options.maxAttempts]
 * @param {(ms: number) => Promise<void>} [options.sleep]
 * @returns {Promise<SpawnResult>}
 */
export async function spawnWithAcquireRetry(spawn, command, args, options = {}) {
  const { maxAttempts = DEFAULT_MAX_ACQUIRE_ATTEMPTS, sleep = sleepMs, ...spawnOptions } = options;
  let lastResult = /** @type {SpawnResult | null} */ (null);

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    lastResult = await spawn(command, args, spawnOptions);
    if (lastResult.success) {
      return lastResult;
    }

    const detail = spawnFailureDetail(lastResult);
    const canRetry = attempt < maxAttempts - 1 && isRetryableAcquireError(detail);
    if (!canRetry) {
      return lastResult;
    }

    const waitMs = computeAcquireBackoffMs(attempt);
    await sleep(waitMs);
  }

  return (
    lastResult ?? { success: false, code: 1, signal: null, stdout: "", stderr: "", timedOut: false }
  );
}
