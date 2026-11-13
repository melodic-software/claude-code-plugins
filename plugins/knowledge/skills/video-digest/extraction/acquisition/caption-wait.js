/**
 * Caption wait for a live-derived YouTube video: auto-captions on a just-ended
 * stream appear only after the platform's post-stream processing, so an
 * exhausted caption ladder on such a video waits for them, within a bounded
 * window, instead of digesting caption-less. The yt-dlp `live_status` values
 * and the decision behind this module are cited in `reference/sources/youtube.md`.
 */

/** How long a held video waits between caption re-checks. */
export const CAPTION_WAIT_CHECK_INTERVAL_MS = 30 * 60 * 1000;

/** Longest wait, counted from the stream's end (or from the first hold when the end is unknown). */
export const CAPTION_WAIT_MAX_MS = 12 * 60 * 60 * 1000;

/** Exit code a CLI returns while captions are pending. */
export const CAPTIONS_PENDING_EXIT = 3;

/** `live_status` values whose captions may still be in processing. */
const LIVE_DERIVED_STATUSES = new Set(["is_live", "post_live", "was_live"]);

/**
 * @typedef {Object} LiveStreamInfo
 * @property {string|null} liveStatus - yt-dlp `live_status`; null when absent
 * @property {number|null} endedAtMs - stream start (`release_timestamp`) plus `duration`; null when either is absent
 */

/**
 * @typedef {{ state: 'none' } |
 *   { state: 'wait', liveStatus: string, nextCheckAt: string, deadline: string } |
 *   { state: 'expired', liveStatus: string, deadline: string }} CaptionWaitDecision
 */

/**
 * @param {unknown} value
 * @returns {number|null}
 */
function finiteNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * @param {unknown} info - parsed yt-dlp info.json
 * @returns {LiveStreamInfo}
 */
export function liveStreamInfo(info) {
  const record =
    info && typeof info === "object" ? /** @type {Record<string, unknown>} */ (info) : {};
  const liveStatus = typeof record.live_status === "string" ? record.live_status : null;
  const startSec = finiteNumber(record.release_timestamp);
  const durationSec = finiteNumber(record.duration);
  const endedAtMs = startSec !== null && durationSec !== null ? (startSec + durationSec) * 1000 : null;
  return { liveStatus, endedAtMs };
}

/**
 * Decide whether a video with no captions waits for them.
 *
 * `deadline` is the one a queue row recorded at its first hold; it makes the
 * wait bounded across runs. Without it the deadline is the stream end plus the
 * maximum wait, or now plus the maximum wait for a stream whose end is unknown.
 * A `was_live` video with no known end, or one whose wait passed without a
 * recorded hold, is not waited on: nothing shows its captions are still coming.
 *
 * @param {LiveStreamInfo} stream
 * @param {{ deadline?: string|null, nowMs?: number }} [options]
 * @returns {CaptionWaitDecision}
 */
export function decideCaptionWait({ liveStatus, endedAtMs }, { deadline = null, nowMs = Date.now() } = {}) {
  if (liveStatus === null || !LIVE_DERIVED_STATUSES.has(liveStatus)) {
    return { state: "none" };
  }
  const heldDeadlineMs = deadline ? Date.parse(deadline) : Number.NaN;
  const held = Number.isFinite(heldDeadlineMs);
  if (!held && endedAtMs === null && liveStatus === "was_live") {
    return { state: "none" };
  }
  const deadlineMs = held ? heldDeadlineMs : (endedAtMs === null ? nowMs : endedAtMs) + CAPTION_WAIT_MAX_MS;

  if (nowMs < deadlineMs) {
    return {
      state: "wait",
      liveStatus,
      nextCheckAt: new Date(Math.min(nowMs + CAPTION_WAIT_CHECK_INTERVAL_MS, deadlineMs)).toISOString(),
      deadline: new Date(deadlineMs).toISOString(),
    };
  }
  return held
    ? { state: "expired", liveStatus, deadline: new Date(deadlineMs).toISOString() }
    : { state: "none" };
}

/**
 * @param {{ liveStatus: string, nextCheckAt: string, deadline: string }} wait
 * @returns {string}
 */
export function captionsPendingMessage({ liveStatus, nextCheckAt, deadline }) {
  return `captions pending, next check at ${nextCheckAt} (live_status ${liveStatus}; wait ends ${deadline})`;
}

/**
 * The stdout payload of a run the caption wait held.
 *
 * @param {{ liveStatus: string, nextCheckAt: string, deadline: string }} wait
 */
export function captionsPendingReport(wait) {
  const { liveStatus, nextCheckAt, deadline } = wait;
  return { captionsPending: true, liveStatus, nextCheckAt, deadline, message: captionsPendingMessage(wait) };
}

/**
 * @param {{ liveStatus: string, deadline: string }} expired
 * @returns {string}
 */
export function captionWaitEndedNote({ liveStatus, deadline }) {
  return `caption wait ended at deadline ${deadline} with no captions (live_status ${liveStatus}); falls through to ASR or transcriptDegradation`;
}

/**
 * The value of a `--caption-wait-deadline <iso>` flag, normalized to UTC ISO form; null when absent.
 *
 * @param {string[]} argv
 * @returns {{ ok: true, deadline: string|null } | { ok: false, error: string }}
 */
export function parseCaptionWaitDeadline(argv) {
  const index = argv.indexOf("--caption-wait-deadline");
  if (index === -1) return { ok: true, deadline: null };
  const deadline = toIsoTime(argv[index + 1]);
  return deadline
    ? { ok: true, deadline }
    : { ok: false, error: "`--caption-wait-deadline` requires an ISO 8601 time" };
}

/**
 * A time normalized to the UTC ISO form the queue's `notes` record; null when unparsable.
 *
 * @param {string|undefined} value
 * @returns {string|null}
 */
export function toIsoTime(value) {
  const ms = value ? Date.parse(value) : Number.NaN;
  return Number.isNaN(ms) ? null : new Date(ms).toISOString();
}
