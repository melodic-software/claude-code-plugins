/**
 * Time range for a ranged `watch` (`--from <h:mm:ss>` / `--to <h:mm:ss>`).
 *
 * Acquisition downloads only the range (yt-dlp `--download-sections "*<from>-<to>"`),
 * so the media file starts at the range's start. Watching runs in that media time;
 * everything the slice stores is full-video time, the range's start added back here.
 *
 * We do not force the cut to `--from` (no `--force-keyframes-at-cuts`), so the media
 * can begin before it; the extra length is the error bound recorded on the offset
 * ({@link keyframeOffsetErrorSec}). Where the cut lands is read live: yt-dlp's
 * download options (https://github.com/yt-dlp/yt-dlp#download-options) and ffmpeg's
 * `-ss` (https://ffmpeg.org/ffmpeg.html#Main-options).
 */

import { formatClock } from "../watch/duration-mismatch.js";

/**
 * @typedef {Object} TimeRange
 * @property {number} fromSec - range start in full-video seconds; 0 when `--from` is omitted
 * @property {number|null} toSec - range end in full-video seconds; null when `--to` is omitted
 */

/**
 * Parse `h:mm:ss`, `m:ss` or plain seconds into whole seconds. Every field after
 * the first is at most 59.
 *
 * @param {string|undefined} value
 * @returns {number|null} null when the value is not a clock time
 */
export function parseClock(value) {
  const fields = (value ?? "").split(":");
  if (fields.length > 3 || !fields.every((field) => /^\d+$/.test(field))) return null;
  const numbers = fields.map(Number);
  if (numbers.slice(1).some((field) => field > 59)) return null;
  return numbers.reduce((total, field) => total * 60 + field, 0);
}

/**
 * @param {string[]} argv
 * @param {string} flag
 * @returns {{ ok: true, sec: number|null } | { ok: false, error: string }}
 */
function parseClockFlag(argv, flag) {
  const index = argv.indexOf(flag);
  if (index === -1) return { ok: true, sec: null };
  const sec = parseClock(argv[index + 1]);
  if (sec === null) {
    return { ok: false, error: `${flag} requires a time as h:mm:ss, m:ss or seconds` };
  }
  return { ok: true, sec };
}

/**
 * Parse `--from` / `--to` out of argv. Either bound is optional; with neither the
 * run digests the whole video (`range: null`).
 *
 * @param {string[]} argv
 * @returns {{ ok: true, range: TimeRange|null } | { ok: false, error: string }}
 */
export function parseTimeRangeArgs(argv) {
  const from = parseClockFlag(argv, "--from");
  if (!from.ok) return from;
  const to = parseClockFlag(argv, "--to");
  if (!to.ok) return to;
  if (from.sec === null && to.sec === null) return { ok: true, range: null };
  const fromSec = from.sec ?? 0;
  if (to.sec !== null && to.sec <= fromSec) {
    return { ok: false, error: "--to must be later than --from (or 0:00:00 without --from)" };
  }
  return { ok: true, range: { fromSec, toSec: to.sec } };
}

/**
 * The yt-dlp `--download-sections` value for a range: `*<from>-<to>`, with `inf`
 * for an open end.
 *
 * @param {TimeRange} range
 * @returns {string}
 */
export function downloadSectionSpec(range) {
  const end = range.toSec === null ? "inf" : formatClock(range.toSec);
  return `*${formatClock(range.fromSec)}-${end}`;
}

/**
 * `1:00:00 to 1:20:00`, or `1:00:00 to the end` for an open end.
 *
 * @param {TimeRange} range
 * @returns {string}
 */
export function describeTimeRange(range) {
  const end = range.toSec === null ? "the end" : formatClock(range.toSec);
  return `${formatClock(range.fromSec)} to ${end}`;
}

/**
 * Error bound on the range's start offset: how much longer the media is than the
 * range asked for, which is the segment a keyframe-aligned cut kept before `--from`.
 * Zero when the range starts at 0 (nothing to seek). Null when either duration is
 * unknown. A `--to` past the video's end is capped at the video duration, since the
 * media then stops at the end of the video, not at `--to`.
 *
 * @param {TimeRange} range
 * @param {{ probedDurationSec: number|null|undefined, videoDurationSec: number|null|undefined }} durations
 * @returns {number|null}
 */
export function keyframeOffsetErrorSec(range, { probedDurationSec, videoDurationSec }) {
  if (range.fromSec === 0) return 0;
  const endSec =
    range.toSec !== null && isFiniteNumber(videoDurationSec)
      ? Math.min(range.toSec, videoDurationSec)
      : (range.toSec ?? videoDurationSec);
  if (!isFiniteNumber(endSec) || !isFiniteNumber(probedDurationSec)) return null;
  const extra = probedDurationSec - (endSec - range.fromSec);
  return Math.max(0, Math.round(extra * 1000) / 1000);
}

/**
 * @param {unknown} value
 * @returns {value is number}
 */
function isFiniteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

/**
 * The cues that overlap the range, moved into media time (the range's start at 0),
 * for watching to run on the ranged media file.
 *
 * @template {{ startSec: number, endSec: number }} Cue
 * @param {readonly Cue[]} cues - full-video time
 * @param {TimeRange} range
 * @returns {Cue[]}
 */
export function cuesInMediaTime(cues, range) {
  const endSec = range.toSec ?? Number.POSITIVE_INFINITY;
  return cues
    .filter((cue) => cue.endSec > range.fromSec && cue.startSec < endSec)
    .map((cue) => ({
      ...cue,
      startSec: Math.max(0, cue.startSec - range.fromSec),
      endSec: Math.min(endSec, cue.endSec) - range.fromSec,
    }));
}

/**
 * Move media-time cues (ASR run on the ranged media) into full-video time.
 *
 * @template {{ startSec: number, endSec: number }} Cue
 * @param {readonly Cue[]} cues
 * @param {number} offsetSec
 * @returns {Cue[]}
 */
export function cuesInVideoTime(cues, offsetSec) {
  return cues.map((cue) => ({
    ...cue,
    startSec: cue.startSec + offsetSec,
    endSec: cue.endSec + offsetSec,
  }));
}

/**
 * @template {{ timestampSec?: number|null, timestampErrorSec?: number|null }} Frame
 * @param {Frame} frame
 * @param {number} offsetSec
 * @param {number} offsetErrorSec
 * @returns {Frame}
 */
function frameInVideoTime(frame, offsetSec, offsetErrorSec) {
  if (frame.timestampSec == null || !Number.isFinite(frame.timestampSec)) return frame;
  return {
    ...frame,
    timestampSec: frame.timestampSec + offsetSec,
    ...(offsetErrorSec > 0
      ? { timestampErrorSec: (frame.timestampErrorSec ?? 0) + offsetErrorSec }
      : {}),
  };
}

/**
 * Move a watching result from media time into full-video time: every frame time,
 * densification window and timeline entry gets the range's start added, and a timed
 * frame's `timestampErrorSec` grows by the offset's error bound. Durations, counts
 * and the coverage plan describe the range itself and stay as they are.
 *
 * @param {import('../watching/models.js').WatchingSelectionState} watching
 * @param {{ offsetSec: number, offsetErrorSec: number|null }} offset
 * @returns {import('../watching/models.js').WatchingSelectionState}
 */
export function watchingInVideoTime(watching, { offsetSec, offsetErrorSec }) {
  const errorSec = offsetErrorSec ?? 0;
  return {
    ...watching,
    sceneFrames: watching.sceneFrames.map((f) => frameInVideoTime(f, offsetSec, errorSec)),
    uniqueFrames: watching.uniqueFrames.map((f) => frameInVideoTime(f, offsetSec, errorSec)),
    selectedFrames: watching.selectedFrames.map((f) => frameInVideoTime(f, offsetSec, errorSec)),
    densificationWindows: watching.densificationWindows.map((window) => ({
      ...window,
      startSec: window.startSec + offsetSec,
      endSec: window.endSec + offsetSec,
    })),
    interleavedTimeline: watching.interleavedTimeline.map((entry) => ({
      ...entry,
      timestampSec:
        entry.timestampSec == null || !Number.isFinite(entry.timestampSec)
          ? entry.timestampSec
          : entry.timestampSec + offsetSec,
      ...(entry.frame ? { frame: frameInVideoTime(entry.frame, offsetSec, errorSec) } : {}),
    })),
  };
}
