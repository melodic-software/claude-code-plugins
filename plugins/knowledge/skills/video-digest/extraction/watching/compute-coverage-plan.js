/**
 * Dynamic per-video frame coverage plan — no hard cap.
 */

import { findDensificationWindows } from "./densification.js";

/** @typedef {import('./models.js').TranscriptCue} TranscriptCue */
/** @typedef {import('./models.js').DensificationWindow} DensificationWindow */

export const SHORT_VIDEO_MAX_SEC = 90;
export const SHORT_STRATIFIED_INTERVAL_SEC = 5;
export const LONG_STRATIFIED_INTERVAL_SEC = 60;
export const MEDIUM_STRATIFIED_INTERVAL_SEC = 45;
export const MEDIUM_DURATION_THRESHOLD_SEC = 300;
export const SCENE_SPARSE_RATIO = 120;
/**
 * Longest stretch, in seconds, allowed between two timed frames before a gap-fill
 * frame is extracted. Defaults to the long-video stratified interval. Basis:
 * judgment; each fill frame costs vision tokens. Override per run with
 * `run-watch.js --max-frame-gap-sec <sec>`.
 */
export const MAX_FRAME_GAP_SEC = LONG_STRATIFIED_INTERVAL_SEC;

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
 * Round a second value to the timestamp precision the pipeline emits.
 *
 * @param {number} sec
 * @returns {number}
 */
function roundSec(sec) {
  return Number(sec.toFixed(3));
}

/**
 * @typedef {Object} CoveragePlan
 * @property {number} durationSec
 * @property {number} stratifiedIntervalSec
 * @property {number} densificationWindowCount
 * @property {number} targetMinFrames
 * @property {number|null} targetMaxFrames
 * @property {boolean} forceStratifiedPass
 * @property {number} maxFrameGapSec
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
 * @param {number} [input.maxFrameGapSec=MAX_FRAME_GAP_SEC]
 * @returns {CoveragePlan}
 */
export function computeCoveragePlan({
  durationSec,
  densificationWindows,
  sceneCandidateCount = 0,
  maxFrameGapSec = MAX_FRAME_GAP_SEC,
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

  let content;
  if (safeDuration <= SHORT_VIDEO_MAX_SEC) {
    content = `short video (${Math.round(safeDuration)}s)`;
  } else if (forceStratifiedPass) {
    content = `sparse scene yield (${sceneCandidateCount} vs ${Math.round(safeDuration / SCENE_SPARSE_RATIO)} expected)`;
  } else {
    content = `${Math.round(safeDuration / 60)}m content`;
  }
  const sampling = [
    "scene cuts",
    ...(forceStratifiedPass ? [`stratified every ${stratifiedIntervalSec}s`] : []),
    `gap fill above ${maxFrameGapSec}s`,
    `${densificationWindowCount} densification windows`,
  ];

  return {
    durationSec: safeDuration,
    stratifiedIntervalSec,
    densificationWindowCount,
    targetMinFrames,
    targetMaxFrames: null,
    forceStratifiedPass,
    maxFrameGapSec,
    rationale: `${content}: ${sampling.join(" + ")}`,
  };
}

/**
 * Parse the `--max-frame-gap-sec` override out of argv.
 *
 * @param {string[]} argv
 * @returns {{ ok: true, override: number|null } | { ok: false, error: string }}
 */
export function parseMaxFrameGapSecOverride(argv) {
  const flagIndex = argv.indexOf("--max-frame-gap-sec");
  if (flagIndex === -1) {
    return { ok: true, override: null };
  }
  const value = Number(argv[flagIndex + 1]);
  if (!Number.isFinite(value) || value <= 0) {
    return { ok: false, error: "--max-frame-gap-sec requires a positive number of seconds" };
  }
  return { ok: true, override: value };
}

/**
 * Densification windows plus the coverage plan they feed, for callers that
 * need both from the same cue list.
 *
 * @param {TranscriptCue[]} cues
 * @param {object} input
 * @param {number} input.durationSec
 * @param {number} [input.sceneCandidateCount=0]
 * @param {number} [input.maxFrameGapSec]
 * @returns {{ windows: DensificationWindow[], coveragePlan: CoveragePlan }}
 */
export function planFrameCoverage(cues, { durationSec, sceneCandidateCount = 0, maxFrameGapSec }) {
  const windows = findDensificationWindows(cues);
  return {
    windows,
    coveragePlan: computeCoveragePlan({
      durationSec,
      densificationWindows: windows,
      sceneCandidateCount,
      maxFrameGapSec,
    }),
  };
}

/**
 * Timestamps that split every stretch longer than `maxGapSec` without a timed
 * frame, counting 0 to the first frame and the last frame to the end, into
 * equal parts no longer than `maxGapSec`.
 *
 * @param {number[]} timestampsSec - times of frames already held; untimed frames are left out
 * @param {number} durationSec
 * @param {number} maxGapSec
 * @returns {number[]}
 */
export function gapFillTimestamps(timestampsSec, durationSec, maxGapSec) {
  if (durationSec <= 0 || maxGapSec <= 0) return [];
  const bounds = [0, ...[...timestampsSec].sort((a, b) => a - b), durationSec];
  /** @type {number[]} */
  const fill = [];
  for (let i = 1; i < bounds.length; i++) {
    const start = bounds[i - 1];
    const gap = bounds[i] - start;
    if (gap <= maxGapSec) continue;
    const parts = Math.ceil(gap / maxGapSec);
    for (let k = 1; k < parts; k++) {
      fill.push(roundSec(start + (gap * k) / parts));
    }
  }
  return fill;
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
    timestamps.push(roundSec(t));
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
  return windows.map((window) => roundSec((window.startSec + window.endSec) / 2));
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
    timestamps.push(roundSec((cue.startSec + cue.endSec) / 2));
  }
  return timestamps;
}
