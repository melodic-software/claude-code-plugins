#!/usr/bin/env node
/**
 * Apply vision-gated promotion decisions to the key-frames/frames/ lane.
 *
 * Usage: node watch/vision-gated-promote.js <slice-dir> [--dry-run]
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { forbiddenSynthesisFileNameReason } from "../lib/synthesis-filename.js";
import { resolveTempSession } from "../lib/temp-session-paths.js";
import { validatePromotionDecisionsForSlice } from "../lib/watch-vision-validation.js";
import { dedupeSynthesisDir } from "./dedupe-synthesis-dir.js";
import { promoteKeyFrames } from "./promote-key-frames.js";
import { watchStatePath } from "./watch-state.js";

/**
 * @param {string} destName
 * @returns {string}
 */
function normalizeDestName(destName) {
  const base = path.basename(destName);
  return base.endsWith(".png") ? base : `${base}.png`;
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
    const destName = normalizeDestName(row.destName);
    const forbidden = forbiddenSynthesisFileNameReason(destName);
    if (forbidden) {
      throw new Error(`forbidden destName ${destName}: ${forbidden}`);
    }
    const sourcePath = path.join(framesDir, row.sourceFile);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`source frame missing: ${row.sourceFile}`);
    }
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

const sliceDir = process.argv[2];
const dryRun = process.argv.includes("--dry-run");
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    writeStderr("Usage: node watch/vision-gated-promote.js <slice-dir> [--dry-run]\n");
    process.exit(2);
  }
  visionGatedPromote(sliceDir, { dryRun })
    .then((result) => {
      writeStdout(`${JSON.stringify(result, null, 2)}\n`);
    })
    .catch((error) => {
      writeStderr(`${error instanceof Error ? error.message : String(error)}\n`);
      process.exit(1);
    });
}
