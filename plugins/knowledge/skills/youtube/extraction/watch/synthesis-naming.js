/**
 * Semantic naming for synthesis key-frame promotions.
 */

import path from "node:path";

import { loadPromotionNameMap } from "./promotion-name-map.js";

const IMAGE_EXT = /\.(png|jpe?g|webp)$/i;

/**
 * @param {number} timestampSec
 * @returns {string}
 */
export function formatTimestampSlug(timestampSec) {
  const totalSec = Math.max(0, Math.round(timestampSec));
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  return `${min}m${String(sec).padStart(2, "0")}s`;
}

/**
 * @param {string} sourceFile
 * @returns {string}
 */
export function sourceStem(sourceFile) {
  return sourceFile.replace(IMAGE_EXT, "").toLowerCase();
}

/**
 * @param {string} sourceFile
 * @param {number} timestampSec
 * @param {Record<string, string>} [knownDestBySource]
 * @returns {string}
 */
export function synthesisDestName(sourceFile, timestampSec, knownDestBySource = {}) {
  if (knownDestBySource[sourceFile]) {
    return knownDestBySource[sourceFile];
  }
  const stem = sourceStem(sourceFile);
  const at = formatTimestampSlug(timestampSec);
  return `at-${at}-${stem}.png`;
}

/**
 * @param {string} sourceFile
 * @param {number} timestampSec
 * @param {string} sliceDir
 * @returns {string}
 */
export function synthesisDestNameForSlice(sourceFile, timestampSec, sliceDir) {
  const map = loadPromotionNameMap(sliceDir);
  return synthesisDestName(sourceFile, timestampSec, map);
}

/**
 * Prefer semantic names when two files share identical pixels.
 *
 * @param {string} fileName
 * @returns {number}
 */
export function synthesisNameQualityScore(fileName) {
  const base = path.basename(fileName, path.extname(fileName));
  let score = 0;
  if (/[a-z]/i.test(base)) score += 20;
  if (base.startsWith("at-") && base.includes("scene_")) score += 5;
  if (base.startsWith("at-") && base.includes("anchor_")) score += 8;
  if (/^\d+(-\d+)*$/.test(base)) score -= 15;
  if (/-\d+(-\d+)+$/.test(base)) score -= 10;
  if (
    !fileName.startsWith("at-") &&
    !fileName.startsWith("scene_") &&
    !fileName.startsWith("anchor_")
  ) {
    score += 30;
  }
  return score;
}
