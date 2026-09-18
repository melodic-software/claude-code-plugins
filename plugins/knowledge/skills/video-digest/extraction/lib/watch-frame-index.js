/**
 * Shared slice-artifact JSON reads and the selected-frame index for the watch scripts.
 *
 * The `watch/` CLI scripts all read the same lane JSON and rebuild the same
 * `file` -> frame lookup from `key-frames/selection.json`; both live here so the
 * scripts stay siblings instead of importing one another.
 */

import fs from "node:fs";

import { lanePath } from "./slice-lanes.js";

/**
 * Parse a JSON artifact from disk.
 *
 * @param {string} filePath
 * @returns {any}
 */
export function readJsonFile(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

/**
 * Parse a JSON artifact addressed by slice lane.
 *
 * @param {string} sliceDir - slice root (absolute or relative; caller resolves when needed)
 * @param {string} lane - a value from {@link import('./slice-lanes.js').LANES}
 * @param {...string} rest - nested path segments inside the lane
 * @returns {any}
 */
export function readLaneJson(sliceDir, lane, ...rest) {
  return readJsonFile(lanePath(sliceDir, lane, ...rest));
}

/**
 * @typedef {{ file: string, [key: string]: any }} SelectedFrame
 */

/**
 * Index a `key-frames/selection.json` document's frames by their `file` name.
 *
 * @param {{ selectedFrames: SelectedFrame[] }} selection
 * @returns {Record<string, SelectedFrame>}
 */
export function indexSelectedFrames(selection) {
  return Object.fromEntries(selection.selectedFrames.map((f) => [f.file, f]));
}
