#!/usr/bin/env node
/**
 * Render key-frames/frame-triage-log.md from key-frames/triage/manifest.json
 *
 * Usage: node watch/render-triage-log.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { isMainModule } from "../lib/cli-entrypoint.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";
import { readLaneJson } from "../lib/watch-frame-index.js";

/**
 * @param {string} sliceDir
 * @returns {string}
 */
export function renderTriageLog(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const manifest = readLaneJson(absSlice, LANES.keyFrames, "triage", "manifest.json");

  const lines = [
    "# Frame triage log",
    "",
    `Source: \`key-frames/triage/manifest.json\` (${manifest.sheetCount ?? manifest.sheets.length} sheets).`,
    "",
  ];

  for (const sheet of manifest.sheets) {
    const midCell = sheet.cells.find((c) => c.cell === "R3C2");
    const midMin = midCell?.timestampSec ? Math.round(midCell.timestampSec / 60) : null;
    lines.push(
      `## ${sheet.sheetId}${midMin != null ? ` (~${midMin}m)` : ""}`,
      "",
      "| Cell | Frame | Verdict | Notes |",
      "| --- | --- | --- | --- |",
    );
    for (const cell of sheet.cells) {
      lines.push(`| ${cell.cell} | ${cell.frame} | ${cell.verdict} | ${cell.note ?? ""} |`);
    }
    lines.push("");
  }

  const outPath = lanePath(absSlice, LANES.keyFrames, "frame-triage-log.md");
  fs.writeFileSync(outPath, `${lines.join("\n")}\n`, "utf8");
  return outPath;
}

if (isMainModule(import.meta.url)) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node watch/render-triage-log.js <slice-dir>");
    process.exit(2);
  }
  writeStdout(renderTriageLog(sliceDir));
}
