#!/usr/bin/env node
/**
 * Recover run-watch bootstrap from an interrupted session when temp dirs still exist.
 *
 * Usage:
 *   node watch/recover-watch-bootstrap.js <slice-dir> <workDir> <framesDir> <contactSheetsDir>
 */

import fs from "node:fs";
import fsPromises from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { probeVideoDuration } from "@melodic/video-digestion/media/ffprobe-duration";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";
import { parseVttSegment } from "@melodic/video-digestion/transcript/vtt-parser";

import { parseVideoMetadata } from "../acquisition/video-metadata.js";
import { harvestMetadataLinks } from "../harvesting/harvest-links.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";
import { computeCoveragePlan } from "../watching/compute-coverage-plan.js";
import { findDensificationWindows, scoreFramePriority } from "../watching/densification.js";
import { summarizeFrameSelection } from "../watching/frame-budget.js";
import { mergeFrameCandidates } from "../watching/merge-frame-candidates.js";
import { assignFrameTimestamps } from "../watching/orchestrate-watching.js";
import { toSelectedFrame } from "../watching/read-policy.js";
import {
  batchFramesForContactSheets,
  interleaveTranscriptAndFrames,
} from "../watching/timestamp-interleave.js";
import { writeWatchingManifest } from "../watching/write-watching-manifest.js";
import {
  createWatchState,
  markPhaseComplete,
  writeContinuationPrompt,
  writeWatchState,
} from "./watch-state.js";

/**
 * @param {string} file
 * @returns {number|null}
 */
function parseTimestampFromFileName(file) {
  const anchorMatch = file.match(/^anchor_(\d+)_/);
  if (anchorMatch) {
    return Number(anchorMatch[1]) / 1000;
  }
  return null;
}

/**
 * @param {string} framesDir
 * @returns {import('@melodic/video-digestion/frames/models.js').FrameCandidate[]}
 */
function loadFramesFromDir(framesDir) {
  const files = fs
    .readdirSync(framesDir)
    .filter((name) => name.endsWith(".png"))
    .sort();
  return files.map((file) => ({
    path: path.join(framesDir, file),
    file,
    timestampSec: parseTimestampFromFileName(file),
  }));
}

/**
 * @param {string} contactSheetsDir
 * @param {import('../watching/models.js').SelectedFrame[][]} batches
 * @returns {import('@melodic/video-digestion/frames/models.js').ContactSheet[]}
 */
function loadExistingContactSheets(contactSheetsDir, batches) {
  const sheetFiles = fs
    .readdirSync(contactSheetsDir)
    .filter((name) => /^sheet_\d+\.jpg$/i.test(name))
    .sort();
  return sheetFiles.map((file, index) => {
    const batch = batches[index] ?? [];
    return {
      outputPath: path.join(contactSheetsDir, file),
      frameCount: batch.length,
      inputPaths: batch.map((frame) => frame.path),
    };
  });
}

/**
 * @param {string} workDir
 * @returns {{ videoPath: string, vttPath: string, infoPath: string }}
 */
function resolveWorkArtifacts(workDir) {
  const entries = fs.readdirSync(workDir);
  const videoPath = entries.find((name) => name.endsWith(".mp4"));
  const vttPath = entries.find((name) => name.endsWith(".vtt") && !name.includes("-orig"));
  const infoPath = entries.find((name) => name.endsWith(".info.json"));
  if (!videoPath || !vttPath || !infoPath) {
    throw new Error(`Missing mp4/vtt/info.json in ${workDir}`);
  }
  return {
    videoPath: path.join(workDir, videoPath),
    vttPath: path.join(workDir, vttPath),
    infoPath: path.join(workDir, infoPath),
  };
}

/**
 * @param {string[]} argv
 */
export async function recoverWatchBootstrapCli(argv) {
  const sliceDir = path.resolve(argv[2]);
  const workDir = path.resolve(argv[3]);
  const framesDir = path.resolve(argv[4]);
  const contactSheetsDir = path.resolve(argv[5]);

  if (!sliceDir || !workDir || !framesDir || !contactSheetsDir) {
    writeStderr(
      "Usage: node watch/recover-watch-bootstrap.js <slice-dir> <workDir> <framesDir> <contactSheetsDir>",
    );
    return 1;
  }

  const { videoPath, vttPath, infoPath } = resolveWorkArtifacts(workDir);
  const metadata = parseVideoMetadata(JSON.parse(fs.readFileSync(infoPath, "utf8")));
  const vttText = fs.readFileSync(vttPath, "utf8");
  const cues = parseVttSegment(vttText).map((cue) => ({
    startSec: cue.startSec,
    endSec: cue.endSec,
    text: cue.text,
  }));

  const probe = await probeVideoDuration(videoPath);
  const durationSec = probe?.durationSec ?? cues[cues.length - 1]?.endSec ?? 0;

  const rawFrames = loadFramesFromDir(framesDir);
  const merged = mergeFrameCandidates(rawFrames);
  assignFrameTimestamps(merged, durationSec);

  const windows = findDensificationWindows(cues);
  const coveragePlan = computeCoveragePlan({
    durationSec,
    densificationWindows: windows,
    sceneCandidateCount: merged.length,
  });

  const scored = merged.map((frame, index) => {
    const priority = scoreFramePriority(frame, index, windows);
    return toSelectedFrame(frame, priority, windows);
  });

  let selection = summarizeFrameSelection(scored, {
    targetMinFrames: coveragePlan.targetMinFrames,
    durationSec,
    densificationWindowCount: windows.length,
  });

  const sheetFiles = fs
    .readdirSync(contactSheetsDir)
    .filter((name) => /^sheet_\d+\.jpg$/i.test(name));
  const expectedSheetCount = sheetFiles.length;
  const expectedFrameCount = expectedSheetCount * 16;

  if (selection.selected.length > expectedFrameCount) {
    const step = selection.selected.length / expectedFrameCount;
    const downsampled = [];
    for (let i = 0; i < expectedFrameCount; i++) {
      downsampled.push(selection.selected[Math.floor(i * step)]);
    }
    selection = {
      ...selection,
      selected: downsampled,
      candidateCount: merged.length,
    };
    writeStderr(
      `WARN: downsampled ${selection.selected.length} → ${expectedFrameCount} frames (stratified) to match ${expectedSheetCount} contact sheets`,
    );
  }

  const batches = batchFramesForContactSheets(selection.selected, 16);
  const contactSheets = loadExistingContactSheets(contactSheetsDir, batches);

  const highVolume = summarizeFrameSelection(selection.selected, {
    targetMinFrames: coveragePlan.targetMinFrames,
    contactSheetCount: contactSheets.length,
    durationSec,
    densificationWindowCount: windows.length,
  }).highVolume;

  const watching = {
    sceneFrames: [],
    uniqueFrames: merged,
    densificationWindows: windows,
    coveragePlan,
    selectedFrames: selection.selected,
    contactSheets,
    interleavedTimeline: interleaveTranscriptAndFrames(cues, selection.selected),
    targetMinFrames: selection.targetMinFrames,
    highVolume,
    durationSec,
    overCap: false,
    candidateCount: selection.candidateCount,
  };

  const tempSession = {
    workDir,
    framesDir,
    contactSheetsDir,
    acquiredAt: new Date().toISOString(),
  };

  let state = createWatchState({
    videoId: metadata.id,
    videoSlug: path.basename(sliceDir),
    sourceUrl: `https://www.youtube.com/watch?v=${metadata.id}`,
    title: metadata.title,
  });
  state.tempSession = tempSession;
  state.status = "vision";
  state = markPhaseComplete(state, "acquire", { videoDownloaded: true, recovered: true });
  state = markPhaseComplete(state, "transcript", { recovered: true });
  state.frameSelection = {
    selectedCount: watching.selectedFrames.length,
    targetMinFrames: watching.targetMinFrames ?? 0,
    highVolume,
    overCap: false,
    candidateCount: watching.candidateCount,
  };

  const manifest = await writeWatchingManifest(sliceDir, watching, tempSession);
  state.artifactPaths = {
    selectionPath: manifest.selectionPath,
    coveragePlanPath: manifest.coveragePlanPath,
    frameCount: manifest.frameCount,
    contactSheetCount: manifest.contactSheetCount,
  };
  state = markPhaseComplete(state, "watching", {
    selectedCount: watching.selectedFrames.length,
    highVolume,
    densificationWindows: windows.length,
    frameCount: manifest.frameCount,
    contactSheetCount: manifest.contactSheetCount,
    targetMinFrames: watching.targetMinFrames ?? 0,
    recovered: true,
  });

  const harvestedLinks = harvestMetadataLinks(metadata);
  await fsPromises.mkdir(lanePath(sliceDir, LANES.source), { recursive: true });
  const harvestPath = lanePath(sliceDir, LANES.source, "harvested-links.json");
  await fsPromises.writeFile(harvestPath, `${JSON.stringify(harvestedLinks, null, 2)}\n`, "utf8");
  state = markPhaseComplete(state, "harvest", {
    linkCount: harvestedLinks.length,
    recovered: true,
  });

  await writeWatchState(sliceDir, state);
  await writeContinuationPrompt(sliceDir, state);

  writeStdout(
    JSON.stringify(
      {
        recovered: true,
        sliceDir,
        selectedCount: watching.selectedFrames.length,
        contactSheetCount: contactSheets.length,
        highVolume,
        durationSec,
        harvestPath,
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
  recoverWatchBootstrapCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
