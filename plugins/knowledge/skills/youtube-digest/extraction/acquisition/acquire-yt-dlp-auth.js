/**
 * yt-dlp auth fallback — login-required detection and browser cookie profiles.
 *
 * The login-required patterns are per-source, declared by each adapter's
 * `errorPatterns.loginRequired`; the cookie-profile retry hints are shared
 * machinery (they describe LOCAL browser-profile extraction failures, not
 * source behavior).
 */

import { YT_DLP_COOKIES_FILE_ENV, YT_DLP_COOKIES_FROM_BROWSER_ENV } from "./build-yt-dlp-args.js";

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
 * @param {string} detail
 * @param {readonly RegExp[]} loginRequiredPatterns - the source adapter's declared patterns
 * @returns {boolean}
 */
export function isLoginRequiredError(detail, loginRequiredPatterns) {
  if (!detail) return false;
  return loginRequiredPatterns.some((pattern) => pattern.test(detail));
}

/**
 * Whether a failed browser-cookie-profile attempt should advance to the next
 * profile (the profile was unusable, or the source still demands login).
 *
 * @param {string} detail
 * @param {readonly RegExp[]} loginRequiredPatterns - the source adapter's declared patterns
 * @returns {boolean}
 */
export function isCookieProfileRetryableError(detail, loginRequiredPatterns) {
  if (!detail) return false;
  return (
    isLoginRequiredError(detail, loginRequiredPatterns) ||
    COOKIE_PROFILE_RETRY_HINT_PATTERNS.some((pattern) => pattern.test(detail))
  );
}

/**
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {boolean}
 */
export function hasExplicitYtDlpCookieConfig(env = process.env) {
  return Boolean(
    env[YT_DLP_COOKIES_FILE_ENV]?.trim() || env[YT_DLP_COOKIES_FROM_BROWSER_ENV]?.trim(),
  );
}

/**
 * Platform-ordered browser profiles for automatic `--cookies-from-browser` fallback.
 *
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {readonly string[]}
 */
export function browserCookieFallbackProfiles(env = process.env) {
  const explicit = env[YT_DLP_COOKIES_FROM_BROWSER_ENV]?.trim();
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
