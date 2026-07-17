#!/usr/bin/env node
/**
 * Expand visual-gaps.md for densification windows without promoted frames.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { parsePromotedTimestampsSec } from "../evals/check-watch-outcomes.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";

/**
 * @param {string} sliceDir
 */
export function expandVisualGaps(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const sel = JSON.parse(
    fs.readFileSync(lanePath(absSlice, LANES.keyFrames, "selection.json"), "utf8"),
  );
  const visualFramesPath = lanePath(absSlice, LANES.keyFrames, "visual-frames.md");
  const promoted = parsePromotedTimestampsSec(fs.readFileSync(visualFramesPath, "utf8"));

  const gapRows = [];
  for (const window of sel.densificationWindows) {
    const inWindow = promoted.some((ts) => ts >= window.startSec && ts <= window.endSec);
    if (!inWindow) {
      const regionMin = Math.round(window.startSec / 60);
      gapRows.push(
        `| ~${regionMin}m | ${window.reason} | No synthesis frame in window; transcript-only |`,
      );
    }
  }

  const body = `# Visual gaps — densification alignment

Pass 3: windows without a promoted synthesis frame (gap-logged per quality gates).

| Region | Trigger | Status |
| --- | --- | --- |
${gapRows.join("\n")}
`;

  const outPath = lanePath(absSlice, LANES.keyFrames, "visual-gaps.md");
  fs.writeFileSync(outPath, body, "utf8");
  return { outPath, gapCount: gapRows.length, total: sel.densificationWindows.length };
}

const sliceDir = process.argv[2];
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    writeStderr("Usage: node watch/expand-visual-gaps.js <slice-dir>");
    process.exit(2);
  }
  const result = expandVisualGaps(sliceDir);
  writeStdout(`${JSON.stringify(result)}\n`);
}
