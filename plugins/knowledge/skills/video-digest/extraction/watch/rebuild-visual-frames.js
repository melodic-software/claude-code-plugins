#!/usr/bin/env node
/**
 * Rebuild key-frames/visual-frames.md from promoted frame PNG images + promotion-map.json.
 */

import fs from "node:fs";
import path from "node:path";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { indexSelectedFrames, readJsonFile, readLaneJson } from "../lib/watch-frame-index.js";
import { compareTimesUntimedLast, frameMinuteLabel } from "../watching/timestamp-interleave.js";

/**
 * Resolve synthesis filename → source frame using slice promotion-map and generic patterns.
 *
 * @param {string} destFile
 * @param {Record<string, { sourceFile?: string } | string>} promotionMap
 * @returns {string|undefined}
 */
export function resolveSourceFile(destFile, promotionMap) {
  const entry = promotionMap[destFile];
  if (typeof entry === "string") return entry;
  if (entry?.sourceFile) return entry.sourceFile;

  const anchorMatch = destFile.match(/^(\d+)-(\d+)(?:-\d+)?\.png$/);
  if (anchorMatch && anchorMatch[1].length >= 5) {
    return `anchor_${anchorMatch[1]}_${anchorMatch[2]}.png`;
  }
  const sceneShort = destFile.match(/^(\d{4})(?:-\d+)?\.png$/);
  if (sceneShort) return `scene_${sceneShort[1]}.png`;
  const atStem = destFile.match(/^(?:at-\d+m\d+s|untimed)-(.+)\.png$/);
  if (atStem) return `${atStem[1]}.png`;
  return undefined;
}

/**
 * A slice's key-frames/promotion-map.json, or `{}` when the slice has none yet.
 *
 * @param {string} sliceDir
 * @returns {Record<string, { sourceFile?: string } | string>}
 */
export function readPromotionMap(sliceDir) {
  const mapPath = lanePath(path.resolve(sliceDir), LANES.keyFrames, "promotion-map.json");
  return fs.existsSync(mapPath) ? readJsonFile(mapPath) : {};
}

/**
 * @param {string} sliceDir
 */
export function rebuildVisualFrames(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const sel = readLaneJson(absSlice, LANES.keyFrames, "selection.json");
  const byFile = indexSelectedFrames(sel);
  const promotionMap = readPromotionMap(absSlice);

  // Pass 2 reads visual-frames.md before promotion creates frames/. A missing
  // directory is an empty synthesis tier, same as a missing promotion-map.json.
  const synDir = lanePath(absSlice, LANES.keyFrames, "frames");
  const files = fs.existsSync(synDir)
    ? fs
        .readdirSync(synDir)
        .filter((f) => f.endsWith(".png"))
        .sort()
    : [];

  const rows = files.map((file) => {
    const source = resolveSourceFile(file, promotionMap);
    const frame = source ? byFile[source] : undefined;
    const timestampSec = frame?.timestampSec ?? null;
    const label = source ?? file.replace(/\.png$/, "");
    return {
      timestampSec,
      time: frameMinuteLabel(timestampSec, frame?.timestampSource, Math.floor),
      file,
      label,
    };
  });
  rows.sort(compareTimesUntimedLast);

  const lines = [
    "# Visual frame log — full vision pass",
    "",
    "Tiers: [`key-frames-manifest.md`](key-frames-manifest.md). Audit: [`key-frame-quality-audit.md`](key-frame-quality-audit.md).",
    "",
    `**Synthesis count:** ${files.length}`,
    "",
    "## Synthesis tier",
    "",
    "| Timestamp | File | Content |",
    "| --- | --- | --- |",
  ];
  for (const row of rows) {
    lines.push(`| ${row.time} | \`frames/${row.file}\` | ${row.label} |`);
  }
  lines.push("");

  const outPath = lanePath(absSlice, LANES.keyFrames, "visual-frames.md");
  fs.writeFileSync(outPath, `${lines.join("\n")}\n`, "utf8");
  return outPath;
}

if (isMainModule(import.meta.url)) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node watch/rebuild-visual-frames.js <slice-dir>");
    process.exit(2);
  }
  writeStdout(rebuildVisualFrames(sliceDir));
}
