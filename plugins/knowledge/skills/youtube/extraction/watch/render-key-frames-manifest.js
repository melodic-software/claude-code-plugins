#!/usr/bin/env node
/**
 * Render key-frames-manifest.md from promotion-decisions + selection timestamps.
 *
 * Usage: node watch/render-key-frames-manifest.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/**
 * @param {string} sliceDir
 * @returns {string}
 */
export function renderKeyFramesManifest(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const decisionsPath = lanePath(absSlice, LANES.keyFrames, "promotion-decisions.json");
  const selectionPath = lanePath(absSlice, LANES.keyFrames, "selection.json");
  const doc = JSON.parse(fs.readFileSync(decisionsPath, "utf8"));
  const selection = JSON.parse(fs.readFileSync(selectionPath, "utf8"));
  const byFile = Object.fromEntries(selection.selectedFrames.map((f) => [f.file, f]));

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

const sliceDir = process.argv[2];
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    process.stderr.write("Usage: node watch/render-key-frames-manifest.js <slice-dir>\n");
    process.exit(2);
  }
  writeStdout(`${renderKeyFramesManifest(sliceDir)}\n`);
}
