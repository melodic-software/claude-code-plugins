#!/usr/bin/env node
/**
 * Validate context/promotion-decisions.json
 *
 * Usage: node watch/validate-promotion-decisions.js <slice-dir>
 */

import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { validatePromotionDecisionsForSlice } from "../lib/watch-vision-validation.js";

/**
 * @param {string} sliceDir
 * @returns {number}
 */
export function runValidatePromotionDecisions(sliceDir) {
  const result = validatePromotionDecisionsForSlice(sliceDir);
  if (result.valid) {
    writeStdout("promotion-decisions: valid\n");
    return 0;
  }
  for (const error of result.errors) {
    writeStderr(`promotion-decisions: ${error}\n`);
  }
  return 1;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node watch/validate-promotion-decisions.js <slice-dir>\n");
    process.exit(2);
  }
  process.exitCode = runValidatePromotionDecisions(sliceDir);
}
