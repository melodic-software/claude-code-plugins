/**
 * yt-dlp auth fallback — login-required detection and browser cookie profiles.
 *
 * Login-required classification is per-source, declared by each adapter's
 * `errorPatterns` and evaluated through the contract's `classifyErrorDetail`;
 * the cookie-profile retry hints are shared machinery (they describe LOCAL
 * browser-profile extraction failures, not source behavior).
 */

import { classifyErrorDetail } from "../adapters/adapter-contract.js";
import { resolveEnvWithLegacy } from "../lib/env-compat.js";
import {
  LEGACY_YT_DLP_COOKIES_FILE_ENV,
  LEGACY_YT_DLP_COOKIES_FROM_BROWSER_ENV,
  YT_DLP_COOKIES_FILE_ENV,
  YT_DLP_COOKIES_FROM_BROWSER_ENV,
} from "./build-yt-dlp-args.js";

/** @type {readonly RegExp[]} */
export const YOUTUBE_BOT_CHALLENGE_PATTERNS = [
  /confirm you(?:'|')re not a bot/i,
  /Sign in to confirm/i,
  /use --cookies-from-browser/i,
];

/** @type {readonly RegExp[]} */
export const COOKIE_PROFILE_RETRY_HINT_PATTERNS = [
  /unsupported browser/i,
  /could not find .* cookies/i,
  /Failed to decrypt with DPAPI/i,
  /extracting cookies/i,
  /no such browser/i,
];

/**
 * Whether a failed browser-cookie-profile attempt should advance to the next
 * profile (the profile was unusable, or the source still demands login).
 *
 * @param {string} detail
 * @param {import('../adapters/adapter-contract.js').SourceErrorPatterns} errorPatterns -
 *   the source adapter's declared taxonomy table
 * @returns {boolean}
 */
export function isCookieProfileRetryableError(detail, errorPatterns) {
  if (!detail) return false;
  return (
    classifyErrorDetail(errorPatterns, detail) === "login-required" ||
    COOKIE_PROFILE_RETRY_HINT_PATTERNS.some((pattern) => pattern.test(detail))
  );
}

/**
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {boolean}
 */
export function hasExplicitYtDlpCookieConfig(env = process.env) {
  return Boolean(
    resolveEnvWithLegacy(YT_DLP_COOKIES_FILE_ENV, LEGACY_YT_DLP_COOKIES_FILE_ENV, env)?.trim() ||
      resolveEnvWithLegacy(
        YT_DLP_COOKIES_FROM_BROWSER_ENV,
        LEGACY_YT_DLP_COOKIES_FROM_BROWSER_ENV,
        env,
      )?.trim(),
  );
}

/**
 * Platform-ordered browser profiles for automatic `--cookies-from-browser` fallback.
 *
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {readonly string[]}
 */
export function browserCookieFallbackProfiles(env = process.env) {
  const explicit = resolveEnvWithLegacy(
    YT_DLP_COOKIES_FROM_BROWSER_ENV,
    LEGACY_YT_DLP_COOKIES_FROM_BROWSER_ENV,
    env,
  )?.trim();
  if (explicit) {
    return [explicit];
  }
  return platformBrowserCookieOrder();
}

/**
 * @returns {readonly string[]}
 */
export function platformBrowserCookieOrder() {
  if (process.platform === "win32") {
    return ["edge", "chrome", "firefox", "brave", "chromium"];
  }
  if (process.platform === "darwin") {
    return ["chrome", "safari", "firefox", "brave", "chromium", "edge"];
  }
  return ["chrome", "chromium", "firefox", "brave", "edge"];
}
