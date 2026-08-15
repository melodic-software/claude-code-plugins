/**
 * yt-dlp spawn with rate-limit retries and automatic browser-cookie fallback on
 * login-required failures.
 *
 * Classification is adapter-declared: the caller passes the source's
 * login-required patterns and its browser-cookie-fallback capability. The
 * fallback loop is CLOSED BY DEFAULT — a source that does not declare the
 * capability (e.g. a cookies-file-only source) never iterates browser
 * profiles — and it fires on login-required classification only.
 */

import { spawnFailureDetail, spawnWithAcquireRetry } from "./acquire-with-retry.js";
import {
  browserCookieFallbackProfiles,
  hasExplicitYtDlpCookieConfig,
  isCookieProfileRetryableError,
  isLoginRequiredError,
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

/**
 * Adapter-declared spawn classification for one source.
 *
 * @typedef {Object} SourceSpawnClassification
 * @property {readonly RegExp[]} [loginRequiredPatterns] - stderr signatures that
 *   classify as login-required (the only class that gates cookie fallback)
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
  const { loginRequiredPatterns = [], allowBrowserCookieProfileFallback = false } = source;
  const spawnOptions = cwd ? { cwd } : {};

  if (!allowBrowserCookieProfileFallback || hasExplicitYtDlpCookieConfig(env)) {
    return spawnWithAcquireRetry(spawn, "yt-dlp", buildArgs(), spawnOptions);
  }

  let result = await spawnWithAcquireRetry(spawn, "yt-dlp", buildArgs(), spawnOptions);
  if (result.success) {
    return result;
  }

  let detail = spawnFailureDetail(result);
  if (!isLoginRequiredError(detail, loginRequiredPatterns)) {
    return result;
  }

  for (const browser of browserCookieFallbackProfiles(env)) {
    result = await spawn("yt-dlp", buildArgs({ cookiesFromBrowser: browser }), spawnOptions);
    if (result.success) {
      return result;
    }

    detail = spawnFailureDetail(result);
    if (!isCookieProfileRetryableError(detail, loginRequiredPatterns)) {
      return result;
    }
  }

  return result;
}
