/**
 * Write watching selection manifest to the work slice — temp paths only, no bulk frame copy.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { serializeTempSession } from "../lib/temp-session-paths.js";

/**
 * @typedef {import('./models.js').WatchingSelectionState} WatchingSelectionState
 */

/**
 * @typedef {Object} TempSessionPaths
 * @property {string} workDir
 * @property {string} framesDir
 * @property {string} contactSheetsDir
 * @property {string} acquiredAt
 */

/**
 * @typedef {Object} WatchingManifestResult
 * @property {string} selectionPath
 * @property {string} coveragePlanPath
 * @property {number} frameCount
 * @property {number} contactSheetCount
 * @property {TempSessionPaths} tempSession
 */

/**
 * Persist selection manifest and coverage plan under the work slice.
 *
 * @param {string} sliceDir
 * @param {WatchingSelectionState} watching
 * @param {TempSessionPaths} tempSession
 * @param {object} [deps]
 * @param {typeof fs.writeFile} [deps.writeFile]
 * @returns {Promise<WatchingManifestResult>}
 */
export async function writeWatchingManifest(
  sliceDir,
  watching,
  tempSession,
  { writeFile = fs.writeFile } = {},
) {
  const keyFramesDir = lanePath(sliceDir, LANES.keyFrames);
  await fs.mkdir(keyFramesDir, { recursive: true });

  const portableSession = serializeTempSession(tempSession);
  const selection = {
    targetMinFrames: watching.targetMinFrames ?? watching.coveragePlan?.targetMinFrames ?? 0,
    highVolume: watching.highVolume ?? false,
    candidateCount: watching.candidateCount,
    durationSec: watching.durationSec ?? watching.coveragePlan?.durationSec ?? 0,
    densificationWindows: watching.densificationWindows,
    tempSession: portableSession,
    selectedFrames: watching.selectedFrames.map((frame) => ({
      file: frame.file,
      timestampSec: frame.timestampSec,
      priorityScore: frame.priorityScore,
      textDense: frame.textDense,
      readResolution: frame.readResolution,
    })),
    contactSheets: watching.contactSheets.map((sheet) => ({
      file: path.basename(sheet.outputPath),
      frameCount: sheet.frameCount,
      inputFiles: sheet.inputPaths.map((inputPath) => path.basename(inputPath)),
    })),
    interleavedTimeline: watching.interleavedTimeline?.map((entry) => {
      if (!entry?.frame) return entry;
      const { path: _omit, ...frame } = entry.frame;
      return { ...entry, frame };
    }),
  };

  const selectionPath = path.join(keyFramesDir, "selection.json");
  await writeFile(selectionPath, `${JSON.stringify(selection, null, 2)}\n`, "utf8");

  const coveragePlanPath = path.join(keyFramesDir, "coverage-plan.json");
  const coveragePayload = {
    ...(watching.coveragePlan ?? {}),
    actualFrameCount: watching.selectedFrames.length,
    highVolume: watching.highVolume ?? false,
  };
  await writeFile(coveragePlanPath, `${JSON.stringify(coveragePayload, null, 2)}\n`, "utf8");

  return {
    selectionPath: path.relative(sliceDir, selectionPath),
    coveragePlanPath: path.relative(sliceDir, coveragePlanPath),
    frameCount: watching.selectedFrames.length,
    contactSheetCount: watching.contactSheets.length,
    tempSession: portableSession,
  };
}
