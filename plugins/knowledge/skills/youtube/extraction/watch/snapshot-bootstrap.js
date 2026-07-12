#!/usr/bin/env node
/**
 * Copy contact sheets from temp session into slice `key-frames/contact-sheets/` for disaster recovery.
 *
 * Usage: node watch/snapshot-bootstrap.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { resolveTempSession, serializeTempPath } from "../lib/temp-session-paths.js";
import { watchStatePath } from "./watch-state.js";

/**
 * @param {string} sliceDir
 * @returns {{ copied: number, destDir: string }}
 */
export function snapshotBootstrapContactSheets(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const watchPath = watchStatePath(absSlice);
  if (!fs.existsSync(watchPath)) {
    throw new Error(`watch.json missing at ${absSlice}`);
  }
  const watch = JSON.parse(fs.readFileSync(watchPath, "utf8"));
  const { contactSheetsDir } = resolveTempSession(watch.tempSession ?? {});
  if (!contactSheetsDir || !fs.existsSync(contactSheetsDir)) {
    throw new Error("contactSheetsDir missing or not found");
  }

  const destDir = lanePath(absSlice, LANES.keyFrames, "contact-sheets");
  fs.mkdirSync(destDir, { recursive: true });

  const sheets = fs
    .readdirSync(contactSheetsDir)
    .filter((name) => /^sheet_\d+\.jpg$/i.test(name))
    .sort();

  for (const name of sheets) {
    fs.copyFileSync(path.join(contactSheetsDir, name), path.join(destDir, name));
  }

  const meta = {
    snapshottedAt: new Date().toISOString(),
    sheetCount: sheets.length,
    sourceDir: serializeTempPath(contactSheetsDir),
  };
  fs.writeFileSync(
    lanePath(absSlice, LANES.keyFrames, "contact-sheets", "snapshot-meta.json"),
    `${JSON.stringify(meta, null, 2)}\n`,
    "utf8",
  );

  return { copied: sheets.length, destDir };
}

const sliceDir = process.argv[2];
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    writeStderr("Usage: node watch/snapshot-bootstrap.js <slice-dir>\n");
    process.exit(2);
  }
  try {
    const result = snapshotBootstrapContactSheets(sliceDir);
    writeStdout(`Snapshotted ${result.copied} sheets to ${result.destDir}\n`);
  } catch (error) {
    writeStderr(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
