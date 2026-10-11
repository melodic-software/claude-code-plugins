#!/usr/bin/env node
/**
 * Apply vision-gated promotion decisions to the key-frames/frames/ lane.
 *
 * Usage: node watch/vision-gated-promote.js <slice-dir> [--dry-run]
 */

import fs from "node:fs";
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
 * Resolve a promotion `sourceFile` to the real path of a regular file directly inside `framesDir`.
 * Throws when the name is not a bare file name, when the file is missing, or when it resolves
 * (through `..` or a symlink) to anywhere other than `framesDir` itself.
 *
 * @param {string} framesDir
 * @param {string} sourceFile
 * @returns {string}
 */
export function resolveContainedFrame(framesDir, sourceFile) {
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
  } catch {
    throw new Error(`source frame missing: ${sourceFile}`);
  }
  if (path.dirname(realSource) !== realFramesDir) {
    throw new Error(`source frame ${sourceFile} resolves outside the frames directory`);
  }
  if (!fs.statSync(realSource).isFile()) {
    throw new Error(`source frame ${sourceFile} is not a regular file`);
  }
  return realSource;
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
    const sourcePath = resolveContainedFrame(framesDir, row.sourceFile);
    promotions.push({ sourcePath, destName: `frames/${destName}` });
    promotionMap[destName] = {
      sourceFile: row.sourceFile,
      gapNote: row.gapNote,
      session: row.session,
    };
  }

  if (dryRun) {
    return { promoted: promotions.map((p) => p.destName), skipped };
  }

  const promotedPaths = await promoteKeyFrames(absSlice, promotions);
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
