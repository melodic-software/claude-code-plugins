/**
 * yt-dlp spawn with rate-limit retries and automatic browser-cookie fallback on
 * login-required failures.
 *
 * Classification is adapter-declared: the caller passes the source's error
 * pattern table and its browser-cookie-fallback capability, and this module
 * classifies stderr through the contract's `classifyErrorDetail`. The fallback
 * loop is CLOSED BY DEFAULT — a source that does not declare the capability
 * (e.g. a cookies-file-only source) never iterates browser profiles — and it
 * fires on login-required classification only.
 */

import { classifyErrorDetail } from "../adapters/adapter-contract.js";
import { spawnFailureDetail, spawnWithAcquireRetry } from "./acquire-with-retry.js";
import {
  browserCookieFallbackProfiles,
  hasExplicitYtDlpCookieConfig,
  isCookieProfileRetryableError,
} from "./acquire-yt-dlp-auth.js";

/**
 * @typedef {import('@melodic/video-digestion/shared/process').SpawnResult} SpawnResult
 */

/**
 * @typedef {{ cookiesFile?: string, cookiesFromBrowser?: string }} YtDlpAuthOverride
 */

/**
 * @typedef {(authOverride?: YtDlpAuthOverride) => string[]} BuildYtDlpArgs
 */

/** Empty pattern table: classifies nothing, so no fallback can fire. */
const NO_ERROR_PATTERNS = Object.freeze({
  retryable: Object.freeze([]),
  fatal: Object.freeze([]),
  loginRequired: Object.freeze([]),
});

/**
 * Adapter-declared spawn classification for one source.
 *
 * @typedef {Object} SourceSpawnClassification
 * @property {import('../adapters/adapter-contract.js').SourceErrorPatterns} [errorPatterns] -
 *   the adapter's declared taxonomy table; only a login-required classification
 *   gates cookie fallback
 * @property {boolean} [allowBrowserCookieProfileFallback] - whether the
 *   browser-cookie-profile loop may iterate for this source (default false)
 */

/**
 * Invoke yt-dlp with HTTP 429 backoff, then auto-retry with local browser
 * cookies when the source classifies the failure as login-required and
 * declares the browser-cookie-fallback capability.
 *
 * @param {(command: string, args: string[], options?: object) => Promise<SpawnResult>} spawn
 * @param {BuildYtDlpArgs} buildArgs
 * @param {object} [options]
 * @param {string} [options.cwd]
 * @param {NodeJS.ProcessEnv} [options.env]
 * @param {SourceSpawnClassification} [options.source]
 * @returns {Promise<SpawnResult>}
 */
export async function spawnYtDlpWithAuthFallback(spawn, buildArgs, options = {}) {
  const { cwd, env = process.env, source = {} } = options;
  const { errorPatterns = NO_ERROR_PATTERNS, allowBrowserCookieProfileFallback = false } = source;
  const spawnOptions = cwd ? { cwd } : {};

  if (!allowBrowserCookieProfileFallback || hasExplicitYtDlpCookieConfig(env)) {
    return spawnWithAcquireRetry(spawn, "yt-dlp", buildArgs(), spawnOptions);
  }

  let result = await spawnWithAcquireRetry(spawn, "yt-dlp", buildArgs(), spawnOptions);
  if (result.success) {
    return result;
  }

  let detail = spawnFailureDetail(result);
  if (classifyErrorDetail(errorPatterns, detail) !== "login-required") {
    return result;
  }

  for (const browser of browserCookieFallbackProfiles(env)) {
    result = await spawn("yt-dlp", buildArgs({ cookiesFromBrowser: browser }), spawnOptions);
    if (result.success) {
      return result;
    }

    detail = spawnFailureDetail(result);
    if (!isCookieProfileRetryableError(detail, errorPatterns)) {
      return result;
    }
  }

  return result;
}
