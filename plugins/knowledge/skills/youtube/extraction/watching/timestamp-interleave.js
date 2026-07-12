/**
 * Interleave transcript cues and selected frames by timestamp for vision absorption.
 */

/** @typedef {import('./models.js').TranscriptCue} TranscriptCue */
/** @typedef {import('./models.js').SelectedFrame} SelectedFrame */
/** @typedef {import('./models.js').InterleavedReadItem} InterleavedReadItem */

/**
 * Build a merged timeline alternating transcript segments and frame detail reads.
 *
 * @param {TranscriptCue[]} cues
 * @param {SelectedFrame[]} frames
 * @returns {InterleavedReadItem[]}
 */
export function interleaveTranscriptAndFrames(cues, frames) {
  /** @type {InterleavedReadItem[]} */
  const items = [];

  for (const cue of cues) {
    items.push({
      kind: "transcript",
      timestampSec: cue.startSec,
      transcriptText: cue.text,
    });
  }

  for (const frame of frames) {
    items.push({
      kind: "frame",
      timestampSec: frame.timestampSec ?? 0,
      frame,
    });
  }

  return items.sort((a, b) => a.timestampSec - b.timestampSec);
}

/**
 * Group selected frames into contact-sheet batches.
 *
 * @param {SelectedFrame[]} frames
 * @param {number} [batchSize=16]
 * @returns {SelectedFrame[][]}
 */
export function batchFramesForContactSheets(frames, batchSize = 16) {
  /** @type {SelectedFrame[][]} */
  const batches = [];
  for (let i = 0; i < frames.length; i += batchSize) {
    batches.push(frames.slice(i, i + batchSize));
  }
  return batches;
}
