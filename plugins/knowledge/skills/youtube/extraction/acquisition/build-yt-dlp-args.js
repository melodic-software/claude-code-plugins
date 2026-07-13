/**
 * yt-dlp CLI argument construction for YouTube acquisition.
 */

export const YT_DLP_SUB_LANGS = "en.*,-live_chat";
export const YT_DLP_SUB_FORMAT = "vtt";
// biome-ignore lint/security/noSecrets: yt-dlp format selector string, not a credential
export const YT_DLP_VIDEO_FORMAT = "bestvideo[height<=1080]+bestaudio/best[height<=1080]";
export const YT_DLP_EXTRACTOR_ARGS = "youtube:max_comments=20,all,top;comment_sort=top";
export const YT_DLP_RETRIES = "3";
export const YT_DLP_FRAGMENT_RETRIES = "3";
export const YT_DLP_SLEEP_REQUESTS_SEC = "1";
export const YT_DLP_SLEEP_SUBTITLES_SEC = "2";
export const YT_DLP_CAPTION_ONLY_SLEEP_SUBTITLES_SEC = "10";

export const YT_DLP_COOKIES_FILE_ENV = "YOUTUBE_YT_DLP_COOKIES_FILE";
export const YT_DLP_COOKIES_FROM_BROWSER_ENV = "YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER";
export const YT_DLP_JS_RUNTIMES_ENV = "YOUTUBE_YT_DLP_JS_RUNTIMES";

/**
 * @typedef {'full' | 'video-only' | 'transcript' | 'captions-only'} AcquisitionMode
 */

/**
 * @typedef {{ cookiesFile?: string, cookiesFromBrowser?: string }} YtDlpAuthOverride
 */

/**
 * Auth / extractor runtime flags from environment (never commit cookie files).
 *
 * `YOUTUBE_YT_DLP_COOKIES_FILE` — path to Netscape cookies.txt
 * `YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER` — e.g. `chrome`, `firefox`, `edge` (file wins if both set)
 * `YOUTUBE_YT_DLP_JS_RUNTIMES` — default `node`; set `off` to omit `--js-runtimes`
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
      : env[YT_DLP_COOKIES_FILE_ENV]?.trim();
  const cookiesBrowser =
    authOverride.cookiesFromBrowser !== undefined
      ? authOverride.cookiesFromBrowser
      : env[YT_DLP_COOKIES_FROM_BROWSER_ENV]?.trim();

  if (cookiesFile) {
    args.push("--cookies", cookiesFile);
  } else if (cookiesBrowser) {
    args.push("--cookies-from-browser", cookiesBrowser);
  }

  const jsRuntimes = env[YT_DLP_JS_RUNTIMES_ENV]?.trim();
  if (jsRuntimes === "off" || jsRuntimes === "0") {
    return args;
  }
  args.push("--js-runtimes", jsRuntimes && jsRuntimes.length > 0 ? jsRuntimes : "node");
  return args;
}

/**
 * Build yt-dlp argument list for YouTube acquisition.
 *
 * @param {string} url - YouTube watch URL
 * @param {object} options
 * @param {AcquisitionMode} [options.mode='full'] - transcript mode skips video download
 * @param {string} options.outputTemplate - yt-dlp -o template (includes ext placeholders)
 * @param {string} options.workDir - OS temp working directory for downloads
 * @param {number} [options.sleepSubtitlesSec] - override --sleep-subtitles
 * @param {NodeJS.ProcessEnv} [options.env] - env for auth flags (defaults to process.env)
 * @param {YtDlpAuthOverride} [options.authOverride] - per-invocation cookie override
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
    "--write-comments",
    "--extractor-args",
    YT_DLP_EXTRACTOR_ARGS,
  ];

  const includeCaptions = mode === "full" || mode === "transcript" || mode === "captions-only";
  if (includeCaptions) {
    args.push(
      "--sleep-subtitles",
      String(sleepSubtitlesSec),
      "--write-subs",
      "--write-auto-subs",
      "--sub-langs",
      YT_DLP_SUB_LANGS,
      "--sub-format",
      YT_DLP_SUB_FORMAT,
    );
  }

  if (mode === "transcript" || mode === "captions-only") {
    args.push("--skip-download");
  } else {
    args.push("-f", YT_DLP_VIDEO_FORMAT, "--remux-video", "mp4");
  }

  args.push(...resolveYtDlpAuthArgs(env, authOverride));
  args.push(url);
  return args;
}
