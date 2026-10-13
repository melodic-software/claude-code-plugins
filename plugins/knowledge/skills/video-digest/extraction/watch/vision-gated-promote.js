#!/usr/bin/env node
/**
 * Apply vision-gated promotion decisions to the key-frames/frames/ lane.
 *
 * Usage: node watch/vision-gated-promote.js <slice-dir> [--dry-run]
 */

import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import {
  forbiddenSynthesisFileNameReason,
  normalizeSynthesisDestName,
} from "../lib/synthesis-filename.js";
import { resolveTempSession } from "../lib/temp-session-paths.js";
import {
  promotionSourceFileReason,
  validatePromotionDecisionsForSlice,
} from "../lib/watch-vision-validation.js";
import { dedupeSynthesisDir } from "./dedupe-synthesis-dir.js";
import { promoteKeyFrames } from "./promote-key-frames.js";
import { watchStatePath } from "./watch-state.js";

/**
 * Resolve a promotion `sourceFile` to the real path of a regular file directly inside `framesDir`,
 * plus that file's identity, so the copy can prove it reads the same file the check passed.
 * Throws when the name is not a bare file name, when the file is missing or cannot be resolved, or
 * when it resolves (through `..` or a symlink) to anywhere other than `framesDir` itself.
 *
 * @param {string} framesDir
 * @param {string} sourceFile
 * @returns {{ path: string, dev: number, ino: number }}
 */
export function checkContainedFrame(framesDir, sourceFile) {
  const reason = promotionSourceFileReason(sourceFile);
  if (reason) {
    throw new Error(`sourceFile ${JSON.stringify(sourceFile)} ${reason}`);
  }
  let realFramesDir;
  try {
    realFramesDir = fs.realpathSync(framesDir);
  } catch {
    realFramesDir = path.resolve(framesDir);
  }
  let realSource;
  try {
    realSource = fs.realpathSync(path.join(realFramesDir, sourceFile));
  } catch (error) {
    const code = /** @type {NodeJS.ErrnoException} */ (error)?.code;
    if (code === "ENOENT") throw new Error(`source frame missing: ${sourceFile}`);
    throw new Error(`source frame ${sourceFile} cannot be resolved (${code ?? "unknown error"})`);
  }
  if (path.dirname(realSource) !== realFramesDir) {
    throw new Error(`source frame ${sourceFile} resolves outside the frames directory`);
  }
  const stat = fs.lstatSync(realSource);
  if (!stat.isFile()) {
    throw new Error(`source frame ${sourceFile} is not a regular file`);
  }
  return { path: realSource, dev: stat.dev, ino: stat.ino };
}

/**
 * Copy a checked frame without following a symlink swapped in after the check. The source is
 * opened with O_NOFOLLOW where the platform defines it, and the open descriptor must be a regular
 * file with the checked dev/ino, which refuses a swap on every platform.
 * A hard link to an outside file made before the check passes, since it IS the checked file.
 *
 * @param {string} sourcePath
 * @param {string} destPath
 * @param {{ dev: number, ino: number }} expected
 * @returns {Promise<void>}
 */
async function copyCheckedFrame(sourcePath, destPath, expected) {
  const changed = () => new Error(`source frame ${sourcePath} changed after it was checked`);
  let handle;
  try {
    handle = await fsp.open(sourcePath, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW ?? 0));
  } catch (error) {
    if (error && error.code === "ELOOP") throw changed();
    throw error;
  }
  try {
    const opened = await handle.stat();
    if (!opened.isFile() || opened.dev !== expected.dev || opened.ino !== expected.ino) {
      throw changed();
    }
    await fsp.writeFile(destPath, await handle.readFile());
  } finally {
    await handle.close();
  }
}

/**
 * @param {string} sliceDir
 * @param {{ dryRun?: boolean }} [options]
 * @returns {Promise<{ promoted: string[], skipped: string[] }>}
 */
export async function visionGatedPromote(sliceDir, { dryRun = false } = {}) {
  const absSlice = path.resolve(sliceDir);
  const validation = validatePromotionDecisionsForSlice(absSlice);
  if (!validation.valid) {
    throw new Error(validation.errors.join("; "));
  }

  const decisionsPath = lanePath(absSlice, LANES.keyFrames, "promotion-decisions.json");
  const doc = JSON.parse(fs.readFileSync(decisionsPath, "utf8"));
  const watch = JSON.parse(fs.readFileSync(watchStatePath(absSlice), "utf8"));
  const selection = JSON.parse(
    fs.readFileSync(lanePath(absSlice, LANES.keyFrames, "selection.json"), "utf8"),
  );
  const { framesDir } = resolveTempSession(watch.tempSession ?? selection.tempSession ?? {});

  if (!framesDir) {
    throw new Error("framesDir not found in tempSession");
  }

  /** @type {{ sourcePath: string, destName: string }[]} */
  const promotions = [];
  /** @type {Record<string, { sourceFile: string, gapNote?: string, session?: string }>} */
  const promotionMap = {};
  const skipped = [];
  /** @type {Map<string, { dev: number, ino: number }>} */
  const identities = new Map();

  for (const row of doc.decisions) {
    if (row.verdict !== "promote") {
      skipped.push(row.sourceFile);
      continue;
    }
    const destName = normalizeSynthesisDestName(row.destName);
    const forbidden = forbiddenSynthesisFileNameReason(destName);
    if (forbidden) {
      throw new Error(`forbidden destName ${destName}: ${forbidden}`);
    }
    const checked = checkContainedFrame(framesDir, row.sourceFile);
    identities.set(checked.path, checked);
    promotions.push({ sourcePath: checked.path, destName: `frames/${destName}` });
    promotionMap[destName] = {
      sourceFile: row.sourceFile,
      gapNote: row.gapNote,
      session: row.session,
    };
  }

  if (dryRun) {
    return { promoted: promotions.map((p) => p.destName), skipped };
  }

  const promotedPaths = await promoteKeyFrames(absSlice, promotions, {
    copyFile: (src, dest) => {
      const expected = identities.get(String(src));
      if (!expected) throw new Error(`no containment check recorded for ${String(src)}`);
      return copyCheckedFrame(String(src), String(dest), expected);
    },
  });
  dedupeSynthesisDir(lanePath(absSlice, LANES.keyFrames, "frames"));

  const mapPath = lanePath(absSlice, LANES.keyFrames, "promotion-map.json");
  fs.writeFileSync(mapPath, `${JSON.stringify(promotionMap, null, 2)}\n`, "utf8");

  return {
    promoted: promotedPaths.map((p) => path.basename(p)),
    skipped,
  };
}

if (isMainModule(import.meta.url)) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node watch/vision-gated-promote.js <slice-dir> [--dry-run]");
    process.exit(2);
  }
  visionGatedPromote(sliceDir, { dryRun: process.argv.includes("--dry-run") })
    .then((result) => {
      writeStdout(JSON.stringify(result, null, 2));
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exit(1);
    });
}
