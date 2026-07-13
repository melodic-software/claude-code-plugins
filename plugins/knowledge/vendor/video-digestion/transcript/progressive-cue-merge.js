/**
 * Progressive / rolling caption cue merge — shared by auto and manual YouTube VTT.
 */

import { parseVttSegment } from "./vtt-parser.js";

/** @typedef {import('./vtt-parser.js').VttCue} VttCue */

const WHITESPACE_RUN = /\s+/g;

/**
 * @param {string} text
 * @returns {string}
 */
export function normalizeProgressiveText(text) {
  return text.toLowerCase().replace(WHITESPACE_RUN, " ").trim();
}

const ADJACENT_CUE_EPSILON_SEC = 0.02;

/**
 * @param {VttCue} a
 * @param {VttCue} b
 * @returns {boolean}
 */
export function cuesOverlap(a, b) {
  return a.startSec < b.endSec && b.startSec < a.endSec;
}

/**
 * Whether cues are back-to-back or overlapping (YouTube manual-EN uses touching timestamps).
 *
 * @param {VttCue} a
 * @param {VttCue} b
 * @returns {boolean}
 */
export function cuesTouchOrOverlap(a, b) {
  if (cuesOverlap(a, b)) return true;
  const gap = b.startSec - a.endSec;
  return gap >= 0 && gap <= ADJACENT_CUE_EPSILON_SEC;
}

/**
 * @param {string} earlier
 * @param {string} later
 * @returns {boolean}
 */
export function isProgressiveExtension(earlier, later) {
  const normEarlier = normalizeProgressiveText(earlier);
  const normLater = normalizeProgressiveText(later);
  if (!normEarlier || !normLater) return false;
  return normLater.startsWith(normEarlier) || normLater.includes(normEarlier);
}

/**
 * @param {VttCue[]} cues
 * @param {object} [options]
 * @param {number} [options.overlapToleranceSec=0.05]
 * @returns {VttCue[]}
 */
export function deduplicateOverlappingCues(
  cues,
  { overlapToleranceSec: _overlapToleranceSec = 0.05 } = {},
) {
  if (cues.length === 0) return [];

  const sorted = [...cues].sort((a, b) => a.startSec - b.startSec || a.endSec - b.endSec);
  /** @type {VttCue[]} */
  const kept = [];

  for (const cue of sorted) {
    const prev = kept[kept.length - 1];
    if (!prev) {
      kept.push({ ...cue });
      continue;
    }

    const touchesOrOverlaps = cuesTouchOrOverlap(prev, cue);
    const progressive =
      touchesOrOverlaps &&
      (isProgressiveExtension(prev.text, cue.text) ||
        normalizeProgressiveText(prev.text) === normalizeProgressiveText(cue.text));

    if (progressive) {
      if (normalizeProgressiveText(cue.text).length >= normalizeProgressiveText(prev.text).length) {
        kept[kept.length - 1] = {
          startSec: Math.min(prev.startSec, cue.startSec),
          endSec: Math.max(prev.endSec, cue.endSec),
          text: cue.text,
        };
      }
      continue;
    }

    kept.push({ ...cue });
  }

  return kept;
}

/**
 * @param {VttCue[]} cues
 * @param {object} [options]
 * @param {number} [options.maxGapSec=0.5]
 * @returns {VttCue[]}
 */
export function mergeProgressiveCues(cues, { maxGapSec = 0.5 } = {}) {
  if (cues.length === 0) return [];

  /** @type {VttCue[]} */
  const merged = [{ ...cues[0] }];

  for (let i = 1; i < cues.length; i++) {
    const prev = merged[merged.length - 1];
    const cue = cues[i];
    const gap = cue.startSec - prev.endSec;
    const extendsPrev = isProgressiveExtension(prev.text, cue.text);

    if (gap <= maxGapSec && extendsPrev) {
      prev.endSec = Math.max(prev.endSec, cue.endSec);
      prev.text = cue.text;
      continue;
    }

    merged.push({ ...cue });
  }

  return merged;
}

/**
 * @param {VttCue[]} cues
 * @param {object} [options]
 * @returns {VttCue[]}
 */
export function mergeProgressiveCaptionCues(cues, options = {}) {
  const deduped = deduplicateOverlappingCues(cues, options);
  return mergeProgressiveCues(deduped, options);
}

/**
 * @param {string} vttText
 * @returns {boolean}
 */
export function shouldCleanProgressiveCaptions(vttText) {
  const cues = parseVttSegment(vttText);
  if (cues.length < 2) return false;

  for (let i = 1; i < cues.length; i++) {
    const prev = cues[i - 1];
    const cue = cues[i];
    if (cuesTouchOrOverlap(prev, cue) && isProgressiveExtension(prev.text, cue.text)) {
      return true;
    }
  }

  return false;
}
