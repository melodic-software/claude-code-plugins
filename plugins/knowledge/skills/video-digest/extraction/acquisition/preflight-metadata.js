#!/usr/bin/env node
/**
 * Queue preflight: validate a video URL and fetch lightweight metadata (title + channel)
 * BEFORE it is enqueued in `.work/<watch-epic>/QUEUE.md`.
 *
 * URL acceptance and failure classification are delegated to the owning source
 * adapter (`acceptForEnqueue` / `errorPatterns`); an unknown host fails closed
 * as `invalid-url` listing the supported sources.
 *
 * Routes through the same `spawnYtDlpWithAuthFallback` path as acquisition so a bot-checked
 * video that `watch` could acquire with browser cookies is not falsely rejected at queue time.
 *
 * Usage:
 *   node acquisition/preflight-metadata.js <video-url> [<video-url>...]
 *   node acquisition/preflight-metadata.js <video-url> [--from <h:mm:ss>] [--to <h:mm:ss>]
 *
 * Emits a JSON array (one entry per URL) to stdout. Each entry:
 *   { url, videoId, queueKey, ok, status, action, note, reason,
 *     title, channel, handle, displayTitle, displayChannel, liveStatus }
 *
 * queueKey is the QUEUE.md `video-id` cell and dedupe key: the videoId, plus the
 * `-r<fromSec>-<toSec>` range suffix for a ranged add (`rangedSliceKey`).
 *
 * status:  ok | unavailable | transient | invalid-url
 * action:  enqueue (ok / transient) | reject (unavailable / invalid-url)
 * Exit code 2 when any URL resolves to `reject` (lets a caller fail-fast on bad input).
 */

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { spawnAsync } from "@melodic/video-digestion/shared/process";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { classifyErrorDetail, UnsupportedSourceError } from "../adapters/adapter-contract.js";
import { resolveSourceAdapter } from "../adapters/registry.js";
import { parseDelegationRefusal } from "../adapters/x.js";
import { parseTimeRangeArgs, rangedSliceKey } from "../lib/time-range.js";
import { adapterSourceDeclarations } from "./acquire.js";
import { spawnFailureDetail } from "./acquire-with-retry.js";
import { resolveYtDlpAuthArgs } from "./build-yt-dlp-args.js";
import { spawnYtDlpWithAuthFallback } from "./spawn-yt-dlp-with-auth-fallback.js";

/** ASCII Unit Separator — never appears in a YouTube title, so it is a safe field delimiter. */
export const PREFLIGHT_FIELD_SEP = String.fromCharCode(0x1f);

/**
 * yt-dlp `--print` template, nine fields: id, title, channel display name, channel @handle,
 * description, repost count, comment count, like count, live status. `isEmptyPostShell` and
 * `LIVE_STATUS_FIELD` read the fields by position, so a new field is appended at the end.
 */
export const PREFLIGHT_PRINT_TEMPLATE = [
  "%(id)s",
  "%(title)s",
  "%(channel)s",
  "%(uploader_id)s",
  "%(description&D|)s",
  "%(repost_count)s",
  "%(comment_count)s",
  "%(like_count)s",
  "%(live_status)s",
].join(PREFLIGHT_FIELD_SEP);

/** Index of `live_status` in a {@link PREFLIGHT_PRINT_TEMPLATE} line. */
const LIVE_STATUS_FIELD = 8;

/** `live_status` values whose captions may still be in post-stream processing. */
const STREAM_PROCESSING_STATUSES = new Set(["is_live", "post_live"]);

/** Display cap for the queue `title` cell (keeps the markdown table scannable). */
export const MAX_QUEUE_TITLE_CHARS = 60;

/** yt-dlp prints this literal for a null/missing field under `--print`. */
const YT_DLP_NULL_FIELD = "NA";

/**
 * Escape a value for a markdown table cell: collapse whitespace/newlines and escape `\` and `|`,
 * either of which would otherwise break the row's column count.
 *
 * @param {string} text
 * @returns {string}
 */
export function escapeTableCell(text) {
  return (text ?? "").replace(/\s+/g, " ").trim().replace(/[\\|]/g, "\\$&");
}

/**
 * Cap a title at `max` code points, appending an ellipsis when truncated.
 *
 * @param {string} text
 * @param {number} [max]
 * @returns {string}
 */
export function truncateTitle(text, max = MAX_QUEUE_TITLE_CHARS) {
  const safe = text ?? "";
  const chars = [...safe];
  if (chars.length <= max) {
    return safe;
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
 * First non-blank line of a multi-line stream capture, trimmed.
 *
 * @param {string} text
 * @returns {string}
 */
function firstNonEmptyLine(text) {
  return (
    (text ?? "")
      .split(/\r?\n/)
      .map((entry) => entry.trim())
      .find((entry) => entry.length > 0) ?? ""
  );
}

/**
 * Parse the first non-empty `--print` line into its component fields.
 *
 * @param {string} stdout
 * @returns {{ id: string, title: string, channel: string, handle: string }}
 */
export function parsePreflightLine(stdout) {
  const line = firstNonEmptyLine(stdout);
  const [id = "", title = "", channel = "", handle = ""] = line.split(PREFLIGHT_FIELD_SEP);
  return {
    id: normalizeField(id),
    title: normalizeField(title),
    channel: normalizeField(channel),
    handle: normalizeField(handle),
  };
}

/**
 * Whether a successful probe printed the empty shell yt-dlp returns for a
 * removed or nonexistent post: no channel, handle, description or counts
 * together. A real post, with or without video, carries an uploader. Returns
 * false when the line has no probe fields (an older or foreign print shape).
 *
 * @param {string} stdout
 * @returns {boolean}
 */
export function isEmptyPostShell(stdout) {
  const fields = firstNonEmptyLine(stdout).split(PREFLIGHT_FIELD_SEP);
  if (fields.length < 8) {
    return false;
  }
  return fields.slice(2, 8).every((field) => normalizeField(field) === "");
}

/**
 * The probe's yt-dlp `live_status`; empty when the line lacks it or yt-dlp printed none.
 *
 * @param {string} stdout
 * @returns {string}
 */
export function parsePreflightLiveStatus(stdout) {
  return normalizeField(firstNonEmptyLine(stdout).split(PREFLIGHT_FIELD_SEP)[LIVE_STATUS_FIELD]);
}

/**
 * Classify a preflight probe failure against the owning adapter's declared
 * pattern table: a fatal classification is permanently `unavailable` (reject,
 * do not enqueue); everything else (bot-check, age-gate, network, unknown) is
 * `transient`.
 *
 * @param {string} detail
 * @param {import('../adapters/adapter-contract.js').SourceErrorPatterns} errorPatterns
 * @returns {'unavailable' | 'transient'}
 */
export function classifyPreflightFailure(detail, errorPatterns) {
  return classifyErrorDetail(errorPatterns, detail) === "fatal" ? "unavailable" : "transient";
}

/**
 * Build the yt-dlp argument list for a metadata-only preflight probe.
 *
 * @param {string} url
 * @param {{ env?: NodeJS.ProcessEnv, authOverride?: import('./build-yt-dlp-args.js').YtDlpAuthOverride, source?: import('./build-yt-dlp-args.js').YtDlpSourceOptions }} [options]
 * @returns {string[]}
 */
export function buildPreflightArgs(url, { env = process.env, authOverride = {}, source = {} } = {}) {
  return [
    "--skip-download",
    "--no-warnings",
    "--no-playlist",
    ...(source.allowedExtractors ? ["--use-extractors", source.allowedExtractors] : []),
    // Sources declaring 0-media posts as well-formed (mediaOptional) keep them
    // enqueueable: yt-dlp reports metadata instead of a no-formats error.
    ...(source.ignoreNoFormatsError ? ["--ignore-no-formats-error"] : []),
    "--print",
    PREFLIGHT_PRINT_TEMPLATE,
    ...resolveYtDlpAuthArgs(env, authOverride, source.allowBrowserCookieProfileFallback === true),
    "--",
    url,
  ];
}

/**
 * @param {string} detail
 * @returns {string}
 */
function summarizeDetail(detail) {
  const cleaned = firstNonEmptyLine(detail).replace(/^ERROR:\s*/i, "");
  return cleaned.length > 120 ? `${cleaned.slice(0, 119)}…` : cleaned;
}

/**
 * @typedef {Object} PreflightResult
 * @property {string} url
 * @property {string|null} videoId
 * @property {string|null} queueKey - QUEUE.md `video-id` cell: videoId plus the range suffix
 *   on a ranged add; null when videoId is
 * @property {boolean} ok
 * @property {'ok'|'unavailable'|'transient'|'invalid-url'} status
 * @property {'enqueue'|'reject'} action
 * @property {string} note - markdown-safe notes cell value (empty for clean ok rows)
 * @property {string} reason - short human reason, markdown-escaped (failures only)
 * @property {string} title - raw title
 * @property {string} channel - raw channel display name
 * @property {string} handle - raw channel handle, leading at-sign included
 * @property {string} displayTitle - escaped + truncated title cell
 * @property {string} displayChannel - escaped channel cell
 * @property {string} liveStatus - yt-dlp `live_status` from the probe; empty when unknown
 */

/**
 * Build a result row; omitted text fields are empty. `queueKey` is derived from
 * `videoId` and `timeRange`, so every enqueueable row carries the cell to paste.
 *
 * @param {Pick<PreflightResult, 'url' | 'videoId' | 'ok' | 'status' | 'action'> & Partial<Omit<PreflightResult, 'queueKey'>> & { timeRange?: import('../lib/time-range.js').TimeRange|null }} fields
 * @returns {PreflightResult}
 */
function preflightResult({
  url,
  videoId,
  timeRange = null,
  ok,
  status,
  action,
  note = "",
  reason = "",
  title = "",
  channel = "",
  handle = "",
  displayTitle = "",
  displayChannel = "",
  liveStatus = "",
}) {
  return {
    url,
    videoId,
    queueKey: videoId === null ? null : rangedSliceKey(videoId, timeRange),
    ok,
    status,
    action,
    note,
    reason,
    title,
    channel,
    handle,
    displayTitle,
    displayChannel,
    liveStatus,
  };
}

/**
 * @typedef {Object} PreflightDeps
 * @property {(command: string, args: string[], options?: object) => ReturnType<typeof spawnAsync>} [spawn]
 * @property {NodeJS.ProcessEnv} [env]
 */

/**
 * Validate a single URL and fetch its title + channel. A `timeRange` (a ranged
 * add) puts the range suffix on `queueKey`; a source without the `timeRange`
 * capability rejects it, as `run-watch.js` would.
 *
 * @param {string} url
 * @param {PreflightDeps} [deps]
 * @param {{ timeRange?: import('../lib/time-range.js').TimeRange|null }} [options]
 * @returns {Promise<PreflightResult>}
 */
export async function preflightVideo(url, deps = {}, { timeRange = null } = {}) {
  const { spawn = spawnAsync, env = process.env } = deps;

  /** @param {string} note @param {string} reason @returns {PreflightResult} */
  const rejectInvalid = (note, reason) =>
    preflightResult({
      url,
      videoId: null,
      ok: false,
      status: "invalid-url",
      action: "reject",
      note: escapeTableCell(note),
      reason: escapeTableCell(reason),
    });

  /** @type {import('../adapters/adapter-contract.js').SourceAdapter} */
  let adapter;
  try {
    adapter = resolveSourceAdapter(url);
  } catch (error) {
    if (error instanceof UnsupportedSourceError) {
      return rejectInvalid(
        `unsupported source (supported: ${error.supportedHosts.join(", ")})`,
        error.message,
      );
    }
    throw error;
  }

  const decision = adapter.acceptForEnqueue(url);
  if (!decision.ok) {
    return rejectInvalid(decision.note ?? "rejected by source adapter", decision.reason ?? "");
  }
  if (timeRange && adapter.capabilities.timeRange !== true) {
    const message = `--from/--to are not supported for ${adapter.id} sources`;
    return rejectInvalid(message, message);
  }
  const videoId = decision.key ?? adapter.extractSliceKey(url, null);

  const claim = adapter.matchUrl(url);
  if (!claim) {
    return rejectInvalid(
      "not claimed by source adapter",
      "the owning adapter declined to claim this URL",
    );
  }
  const sourceDeclarations = adapterSourceDeclarations(adapter);
  const buildArgs = (
    /** @type {import('./build-yt-dlp-args.js').YtDlpAuthOverride} */ authOverride = {},
  ) => buildPreflightArgs(claim.canonicalUrl, { env, authOverride, source: sourceDeclarations });
  const result = await spawnYtDlpWithAuthFallback(spawn, buildArgs, {
    env,
    source: sourceDeclarations,
  });

  const mediaOptional = adapter.capabilities.mediaOptional === true;

  if (result.success && mediaOptional && isEmptyPostShell(result.stdout)) {
    // Removed or nonexistent post: yt-dlp still exits 0 with a synthetic title.
    return preflightResult({
      url,
      videoId,
      timeRange,
      ok: false,
      status: "unavailable",
      action: "reject",
      reason: "post removed or nonexistent (no uploader, description or counts)",
    });
  }

  if (result.success) {
    const { title, channel, handle } = parsePreflightLine(result.stdout);
    const liveStatus = parsePreflightLiveStatus(result.stdout);
    return preflightResult({
      url,
      videoId,
      timeRange,
      ok: true,
      status: "ok",
      action: "enqueue",
      note: STREAM_PROCESSING_STATUSES.has(liveStatus)
        ? `live stream (${liveStatus}): captions may follow post-stream processing`
        : "",
      liveStatus,
      title,
      channel,
      handle,
      displayTitle: escapeTableCell(truncateTitle(title)),
      displayChannel: escapeTableCell(formatChannel(channel, handle)),
    });
  }

  const detail = spawnFailureDetail(result);
  if (mediaOptional && parseDelegationRefusal(detail)) {
    return preflightResult({
      url,
      videoId,
      timeRange,
      ok: true,
      status: "ok",
      action: "enqueue",
      note: "link post, no video (empty media)",
    });
  }
  const status = classifyPreflightFailure(detail, adapter.errorPatterns);
  const reason = escapeTableCell(summarizeDetail(detail));
  return preflightResult({
    url,
    videoId,
    timeRange,
    ok: false,
    status,
    action: status === "unavailable" ? "reject" : "enqueue",
    note: status === "unavailable" ? "" : `preflight: ${reason || "needs auth/cookies"}`,
    reason,
  });
}

/**
 * @param {string[]} urls
 * @param {PreflightDeps} [deps]
 * @param {{ timeRange?: import('../lib/time-range.js').TimeRange|null }} [options]
 * @returns {Promise<PreflightResult[]>}
 */
export async function preflightVideos(urls, deps = {}, options = {}) {
  /** @type {PreflightResult[]} */
  const results = [];
  for (const url of urls) {
    results.push(await preflightVideo(url, deps, options));
  }
  return results;
}

/** Flags that take a value; the value is not a URL. */
const RANGE_FLAGS = new Set(["--from", "--to"]);

/**
 * Split the CLI arguments (after `node <script>`) into URLs and an optional time
 * range. A ranged add names exactly one URL, as the queue's ranged row does.
 *
 * @param {string[]} args
 * @returns {{ ok: true, urls: string[], timeRange: import('../lib/time-range.js').TimeRange|null } | { ok: false, error: string }}
 */
export function parsePreflightArgs(args) {
  const rangeArg = parseTimeRangeArgs(args);
  if (!rangeArg.ok) return rangeArg;
  const urls = args.filter(
    (arg, index) => arg.length > 0 && !RANGE_FLAGS.has(arg) && !RANGE_FLAGS.has(args[index - 1]),
  );
  if (rangeArg.range && urls.length !== 1) {
    return { ok: false, error: "--from/--to take exactly one URL" };
  }
  return { ok: true, urls, timeRange: rangeArg.range };
}

/**
 * @param {string[]} argv
 * @returns {Promise<void>}
 */
async function main(argv) {
  const parsed = parsePreflightArgs(argv.slice(2));
  if (!parsed.ok) {
    writeStderr(parsed.error);
    process.exit(1);
  }
  const { urls, timeRange } = parsed;
  if (urls.length === 0) {
    writeStderr(
      "Usage: preflight-metadata.js <video-url> [<video-url>...] | <video-url> [--from <h:mm:ss>] [--to <h:mm:ss>]",
    );
    process.exit(1);
  }

  const results = await preflightVideos(urls, {}, { timeRange });
  writeStdout(JSON.stringify(results, null, 2));

  if (results.some((entry) => entry.action === "reject")) {
    process.exit(2);
  }
}

if (isMainModule(import.meta.url)) {
  main(process.argv).catch((error) => {
    writeStderr(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
