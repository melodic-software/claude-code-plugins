/**
 * X (Twitter) source adapter: status-URL grammar with adapter-level
 * canonicalization, snowflake slice identity, provenance-guarded yt-dlp
 * acquisition (0..N media per post), silent 429-degradation detection, and
 * post-text link harvest, composed from the shared machinery in `acquisition/`.
 *
 * Acquisition is two-phase by design: a metadata/captions probe (never media)
 * runs first, and every yt-dlp invocation carries the adapter's extractor
 * allow-list (`--use-extractors`), so a delegated foreign URL from a link post
 * (yt-dlp/yt-dlp#9715) is refused by yt-dlp itself WITHOUT any fetch — the
 * refusal is parsed from stderr and the post resolves as a well-formed 0-media
 * result with the blocked link recorded. The info-JSON extractor check remains
 * as defense-in-depth: a foreign info JSON on disk means the allow-list failed
 * and the acquisition fails rather than digesting foreign media. Media
 * downloads only after the probe proves the post itself carries
 * twitter-extracted video.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { spawnAsync } from "@melodic/video-digestion/shared/process";
import { fail, ok } from "@melodic/video-digestion/shared/result";

import {
  adapterSourceDeclarations,
  listWorkDirFiles,
  resolveAcquirePhaseGapMs,
} from "../acquisition/acquire.js";
import { sleepMs } from "../acquisition/acquire-retry-policy.js";
import { withAcquireThrottle } from "../acquisition/acquire-throttle.js";
import { spawnFailureDetail } from "../acquisition/acquire-with-retry.js";
import { buildYtDlpArgs } from "../acquisition/build-yt-dlp-args.js";
import { selectCaptionFile } from "../acquisition/select-caption.js";
import { spawnYtDlpWithAuthFallback } from "../acquisition/spawn-yt-dlp-with-auth-fallback.js";
import { deduplicateHarvestedLinks, linksFromText } from "../harvesting/harvest-links.js";
import { createAcquisitionEnvelope, createSourceAdapter } from "./adapter-contract.js";

/**
 * @import { AcquireContext, AcquireOutcome, EnqueueDecision, SourceAdapterSpec,
 *   SourceMetadata, UrlClaim } from './adapter-contract.js'
 */
/**
 * @import { AcquisitionMode, YtDlpAuthOverride, YtDlpSourceOptions }
 *   from '../acquisition/build-yt-dlp-args.js'
 */
/** @import { SpawnResult } from '@melodic/video-digestion/shared/process' */
/** @import { HarvestedLink } from '../harvesting/models.js' */

/** The `extractor` value yt-dlp stamps into info JSON for TwitterIE results. */
export const X_EXTRACTOR_NAME = "twitter";

/**
 * yt-dlp extractor allow-list for X URLs: the twitter IE family only
 * (twitter, twitter:amplify, twitter:broadcast, twitter:card,
 * twitter:shortener, twitter:spaces — verified against `--list-extractors`).
 * Any delegated foreign URL is refused without a fetch.
 */
export const X_ALLOWED_EXTRACTORS = "twitter.*";

/**
 * Exact refusal yt-dlp emits when the allow-list rejects a URL (verified
 * empirically against yt-dlp 2026.07.04; note there is no colon before the
 * URL). For a link post, the refused URL is the post's outbound link.
 */
const DELEGATION_REFUSAL_PATTERN = /^ERROR: No suitable extractor found for URL (?<url>\S+)$/m;

/**
 * Parse a blocked-delegation refusal out of acquisition stderr: present only
 * when yt-dlp refused a DELEGATED (non-X) URL — a refusal of an X URL itself
 * would mean the allow-list is misconfigured and is never treated as a
 * link-post result.
 *
 * @param {string} stderr
 * @returns {string|null} the refused outbound URL
 */
export function parseDelegationRefusal(stderr) {
  const match = DELEGATION_REFUSAL_PATTERN.exec(stderr);
  const refusedUrl = match?.groups?.url;
  if (!refusedUrl) return null;
  return parseXStatusUrl(refusedUrl) ? null : refusedUrl;
}

/**
 * Exact warning yt-dlp's twitter extractor emits when a 429 silently degrades
 * to the syndication endpoint (losing `*_count` metadata and collapsing
 * multi-media posts to one entry).
 */
export const X_SYNDICATION_DEGRADATION_WARNING =
  "Rate-limit exceeded; falling back to syndication endpoint";

/** Prefix of the failure detail this adapter emits for degraded acquisitions. */
export const X_DEGRADED_ACQUISITION_PREFIX = "X acquisition degraded";

/**
 * The three observed X failure signatures that are post-content facts —
 * reject, do not retry. (With `--ignore-no-formats-error` on the acquisition
 * passes, the first two typically resolve as a well-formed 0-media result
 * before spawn-level classification ever sees them.)
 *
 * @type {readonly RegExp[]}
 */
export const X_FATAL_PATTERNS = Object.freeze([
  /No video could be found in this tweet/,
  /No video formats found/,
  /Unsupported URL:/,
]);

/**
 * Login-required = EXACTLY the three documented `raise_login_required` cases
 * in yt-dlp's twitter extractor; only these gate cookie fallback:
 * NSFW/age-restricted; protected account (the cookie account must follow the
 * author); any `not authorized` API error message. Each pattern is anchored to
 * a `[twitter]`-tagged ERROR line so attacker-influenced text elsewhere on
 * stderr (e.g. a hostile URL echoed in a refusal line) can never classify as
 * login-required and trigger cookie-bearing retries.
 *
 * @type {readonly RegExp[]}
 */
export const X_LOGIN_REQUIRED_PATTERNS = Object.freeze([
  /^ERROR:\s*\[twitter\][^\n]*NSFW tweet requires authentication/im,
  /^ERROR:\s*\[twitter\][^\n]*You are not authorized to view this protected tweet/im,
  /^ERROR:\s*\[twitter\][^\n]*\bnot authorized\b/im,
]);

/**
 * @type {readonly RegExp[]}
 */
export const X_RETRYABLE_PATTERNS = Object.freeze([
  /Rate-limit exceeded; falling back to syndication endpoint/,
  /X acquisition degraded/,
]);

/**
 * X subtitle keys are the raw, unnormalized track `LANGUAGE` attribute with
 * `und` as yt-dlp's fallback — observed `en`, `en-US`, `en-GB`, `und`. The
 * selector must therefore include `und`; never a hardcoded `en` lookup.
 */
const X_SUB_LANGS = "en.*,und,-live_chat";

/** Literal marker of X's word-timing caption tags (kept verbatim on disk). */
const X_WORD_TIMING_TAG_MARKER = "<X-word-ms";

/** Backup suffix (never `.vtt`/`.srt`) holding tagged originals until cleanup succeeds. */
const TAGGED_CAPTION_BACKUP_SUFFIX = ".tagged-original";

const X_OWNED_HOSTS = Object.freeze(["x.com", "twitter.com"]);

/**
 * Mirror of yt-dlp TwitterIE `_VALID_URL` path grammar:
 * `(?:(?:i/web|[^/]+)/status|statuses)/(?P<id>\d+)(?:/(?:video|photo)/(?P<index>\d+))?`
 * — bounded beyond it: snowflakes are <= 19 digits (25 allowed for slack), the
 * media index <= 3 digits, so unbounded digit strings never reach BigInt
 * decoding, slice-key paths, or parseInt round-trips.
 */
const X_STATUS_PATH_PATTERN =
  /^\/(?:(?<handle>i\/web|[^/]+)\/status|statuses)\/(?<statusId>\d{1,25})(?:\/(?:video|photo)\/(?<mediaIndex>\d{1,3}))?\/?$/;

const X_HANDLE_PATTERN = /^[A-Za-z0-9_]{1,20}$/;

const TWITTER_SNOWFLAKE_EPOCH_MS = 1288834974657n;
const SNOWFLAKE_TIMESTAMP_SHIFT = 22n;

/**
 * Media ids for an original post are minted moments before the post's own
 * status id, so a small positive delta is normal composition lag. A result id
 * minted long before the URL's status id means the URL aliases media owned by
 * an older post (quote/retweet). Heuristic threshold; the raw delta is always
 * recorded alongside so downstream consumers can re-judge.
 */
const SNOWFLAKE_ALIAS_THRESHOLD_MS = 60 * 60 * 1000;

/**
 * @typedef {Object} XStatusUrlParts
 * @property {string} statusId - the status id captured from the URL (canonical slice identity)
 * @property {string|null} handle - lowercased author handle when the URL carries a plausible one
 * @property {number|null} mediaIndex - `/video/<n>` (or `/photo/<n>`) pinned 1-based media index
 */

/**
 * Parse an x.com / twitter.com status URL. Pure; returns null for anything
 * that is not a status URL on an owned host (profiles, spaces, foreign hosts,
 * unparseable input).
 *
 * @param {string} url
 * @returns {XStatusUrlParts|null}
 */
export function parseXStatusUrl(url) {
  /** @type {URL} */
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    return null;
  }
  const hostname = parsed.hostname.toLowerCase().replace(/\.$/, "");
  const owned = X_OWNED_HOSTS.some((host) => hostname === host || hostname.endsWith(`.${host}`));
  if (!owned) {
    return null;
  }
  const match = X_STATUS_PATH_PATTERN.exec(parsed.pathname);
  if (!match || !match.groups) {
    return null;
  }
  const rawHandle = match.groups.handle;
  const handle =
    rawHandle && rawHandle !== "i" && X_HANDLE_PATTERN.test(rawHandle)
      ? rawHandle.toLowerCase()
      : null;
  const rawIndex = match.groups.mediaIndex;
  return {
    statusId: match.groups.statusId,
    handle,
    mediaIndex: rawIndex ? Number.parseInt(rawIndex, 10) : null,
  };
}

/**
 * Re-derive the canonical status URL from parsed parts (T10 (ii)): scheme and
 * host pinned, tracking query/fragment dropped, handle lowercased (or `i/web`
 * when the URL carries none), pinned media index preserved as `/video/<n>`.
 *
 * @param {XStatusUrlParts} parts
 * @returns {string}
 */
export function canonicalXStatusUrl(parts) {
  const owner = parts.handle ?? "i/web";
  const indexSuffix = parts.mediaIndex !== null ? `/video/${parts.mediaIndex}` : "";
  return `https://x.com/${owner}/status/${parts.statusId}${indexSuffix}`;
}

/**
 * Millisecond epoch timestamp encoded in a Twitter snowflake id, or null when
 * the id is not snowflake-shaped (including pre-2010 sequential ids).
 *
 * @param {string} id
 * @returns {number|null}
 */
export function snowflakeTimestampMs(id) {
  if (typeof id !== "string" || !/^\d{1,25}$/.test(id)) {
    return null;
  }
  const value = BigInt(id);
  const shifted = value >> SNOWFLAKE_TIMESTAMP_SHIFT;
  if (shifted === 0n) {
    return null;
  }
  return Number(shifted + TWITTER_SNOWFLAKE_EPOCH_MS);
}

/**
 * @typedef {Object} SnowflakeAliasing
 * @property {string} urlStatusId
 * @property {string} resultId
 * @property {number} urlTimestampMs
 * @property {number} resultTimestampMs
 * @property {number} deltaMs - urlTimestampMs - resultTimestampMs
 * @property {boolean} aliasSuspected
 */

/**
 * Flag quote/retweet aliasing: the URL's status id resolving media whose id
 * was minted far earlier. Identical ids (including the link-post branch where
 * the result id IS the twid) never alias.
 *
 * @param {string} urlStatusId
 * @param {string|null} resultId
 * @returns {SnowflakeAliasing|null}
 */
export function detectSnowflakeAliasing(urlStatusId, resultId) {
  if (!resultId || resultId === urlStatusId) {
    return null;
  }
  const urlTimestampMs = snowflakeTimestampMs(urlStatusId);
  const resultTimestampMs = snowflakeTimestampMs(resultId);
  if (urlTimestampMs === null || resultTimestampMs === null) {
    return null;
  }
  const deltaMs = urlTimestampMs - resultTimestampMs;
  return {
    urlStatusId,
    resultId,
    urlTimestampMs,
    resultTimestampMs,
    deltaMs,
    aliasSuspected: deltaMs > SNOWFLAKE_ALIAS_THRESHOLD_MS,
  };
}

/**
 * @typedef {Object} SyndicationDegradation
 * @property {boolean} warningSeen - the exact rate-limit fallback warning appeared on stderr
 * @property {boolean} countsMissing - repost AND comment counts absent from a present post payload
 * @property {number} entryCount
 * @property {boolean} possibleMultiMediaCollapse - degraded AND exactly one entry (the
 *   syndication endpoint keeps only one video of a multi-media post)
 */

/**
 * Compound silent-429 detector. Either signal alone marks the acquisition
 * degraded (never success): the literal fallback warning, or a present post
 * payload missing both repost and comment counts. `countsMissing` is only
 * evaluated when a twitter post payload exists (`postInfo` non-null) — a
 * blocked delegation has no post payload to judge.
 *
 * @param {Object} params
 * @param {string} params.stderr - accumulated stderr across acquisition passes
 * @param {Record<string, unknown>|null} params.postInfo - the twitter post-level info JSON
 * @param {number} params.entryCount
 * @returns {SyndicationDegradation|null} null when the response shows no degradation signal
 */
export function detectSyndicationDegradation({ stderr, postInfo, entryCount }) {
  const warningSeen = stderr.includes(X_SYNDICATION_DEGRADATION_WARNING);
  const countsMissing =
    postInfo !== null && postInfo.repost_count == null && postInfo.comment_count == null;
  if (!warningSeen && !countsMissing) {
    return null;
  }
  return {
    warningSeen,
    countsMissing,
    entryCount,
    possibleMultiMediaCollapse: entryCount === 1,
  };
}

/**
 * Convert yt-dlp's `--convert-subs srt` output back into the WebVTT container
 * the shared transcript pipeline consumes: comma decimals become dots, cue
 * counter lines drop, payload text (already tag-cleaned by the conversion)
 * passes through.
 *
 * @param {string} srtText
 * @returns {string}
 */
export function convertSrtToVtt(srtText) {
  const cues = srtText
    .replace(/\r\n/g, "\n")
    .trim()
    .split(/\n{2,}/)
    .map((block) => {
      const lines = block.split("\n");
      if (/^\d+$/.test((lines[0] ?? "").trim())) {
        lines.shift();
      }
      return lines.join("\n").replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, "$1.$2");
    })
    .filter((block) => block.trim().length > 0);
  return `WEBVTT\n\n${cues.join("\n\n")}\n`;
}

/**
 * @typedef {Object} ParsedInfoFile
 * @property {string} path
 * @property {Record<string, unknown>} info
 */

/**
 * @typedef {Object} InspectedInfoFiles
 * @property {ParsedInfoFile|null} twitterPlaylist - twitter playlist-level info (N-media posts)
 * @property {ParsedInfoFile[]} twitterVideos - twitter media entries (non-empty formats)
 * @property {ParsedInfoFile|null} twitterMetadataOnly - twitter post info without formats (0-media)
 * @property {ParsedInfoFile[]} foreign - non-twitter results = blocked delegations
 * @property {string[]} parseErrors
 */

/**
 * Parse and partition every `*.info.json` under the working directory.
 *
 * @param {string[]} files
 * @param {(filePath: string) => Promise<string>} readFile
 * @returns {Promise<InspectedInfoFiles>}
 */
async function inspectInfoFiles(files, readFile) {
  /** @type {InspectedInfoFiles} */
  const inspected = {
    twitterPlaylist: null,
    twitterVideos: [],
    twitterMetadataOnly: null,
    foreign: [],
    parseErrors: [],
  };
  for (const filePath of files.filter((entry) => entry.endsWith(".info.json"))) {
    /** @type {unknown} */
    let parsed;
    try {
      parsed = JSON.parse(String(await readFile(filePath)));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      inspected.parseErrors.push(`${filePath}: ${message}`);
      continue;
    }
    if (!parsed || typeof parsed !== "object") {
      inspected.parseErrors.push(`${filePath}: info JSON is not an object`);
      continue;
    }
    const info = /** @type {Record<string, unknown>} */ (parsed);
    if (info.extractor !== X_EXTRACTOR_NAME) {
      inspected.foreign.push({ path: filePath, info });
      continue;
    }
    if (info._type === "playlist") {
      inspected.twitterPlaylist = { path: filePath, info };
      continue;
    }
    if (Array.isArray(info.formats) && info.formats.length > 0) {
      inspected.twitterVideos.push({ path: filePath, info });
    } else {
      inspected.twitterMetadataOnly = { path: filePath, info };
    }
  }
  return inspected;
}

/**
 * Order media entries: playlist declaration order when the playlist info is
 * present, else ascending snowflake id (upload order).
 *
 * @param {ParsedInfoFile[]} twitterVideos
 * @param {ParsedInfoFile|null} twitterPlaylist
 * @returns {ParsedInfoFile[]}
 */
function orderTwitterVideos(twitterVideos, twitterPlaylist) {
  const rawEntries = twitterPlaylist?.info.entries;
  const playlistEntries = Array.isArray(rawEntries) ? rawEntries : null;
  if (playlistEntries) {
    /** @type {Map<string, number>} */
    const order = new Map();
    for (const [index, entry] of playlistEntries.entries()) {
      const id = entry && typeof entry === "object" ? String((/** @type {Record<string, unknown>} */ (entry)).id ?? "") : "";
      if (id && !order.has(id)) {
        order.set(id, index);
      }
    }
    return [...twitterVideos].sort(
      (a, b) =>
        (order.get(String(a.info.id)) ?? Number.MAX_SAFE_INTEGER) -
        (order.get(String(b.info.id)) ?? Number.MAX_SAFE_INTEGER),
    );
  }
  return [...twitterVideos].sort((a, b) => {
    const left = String(a.info.id);
    const right = String(b.info.id);
    if (/^\d+$/.test(left) && /^\d+$/.test(right)) {
      const delta = BigInt(left) - BigInt(right);
      return delta < 0n ? -1 : delta > 0n ? 1 : 0;
    }
    return left.localeCompare(right);
  });
}

/**
 * @param {unknown} value
 * @returns {number|null}
 */
function countOrNull(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * @typedef {Object} BlockedDelegation
 * @property {string} url - the outbound link the delegation resolved to
 * @property {string} extractor - the foreign extractor that claimed it
 */

/**
 * Build the shared post metadata object. Source-specific fields ride under the
 * reserved `source:` key prefix (open metadata namespace).
 *
 * @param {Object} params
 * @param {string} params.statusId
 * @param {Record<string, unknown>|null} params.postInfo
 * @param {SnowflakeAliasing|null} params.aliasing
 * @param {BlockedDelegation[]} params.blockedDelegations
 * @returns {SourceMetadata & Record<string, unknown>}
 */
function buildXPostMetadata({ statusId, postInfo, aliasing, blockedDelegations }) {
  const record = postInfo ?? {};
  /** @type {SourceMetadata & Record<string, unknown>} */
  const metadata = {
    id: typeof record.id === "string" && record.id ? record.id : statusId,
    title: typeof record.title === "string" ? record.title : "",
    description: typeof record.description === "string" ? record.description : "",
    "source:displayId":
      typeof record.display_id === "string" && record.display_id ? record.display_id : statusId,
    "source:counts": {
      likeCount: countOrNull(record.like_count),
      repostCount: countOrNull(record.repost_count),
      commentCount: countOrNull(record.comment_count),
      viewCount: countOrNull(record.view_count),
    },
  };
  if (aliasing) {
    metadata["source:snowflakeAliasing"] = aliasing;
  }
  if (blockedDelegations.length > 0) {
    metadata["source:blockedDelegations"] = blockedDelegations;
  }
  return metadata;
}

/**
 * Match downloaded artifacts to one media entry by yt-dlp's `%(id)s.%(ext)s`
 * output template.
 *
 * @param {string[]} files
 * @param {string} mediaId
 * @returns {{ mediaPath: string, captionPaths: string[] }}
 */
function matchEntryArtifacts(files, mediaId) {
  const belongsToEntry = (/** @type {string} */ filePath) =>
    path.basename(filePath).startsWith(`${mediaId}.`);
  const mediaPath =
    files.find(
      (filePath) =>
        belongsToEntry(filePath) &&
        (filePath.endsWith(".mp4") || filePath.endsWith(".mkv") || filePath.endsWith(".webm")),
    ) ?? "";
  const captionPaths = files.filter(
    (filePath) => belongsToEntry(filePath) && filePath.endsWith(".vtt"),
  );
  return { mediaPath, captionPaths };
}

/**
 * Injectable I/O for {@link acquireXMedia} (tests only).
 *
 * @typedef {Object} XAcquireDeps
 * @property {(command: string, args: string[], options?: object) => Promise<SpawnResult>} [spawn]
 * @property {(dir: string) => Promise<string[]>} [listFiles]
 * @property {(filePath: string) => Promise<string>} [readFile]
 * @property {(filePath: string, content: string, encoding: string) => Promise<void>} [writeFile]
 * @property {(filePath: string) => Promise<void>} [removeFile]
 * @property {(ms: number) => Promise<void>} [sleep]
 * @property {<T>(fn: () => Promise<T>) => Promise<T>} [withThrottle]
 */

/**
 * Acquire an X post's media, captions, and metadata as a 0..N envelope.
 *
 * @param {string} url - canonical status URL (from `matchUrl`)
 * @param {AcquireContext} context
 * @returns {Promise<AcquireOutcome>}
 */
export async function acquireXMedia(url, context) {
  const started = Date.now();
  const { workDir, mode } = context;
  const deps = /** @type {XAcquireDeps} */ (context.deps ?? {});
  const {
    spawn = spawnAsync,
    listFiles = listWorkDirFiles,
    readFile = (/** @type {string} */ filePath) => fs.readFile(filePath, "utf8"),
    writeFile = (/** @type {string} */ filePath, /** @type {string} */ content) =>
      fs.writeFile(filePath, content, "utf8"),
    removeFile = (/** @type {string} */ filePath) => fs.rm(filePath, { force: true }),
    sleep = sleepMs,
    withThrottle = withAcquireThrottle,
  } = deps;
  const throttle = /** @type {<T>(fn: () => Promise<T>) => Promise<T>} */ (withThrottle);

  const parts = parseXStatusUrl(url);
  if (!parts) {
    return /** @type {AcquireOutcome} */ (
      fail(`Not an X status URL: ${url}`, "acquire-x-media", { label: url }, Date.now() - started)
    );
  }
  const { statusId } = parts;

  /** @param {string} message @returns {AcquireOutcome} */
  const failX = (message) =>
    /** @type {AcquireOutcome} */ (
      fail(message, "acquire-x-media", { label: statusId }, Date.now() - started)
    );

  const source = {
    ...adapterSourceDeclarations(adapter),
    subLangs: X_SUB_LANGS,
    omitAutoSubs: true,
    ignoreNoFormatsError: true,
  };
  const outputTemplate = path.join(workDir, "%(id)s.%(ext)s");

  /**
   * @param {AcquisitionMode} passMode
   * @param {Partial<YtDlpSourceOptions>} [extraSource]
   */
  const runPass = (passMode, extraSource = {}) =>
    throttle(() => {
      const buildArgs = (/** @type {YtDlpAuthOverride} */ authOverride = {}) =>
        buildYtDlpArgs(url, {
          mode: passMode,
          outputTemplate,
          workDir,
          authOverride,
          source: { ...source, ...extraSource },
        });
      return spawnYtDlpWithAuthFallback(spawn, buildArgs, { cwd: workDir, source });
    });

  // Pass 1 — metadata + captions probe. Never media; the extractor allow-list
  // rides on every pass, so a delegated foreign URL is refused unfetched.
  const probe = await runPass("transcript");
  const probeStderr = probe.stderr ?? "";
  if (!probe.success) {
    // Link post: the allow-list refused the post's delegated outbound URL
    // without fetching it (yt-dlp writes no info JSON for an intermediate url
    // result, so no post payload exists). The post resolves as a well-formed
    // 0-media result with the blocked link recorded — unless the response was
    // also rate-limit degraded, which stays a retryable failure.
    const refusedUrl = parseDelegationRefusal(probeStderr);
    if (refusedUrl) {
      const degradation = detectSyndicationDegradation({
        stderr: probeStderr,
        postInfo: null,
        entryCount: 0,
      });
      if (degradation) {
        return failX(
          `${X_DEGRADED_ACQUISITION_PREFIX} (rate-limited syndication fallback is a partial response, retry later): ${JSON.stringify(degradation)}`,
        );
      }
      const envelope = createAcquisitionEnvelope({
        entries: [],
        metadata: buildXPostMetadata({
          statusId,
          postInfo: null,
          aliasing: null,
          blockedDelegations: [{ url: refusedUrl, extractor: "refused-before-fetch" }],
        }),
        workDir,
        acquireMetrics: { stagedAcquire: true, probeFirst: true, blockedDelegationCount: 1 },
      });
      return /** @type {AcquireOutcome} */ (
        ok(envelope, "acquire-x-media", { label: statusId }, Date.now() - started)
      );
    }
    return failX(spawnFailureDetail(probe) || "yt-dlp metadata/captions probe failed");
  }
  let stderrLog = probeStderr;
  let files = await listFiles(workDir);

  let inspected = await inspectInfoFiles(files, readFile);
  if (inspected.parseErrors.length > 0) {
    return failX(`Invalid info JSON: ${inspected.parseErrors.join("; ")}`);
  }

  // Defense-in-depth provenance guard: a foreign info JSON on disk means the
  // extractor allow-list failed to refuse a delegation — never digest it.
  if (inspected.foreign.length > 0) {
    const foreignSummary = inspected.foreign
      .map(
        (entry) =>
          `${String(entry.info.extractor ?? "unknown")}: ${String(entry.info.webpage_url ?? entry.info.original_url ?? entry.path)}`,
      )
      .join("; ");
    return failX(
      `Provenance violation: non-twitter extractor result(s) present despite the extractor allow-list — refusing to digest foreign media (${foreignSummary})`,
    );
  }

  const postInfo =
    inspected.twitterPlaylist?.info ??
    inspected.twitterVideos[0]?.info ??
    inspected.twitterMetadataOnly?.info ??
    null;

  // A successful spawn that wrote no twitter payload is a laundered failure
  // (rate-limited, blocked, or tampered response) — never a durable 0-result.
  if (!postInfo) {
    return failX(
      "yt-dlp wrote no info JSON for the post (rate-limited, blocked, or tampered response)",
    );
  }

  /** @param {number} entryCount */
  const degradationFailure = (entryCount) => {
    const degradation = detectSyndicationDegradation({
      stderr: stderrLog,
      postInfo,
      entryCount,
    });
    if (!degradation) {
      return null;
    }
    return failX(
      `${X_DEGRADED_ACQUISITION_PREFIX} (rate-limited syndication fallback is a partial response, retry later): ${JSON.stringify(degradation)}`,
    );
  };

  const probeDegradation = degradationFailure(inspected.twitterVideos.length);
  if (probeDegradation) {
    return probeDegradation;
  }

  // Caption cleanup — X word-timing tags are kept verbatim in the downloaded
  // VTT; `--convert-subs srt` yields clean text, converted back to the VTT
  // container the shared pipeline consumes.
  let captionCleanup = "none";
  const taggedVtts = [];
  for (const filePath of files.filter((entry) => entry.endsWith(".vtt"))) {
    if (String(await readFile(filePath)).includes(X_WORD_TIMING_TAG_MARKER)) {
      taggedVtts.push(filePath);
    }
  }
  if (taggedVtts.length > 0) {
    // Originals move aside (yt-dlp only re-downloads absent subtitles) and are
    // unlinked ONLY after the cleanup pass succeeds and produced output; a
    // failed cleanup fails the acquisition instead of silently losing captions.
    for (const filePath of taggedVtts) {
      await writeFile(
        `${filePath}${TAGGED_CAPTION_BACKUP_SUFFIX}`,
        String(await readFile(filePath)),
        "utf8",
      );
      await removeFile(filePath);
    }
    await sleep(resolveAcquirePhaseGapMs());
    const cleanupPass = await runPass("captions-only", { convertSubs: "srt" });
    stderrLog += `\n${cleanupPass.stderr ?? ""}`;
    files = await listFiles(workDir);
    const srtPaths = files.filter((entry) => entry.endsWith(".srt"));
    if (!cleanupPass.success || srtPaths.length === 0) {
      const detail = cleanupPass.success
        ? "cleanup pass produced no .srt output"
        : spawnFailureDetail(cleanupPass);
      return failX(`Caption cleanup failed after word-timing tags were detected: ${detail}`);
    }
    for (const srtPath of srtPaths) {
      await writeFile(
        srtPath.replace(/\.srt$/, ".vtt"),
        convertSrtToVtt(String(await readFile(srtPath))),
        "utf8",
      );
    }
    for (const filePath of taggedVtts) {
      await removeFile(`${filePath}${TAGGED_CAPTION_BACKUP_SUFFIX}`);
    }
    files = await listFiles(workDir);
    captionCleanup = "converted";
    inspected = await inspectInfoFiles(files, readFile);
    if (inspected.parseErrors.length > 0) {
      return failX(`Invalid info JSON: ${inspected.parseErrors.join("; ")}`);
    }
  }

  // Pass 2 — media, only in full mode and only when the post itself carries
  // twitter-extracted video (a blocked delegation or 0-media post never
  // reaches this pass).
  let mediaPassMs = null;
  if (mode === "full" && inspected.twitterVideos.length > 0) {
    await sleep(resolveAcquirePhaseGapMs());
    const mediaStarted = Date.now();
    const mediaPass = await runPass("video-only");
    if (!mediaPass.success) {
      return failX(spawnFailureDetail(mediaPass) || "yt-dlp media pass failed");
    }
    stderrLog += `\n${mediaPass.stderr ?? ""}`;
    mediaPassMs = Date.now() - mediaStarted;
    files = await listFiles(workDir);
  }

  const finalDegradation = degradationFailure(inspected.twitterVideos.length);
  if (finalDegradation) {
    return finalDegradation;
  }

  const firstVideoId = inspected.twitterVideos[0]?.info.id;
  const resultIdRaw = firstVideoId ?? postInfo?.id;
  const aliasingDelta = detectSnowflakeAliasing(
    statusId,
    typeof resultIdRaw === "string" ? resultIdRaw : null,
  );
  // Media ids always differ from the status id; only a FLAGGED aliasing (media
  // minted far before the URL's status) is recorded in slice metadata.
  const aliasing = aliasingDelta?.aliasSuspected ? aliasingDelta : null;

  const orderedVideos = orderTwitterVideos(inspected.twitterVideos, inspected.twitterPlaylist);
  const entries = orderedVideos.map((video) => {
    const artifacts = matchEntryArtifacts(files, String(video.info.id));
    const captionResult = selectCaptionFile(artifacts.captionPaths);
    return {
      mediaPath: mode === "full" ? artifacts.mediaPath : "",
      captionPaths: artifacts.captionPaths,
      metadataPath: video.path,
      caption: captionResult.success ? captionResult.selection : null,
    };
  });

  const metadata = buildXPostMetadata({ statusId, postInfo, aliasing, blockedDelegations: [] });
  const envelope = createAcquisitionEnvelope({
    entries,
    metadata,
    workDir,
    acquireMetrics: {
      stagedAcquire: true,
      probeFirst: true,
      ...(mediaPassMs !== null ? { mediaPassMs } : {}),
      captionCleanup,
    },
  });
  return /** @type {AcquireOutcome} */ (
    ok(envelope, "acquire-x-media", { label: statusId }, Date.now() - started)
  );
}

const spec = /** @satisfies {SourceAdapterSpec} */ ({
  id: "x",
  hosts: [...X_OWNED_HOSTS],
  extractorArgs: null,
  allowedExtractors: X_ALLOWED_EXTRACTORS,
  captionClass: "platform-asr",
  errorPatterns: {
    retryable: [...X_RETRYABLE_PATTERNS],
    fatal: [...X_FATAL_PATTERNS],
    loginRequired: [...X_LOGIN_REQUIRED_PATTERNS],
  },
  transcriptStrategy: /** @type {'captions+repair'} */ ("captions+repair"),
  capabilities: {
    comments: false,
    browserCookieFallback: false,
  },

  /**
   * Claim + canonicalization: the canonical status URL is re-derived here so
   * every entry path (watch, queue, transcript, resume, recovery) gets it by
   * construction.
   *
   * @param {string} url
   * @returns {UrlClaim|null}
   */
  matchUrl: (url) => {
    const parts = parseXStatusUrl(url);
    if (!parts) return null;
    return { sliceKey: parts.statusId, canonicalUrl: canonicalXStatusUrl(parts) };
  },

  /**
   * Canonical slice identity is the status id captured from the URL
   * (`display_id`); the media id rides in metadata as the media discriminator,
   * never in the slice key — so the same post always resolves the same slice.
   *
   * @param {string} url
   * @param {SourceMetadata|null} metadata
   * @returns {string|null}
   */
  extractSliceKey: (url, metadata) => {
    const parts = parseXStatusUrl(url);
    if (parts) return parts.statusId;
    if (!metadata) return null;
    const displayId = /** @type {Record<string, unknown>} */ (metadata)["source:displayId"];
    const fallback =
      typeof displayId === "string" && displayId ? displayId : metadata.id;
    // Path-safe AND length-bounded — the key becomes an on-disk directory segment.
    return typeof fallback === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(fallback)
      ? fallback
      : null;
  },

  /**
   * @param {string} url
   * @param {AcquireContext} context
   * @returns {Promise<AcquireOutcome>}
   */
  acquire: (url, context) => acquireXMedia(url, context),

  /**
   * Post-text links only (reply-chain harvest is the optional agent-lane
   * `/x:read` route). Blocked-delegation outbound links are appended so a
   * 0-media link post still records its link in provenance.
   *
   * @param {SourceMetadata} metadata
   * @returns {HarvestedLink[]}
   */
  harvestLinks: (metadata) => {
    /** @type {HarvestedLink[]} */
    const links = linksFromText(metadata.description, "description");
    const blocked = /** @type {Record<string, unknown>} */ (metadata)["source:blockedDelegations"];
    if (Array.isArray(blocked)) {
      for (const delegation of blocked) {
        const delegationUrl =
          delegation && typeof delegation === "object"
            ? /** @type {Record<string, unknown>} */ (delegation).url
            : null;
        if (typeof delegationUrl === "string" && delegationUrl) {
          links.push({
            url: delegationUrl,
            source: "description",
            timestampSec: null,
            context: "blocked delegation: outbound link from a media-less post",
          });
        }
      }
    }
    return deduplicateHarvestedLinks(links);
  },

  /**
   * @param {string} url
   * @returns {EnqueueDecision}
   */
  acceptForEnqueue: (url) => {
    const parts = parseXStatusUrl(url);
    if (!parts) {
      return {
        ok: false,
        note: "not an X status URL",
        reason: "URL does not resolve to an X (Twitter) status id",
      };
    }
    return { ok: true, key: parts.statusId };
  },
});

export const adapter = createSourceAdapter(spec);
