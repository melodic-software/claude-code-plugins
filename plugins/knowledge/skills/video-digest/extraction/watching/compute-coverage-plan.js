/**
 * Dynamic per-video frame coverage plan — no hard cap.
 */

/** @typedef {import('./models.js').TranscriptCue} TranscriptCue */
/** @typedef {import('./models.js').DensificationWindow} DensificationWindow */

export const SHORT_VIDEO_MAX_SEC = 90;
export const SHORT_STRATIFIED_INTERVAL_SEC = 5;
export const LONG_STRATIFIED_INTERVAL_SEC = 60;
export const MEDIUM_STRATIFIED_INTERVAL_SEC = 45;
export const MEDIUM_DURATION_THRESHOLD_SEC = 300;
export const SCENE_SPARSE_RATIO = 120;

const DEFAULT_CUE_ANCHOR_PATTERNS = [
  /\blook at\b/i,
  /\bon screen\b/i,
  /\bshow you\b/i,
  /\bhere('s| is)\b/i,
  /\bcode\b/i,
  /\bterminal\b/i,
  /\bslide\b/i,
];

/**
 * @typedef {Object} CoveragePlan
 * @property {number} durationSec
 * @property {number} stratifiedIntervalSec
 * @property {number} densificationWindowCount
 * @property {number} targetMinFrames
 * @property {number|null} targetMaxFrames
 * @property {boolean} forceStratifiedPass
 * @property {string} rationale
 */

/**
 * @param {number} durationSec
 * @returns {number}
 */
export function stratifiedIntervalForDuration(durationSec) {
  if (durationSec <= SHORT_VIDEO_MAX_SEC) return SHORT_STRATIFIED_INTERVAL_SEC;
  if (durationSec <= MEDIUM_DURATION_THRESHOLD_SEC) return MEDIUM_STRATIFIED_INTERVAL_SEC;
  return LONG_STRATIFIED_INTERVAL_SEC;
}

/**
 * @param {number} durationSec
 * @param {number} intervalSec
 * @returns {number}
 */
export function estimateStratifiedFrameCount(durationSec, intervalSec) {
  if (durationSec <= 0 || intervalSec <= 0) return 0;
  return Math.max(1, Math.ceil(durationSec / intervalSec));
}

/**
 * Compute dynamic coverage targets from duration, transcript, and scene yield.
 *
 * @param {object} input
 * @param {number} input.durationSec
 * @param {DensificationWindow[]} input.densificationWindows
 * @param {number} [input.sceneCandidateCount=0]
 * @returns {CoveragePlan}
 */
export function computeCoveragePlan({
  durationSec,
  densificationWindows,
  sceneCandidateCount = 0,
}) {
  const safeDuration = Math.max(0, durationSec);
  const stratifiedIntervalSec = stratifiedIntervalForDuration(safeDuration);
  const baselineStratified = estimateStratifiedFrameCount(safeDuration, stratifiedIntervalSec);
  const densificationWindowCount = densificationWindows.length;
  const anchorBonus = densificationWindowCount * 2;
  const targetMinFrames = baselineStratified + anchorBonus;
  const forceStratifiedPass =
    sceneCandidateCount === 0 ||
    (safeDuration > 0 && sceneCandidateCount < safeDuration / SCENE_SPARSE_RATIO);

  let rationale;
  if (safeDuration <= SHORT_VIDEO_MAX_SEC) {
    rationale = `short video (${Math.round(safeDuration)}s): dense stratified every ${stratifiedIntervalSec}s + scene cuts`;
  } else if (forceStratifiedPass) {
    rationale = `sparse scene yield (${sceneCandidateCount} vs ${Math.round(safeDuration / SCENE_SPARSE_RATIO)} expected): add stratified every ${stratifiedIntervalSec}s + densification anchors`;
  } else {
    rationale = `${Math.round(safeDuration / 60)}m content: scene cuts + stratified every ${stratifiedIntervalSec}s + ${densificationWindowCount} densification windows`;
  }

  return {
    durationSec: safeDuration,
    stratifiedIntervalSec,
    densificationWindowCount,
    targetMinFrames,
    targetMaxFrames: null,
    forceStratifiedPass,
    rationale,
  };
}

/**
 * Timestamps for stratified interval sampling.
 *
 * @param {number} durationSec
 * @param {number} intervalSec
 * @returns {number[]}
 */
export function stratifiedSampleTimestamps(durationSec, intervalSec) {
  if (durationSec <= 0 || intervalSec <= 0) return [];
  /** @type {number[]} */
  const timestamps = [];
  for (let t = intervalSec / 2; t < durationSec; t += intervalSec) {
    timestamps.push(Number(t.toFixed(3)));
  }
  return timestamps;
}

/**
 * Midpoint timestamps for densification windows.
 *
 * @param {DensificationWindow[]} windows
 * @returns {number[]}
 */
export function densificationAnchorTimestamps(windows) {
  return windows.map((window) => Number(((window.startSec + window.endSec) / 2).toFixed(3)));
}

/**
 * Cue timestamps for high-signal transcript lines (screen/code/demo).
 *
 * @param {TranscriptCue[]} cues
 * @param {readonly RegExp[]} [patterns]
 * @returns {number[]}
 */
export function cueAnchorTimestamps(cues, patterns = DEFAULT_CUE_ANCHOR_PATTERNS) {
  /** @type {number[]} */
  const timestamps = [];
  for (const cue of cues) {
    if (!patterns.some((pattern) => pattern.test(cue.text))) continue;
    const midpoint = (cue.startSec + cue.endSec) / 2;
    timestamps.push(Number(midpoint.toFixed(3)));
  }
  return timestamps;
}
