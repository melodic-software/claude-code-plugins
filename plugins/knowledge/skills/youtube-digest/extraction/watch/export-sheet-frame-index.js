#!/usr/bin/env node
/**
 * Export contact-sheet cell → frame mapping for vision triage.
 *
 * Usage: node watch/export-sheet-frame-index.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { resolveTempSession, serializeTempPath } from "../lib/temp-session-paths.js";
import { watchStatePath } from "./watch-state.js";

const CELLS = [
  "R1C1",
  "R1C2",
  "R1C3",
  "R1C4",
  "R2C1",
  "R2C2",
  "R2C3",
  "R2C4",
  "R3C1",
  "R3C2",
  "R3C3",
  "R3C4",
  "R4C1",
  "R4C2",
  "R4C3",
  "R4C4",
];

/**
 * @param {string} sliceDir
 * @returns {string}
 */
export function exportSheetFrameIndex(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const selectionPath = lanePath(absSlice, LANES.keyFrames, "selection.json");
  const watchPath = watchStatePath(absSlice);
  const selection = JSON.parse(fs.readFileSync(selectionPath, "utf8"));
  const watch = fs.existsSync(watchPath) ? JSON.parse(fs.readFileSync(watchPath, "utf8")) : {};

  const byFile = Object.fromEntries(
    selection.selectedFrames.map((frame) => [
      frame.file,
      { timestampSec: frame.timestampSec, path: frame.path, textDense: frame.textDense },
    ]),
  );

  const sheets = selection.contactSheets.map((sheet, index) => {
    const id = String(index + 1).padStart(3, "0");
    return {
      sheetId: `sheet_${id}`,
      file: sheet.file,
      path: sheet.path,
      midTimestampSec: byFile[sheet.inputFiles[8]]?.timestampSec ?? null,
      cells: sheet.inputFiles.map((file, cellIndex) => ({
        cell: CELLS[cellIndex],
        frame: file,
        timestampSec: byFile[file]?.timestampSec ?? null,
        framePath: byFile[file]?.path ?? null,
        textDense: byFile[file]?.textDense ?? false,
      })),
    };
  });

  const resolvedSession = resolveTempSession(watch.tempSession ?? {});
  const sheetsDir = resolvedSession.contactSheetsDir
    ? serializeTempPath(resolvedSession.contactSheetsDir)
    : "{tmp}/youtube-sheets-unknown";
  const framesDir = resolvedSession.framesDir ? serializeTempPath(resolvedSession.framesDir) : null;

  const payload = {
    sheetsDir,
    framesDir,
    sheets: sheets.map((sheet) => ({
      ...sheet,
      path: sheet.path ? serializeTempPath(sheet.path) : undefined,
      cells: sheet.cells.map((cell) => ({ ...cell, framePath: undefined })),
    })),
  };
  const outPath = lanePath(absSlice, LANES.keyFrames, "sheet-frame-index.json");
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
  return outPath;
}

const sliceDir = process.argv[2];
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    writeStderr("Usage: node watch/export-sheet-frame-index.js <slice-dir>");
    process.exit(2);
  }
  writeStdout(`${exportSheetFrameIndex(sliceDir)}\n`);
}
