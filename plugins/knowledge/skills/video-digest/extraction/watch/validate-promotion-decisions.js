#!/usr/bin/env node
/**
 * Validate context/promotion-decisions.json
 *
 * Usage: node watch/validate-promotion-decisions.js <slice-dir>
 */

import { writeStderr } from "@melodic/video-digestion/shared/terminal";

import { isMainModule } from "../lib/cli-entrypoint.js";
import {
  reportSliceValidation,
  validatePromotionDecisionsForSlice,
} from "../lib/watch-vision-validation.js";

/**
 * @param {string} sliceDir
 * @returns {number}
 */
export function runValidatePromotionDecisions(sliceDir) {
  return reportSliceValidation(validatePromotionDecisionsForSlice(sliceDir), "promotion-decisions");
}

if (isMainModule(import.meta.url)) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node watch/validate-promotion-decisions.js <slice-dir>");
    process.exit(2);
  }
  process.exitCode = runValidatePromotionDecisions(sliceDir);
}
