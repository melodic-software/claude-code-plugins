/**
 * Metadata versus probed duration mismatch for `/video-digest watch`.
 *
 * The pipeline plans frames from the probed media duration. A post-live stream can
 * serve an edit far shorter than its metadata claims (metadata 10446 s, served edit
 * 3995 s), so a slice reader who sees the metadata duration beside a shorter
 * transcript needs both values recorded. Which duration the pipeline uses is
 * unchanged; this module only decides whether the two disagree and writes the record.
 */

import fs from "node:fs/promises";
import path from "node:path";

/**
 * Absolute tolerance floor (seconds). yt-dlp reports an integer-second metadata
 * duration and a container probe differs from it by a fraction of a second to a few
 * seconds (rounding, leading/trailing stream padding), so a gap this small is noise.
 */
export const DURATION_MISMATCH_FLOOR_SEC = 5;

/**
 * Relative tolerance (fraction of the longer duration). A long stream's container and
 * metadata can drift further than the floor without any edit, so the allowance scales.
 */
export const DURATION_MISMATCH_RELATIVE = 0.01;

/**
 * @typedef {Object} DurationMismatch
 * @property {number} metadataDurationSec - duration the source metadata reports
 * @property {number} probedDurationSec - duration of the media file the pipeline used
 * @property {number} deltaSec - absolute difference
 * @property {number} thresholdSec - tolerance the difference exceeded
 */

/**
 * @param {unknown} value
 * @returns {value is number}
 */
function isPositiveFinite(value) {
  return typeof value === "number" && Number.isFinite(value) && value > 0;
}

/**
 * Compare the metadata duration with the probed media duration.
 *
 * Returns null when either value is missing or non-positive (nothing to compare) or
 * when they agree within `max(floor, relative × longer)`.
 *
 * @param {unknown} metadataDurationSec
 * @param {unknown} probedDurationSec
 * @returns {DurationMismatch|null}
 */
export function detectDurationMismatch(metadataDurationSec, probedDurationSec) {
  if (!(isPositiveFinite(metadataDurationSec) && isPositiveFinite(probedDurationSec))) {
    return null;
  }
  const deltaSec = Math.abs(metadataDurationSec - probedDurationSec);
  const thresholdSec = Math.max(
    DURATION_MISMATCH_FLOOR_SEC,
    DURATION_MISMATCH_RELATIVE * Math.max(metadataDurationSec, probedDurationSec),
  );
  if (deltaSec <= thresholdSec) return null;
  return { metadataDurationSec, probedDurationSec, deltaSec, thresholdSec };
}

/**
 * @param {number} totalSec
 * @returns {string} `H:MM:SS`
 */
export function formatClock(totalSec) {
  const whole = Math.round(totalSec);
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  const seconds = whole % 60;
  return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

/**
 * Record a metadata versus probed duration mismatch on the watch state and in the slice
 * README. Writes nothing when the durations agree within the threshold, or when the
 * probe gave no duration (the pipeline then fell back to the transcript's last cue and
 * there is no probed value to set beside the metadata).
 *
 * @param {import('./watch-state.js').WatchState} state
 * @param {string} sliceDir
 * @param {{ metadataDurationSec: unknown, probedDurationSec: unknown }} durations
 * @returns {Promise<import('./watch-state.js').WatchState>} the state, with
 *   `durationMismatch` set when a mismatch was recorded
 */
export async function recordDurationMismatch(state, sliceDir, durations) {
  const mismatch = detectDurationMismatch(
    durations.metadataDurationSec,
    durations.probedDurationSec,
  );
  if (!mismatch) return state;
  await appendDurationMismatchToReadme(sliceDir, mismatch);
  return { ...state, durationMismatch: mismatch };
}

/** Heading of the README section; its presence makes the append idempotent. */
export const DURATION_MISMATCH_HEADING = "## Duration mismatch";

/**
 * @param {DurationMismatch} mismatch
 * @returns {string}
 */
export function renderDurationMismatchSection(mismatch) {
  const { metadataDurationSec, probedDurationSec } = mismatch;
  return `${DURATION_MISMATCH_HEADING}

The source metadata reports ${formatClock(metadataDurationSec)} (${Math.round(metadataDurationSec)} s), but the media file this watch used is ${formatClock(probedDurationSec)} (${Math.round(probedDurationSec)} s). The transcript and frames cover the media file, so they can be shorter than the metadata duration suggests.
`;
}

/**
 * Append the mismatch section to the slice README. A no-op when the README already
 * carries the section, so a re-run does not duplicate it.
 *
 * @param {string} sliceDir
 * @param {DurationMismatch} mismatch
 * @returns {Promise<boolean>} true when the section was written
 */
export async function appendDurationMismatchToReadme(sliceDir, mismatch) {
  const readmePath = path.join(sliceDir, "README.md");
  const existing = await fs.readFile(readmePath, "utf8");
  if (existing.includes(DURATION_MISMATCH_HEADING)) return false;
  const separator = existing.endsWith("\n") ? "\n" : "\n\n";
  await fs.writeFile(
    readmePath,
    `${existing}${separator}${renderDurationMismatchSection(mismatch)}`,
    "utf8",
  );
  return true;
}
