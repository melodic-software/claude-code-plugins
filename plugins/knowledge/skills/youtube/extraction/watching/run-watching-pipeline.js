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
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";
import { parseVttSegment } from "@melodic/video-digestion/transcript/vtt-parser";

import { orchestrateWatching } from "./orchestrate-watching.js";

/**
 * @param {string[]} argv
 */
export async function runWatchingPipelineCli(argv) {
  const videoPath = argv[2];
  const vttPath = argv[3];

  if (!videoPath || !vttPath) {
    writeStderr("Usage: node watching/run-watching-pipeline.js <video-path> <transcript-vtt-path>");
    return 1;
  }

  // Temp dirs are retained for the skill's vision reads — the caller cleans them up after absorption.
  const framesDir = await fs.mkdtemp(path.join(os.tmpdir(), "youtube-frames-"));
  const sheetsDir = await fs.mkdtemp(path.join(os.tmpdir(), "youtube-sheets-"));

  const vttText = await fs.readFile(vttPath, "utf8");
  const cues = parseVttSegment(vttText).map((cue) => ({
    startSec: cue.startSec,
    endSec: cue.endSec,
    text: cue.text,
  }));

  const state = await orchestrateWatching({
    videoPath,
    framesDir,
    contactSheetsDir: sheetsDir,
    cues,
  });

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
        contactSheetsDir: sheetsDir,
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

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  runWatchingPipelineCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
