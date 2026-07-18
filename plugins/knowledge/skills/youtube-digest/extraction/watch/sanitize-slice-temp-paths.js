#!/usr/bin/env node
/**
 * Replace absolute temp paths in slice artifacts with {tmp} placeholders.
 *
 * Usage: node watch/sanitize-slice-temp-paths.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { normalizePortableTempPath, serializeTempSession } from "../lib/temp-session-paths.js";
import { watchStatePath } from "./watch-state.js";

/**
 * @param {string} sliceDir
 */
export function sanitizeSliceTempPaths(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const touched = [];

  const watchPath = watchStatePath(absSlice);
  if (fs.existsSync(watchPath)) {
    const watch = JSON.parse(fs.readFileSync(watchPath, "utf8"));
    if (watch.tempSession) {
      watch.tempSession = serializeTempSession(watch.tempSession);
      fs.writeFileSync(watchPath, `${JSON.stringify(watch, null, 2)}\n`, "utf8");
      touched.push("run-state/watch.json");
    }
  }

  const selectionPath = lanePath(absSlice, LANES.keyFrames, "selection.json");
  if (fs.existsSync(selectionPath)) {
    const selection = JSON.parse(fs.readFileSync(selectionPath, "utf8"));
    if (selection.tempSession) {
      selection.tempSession = serializeTempSession(selection.tempSession);
    }
    if (Array.isArray(selection.selectedFrames)) {
      selection.selectedFrames = selection.selectedFrames.map((frame) => {
        const { path: _omit, ...rest } = frame;
        return rest;
      });
    }
    if (Array.isArray(selection.contactSheets)) {
      selection.contactSheets = selection.contactSheets.map((sheet) => {
        const { path: _omit, ...rest } = sheet;
        return rest;
      });
    }
    if (Array.isArray(selection.interleavedTimeline)) {
      selection.interleavedTimeline = selection.interleavedTimeline.map((entry) => {
        if (!entry?.frame) return entry;
        const { path: _omit, ...frame } = entry.frame;
        return { ...entry, frame };
      });
    }
    fs.writeFileSync(selectionPath, `${JSON.stringify(selection, null, 2)}\n`, "utf8");
    touched.push("key-frames/selection.json");
  }

  const indexPath = lanePath(absSlice, LANES.keyFrames, "sheet-frame-index.json");
  if (fs.existsSync(indexPath)) {
    const index = JSON.parse(fs.readFileSync(indexPath, "utf8"));
    if (index.sheetsDir) {
      index.sheetsDir = normalizePortableTempPath(index.sheetsDir);
    }
    if (index.framesDir) {
      index.framesDir = normalizePortableTempPath(index.framesDir);
    }
    if (Array.isArray(index.sheets)) {
      index.sheets = index.sheets.map((sheet) => ({
        ...sheet,
        path: sheet.path ? normalizePortableTempPath(sheet.path) : undefined,
        cells: sheet.cells?.map((cell) => ({
          ...cell,
          framePath: undefined,
        })),
      }));
    }
    fs.writeFileSync(indexPath, `${JSON.stringify(index, null, 2)}\n`, "utf8");
    touched.push("key-frames/sheet-frame-index.json");
  }

  const snapshotMetaPath = lanePath(
    absSlice,
    LANES.keyFrames,
    "contact-sheets",
    "snapshot-meta.json",
  );
  if (fs.existsSync(snapshotMetaPath)) {
    const meta = JSON.parse(fs.readFileSync(snapshotMetaPath, "utf8"));
    if (meta.sourceDir) {
      meta.sourceDir = normalizePortableTempPath(meta.sourceDir);
      fs.writeFileSync(snapshotMetaPath, `${JSON.stringify(meta, null, 2)}\n`, "utf8");
      touched.push("key-frames/contact-sheets/snapshot-meta.json");
    }
  }

  const promptPath = lanePath(absSlice, LANES.runState, "continuation-prompt.md");
  if (fs.existsSync(promptPath)) {
    const original = fs.readFileSync(promptPath, "utf8");
    // Scoped to the two temp-session lines only — a blanket backtick replace would
    // path.resolve() non-temp backtick spans (e.g. `key-frames/triage/...`) into garbage.
    const sanitized = original.replace(
      /^(- (?:Frames|Contact sheets) temp: `)([^`]+)(`)/gm,
      (_match, prefix, value, suffix) => `${prefix}${normalizePortableTempPath(value)}${suffix}`,
    );
    if (sanitized !== original) {
      fs.writeFileSync(promptPath, sanitized, "utf8");
      touched.push("continuation-prompt.md");
    }
  }

  return touched;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    process.stderr.write("Usage: node watch/sanitize-slice-temp-paths.js <slice-dir>\n");
    process.exit(2);
  }
  writeStdout(`${JSON.stringify(sanitizeSliceTempPaths(sliceDir), null, 2)}\n`);
}
