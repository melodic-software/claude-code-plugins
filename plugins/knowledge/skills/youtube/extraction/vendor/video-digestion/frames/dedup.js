/**
 * Perceptual-hash frame deduplication via imghash (blockhash).
 *
 * Compares consecutive frames using Hamming distance on hex hashes.
 * Default threshold ≤8 bits per RESEARCH lane 2 / design-threads D9.
 */

import { basename } from "node:path";

import imghash from "imghash";

import { createLogger } from "../shared/logger.js";

/** @typedef {import('./models.js').FrameCandidate} FrameCandidate */
/** @typedef {import('./models.js').FrameSet} FrameSet */

export const DEFAULT_MAX_HAMMING_DISTANCE = 8;

/**
 * Hamming distance between two hex perceptual hashes.
 * @param {string} hashA
 * @param {string} hashB
 * @returns {number}
 */
export function hammingDistanceHex(hashA, hashB) {
  const binA = imghash.hexToBinary(hashA);
  const binB = imghash.hexToBinary(hashB);
  const length = Math.min(binA.length, binB.length);
  let distance = 0;
  for (let i = 0; i < length; i++) {
    if (binA[i] !== binB[i]) {
      distance++;
    }
  }
  return distance + Math.abs(binA.length - binB.length);
}

/**
 * Whether a frame basename is from interval fallback capture.
 * @param {string} fileName
 * @returns {boolean}
 */
export function isIntervalFrame(fileName) {
  return basename(fileName).startsWith("interval_");
}

/**
 * Build a FrameCandidate from a file path.
 * @param {string} framePath
 * @returns {FrameCandidate}
 */
export function toFrameCandidate(framePath) {
  const file = basename(framePath);
  return {
    path: framePath,
    file,
    timestampSec: null,
    sceneScore: null,
    isInterval: isIntervalFrame(file),
    phash: null,
    likelyDuplicate: false,
  };
}

/**
 * Deduplicate near-identical frames using perceptual hashing.
 *
 * Compares each frame to the most recent kept frame of the same capture type
 * (interval vs scene). When Hamming distance ≤ threshold, marks duplicate.
 *
 * @param {string[]} framePaths - Ordered frame file paths
 * @param {object} [options]
 * @param {number} [options.maxHammingDistance=8]
 * @param {object} [deps]
 * @param {(path: string) => Promise<string>} [deps.hashImage]
 * @param {import('../shared/logger.js').PipelineLogger} [deps.log]
 * @returns {Promise<FrameSet>}
 */
export async function deduplicateFrames(
  framePaths,
  { maxHammingDistance = DEFAULT_MAX_HAMMING_DISTANCE } = {},
  { hashImage = (path) => imghash.hash(path), log = createLogger() } = {},
) {
  log.info(`dedup: starting (${framePaths.length} frames, maxHamming=${maxHammingDistance})`);

  /** @type {FrameCandidate[]} */
  const frames = framePaths.map(toFrameCandidate);

  let duplicateCount = 0;
  /** @type {FrameCandidate|null} */
  let lastKept = null;

  for (const frame of frames) {
    // biome-ignore lint/performance/noAwaitInLoops: perceptual hashes are computed sequentially to bound memory
    frame.phash = await hashImage(frame.path);

    if (!lastKept) {
      lastKept = frame;
      continue;
    }

    const sameCaptureType = frame.isInterval === lastKept.isInterval;
    if (!sameCaptureType) {
      lastKept = frame;
      continue;
    }

    if (!frame.phash || !lastKept.phash) {
      continue;
    }
    const distance = hammingDistanceHex(frame.phash, lastKept.phash);
    if (distance <= maxHammingDistance) {
      frame.likelyDuplicate = true;
      duplicateCount++;
    } else {
      lastKept = frame;
    }
  }

  const unique = frames.filter((frame) => !frame.likelyDuplicate);

  log.info(
    `dedup: complete total=${frames.length} duplicates=${duplicateCount} unique=${unique.length}`,
  );

  return {
    frames,
    unique,
    total: frames.length,
    duplicates: duplicateCount,
  };
}
