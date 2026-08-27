/**
 * Promote curated vision-triage frames into the staged `key-frames/` lane.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { isMainModule } from "../lib/cli-entrypoint.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";

const KEY_FRAME_IMAGE_EXTENSION_PATTERN = /\.(png|jpe?g|webp)$/i;

/** Allowed single-level subfolders under the `key-frames/` lane. */
export const KEY_FRAME_TIER_SUBDIRS = new Set(["frames", "presentation"]);

/**
 * @typedef {Object} KeyFramePromotion
 * @property {string} sourcePath - Absolute or slice-relative source image
 * @property {string} destName - Filename under key-frames/ (optional `frames/` or `presentation/` prefix)
 */

/**
 * @param {string} name
 * @returns {string}
 */
export function sanitizeKeyFrameDestName(name) {
  const normalized = name.replace(/\\/g, "/").replace(/^\/+/, "");
  const segments = normalized.split("/").filter(Boolean);
  if (segments.length === 0) {
    throw new Error("destName must not be empty");
  }

  let tier = "";
  let fileSegments = segments;
  if (segments.length > 1 && KEY_FRAME_TIER_SUBDIRS.has(segments[0])) {
    tier = segments[0];
    fileSegments = segments.slice(1);
  }

  const base = path.basename(fileSegments.join("/"));
  const safeBase = KEY_FRAME_IMAGE_EXTENSION_PATTERN.test(base) ? base : `${base}.jpg`;
  return tier ? `${tier}/${safeBase}` : safeBase;
}

/**
 * Promote curated frames into `.work/<slug>/key-frames/`.
 *
 * @param {string} sliceDir
 * @param {KeyFramePromotion[]} promotions
 * @param {object} [deps]
 * @param {typeof fs.copyFile} [deps.copyFile]
 * @returns {Promise<string[]>} promoted absolute paths
 */
export async function promoteKeyFrames(sliceDir, promotions, { copyFile = fs.copyFile } = {}) {
  const keyFramesDir = lanePath(sliceDir, LANES.keyFrames);
  await fs.mkdir(keyFramesDir, { recursive: true });

  const promoted = [];
  for (const promotion of promotions) {
    const sourcePath = path.isAbsolute(promotion.sourcePath)
      ? promotion.sourcePath
      : path.join(sliceDir, promotion.sourcePath);
    const destName = sanitizeKeyFrameDestName(promotion.destName);
    const destPath = path.join(keyFramesDir, destName);
    await fs.mkdir(path.dirname(destPath), { recursive: true });
    await copyFile(sourcePath, destPath);
    promoted.push(destPath);
  }

  return promoted;
}

/**
 * Parse `source:dest` pairs, including Windows absolute paths (`C:\...:dest.png`).
 *
 * @param {string} pair
 * @returns {KeyFramePromotion}
 */
export function parsePromotionPair(pair) {
  const pipeSeparator = pair.indexOf("|");
  if (pipeSeparator !== -1) {
    return {
      sourcePath: pair.slice(0, pipeSeparator),
      destName: pair.slice(pipeSeparator + 1),
    };
  }

  const windowsDrive = /^[A-Za-z]:/.test(pair);
  const separator = windowsDrive ? pair.indexOf(":", 2) : pair.indexOf(":");
  if (separator === -1) {
    throw new Error(`Invalid promotion pair (expected source:dest or source|dest): ${pair}`);
  }

  return {
    sourcePath: pair.slice(0, separator),
    destName: pair.slice(separator + 1),
  };
}

/**
 * CLI: node watch/promote-key-frames.js <slice-dir> <source>:<destName> [...]
 *
 * Windows absolute paths: use `source|dest` or `C:/path/frame.png:dest.png` (forward slashes).
 *
 * @param {string[]} argv
 * @returns {Promise<number>}
 */
export async function runPromoteKeyFramesCli(argv) {
  const sliceDir = argv[2];
  const pairs = argv.slice(3);
  if (!sliceDir || pairs.length === 0) {
    writeStderr("Usage: node watch/promote-key-frames.js <slice-dir> <source>:<dest-name> [...]");
    return 1;
  }

  const promotions = pairs.map((pair) => parsePromotionPair(pair));

  const promoted = await promoteKeyFrames(sliceDir, promotions);
  writeStdout(JSON.stringify({ promoted }, null, 2));
  return 0;
}

if (isMainModule(import.meta.url)) {
  runPromoteKeyFramesCli(process.argv)
    .then((code) => process.exit(code))
    .catch((err) => {
      writeStderr(err instanceof Error ? err.message : String(err));
      process.exit(1);
    });
}
