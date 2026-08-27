#!/usr/bin/env node
/**
 * Validate key-frames/triage/manifest.json against sheet-frame-index.
 *
 * Usage: node watch/validate-triage-json.js <slice-dir>
 */

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { isMainModule } from "../lib/cli-entrypoint.js";
import { validateTriageManifestForSlice } from "../lib/watch-vision-validation.js";

/**
 * @param {string} sliceDir
 * @returns {number}
 */
export function runValidateTriageJson(sliceDir) {
  const result = validateTriageManifestForSlice(sliceDir, { requireIndexMatch: true });
  if (result.valid) {
    writeStdout("triage manifest: valid\n");
    return 0;
  }
  for (const error of result.errors) {
    writeStderr(`triage manifest: ${error}\n`);
  }
  return 1;
}

if (isMainModule(import.meta.url)) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node watch/validate-triage-json.js <slice-dir>\n");
    process.exit(2);
  }
  process.exitCode = runValidateTriageJson(sliceDir);
}
