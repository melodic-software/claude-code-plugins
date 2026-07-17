/**
 * Transcript-driven densification windows for adaptive frame sampling.
 *
 * High-signal segments (code, slides, demos) get denser sampling; talking-head
 * segments stay sparse. Starting keywords from RESEARCH lane 2.
 */

/** @typedef {import('./models.js').TranscriptCue} TranscriptCue */
/** @typedef {import('./models.js').DensificationWindow} DensificationWindow */

export const DEFAULT_WINDOW_PADDING_SEC = 5;
export const DEFAULT_DENSITY_MULTIPLIER = 3;
export const DEFAULT_SPARSE_MULTIPLIER = 1;

/** @type {readonly {pattern: RegExp, reason: string, multiplier?: number}[]} */
export const DENSIFICATION_SIGNALS = [
  { pattern: /\blet me show\b/i, reason: "demo-phrase" },
  { pattern: /\bhere we can see\b/i, reason: "demo-phrase" },
  { pattern: /\bwatch (this|how)\b/i, reason: "demo-phrase" },
  { pattern: /\bdemo(nstrate|stration)?\b/i, reason: "demo" },
  { pattern: /\bscreen\s*share\b/i, reason: "screen-share" },
  { pattern: /\bslide(s)?\b/i, reason: "slides" },
  { pattern: /\bpresentation\b/i, reason: "slides" },
  { pattern: /\bterminal\b/i, reason: "terminal", multiplier: 4 },
  { pattern: /\bconsole\b/i, reason: "terminal", multiplier: 4 },
  { pattern: /\bcode\b/i, reason: "code" },
  { pattern: /\bfunction\b/i, reason: "code" },
  { pattern: /\bclass\b/i, reason: "code" },
  { pattern: /\bimport\b/i, reason: "code" },
  { pattern: /\btypescript\b/i, reason: "code" },
  { pattern: /\bjavascript\b/i, reason: "code" },
  { pattern: /\bpython\b/i, reason: "code" },
  { pattern: /\bC#\b/i, reason: "code" },
  { pattern: /\b\.NET\b/i, reason: "code" },
];

/**
 * Find densification windows from transcript cues matching high-signal keywords.
 *
 * @param {TranscriptCue[]} cues
 * @param {object} [options]
 * @param {number} [options.paddingSec=5]
 * @param {number} [options.defaultMultiplier=3]
 * @param {typeof DENSIFICATION_SIGNALS} [options.signals]
 * @returns {DensificationWindow[]}
 */
export function findDensificationWindows(
  cues,
  {
    paddingSec = DEFAULT_WINDOW_PADDING_SEC,
    defaultMultiplier = DEFAULT_DENSITY_MULTIPLIER,
    signals = DENSIFICATION_SIGNALS,
  } = {},
) {
  /** @type {DensificationWindow[]} */
  const windows = [];

  for (const cue of cues) {
    for (const signal of signals) {
      if (!signal.pattern.test(cue.text)) continue;

      const multiplier = signal.multiplier ?? defaultMultiplier;
      windows.push({
        startSec: Math.max(0, cue.startSec - paddingSec),
        endSec: cue.endSec + paddingSec,
        densityMultiplier: multiplier,
        reason: signal.reason,
      });
      break;
    }
  }

  return mergeOverlappingWindows(windows);
}

/**
 * Merge overlapping densification windows, keeping the highest multiplier.
 *
 * @param {DensificationWindow[]} windows
 * @returns {DensificationWindow[]}
 */
export function mergeOverlappingWindows(windows) {
  if (windows.length === 0) return [];

  const sorted = [...windows].sort((a, b) => a.startSec - b.startSec);
  /** @type {DensificationWindow[]} */
  const merged = [{ ...sorted[0] }];

  for (let i = 1; i < sorted.length; i++) {
    const current = sorted[i];
    const last = merged[merged.length - 1];

    if (current.startSec <= last.endSec) {
      last.endSec = Math.max(last.endSec, current.endSec);
      last.densityMultiplier = Math.max(last.densityMultiplier, current.densityMultiplier);
      if (last.reason !== current.reason) {
        last.reason = `${last.reason}+${current.reason}`;
      }
    } else {
      merged.push({ ...current });
    }
  }

  return merged;
}

/**
 * Density multiplier at a given timestamp (1 outside windows).
 *
 * @param {number} timestampSec
 * @param {DensificationWindow[]} windows
 * @returns {number}
 */
export function densityAtTimestamp(timestampSec, windows) {
  let max = DEFAULT_SPARSE_MULTIPLIER;
  for (const window of windows) {
    if (timestampSec >= window.startSec && timestampSec <= window.endSec) {
      max = Math.max(max, window.densityMultiplier);
    }
  }
  return max;
}

/**
 * Score a frame by densification windows and base scene priority.
 *
 * @param {import('@melodic/video-digestion/frames/models.js').FrameCandidate} frame
 * @param {number} index - Ordinal position in unique frame list
 * @param {DensificationWindow[]} windows
 * @returns {number}
 */
export function scoreFramePriority(frame, index, windows) {
  const timestamp = frame.timestampSec ?? index;
  const density = densityAtTimestamp(timestamp, windows);
  const intervalPenalty = frame.isInterval ? 0.5 : 1;
  return density * intervalPenalty + (frame.sceneScore ?? 0);
}
