/**
 * yt-dlp CLI argument construction for media acquisition.
 */

import { resolveEnvWithLegacy } from "../lib/env-compat.js";

export const YT_DLP_SUB_LANGS = "en.*,-live_chat";
export const YT_DLP_SUB_FORMAT = "vtt";
// biome-ignore lint/security/noSecrets: yt-dlp format selector string, not a credential
export const YT_DLP_VIDEO_FORMAT = "bestvideo[height<=1080]+bestaudio/best[height<=1080]";
export const YT_DLP_RETRIES = "3";
export const YT_DLP_FRAGMENT_RETRIES = "3";
export const YT_DLP_SLEEP_REQUESTS_SEC = "1";
export const YT_DLP_SLEEP_SUBTITLES_SEC = "2";
export const YT_DLP_CAPTION_ONLY_SLEEP_SUBTITLES_SEC = "10";

export const YT_DLP_COOKIES_FILE_ENV = "VIDEO_DIGEST_YT_DLP_COOKIES_FILE";
export const YT_DLP_COOKIES_FROM_BROWSER_ENV = "VIDEO_DIGEST_YT_DLP_COOKIES_FROM_BROWSER";
export const YT_DLP_JS_RUNTIMES_ENV = "VIDEO_DIGEST_YT_DLP_JS_RUNTIMES";

// Deprecated pre-rename spellings, resolved through `resolveEnvWithLegacy` at
// every read site so existing environments keep working (with a warning).
export const LEGACY_YT_DLP_COOKIES_FILE_ENV = "YOUTUBE_YT_DLP_COOKIES_FILE";
export const LEGACY_YT_DLP_COOKIES_FROM_BROWSER_ENV = "YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER";
export const LEGACY_YT_DLP_JS_RUNTIMES_ENV = "YOUTUBE_YT_DLP_JS_RUNTIMES";

/**
 * @typedef {'full' | 'video-only' | 'transcript' | 'captions-only'} AcquisitionMode
 */

/**
 * @typedef {{ cookiesFile?: string, cookiesFromBrowser?: string }} YtDlpAuthOverride
 */

/**
 * Per-source yt-dlp argument declarations (adapter-declared, closed by default:
 * omitting a field means the corresponding flag is NOT pushed).
 *
 * @typedef {Object} YtDlpSourceOptions
 * @property {boolean} [writeComments] - push `--write-comments` (comments capability)
 * @property {string|null} [extractorArgs] - push `--extractor-args <value>` when non-null
 * @property {string|null} [allowedExtractors] - push `--use-extractors <value>` when
 *   non-null: refuses any delegated foreign URL without fetching it (SSRF guard)
 * @property {string} [subLangs] - override `--sub-langs` (default {@link YT_DLP_SUB_LANGS});
 *   sources whose subtitle keys are raw track languages (e.g. `und`) declare their own selector
 * @property {boolean} [omitAutoSubs] - skip `--write-auto-subs` (sources whose
 *   automatic-caption channel is never populated)
 * @property {boolean} [ignoreNoFormatsError] - push `--ignore-no-formats-error` so a
 *   0-media post resolves as a metadata-only result instead of a fatal spawn
 * @property {string} [convertSubs] - push `--convert-subs <format>` (caption cleanup pass)
 */

/**
 * Auth / extractor runtime flags from the child environment (never commit cookie files).
 *
 * These variables are the launcher-to-child interface, set by `run.mjs` from the
 * knowledge plugin's `yt_dlp_cookies_file` / `yt_dlp_cookies_from_browser` /
 * `yt_dlp_js_runtimes` userConfig options — not a consumer-facing env channel:
 * `VIDEO_DIGEST_YT_DLP_COOKIES_FILE` — path to Netscape cookies.txt
 * `VIDEO_DIGEST_YT_DLP_COOKIES_FROM_BROWSER` — e.g. `chrome`, `firefox`, `edge` (file wins if both set)
 * `VIDEO_DIGEST_YT_DLP_JS_RUNTIMES` — default `node`; `off` omits `--js-runtimes`
 * (deprecated `YOUTUBE_`-prefixed spellings of each still resolve, with a warning)
 *
 * Override wins over env when `authOverride` fields are set (used for automatic browser fallback).
 *
 * @param {NodeJS.ProcessEnv} [env]
 * @param {YtDlpAuthOverride} [authOverride]
 * @returns {string[]}
 */
export function resolveYtDlpAuthArgs(env = process.env, authOverride = {}) {
  /** @type {string[]} */
  const args = [];

  const cookiesFile =
    authOverride.cookiesFile !== undefined
      ? authOverride.cookiesFile
      : resolveEnvWithLegacy(YT_DLP_COOKIES_FILE_ENV, LEGACY_YT_DLP_COOKIES_FILE_ENV, env)?.trim();
  const cookiesBrowser =
    authOverride.cookiesFromBrowser !== undefined
      ? authOverride.cookiesFromBrowser
      : resolveEnvWithLegacy(
          YT_DLP_COOKIES_FROM_BROWSER_ENV,
          LEGACY_YT_DLP_COOKIES_FROM_BROWSER_ENV,
          env,
        )?.trim();

  if (cookiesFile) {
    args.push("--cookies", cookiesFile);
  } else if (cookiesBrowser) {
    args.push("--cookies-from-browser", cookiesBrowser);
  }

  const jsRuntimes = resolveEnvWithLegacy(
    YT_DLP_JS_RUNTIMES_ENV,
    LEGACY_YT_DLP_JS_RUNTIMES_ENV,
    env,
  )?.trim();
  if (jsRuntimes === "off" || jsRuntimes === "0") {
    return args;
  }
  args.push("--js-runtimes", jsRuntimes && jsRuntimes.length > 0 ? jsRuntimes : "node");
  return args;
}

/**
 * Build yt-dlp argument list for media acquisition.
 *
 * @param {string} url - media URL
 * @param {object} options
 * @param {AcquisitionMode} [options.mode='full'] - transcript mode skips video download
 * @param {string} options.outputTemplate - yt-dlp -o template (includes ext placeholders)
 * @param {string} options.workDir - OS temp working directory for downloads
 * @param {number|string} [options.sleepSubtitlesSec] - override --sleep-subtitles
 * @param {NodeJS.ProcessEnv} [options.env] - env for auth flags (defaults to process.env)
 * @param {YtDlpAuthOverride} [options.authOverride] - per-invocation cookie override
 * @param {YtDlpSourceOptions} [options.source] - adapter-declared flags; omitted fields push nothing
 * @returns {string[]}
 */
export function buildYtDlpArgs(
  url,
  {
    mode = "full",
    outputTemplate,
    workDir,
    sleepSubtitlesSec = YT_DLP_SLEEP_SUBTITLES_SEC,
    env = process.env,
    authOverride = {},
    source = {},
  },
) {
  /** @type {string[]} */
  const args = [
    "--no-progress",
    // A watch URL copied from a playlist carries `&list=…`; without this,
    // yt-dlp would fetch every playlist entry into the same workDir and
    // resolve artifacts for the wrong video (preflight already forces it).
    "--no-playlist",
    "--paths",
    `temp:${workDir}`,
    "-o",
    outputTemplate,
    "--retries",
    YT_DLP_RETRIES,
    "--fragment-retries",
    YT_DLP_FRAGMENT_RETRIES,
    "--sleep-requests",
    YT_DLP_SLEEP_REQUESTS_SEC,
    "--write-info-json",
  ];

  if (source.writeComments) {
    args.push("--write-comments");
  }
  if (source.extractorArgs) {
    args.push("--extractor-args", source.extractorArgs);
  }
  if (source.allowedExtractors) {
    args.push("--use-extractors", source.allowedExtractors);
  }

  const includeCaptions = mode === "full" || mode === "transcript" || mode === "captions-only";
  if (includeCaptions) {
    args.push("--sleep-subtitles", String(sleepSubtitlesSec), "--write-subs");
    if (!source.omitAutoSubs) {
      args.push("--write-auto-subs");
    }
    args.push("--sub-langs", source.subLangs ?? YT_DLP_SUB_LANGS, "--sub-format", YT_DLP_SUB_FORMAT);
    if (source.convertSubs) {
      args.push("--convert-subs", source.convertSubs);
    }
  }

  if (source.ignoreNoFormatsError) {
    args.push("--ignore-no-formats-error");
  }

  if (mode === "transcript" || mode === "captions-only") {
    args.push("--skip-download");
  } else {
    args.push("-f", YT_DLP_VIDEO_FORMAT, "--remux-video", "mp4");
  }

  args.push(...resolveYtDlpAuthArgs(env, authOverride));
  // End-of-options sentinel: the URL can never be parsed as a flag, so the
  // argv boundary defends itself instead of relying on upstream URL vetting.
  args.push("--", url);
  return args;
}
