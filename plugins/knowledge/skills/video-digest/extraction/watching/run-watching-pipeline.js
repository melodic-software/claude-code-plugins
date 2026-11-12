#!/usr/bin/env node
/**
 * CLI: run deterministic watching pipeline (scene-detect → dedup → selection).
 *
 * Usage: node watching/run-watching-pipeline.js <video-path> <transcript-vtt-path>
 *
 * Outputs JSON selection state to stdout. Contact sheets land in OS temp dir.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { runMain } from "../lib/run-main.js";
import { normalizeVttCues } from "./cue-normalize.js";
import { orchestrateWatching } from "./orchestrate-watching.js";

/**
 * @param {string[]} argv
 */
export async function runWatchingPipelineCli(argv) {
  const [, , videoPath, vttPath] = argv;
  if (!videoPath || !vttPath) {
    writeStderr("Usage: node watching/run-watching-pipeline.js <video-path> <transcript-vtt-path>");
    return 1;
  }

  // Temp dirs are retained for the skill's vision reads — the caller cleans them up after absorption.
  const framesDir = await fs.mkdtemp(path.join(os.tmpdir(), "video-frames-"));
  const contactSheetsDir = await fs.mkdtemp(path.join(os.tmpdir(), "video-sheets-"));
  const cues = normalizeVttCues(await fs.readFile(vttPath, "utf8"));

  const state = await orchestrateWatching({ videoPath, framesDir, contactSheetsDir, cues });

  writeStdout(
    JSON.stringify(
      {
        targetMinFrames: state.targetMinFrames,
        highVolume: state.highVolume,
        candidateCount: state.candidateCount,
        selectedCount: state.selectedFrames.length,
        densificationWindows: state.densificationWindows.length,
        contactSheetCount: state.contactSheets.length,
        timelineLength: state.interleavedTimeline.length,
        coveragePlan: state.coveragePlan,
        framesDir,
        contactSheetsDir,
        selectedFrames: state.selectedFrames.map((frame) => ({
          file: frame.file,
          timestampSec: frame.timestampSec,
          readResolution: frame.readResolution,
          textDense: frame.textDense,
          priorityScore: frame.priorityScore,
        })),
      },
      null,
      2,
    ),
  );

  return 0;
}

runMain(import.meta.url, runWatchingPipelineCli);
