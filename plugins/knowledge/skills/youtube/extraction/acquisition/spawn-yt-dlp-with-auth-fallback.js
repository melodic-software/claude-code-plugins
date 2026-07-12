/**
 * yt-dlp spawn with rate-limit retries and automatic browser-cookie fallback on bot challenges.
 */

import { spawnFailureDetail, spawnWithAcquireRetry } from "./acquire-with-retry.js";
import {
  browserCookieFallbackProfiles,
  hasExplicitYtDlpCookieConfig,
  isCookieProfileRetryableError,
  isYoutubeBotChallengeError,
} from "./acquire-yt-dlp-auth.js";

/**
 * @typedef {import('@melodic/video-digestion/shared/process.js').SpawnResult} SpawnResult
 */

/**
 * @typedef {{ cookiesFile?: string, cookiesFromBrowser?: string }} YtDlpAuthOverride
 */

/**
 * @typedef {(authOverride?: YtDlpAuthOverride) => string[]} BuildYtDlpArgs
 */

/**
 * Invoke yt-dlp with HTTP 429 backoff, then auto-retry with local browser cookies on bot challenges.
 *
 * @param {(command: string, args: string[], options?: object) => Promise<SpawnResult>} spawn
 * @param {BuildYtDlpArgs} buildArgs
 * @param {object} [options]
 * @param {string} [options.cwd]
 * @param {NodeJS.ProcessEnv} [options.env]
 * @returns {Promise<SpawnResult>}
 */
export async function spawnYtDlpWithAuthFallback(spawn, buildArgs, options = {}) {
  const { cwd, env = process.env } = options;
  const spawnOptions = cwd ? { cwd } : {};

  if (hasExplicitYtDlpCookieConfig(env)) {
    return spawnWithAcquireRetry(spawn, "yt-dlp", buildArgs(), spawnOptions);
  }

  let result = await spawnWithAcquireRetry(spawn, "yt-dlp", buildArgs(), spawnOptions);
  if (result.success) {
    return result;
  }

  let detail = spawnFailureDetail(result);
  if (!isYoutubeBotChallengeError(detail)) {
    return result;
  }

  for (const browser of browserCookieFallbackProfiles(env)) {
    result = await spawn("yt-dlp", buildArgs({ cookiesFromBrowser: browser }), spawnOptions);
    if (result.success) {
      return result;
    }

    detail = spawnFailureDetail(result);
    if (!isCookieProfileRetryableError(detail)) {
      return result;
    }
  }

  return result;
}
