#!/usr/bin/env node
/**
 * Merge key-frames/triage/batches/*.json into key-frames/triage/manifest.json
 *
 * Usage: node watch/merge-triage-json.js <slice-dir> [batch.json ...]
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { validateTriageSheet } from "../lib/watch-vision-validation.js";

/**
 * @param {string} sliceDir
 * @param {string[]} [batchPaths]
 * @returns {string}
 */
export function mergeTriageJson(sliceDir, batchPaths) {
  const absSlice = path.resolve(sliceDir);
  const batchesDir = lanePath(absSlice, LANES.keyFrames, "triage", "batches");
  const paths =
    batchPaths && batchPaths.length > 0
      ? batchPaths.map((p) => path.resolve(p))
      : fs.existsSync(batchesDir)
        ? fs
            .readdirSync(batchesDir)
            .filter((n) => n.endsWith(".json"))
            .sort()
            .map((n) => path.join(batchesDir, n))
        : [];

  if (paths.length === 0) {
    throw new Error("no triage batch JSON files found");
  }

  const indexPath = lanePath(absSlice, LANES.keyFrames, "sheet-frame-index.json");
  /** @type {Map<string, number>} */
  const expectedCounts = new Map();
  if (fs.existsSync(indexPath)) {
    const index = JSON.parse(fs.readFileSync(indexPath, "utf8"));
    for (const indexSheet of index.sheets ?? []) {
      expectedCounts.set(indexSheet.sheetId, indexSheet.cells.length);
    }
  }

  /** @type {object[]} */
  const sheets = [];
  for (const batchPath of paths) {
    const sheet = JSON.parse(fs.readFileSync(batchPath, "utf8"));
    const expected = expectedCounts.get(sheet.sheetId) ?? 16;
    const errors = validateTriageSheet(sheet, expected);
    if (errors.length > 0) {
      throw new Error(`${batchPath}: ${errors.join("; ")}`);
    }
    sheets.push(sheet);
  }

  sheets.sort((a, b) => a.sheetId.localeCompare(b.sheetId));

  const manifest = {
    mergedAt: new Date().toISOString(),
    sheetCount: sheets.length,
    sheets,
  };

  const outDir = lanePath(absSlice, LANES.keyFrames, "triage");
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, "manifest.json");
  fs.writeFileSync(outPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  return outPath;
}

const sliceDir = process.argv[2];
const batchPaths = process.argv.slice(3);
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    writeStderr("Usage: node watch/merge-triage-json.js <slice-dir> [batch.json ...]\n");
    process.exit(2);
  }
  try {
    writeStdout(`${mergeTriageJson(sliceDir, batchPaths)}\n`);
  } catch (error) {
    writeStderr(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exit(1);
  }
}
