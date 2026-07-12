/**
 * Slice SSOT: source file → synthesis destination from promotion-decisions.json.
 */

import fs from "node:fs";
import path from "node:path";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/**
 * @param {string} sliceDir
 * @returns {Record<string, string>}
 */
export function loadPromotionNameMap(sliceDir) {
  const decisionsPath = lanePath(
    path.resolve(sliceDir),
    LANES.keyFrames,
    "promotion-decisions.json",
  );
  if (!fs.existsSync(decisionsPath)) {
    return {};
  }
  const doc = JSON.parse(fs.readFileSync(decisionsPath, "utf8"));
  /** @type {Record<string, string>} */
  const map = {};
  for (const row of doc.decisions ?? []) {
    if (row.verdict !== "promote" || !row.destName) continue;
    const dest = row.destName.endsWith(".png") ? row.destName : `${row.destName}.png`;
    map[row.sourceFile] = dest;
  }
  return map;
}
