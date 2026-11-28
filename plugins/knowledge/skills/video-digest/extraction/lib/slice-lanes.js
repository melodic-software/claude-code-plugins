import path from "node:path";

/** @typedef {'source'|'research'|'keyFrames'|'recommendations'|'verification'|'runState'} LaneKey */

/** @type {Readonly<Record<LaneKey, string>>} */
export const LANES = Object.freeze({
  source: "source",
  research: "research",
  keyFrames: "key-frames",
  recommendations: "recommendations",
  verification: "verification",
  runState: "run-state",
});

/**
 * Join a lane directory (and optional nested segments) under a slice root.
 *
 * @param {string} sliceDir - slice root (absolute or relative; caller resolves when needed)
 * @param {string} lane - a value from {@link LANES}
 * @param {...string} rest - nested path segments inside the lane
 * @returns {string}
 */
export function lanePath(sliceDir, lane, ...rest) {
  return path.join(sliceDir, lane, ...rest);
}
