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
 * @property {string} [workDir]
 * @property {string} [framesDir]
 * @property {string} [contactSheetsDir]
 * @property {string} [acquiredAt]
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
 * @param {string} filePath
 * @param {unknown} value
 */
async function writeJson(filePath, value) {
  await fs.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

/**
 * Persist selection manifest and coverage plan under the work slice.
 *
 * @param {string} sliceDir
 * @param {WatchingSelectionState} watching
 * @param {TempSessionPaths} tempSession
 * @returns {Promise<WatchingManifestResult>}
 */
export async function writeWatchingManifest(sliceDir, watching, tempSession) {
  const keyFramesDir = lanePath(sliceDir, LANES.keyFrames);
  await fs.mkdir(keyFramesDir, { recursive: true });

  const portableSession = serializeTempSession(tempSession);
  const highVolume = watching.highVolume ?? false;
  const selection = {
    targetMinFrames: watching.targetMinFrames ?? watching.coveragePlan?.targetMinFrames ?? 0,
    highVolume,
    candidateCount: watching.candidateCount,
    durationSec: watching.durationSec ?? watching.coveragePlan?.durationSec ?? 0,
    densificationWindows: watching.densificationWindows,
    tempSession: portableSession,
    selectedFrames: watching.selectedFrames.map((frame) => ({
      file: frame.file,
      timestampSec: frame.timestampSec,
      timestampSource: frame.timestampSource,
      timestampMethod: frame.timestampMethod,
      timestampErrorSec: frame.timestampErrorSec,
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
  await writeJson(selectionPath, selection);

  const coveragePlanPath = path.join(keyFramesDir, "coverage-plan.json");
  await writeJson(coveragePlanPath, {
    ...(watching.coveragePlan ?? {}),
    actualFrameCount: watching.selectedFrames.length,
    highVolume,
  });

  return {
    selectionPath: path.relative(sliceDir, selectionPath),
    coveragePlanPath: path.relative(sliceDir, coveragePlanPath),
    frameCount: watching.selectedFrames.length,
    contactSheetCount: watching.contactSheets.length,
    tempSession: portableSession,
  };
}
