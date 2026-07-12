/**
 * Vision read resolution policy per design-threads T3.
 *
 * Contact-sheet triage: 1280×720 canvas (~1229 tok).
 * Detail reads default 1280×720; escalate to native 1920×1080 for text-dense frames.
 */

/** @typedef {import('./models.js').SelectedFrame} SelectedFrame */
/** @typedef {import('./models.js').DensificationWindow} DensificationWindow */

export const DEFAULT_DETAIL_RESOLUTION = "1280x720";
export const NATIVE_ESCALATION_RESOLUTION = "1920x1080";

/** Reasons that imply text-dense on-screen content. */
export const TEXT_DENSE_REASONS = new Set(["code", "terminal", "slides", "demo", "screen-share"]);

/**
 * Whether a densification reason implies text-dense frame content.
 *
 * @param {string} reason
 * @returns {boolean}
 */
export function isTextDenseReason(reason) {
  return (
    TEXT_DENSE_REASONS.has(reason) || reason.split("+").some((part) => TEXT_DENSE_REASONS.has(part))
  );
}

/**
 * Whether a frame falls in a text-dense densification window.
 *
 * @param {number|null|undefined} timestampSec
 * @param {DensificationWindow[]} windows
 * @returns {boolean}
 */
export function isInTextDenseWindow(timestampSec, windows) {
  if (timestampSec == null) return false;
  return windows.some(
    (window) =>
      timestampSec >= window.startSec &&
      timestampSec <= window.endSec &&
      isTextDenseReason(window.reason),
  );
}

/**
 * Resolve detail-read resolution for a frame per T3.
 *
 * @param {number|null|undefined} timestampSec
 * @param {DensificationWindow[]} windows
 * @param {boolean} [forceTextDense=false]
 * @returns {'1280x720'|'1920x1080'}
 */
export function resolveReadResolution(timestampSec, windows, forceTextDense = false) {
  if (forceTextDense || isInTextDenseWindow(timestampSec, windows)) {
    return NATIVE_ESCALATION_RESOLUTION;
  }
  return DEFAULT_DETAIL_RESOLUTION;
}

/**
 * Apply read policy to a scored frame candidate.
 *
 * @param {import('@melodic/video-digestion/frames/models.js').FrameCandidate} frame
 * @param {number} priorityScore
 * @param {DensificationWindow[]} windows
 * @returns {SelectedFrame}
 */
export function toSelectedFrame(frame, priorityScore, windows) {
  const textDense = isInTextDenseWindow(frame.timestampSec, windows);
  const readResolution = resolveReadResolution(frame.timestampSec, windows, textDense);

  return {
    path: frame.path,
    file: frame.file,
    timestampSec: frame.timestampSec ?? null,
    priorityScore,
    textDense,
    readResolution,
    likelyDuplicate: frame.likelyDuplicate,
    isInterval: frame.isInterval,
  };
}
