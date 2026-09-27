#!/usr/bin/env node
/**
 * Render key-frames-manifest.md from promotion-decisions + selection timestamps.
 *
 * Usage: node watch/render-key-frames-manifest.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { isMainModule } from "../lib/cli-entrypoint.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";
import { indexSelectedFrames, readLaneJson } from "../lib/watch-frame-index.js";

/**
 * @param {string} sliceDir
 * @returns {string}
 */
export function renderKeyFramesManifest(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const doc = readLaneJson(absSlice, LANES.keyFrames, "promotion-decisions.json");
  const selection = readLaneJson(absSlice, LANES.keyFrames, "selection.json");
  const byFile = indexSelectedFrames(selection);

  const promotes = doc.decisions.filter((d) => d.verdict === "promote");

  const lines = [
    "# Key frames manifest",
    "",
    `Vision-gated promotions (${promotes.length} frames).`,
    "",
    "| Filename | Session | ~Timestamp | Gap note |",
    "| --- | --- | --- | --- |",
  ];

  for (const row of promotes) {
    const destName = row.destName.endsWith(".png") ? row.destName : `${row.destName}.png`;
    const ts = byFile[row.sourceFile]?.timestampSec;
    const tsLabel = ts != null ? `~${Math.round(ts / 60)}m` : "—";
    lines.push(`| ${destName} | ${row.session ?? "—"} | ${tsLabel} | ${row.gapNote ?? ""} |`);
  }

  lines.push("");
  const outPath = lanePath(absSlice, LANES.keyFrames, "key-frames-manifest.md");
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, `${lines.join("\n")}\n`, "utf8");
  return outPath;
}

if (isMainModule(import.meta.url)) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node watch/render-key-frames-manifest.js <slice-dir>");
    process.exit(2);
  }
  writeStdout(renderKeyFramesManifest(sliceDir));
}
