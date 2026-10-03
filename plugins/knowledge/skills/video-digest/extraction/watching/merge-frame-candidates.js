/**
 * Merge frame candidates by file name, preferring entries with timestamps.
 */

import { compareTimesUntimedLast } from "./timestamp-interleave.js";

/** @typedef {import('@melodic/video-digestion/frames/models').FrameCandidate} FrameCandidate */

/**
 * @param {FrameCandidate[]} frames
 * @returns {FrameCandidate[]}
 */
export function mergeFrameCandidates(frames) {
  /** @type {Map<string, FrameCandidate>} */
  const byFile = new Map();

  for (const frame of frames) {
    const existing = byFile.get(frame.file);
    if (!existing || (frame.timestampSec ?? -1) >= (existing.timestampSec ?? -1)) {
      byFile.set(frame.file, frame);
    }
  }

  return [...byFile.values()].sort(compareTimesUntimedLast);
}
