/**
 * Perceptual-hash frame deduplication via imghash (blockhash).
 *
 * Compares consecutive frames using Hamming distance on hex hashes.
 * Default threshold ≤8 bits per RESEARCH lane 2 / design-threads D9.
 */

import { basename } from "node:path";

import { createLogger } from "../shared/logger.js";

/** @typedef {import('./models.js').FrameCandidate} FrameCandidate */
/** @typedef {import('./models.js').FrameSet} FrameSet */

export const DEFAULT_MAX_HAMMING_DISTANCE = 8;

/**
 * Perceptual hash of an image file. imghash is loaded on first use, so callers
 * that inject their own `hashImage` never need it installed.
 * @param {string} path
 * @returns {Promise<string>}
 */
async function hashImageFile(path) {
  const { default: imghash } = await import("imghash");
  return imghash.hash(path);
}

/**
 * Binary digits of a hex string, four per hex digit; other characters are skipped.
 * @param {string} hex
 * @returns {string}
 */
function hexToBinary(hex) {
  return [...hex]
    .filter((digit) => /[0-9a-f]/i.test(digit))
    .map((digit) => Number.parseInt(digit, 16).toString(2).padStart(4, "0"))
    .join("");
}

/**
 * Hamming distance between two hex perceptual hashes.
 * @param {string} hashA
 * @param {string} hashB
 * @returns {number}
 */
export function hammingDistanceHex(hashA, hashB) {
  const binA = hexToBinary(hashA);
  const binB = hexToBinary(hashB);
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

const TIME_FIELDS = /** @type {const} */ ([
  "timestampSource",
  "timestampMethod",
  "timestampErrorSec",
]);

/**
 * Build a FrameCandidate from a file path, or from a frame whose time fields it keeps.
 * @param {string|FrameCandidate} input
 * @returns {FrameCandidate}
 */
export function toFrameCandidate(input) {
  const source = typeof input === "string" ? { path: input } : input;
  const file = basename(source.path);
  /** @type {FrameCandidate} */
  const frame = {
    path: source.path,
    file,
    timestampSec: source.timestampSec ?? null,
    sceneScore: null,
    isInterval: isIntervalFrame(file),
    phash: null,
    likelyDuplicate: false,
  };
  for (const field of TIME_FIELDS) {
    if (source[field] !== undefined) frame[field] = source[field];
  }
  return frame;
}

/**
 * Deduplicate near-identical frames using perceptual hashing.
 *
 * Compares each frame to the most recent kept frame of the same capture type
 * (interval vs scene). When Hamming distance ≤ threshold, marks duplicate.
 *
 * @param {(string|FrameCandidate)[]} inputs - Ordered frame file paths, or frames whose
 *   time fields are carried into the result
 * @param {object} [options]
 * @param {number} [options.maxHammingDistance=8]
 * @param {object} [deps]
 * @param {(path: string) => Promise<string>} [deps.hashImage]
 * @param {import('../shared/logger.js').PipelineLogger} [deps.log]
 * @returns {Promise<FrameSet>}
 */
export async function deduplicateFrames(
  inputs,
  { maxHammingDistance = DEFAULT_MAX_HAMMING_DISTANCE } = {},
  { hashImage = hashImageFile, log = createLogger() } = {},
) {
  log.info(`dedup: starting (${inputs.length} frames, maxHamming=${maxHammingDistance})`);

  /** @type {FrameCandidate[]} */
  const frames = inputs.map((input) => toFrameCandidate(input));

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
