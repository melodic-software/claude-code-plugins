/**
 * YouTube auto-caption WebVTT cleaning.
 *
 * yt-dlp downloads auto-captions as-is — overlapping progressive cues with
 * no punctuation. This opt-in pre-parser step deduplicates overlapping cues
 * and merges adjacent incremental text before the standard VTT parser runs.
 *
 * Course-platform VTT (clean manual captions) should skip this step.
 */

import {
  cuesOverlap,
  deduplicateOverlappingCues,
  isProgressiveExtension,
  mergeProgressiveCaptionCues,
  mergeProgressiveCues,
  normalizeProgressiveText,
  shouldCleanProgressiveCaptions,
} from "./progressive-cue-merge.js";
import { parseVttSegment } from "./vtt-parser.js";

const VTT_TIMESTAMP = /(\d{2}:\d{2}:\d{2}\.\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}\.\d{3})/;

/** @typedef {import('./vtt-parser.js').VttCue} VttCue */

/**
 * @param {number} seconds
 * @returns {string}
 */
function formatVttTimestamp(seconds) {
  const totalMs = Math.round(seconds * 1000);
  const hrs = Math.floor(totalMs / 3_600_000);
  const mins = Math.floor((totalMs % 3_600_000) / 60_000);
  const secs = Math.floor((totalMs % 60_000) / 1000);
  const ms = totalMs % 1000;
  return `${String(hrs).padStart(2, "0")}:${String(mins).padStart(2, "0")}:${String(secs).padStart(2, "0")}.${String(ms).padStart(3, "0")}`;
}

/**
 * @param {VttCue[]} cues
 * @returns {string}
 */
export function formatVttCues(cues) {
  if (cues.length === 0) return "WEBVTT\n";

  const body = cues
    .map((cue) => {
      const start = formatVttTimestamp(cue.startSec);
      const end = formatVttTimestamp(cue.endSec);
      return `${start} --> ${end}\n${cue.text}`;
    })
    .join("\n\n");

  return `WEBVTT\n\n${body}\n`;
}

/**
 * @param {string} vttText
 * @param {object} [options]
 * @returns {{ vtt: string, cues: VttCue[], inputCueCount: number, outputCueCount: number }}
 */
export function cleanAutoCaptions(vttText, options = {}) {
  const inputCues = parseVttSegment(vttText);
  const merged = mergeProgressiveCaptionCues(inputCues, options);
  return {
    vtt: formatVttCues(merged),
    cues: merged,
    inputCueCount: inputCues.length,
    outputCueCount: merged.length,
  };
}

/**
 * @param {string} vttText
 * @returns {boolean}
 */
export function shouldCleanAutoCaptions(vttText) {
  return shouldCleanProgressiveCaptions(vttText);
}

/**
 * @param {string} vttText
 * @returns {VttCue[]}
 */
export function parseCleanedVtt(vttText) {
  return parseVttSegment(vttText);
}

export {
  cuesOverlap,
  deduplicateOverlappingCues,
  isProgressiveExtension,
  mergeProgressiveCues,
  normalizeProgressiveText as normalizeText,
  shouldCleanProgressiveCaptions,
  VTT_TIMESTAMP,
};
