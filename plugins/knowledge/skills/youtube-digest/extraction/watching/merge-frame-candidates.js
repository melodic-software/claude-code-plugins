/**
 * Merge frame candidates by file name, preferring entries with timestamps.
 */

/** @typedef {import('@melodic/video-digestion/frames/models.js').FrameCandidate} FrameCandidate */

/**
 * @param {FrameCandidate[]} frames
 * @returns {FrameCandidate[]}
 */
export function mergeFrameCandidates(frames) {
  /** @type {Map<string, FrameCandidate>} */
  const byFile = new Map();

  for (const frame of frames) {
    const existing = byFile.get(frame.file);
    if (!existing) {
      byFile.set(frame.file, frame);
      continue;
    }

    const existingTs = existing.timestampSec ?? -1;
    const nextTs = frame.timestampSec ?? -1;
    if (nextTs >= existingTs) {
      byFile.set(frame.file, frame);
    }
  }

  return [...byFile.values()].sort((a, b) => (a.timestampSec ?? 0) - (b.timestampSec ?? 0));
}
