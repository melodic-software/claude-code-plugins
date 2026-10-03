/**
 * Interleave transcript cues and selected frames by timestamp for vision absorption.
 */

/** @typedef {import('./models.js').TranscriptCue} TranscriptCue */
/** @typedef {import('./models.js').SelectedFrame} SelectedFrame */
/** @typedef {import('./models.js').InterleavedReadItem} InterleavedReadItem */

/**
 * Sort comparator on `timestampSec` that puts untimed (`null`) items after
 * every timed one instead of treating them as 0.
 *
 * @param {{ timestampSec?: number|null }} a
 * @param {{ timestampSec?: number|null }} b
 * @returns {number}
 */
export function compareTimesUntimedLast(a, b) {
  const aTime = a.timestampSec;
  const bTime = b.timestampSec;
  const aTimed = Number.isFinite(aTime);
  const bTimed = Number.isFinite(bTime);
  if (aTimed && bTimed) return Number(aTime) - Number(bTime);
  return Number(!aTimed) - Number(!bTimed);
}

/**
 * Minute label for a frame time in a rendered table or heading: `~5m`;
 * `~5m, estimated` when the time was derived rather than measured; `untimed`
 * when the frame has no time.
 *
 * @param {number|null|undefined} timestampSec
 * @param {string|null|undefined} timestampSource
 * @param {(minutes: number) => number} [roundMinutes=Math.round]
 * @returns {string}
 */
export function frameMinuteLabel(timestampSec, timestampSource, roundMinutes = Math.round) {
  if (timestampSec == null || !Number.isFinite(timestampSec)) return "untimed";
  const label = `~${roundMinutes(timestampSec / 60)}m`;
  return timestampSource === "estimated" ? `${label}, estimated` : label;
}

/**
 * Build a merged timeline alternating transcript segments and frame detail reads.
 * Untimed frames come last with a `null` time.
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
      timestampSec: frame.timestampSec,
      frame,
    });
  }

  return items.sort(compareTimesUntimedLast);
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
