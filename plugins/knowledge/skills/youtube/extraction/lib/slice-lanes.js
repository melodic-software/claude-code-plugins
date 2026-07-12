/**
 * Single source of truth for the `/youtube watch` slice's concern-lane directory names.
 *
 * Every writer, consumer, eval gate, and lib validator joins lane paths through this
 * registry instead of inlining `context/` / `watching/` / `.bootstrap/` / `media/key-frames/`
 * literals — so the lane layout is enforced in one place and a rename is a one-file flip.
 *
 * The six lanes are an intentional, user-approved concern-layout — each owns its deliverable +
 * working trail + machine-state together (Common Closure Principle). `verification` is deliberately
 * a content-noun, NOT the canonical `.work` verb `verify/`: no `/youtube` tooling binds a `verify/`
 * path, so internal consistency with the other five content-noun lanes wins. Do not "align" it back.
 */

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
