/**
 * Free-space check before a watch downloads media. yt-dlp stages the separate streams, the
 * merged file and the remuxed mp4 in the run's temp work dir (`--paths temp:`), so a long video
 * on a small temp filesystem fails mid-merge. One metadata-only probe reads the size of the
 * formats the download would select, and the check compares twice that size to the free space.
 */

import fs from "node:fs/promises";

import { spawnAsync } from "@melodic/video-digestion/shared/process";

import { adapterSourceDeclarations } from "../acquisition/acquire.js";
import { spawnFailureDetail } from "../acquisition/acquire-with-retry.js";
import {
  resolveYtDlpAuthArgs,
  YT_DLP_SLEEP_REQUESTS_SEC,
  YT_DLP_VIDEO_FORMAT,
} from "../acquisition/build-yt-dlp-args.js";
import { spawnYtDlpWithAuthFallback } from "../acquisition/spawn-yt-dlp-with-auth-fallback.js";

/** The merge writes a copy beside the streams, and the remux one beside the merged file. */
export const STAGING_SIZE_FACTOR = 2;

const FIELD_SEP = String.fromCharCode(0x1f);

/** A merged format's `filesize_approx` is the sum of its streams' sizes. */
const SIZE_PRINT_TEMPLATE = ["%(filesize,filesize_approx)s", "%(duration)s"].join(FIELD_SEP);

/**
 * @typedef {Object} MediaSize
 * @property {number|null} bytes - selected formats' size; null when yt-dlp reports none
 * @property {number|null} durationSec
 * @property {string} [error] - why the probe failed, when it did
 */

/**
 * @typedef {Object} TempSpaceResult
 * @property {'enough'|'short'|'unknown'} state
 * @property {string} message - empty for `enough`
 */

/**
 * @param {string} url
 * @param {{ env?: NodeJS.ProcessEnv, authOverride?: import('../acquisition/build-yt-dlp-args.js').YtDlpAuthOverride, source?: import('../acquisition/build-yt-dlp-args.js').YtDlpSourceOptions }} [options]
 * @returns {string[]}
 */
export function buildSizeProbeArgs(url, { env = process.env, authOverride = {}, source = {} } = {}) {
  return [
    "--skip-download",
    "--no-warnings",
    "--no-playlist",
    "--sleep-requests",
    YT_DLP_SLEEP_REQUESTS_SEC,
    ...(source.extractorArgs ? ["--extractor-args", source.extractorArgs] : []),
    ...(source.allowedExtractors ? ["--use-extractors", source.allowedExtractors] : []),
    ...(source.ignoreNoFormatsError ? ["--ignore-no-formats-error"] : []),
    "-f",
    YT_DLP_VIDEO_FORMAT,
    "--print",
    SIZE_PRINT_TEMPLATE,
    ...resolveYtDlpAuthArgs(env, authOverride, source.allowBrowserCookieProfileFallback === true),
    "--",
    url,
  ];
}

/**
 * @param {string|undefined} field
 * @returns {number|null}
 */
function positiveNumber(field) {
  const value = Number(field?.trim());
  return Number.isFinite(value) && value > 0 ? value : null;
}

/**
 * Parse the probe's output: one line per media entry (an X post can carry several), each
 * `<size><SEP><duration>`, with `NA` for a missing field. The size is the entries' sum, unknown
 * when any entry has none; the duration is read only from a single entry.
 *
 * @param {string} stdout
 * @returns {MediaSize}
 */
export function parseSizeProbe(stdout) {
  const entries = (stdout ?? "")
    .split(/\r?\n/)
    .filter((line) => line.trim())
    .map((line) => line.split(FIELD_SEP));
  const sizes = entries.map(([size]) => positiveNumber(size));
  const known = sizes.length > 0 && sizes.every((size) => size !== null);
  return {
    bytes: known ? sizes.reduce((total, size) => total + Number(size), 0) : null,
    durationSec: entries.length === 1 ? positiveNumber(entries[0][1]) : null,
  };
}

/**
 * @param {string} url - a URL the adapter claimed
 * @param {import('../adapters/adapter-contract.js').SourceAdapter} adapter
 * @param {{ spawn?: typeof spawnAsync, env?: NodeJS.ProcessEnv }} [deps]
 * @returns {Promise<MediaSize>}
 */
export async function probeMediaSize(url, adapter, { spawn = spawnAsync, env = process.env } = {}) {
  const source = adapterSourceDeclarations(adapter);
  const result = await spawnYtDlpWithAuthFallback(
    spawn,
    (authOverride = {}) => buildSizeProbeArgs(url, { env, authOverride, source }),
    { env, source },
  );
  if (!result.success) {
    const detail = spawnFailureDetail(result).split(/\r?\n/).find((line) => line.trim()) ?? "";
    return { bytes: null, durationSec: null, error: detail.trim() || "yt-dlp failed" };
  }
  return parseSizeProbe(result.stdout);
}

/**
 * Bytes the download stages: the media size times {@link STAGING_SIZE_FACTOR}, scaled to the
 * range's share of the video for a ranged run. Null when the size, or a ranged run's duration,
 * is unknown.
 *
 * @param {MediaSize} size
 * @param {import('../lib/time-range.js').TimeRange|null} timeRange
 * @returns {number|null}
 */
export function estimateStagingBytes({ bytes, durationSec }, timeRange) {
  if (bytes === null) return null;
  if (!timeRange) return bytes * STAGING_SIZE_FACTOR;
  if (durationSec === null) return null;
  const endSec = Math.min(timeRange.toSec ?? durationSec, durationSec);
  const share = Math.max(0, endSec - timeRange.fromSec) / durationSec;
  return bytes * share * STAGING_SIZE_FACTOR;
}

/**
 * @param {string} dir
 * @returns {Promise<number>}
 */
async function readFreeBytes(dir) {
  const stats = await fs.statfs(dir);
  return stats.bavail * stats.bsize;
}

/**
 * @param {number} bytes
 * @returns {string}
 */
export function formatBytes(bytes) {
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

/**
 * @param {string} tempDir
 * @returns {string}
 */
function tmpdirAdvice(tempDir) {
  return (
    `To stage on a larger disk, set TMPDIR (TEMP on Windows) to a directory there instead of ${tempDir}, ` +
    "and keep it set for every later run.mjs call in this session: the slice records its temp paths relative to that directory."
  );
}

/**
 * Compare the staging estimate to the free space in `tempDir`.
 *
 * @param {{ url: string, adapter: import('../adapters/adapter-contract.js').SourceAdapter, tempDir: string, timeRange: import('../lib/time-range.js').TimeRange|null }} options
 * @param {{ probe?: typeof probeMediaSize, freeBytes?: (dir: string) => Promise<number> }} [deps]
 * @returns {Promise<TempSpaceResult>}
 */
export async function checkTempSpace(
  { url, adapter, tempDir, timeRange },
  { probe = probeMediaSize, freeBytes = readFreeBytes } = {},
) {
  /** @param {string} reason */
  const unknown = (reason) => ({
    state: /** @type {const} */ ("unknown"),
    message: `WARN: free space in ${tempDir} not checked (${reason}); continuing. A video needs about ${STAGING_SIZE_FACTOR}x its size free there. ${tmpdirAdvice(tempDir)}`,
  });

  // An unclaimed URL (a playlist or channel page) is never probed: yt-dlp would walk every
  // entry, and acquisition refuses the URL next anyway.
  const claim = adapter.matchUrl(url);
  if (!claim) return { state: "enough", message: "" };
  const size = await probe(claim.canonicalUrl, adapter);
  const neededBytes = estimateStagingBytes(size, timeRange);
  if (neededBytes === null) {
    return unknown(size.error ? `size probe failed: ${size.error}` : "yt-dlp reported no media size");
  }

  let free;
  try {
    free = await freeBytes(tempDir);
  } catch (error) {
    return unknown(`free space unreadable: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (free >= neededBytes) return { state: "enough", message: "" };
  return {
    state: "short",
    message: `ERROR: not enough free space in ${tempDir} to stage this video: needs about ${formatBytes(neededBytes)} (${STAGING_SIZE_FACTOR}x the selected formats' size), ${formatBytes(free)} free. ${tmpdirAdvice(tempDir)}`,
  };
}
