#!/usr/bin/env node
/**
 * Queue preflight: validate a YouTube URL and fetch lightweight metadata (title + channel)
 * BEFORE it is enqueued in `.work/<watch-epic>/QUEUE.md`.
 *
 * Routes through the same `spawnYtDlpWithAuthFallback` path as acquisition so a bot-checked
 * video that `watch` could acquire with browser cookies is not falsely rejected at queue time.
 *
 * Usage:
 *   node acquisition/preflight-metadata.js <youtube-url> [<youtube-url>...]
 *
 * Emits a JSON array (one entry per URL) to stdout. Each entry:
 *   { url, videoId, ok, status, action, note, reason,
 *     title, channel, handle, displayTitle, displayChannel }
 *
 * status:  ok | unavailable | transient | invalid-url
 * action:  enqueue (ok / transient) | reject (unavailable / invalid-url)
 * Exit code 2 when any URL resolves to `reject` (lets a caller fail-fast on bad input).
 */

import path from "node:path";
import { fileURLToPath } from "node:url";

import { spawnAsync } from "@melodic/video-digestion/shared/process";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { extractVideoId } from "./acquire.js";
import { spawnFailureDetail } from "./acquire-with-retry.js";
import { resolveYtDlpAuthArgs } from "./build-yt-dlp-args.js";
import { spawnYtDlpWithAuthFallback } from "./spawn-yt-dlp-with-auth-fallback.js";

/** ASCII Unit Separator — never appears in a YouTube title, so it is a safe field delimiter. */
export const PREFLIGHT_FIELD_SEP = String.fromCharCode(0x1f);

/** yt-dlp `--print` template: id, title, channel display name, channel @handle. */
export const PREFLIGHT_PRINT_TEMPLATE = [
  "%(id)s",
  "%(title)s",
  "%(channel)s",
  "%(uploader_id)s",
].join(PREFLIGHT_FIELD_SEP);

/** Display cap for the queue `title` cell (keeps the markdown table scannable). */
export const MAX_QUEUE_TITLE_CHARS = 60;

/** yt-dlp prints this literal for a null/missing field under `--print`. */
const YT_DLP_NULL_FIELD = "NA";

/**
 * stderr signatures that mean the video is permanently gone / wrong — reject, do not enqueue.
 * Everything else (bot-check, age-gate, network, unknown) is treated as transient.
 *
 * @type {readonly RegExp[]}
 */
export const PREFLIGHT_UNAVAILABLE_PATTERNS = [
  /Video unavailable/i,
  /Private video/i,
  /This video (?:is|has been) (?:no longer available|removed|private)/i,
  /removed by the uploader/i,
  /(?:account|channel) (?:.*)?has been terminated/i,
  /does not exist/i,
  /Incomplete YouTube ID/i,
  /is not a valid URL/i,
];

/**
 * Escape a value for a markdown table cell: collapse whitespace/newlines and escape `|`,
 * which would otherwise silently break the row's column count.
 *
 * @param {string} text
 * @returns {string}
 */
export function escapeTableCell(text) {
  return (text ?? "").replace(/\s+/g, " ").trim().replace(/\|/g, "\\|");
}

/**
 * Cap a title at `max` code points, appending an ellipsis when truncated.
 *
 * @param {string} text
 * @param {number} [max]
 * @returns {string}
 */
export function truncateTitle(text, max = MAX_QUEUE_TITLE_CHARS) {
  const chars = [...(text ?? "")];
  if (chars.length <= max) {
    return text ?? "";
  }
  return `${chars.slice(0, max - 1).join("")}…`;
}

/**
 * Combine channel display name and @handle into one cell value.
 *
 * @param {string} channel
 * @param {string} handle
 * @returns {string}
 */
export function formatChannel(channel, handle) {
  if (channel && handle) {
    return `${channel} (${handle})`;
  }
  return channel || handle || "";
}

/**
 * @param {string} value
 * @returns {string}
 */
function normalizeField(value) {
  const trimmed = (value ?? "").trim();
  return trimmed === YT_DLP_NULL_FIELD ? "" : trimmed;
}

/**
 * Parse the first non-empty `--print` line into its component fields.
 *
 * @param {string} stdout
 * @returns {{ id: string, title: string, channel: string, handle: string }}
 */
export function parsePreflightLine(stdout) {
  const line = (stdout ?? "")
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .find((entry) => entry.length > 0);
  const [id = "", title = "", channel = "", handle = ""] = (line ?? "").split(PREFLIGHT_FIELD_SEP);
  return {
    id: normalizeField(id),
    title: normalizeField(title),
    channel: normalizeField(channel),
    handle: normalizeField(handle),
  };
}

/**
 * @param {string} detail
 * @returns {'unavailable' | 'transient'}
 */
export function classifyPreflightFailure(detail) {
  if (detail && PREFLIGHT_UNAVAILABLE_PATTERNS.some((pattern) => pattern.test(detail))) {
    return "unavailable";
  }
  return "transient";
}

/**
 * Build the yt-dlp argument list for a metadata-only preflight probe.
 *
 * @param {string} url
 * @param {{ env?: NodeJS.ProcessEnv, authOverride?: import('./build-yt-dlp-args.js').YtDlpAuthOverride }} [options]
 * @returns {string[]}
 */
export function buildPreflightArgs(url, { env = process.env, authOverride = {} } = {}) {
  return [
    "--skip-download",
    "--no-warnings",
    "--no-playlist",
    "--print",
    PREFLIGHT_PRINT_TEMPLATE,
    ...resolveYtDlpAuthArgs(env, authOverride),
    url,
  ];
}

/**
 * @param {string} detail
 * @returns {string}
 */
function summarizeDetail(detail) {
  const firstLine = (detail ?? "")
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .find((entry) => entry.length > 0);
  const cleaned = (firstLine ?? "").replace(/^ERROR:\s*/i, "");
  return cleaned.length > 120 ? `${cleaned.slice(0, 119)}…` : cleaned;
}

/**
 * @typedef {Object} PreflightResult
 * @property {string} url
 * @property {string|null} videoId
 * @property {boolean} ok
 * @property {'ok'|'unavailable'|'transient'|'invalid-url'} status
 * @property {'enqueue'|'reject'} action
 * @property {string} note - markdown-safe notes cell value (empty for clean ok rows)
 * @property {string} reason - short human reason (failures only)
 * @property {string} title - raw title
 * @property {string} channel - raw channel display name
 * @property {string} handle - raw channel @handle
 * @property {string} displayTitle - escaped + truncated title cell
 * @property {string} displayChannel - escaped channel cell
 */

/**
 * @typedef {Object} PreflightDeps
 * @property {(command: string, args: string[], options?: object) => ReturnType<typeof spawnAsync>} [spawn]
 * @property {NodeJS.ProcessEnv} [env]
 */

/**
 * Validate a single URL and fetch its title + channel.
 *
 * @param {string} url
 * @param {PreflightDeps} [deps]
 * @returns {Promise<PreflightResult>}
 */
export async function preflightVideo(url, deps = {}) {
  const { spawn = spawnAsync, env = process.env } = deps;
  const videoId = extractVideoId(url);

  if (!videoId) {
    return {
      url,
      videoId: null,
      ok: false,
      status: "invalid-url",
      action: "reject",
      note: "not a YouTube video URL",
      reason: "URL does not resolve to a YouTube video id",
      title: "",
      channel: "",
      handle: "",
      displayTitle: "",
      displayChannel: "",
    };
  }

  const buildArgs = (
    /** @type {import('./build-yt-dlp-args.js').YtDlpAuthOverride} */ authOverride = {},
  ) => buildPreflightArgs(url, { env, authOverride });
  const result = await spawnYtDlpWithAuthFallback(spawn, buildArgs, { env });

  if (result.success) {
    const parsed = parsePreflightLine(result.stdout);
    return {
      url,
      videoId,
      ok: true,
      status: "ok",
      action: "enqueue",
      note: "",
      reason: "",
      title: parsed.title,
      channel: parsed.channel,
      handle: parsed.handle,
      displayTitle: truncateTitle(escapeTableCell(parsed.title)),
      displayChannel: escapeTableCell(formatChannel(parsed.channel, parsed.handle)),
    };
  }

  const detail = spawnFailureDetail(result);
  const status = classifyPreflightFailure(detail);
  const reason = summarizeDetail(detail);
  return {
    url,
    videoId,
    ok: false,
    status,
    action: status === "unavailable" ? "reject" : "enqueue",
    note: status === "unavailable" ? "" : `preflight: ${reason || "needs auth/cookies"}`,
    reason,
    title: "",
    channel: "",
    handle: "",
    displayTitle: "",
    displayChannel: "",
  };
}

/**
 * @param {string[]} urls
 * @param {PreflightDeps} [deps]
 * @returns {Promise<PreflightResult[]>}
 */
export async function preflightVideos(urls, deps = {}) {
  /** @type {PreflightResult[]} */
  const results = [];
  for (const url of urls) {
    results.push(await preflightVideo(url, deps));
  }
  return results;
}

/**
 * @param {string[]} argv
 * @returns {Promise<void>}
 */
async function main(argv) {
  const urls = argv.slice(2).filter((arg) => arg.length > 0);
  if (urls.length === 0) {
    writeStderr("Usage: preflight-metadata.js <youtube-url> [<youtube-url>...]");
    process.exit(1);
  }

  const results = await preflightVideos(urls);
  writeStdout(JSON.stringify(results, null, 2));

  if (results.some((entry) => entry.action === "reject")) {
    process.exit(2);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv).catch((error) => {
    writeStderr(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
