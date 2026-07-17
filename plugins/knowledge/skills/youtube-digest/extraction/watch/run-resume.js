#!/usr/bin/env node
/**
 * CLI: resume interrupted `/youtube-digest watch` from phase-map state.
 *
 * Usage: node watch/run-resume.js <video-slug>
 */

import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { resolveWorkRoot } from "../lib/work-root.js";
import { resolveWorkSliceDir } from "../transcript/derive-video-slug.js";
import {
  detectRecoverableBootstrap,
  formatRecoverCommand,
} from "./detect-recoverable-bootstrap.js";
import {
  buildContinuationPrompt,
  continuationPromptPath,
  findNextPhase,
  readWatchState,
  writeContinuationPrompt,
} from "./watch-state.js";

/**
 * @param {string[]} argv
 */
export async function runResumeCli(argv) {
  const videoSlug = argv[2];
  if (!videoSlug) {
    writeStderr("Usage: node watch/run-resume.js <video-slug>");
    return 1;
  }

  const sliceDir = resolveWorkSliceDir(resolveWorkRoot(), videoSlug);
  const state = await readWatchState(sliceDir);

  if (!state) {
    writeStderr(`No watch.json found at ${sliceDir}`);
    return 1;
  }

  const nextPhase = findNextPhase(state.phases);
  const continuationPrompt = buildContinuationPrompt(state);
  await writeContinuationPrompt(sliceDir, state);
  const recovery = detectRecoverableBootstrap(sliceDir);

  writeStdout(
    JSON.stringify(
      {
        videoSlug,
        sliceDir,
        status: state.status,
        nextPhase,
        frameSelection: state.frameSelection ?? null,
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

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  runResumeCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
