#!/usr/bin/env node
/**
 * Rebuild key-frames/visual-frames.md from promoted frame PNG images + promotion-map.json.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";

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
  const atStem = destFile.match(/^at-\d+m\d+s-(.+)\.png$/);
  if (atStem) return `${atStem[1]}.png`;
  return undefined;
}

/**
 * @param {string} sliceDir
 */
export function rebuildVisualFrames(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const sel = JSON.parse(
    fs.readFileSync(lanePath(absSlice, LANES.keyFrames, "selection.json"), "utf8"),
  );
  const byFile = Object.fromEntries(sel.selectedFrames.map((f) => [f.file, f]));
  const mapPath = lanePath(absSlice, LANES.keyFrames, "promotion-map.json");
  const promotionMap = fs.existsSync(mapPath) ? JSON.parse(fs.readFileSync(mapPath, "utf8")) : {};

  const synDir = lanePath(absSlice, LANES.keyFrames, "frames");
  const files = fs
    .readdirSync(synDir)
    .filter((f) => f.endsWith(".png"))
    .sort();

  const rows = files.map((file) => {
    const source = resolveSourceFile(file, promotionMap);
    const ts = source && byFile[source] ? byFile[source].timestampSec : 0;
    const min = Math.floor(ts / 60);
    const label = source ?? file.replace(/\.png$/, "");
    return { min, file, label, source };
  });
  rows.sort((a, b) => a.min - b.min);

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
    lines.push(`| ~${row.min}m | \`frames/${row.file}\` | ${row.label} |`);
  }
  lines.push("");

  const outPath = lanePath(absSlice, LANES.keyFrames, "visual-frames.md");
  fs.writeFileSync(outPath, `${lines.join("\n")}\n`, "utf8");
  return outPath;
}

const sliceDir = process.argv[2];
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    process.stderr.write("Usage: node watch/rebuild-visual-frames.js <slice-dir>\n");
    process.exit(2);
  }
  writeStdout(`${rebuildVisualFrames(sliceDir)}\n`);
}
