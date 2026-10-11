#!/usr/bin/env node
/**
 * CLI: resume interrupted `/video-digest watch` from phase-map state.
 *
 * Usage: node watch/run-resume.js <slice-slug>
 */

import fs from "node:fs";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { normalizePortableTempPath, resolveTempSession } from "../lib/temp-session-paths.js";
import { resolveWorkRoot } from "../lib/work-root.js";
import { resolveWorkSliceDir } from "../transcript/derive-video-slug.js";
import {
  detectRecoverableBootstrap,
  formatRecoverCommand,
} from "./detect-recoverable-bootstrap.js";
import {
  continuationPromptPath,
  findNextPhase,
  readWatchState,
  writeContinuationPrompt,
} from "./watch-state.js";

/** Temp-session dirs vision reads its frames and contact sheets from. */
const VISION_TEMP_KEYS = /** @type {const} */ (["framesDir", "contactSheetsDir"]);

/**
 * Recorded vision temp dirs that no longer exist, in portable `{tmp}` form.
 *
 * @param {{ workDir?: string, framesDir?: string, contactSheetsDir?: string }|undefined} tempSession
 * @returns {string[]}
 */
function missingTempSessionDirs(tempSession) {
  if (!tempSession) return [];
  const resolved = resolveTempSession(tempSession);
  return VISION_TEMP_KEYS.filter((key) => {
    const dir = resolved[key];
    return dir !== undefined && !fs.existsSync(dir);
  }).map((key) => String(normalizePortableTempPath(tempSession[key])));
}

/**
 * @param {string[]} argv
 */
export async function runResumeCli(argv) {
  const videoSlug = argv[2];
  if (!videoSlug) {
    writeStderr("Usage: node watch/run-resume.js <slice-slug>");
    return 1;
  }

  let sliceDir;
  try {
    sliceDir = resolveWorkSliceDir(resolveWorkRoot(), videoSlug);
  } catch (error) {
    writeStderr(error instanceof Error ? error.message : String(error));
    return 1;
  }
  const state = await readWatchState(sliceDir);

  if (!state) {
    writeStderr(`No watch.json found at ${sliceDir}`);
    return 1;
  }

  const nextPhase = findNextPhase(state.phases);
  const summary = { videoSlug, sliceDir, status: state.status, nextPhase };

  // A closed slice has nothing to resume, and its prompt may be committed: leave it as is.
  if (state.status === "complete") {
    writeStdout(JSON.stringify({ ...summary, nothingToResume: true }, null, 2));
    return 0;
  }

  const missingTempDirs = missingTempSessionDirs(state.tempSession);
  const tempSessionPresent = missingTempDirs.length === 0;

  if (nextPhase === "vision" && !tempSessionPresent) {
    writeStdout(JSON.stringify({ ...summary, tempSessionPresent, missingTempDirs }, null, 2));
    writeStderr(
      `resume: temp session dirs are gone (${missingTempDirs.join(", ")}) and vision reads its frames from them. Re-run run-watch.js for this slice, then resume.`,
    );
    return 1;
  }

  const continuationPrompt = await writeContinuationPrompt(sliceDir, state);
  const recovery = detectRecoverableBootstrap(sliceDir);

  writeStdout(
    JSON.stringify(
      {
        ...summary,
        target: state.target ?? null,
        frameSelection: state.frameSelection ?? null,
        tempSessionPresent,
        missingTempDirs,
        continuationPromptPath: continuationPromptPath(sliceDir),
        continuationPrompt,
        recoverableBootstrap: recovery.recoverable,
        recoverCommand: recovery.recoverable ? formatRecoverCommand(sliceDir) : null,
      },
      null,
      2,
    ),
  );

  return 0;
}

if (isMainModule(import.meta.url)) {
  runResumeCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
