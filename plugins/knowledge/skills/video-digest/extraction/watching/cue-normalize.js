/**
 * Transcript cue normalization shared by the watching entry points.
 */

import { parseVttSegment } from "@melodic/video-digestion/transcript/vtt-parser";

/** @typedef {import('./models.js').TranscriptCue} TranscriptCue */

/**
 * Parse a VTT document down to the cue shape the watching pipeline reads.
 *
 * @param {string} vttText
 * @returns {TranscriptCue[]}
 */
export function normalizeVttCues(vttText) {
  return parseVttSegment(vttText).map((cue) => ({
    startSec: cue.startSec,
    endSec: cue.endSec,
    text: cue.text,
  }));
}
