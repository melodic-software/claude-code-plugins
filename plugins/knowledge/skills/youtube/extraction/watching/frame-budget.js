/**
 * Frame selection summary — dynamic coverage, no hard truncation.
 */

/** @typedef {import('./models.js').SelectedFrame} SelectedFrame */

/**
 * @typedef {Object} FrameSelectionSummary
 * @property {SelectedFrame[]} selected
 * @property {number} candidateCount
 * @property {number} targetMinFrames
 * @property {boolean} highVolume
 * @property {boolean} overCap
 */

/** Minimum contact sheets before vision fan-out is advised. */
export const HIGH_VOLUME_CONTACT_SHEET_MIN = 8;

/** Minimum duration (seconds) before vision fan-out is advised. */
export const HIGH_VOLUME_DURATION_SEC_MIN = 7200;

/** Minimum densification windows before vision fan-out is advised. */
export const HIGH_VOLUME_DENSIFICATION_WINDOW_MIN = 30;

/**
 * Whether frame volume warrants parallel vision subagent fan-out.
 *
 * @param {object} [signals]
 * @param {number} [signals.candidateCount=0]
 * @param {number} [signals.targetMinFrames=0]
 * @param {number} [signals.contactSheetCount=0]
 * @param {number} [signals.durationSec=0]
 * @param {number} [signals.densificationWindowCount=0]
 * @returns {boolean}
 */
export function isHighVolume({
  candidateCount = 0,
  targetMinFrames = 0,
  contactSheetCount = 0,
  durationSec = 0,
  densificationWindowCount = 0,
} = {}) {
  if (contactSheetCount >= HIGH_VOLUME_CONTACT_SHEET_MIN) return true;
  if (durationSec >= HIGH_VOLUME_DURATION_SEC_MIN) return true;
  if (densificationWindowCount >= HIGH_VOLUME_DENSIFICATION_WINDOW_MIN) return true;
  return targetMinFrames > 0 && candidateCount > targetMinFrames * 3;
}

/**
 * Summarize frame selection without truncating candidates.
 *
 * @param {SelectedFrame[]} candidates
 * @param {object} [options]
 * @param {number} [options.targetMinFrames=0]
 * @param {number} [options.contactSheetCount=0]
 * @param {number} [options.durationSec=0]
 * @param {number} [options.densificationWindowCount=0]
 * @returns {FrameSelectionSummary}
 */
export function summarizeFrameSelection(
  candidates,
  {
    targetMinFrames = 0,
    contactSheetCount = 0,
    durationSec = 0,
    densificationWindowCount = 0,
  } = {},
) {
  const selected = [...candidates].sort((a, b) => {
    const aTs = a.timestampSec ?? 0;
    const bTs = b.timestampSec ?? 0;
    return aTs - bTs;
  });

  const candidateCount = selected.length;
  const highVolume = isHighVolume({
    candidateCount,
    targetMinFrames,
    contactSheetCount,
    durationSec,
    densificationWindowCount,
  });

  return {
    selected,
    candidateCount,
    targetMinFrames,
    highVolume,
    overCap: false,
  };
}
