/**
 * Two-pass watching orchestration: scene-detect → coverage plan → anchors → dedup → contact sheets.
 */

import { createContactSheet } from "@melodic/video-digestion/frames/contact-sheet";
import { deduplicateFrames } from "@melodic/video-digestion/frames/dedup";
import { extractSceneFrames } from "@melodic/video-digestion/frames/scene-detect";
import { probeVideoDuration } from "@melodic/video-digestion/media/ffprobe-duration";
import { createLogger } from "@melodic/video-digestion/shared/logger";

import {
  computeCoveragePlan,
  cueAnchorTimestamps,
  densificationAnchorTimestamps,
  stratifiedSampleTimestamps,
} from "./compute-coverage-plan.js";
import { findDensificationWindows, scoreFramePriority } from "./densification.js";
import { extractAnchorFrames } from "./extract-anchor-frames.js";
import { isHighVolume, summarizeFrameSelection } from "./frame-budget.js";
import { mergeFrameCandidates } from "./merge-frame-candidates.js";
import { toSelectedFrame } from "./read-policy.js";
import {
  batchFramesForContactSheets,
  interleaveTranscriptAndFrames,
} from "./timestamp-interleave.js";

/** @typedef {import('./models.js').TranscriptCue} TranscriptCue */
/** @typedef {import('./models.js').WatchingSelectionState} WatchingSelectionState */

/**
 * @typedef {Object} OrchestrateWatchingOptions
 * @property {string} videoPath - Local video file path
 * @property {string} framesDir - Temp dir for extracted frames
 * @property {string} contactSheetsDir - Temp dir for contact sheets
 * @property {TranscriptCue[]} cues - Parsed transcript cues for densification
 * @property {number} [contactSheetBatchSize=16]
 */

/**
 * Assign approximate timestamps to frames by ordinal position and video duration hint.
 *
 * @param {import('@melodic/video-digestion/frames/models.js').FrameCandidate[]} frames
 * @param {number} [durationSec=0]
 */
export function assignFrameTimestamps(frames, durationSec = 0) {
  if (frames.length === 0 || durationSec <= 0) return;

  const step = durationSec / frames.length;
  for (let i = 0; i < frames.length; i++) {
    if (frames[i].timestampSec == null) {
      frames[i].timestampSec = Math.round(i * step * 10) / 10;
    }
  }
}

/**
 * Run the deterministic two-pass watching pipeline.
 *
 * @param {OrchestrateWatchingOptions} options
 * @param {object} [deps]
 * @param {typeof extractSceneFrames} [deps.extractSceneFrames]
 * @param {typeof deduplicateFrames} [deps.deduplicateFrames]
 * @param {typeof createContactSheet} [deps.createContactSheet]
 * @param {typeof probeVideoDuration} [deps.probeVideoDuration]
 * @param {typeof extractAnchorFrames} [deps.extractAnchorFrames]
 * @param {import('@melodic/video-digestion/shared/logger.js').PipelineLogger} [deps.log]
 * @returns {Promise<WatchingSelectionState>}
 */
export async function orchestrateWatching(
  { videoPath, framesDir, contactSheetsDir, cues, contactSheetBatchSize = 16 },
  {
    extractSceneFrames: runSceneDetect = extractSceneFrames,
    deduplicateFrames: runDedup = deduplicateFrames,
    createContactSheet: runContactSheet = createContactSheet,
    probeVideoDuration: runProbe = probeVideoDuration,
    extractAnchorFrames: runAnchorExtract = extractAnchorFrames,
    log = createLogger(),
  } = {},
) {
  log.info("watching: pass-1 starting (probe → scene-detect → coverage plan)");

  const probe = await runProbe(videoPath);
  const lastCue = cues.length > 0 ? cues[cues.length - 1] : null;
  const durationSec = probe?.durationSec ?? lastCue?.endSec ?? 0;

  const sceneResult = await runSceneDetect(videoPath, framesDir, {}, { log });
  const scenePaths = sceneResult.frames.map((frame) => frame.path);
  const sceneDedup = await runDedup(scenePaths, {}, { log });

  const windows = findDensificationWindows(cues);
  const coveragePlan = computeCoveragePlan({
    durationSec,
    densificationWindows: windows,
    sceneCandidateCount: sceneDedup.unique.length,
  });

  /** @type {number[]} */
  let anchorTimestamps = [...densificationAnchorTimestamps(windows), ...cueAnchorTimestamps(cues)];

  if (coveragePlan.forceStratifiedPass) {
    anchorTimestamps = [
      ...anchorTimestamps,
      ...stratifiedSampleTimestamps(durationSec, coveragePlan.stratifiedIntervalSec),
    ];
  }

  log.info(`watching: anchor extraction starting count=${anchorTimestamps.length}`);
  const anchorFrames = await runAnchorExtract(videoPath, framesDir, anchorTimestamps, { log });
  const mergedCandidates = mergeFrameCandidates([...sceneDedup.unique, ...anchorFrames]);
  const mergedPaths = mergedCandidates.map((frame) => frame.path);
  const dedupResult = await runDedup(mergedPaths, {}, { log });

  assignFrameTimestamps(dedupResult.unique, durationSec);

  const scored = dedupResult.unique.map((frame, index) => {
    const priority = scoreFramePriority(frame, index, windows);
    return toSelectedFrame(frame, priority, windows);
  });

  const selection = summarizeFrameSelection(scored, {
    targetMinFrames: coveragePlan.targetMinFrames,
    durationSec,
    densificationWindowCount: windows.length,
  });

  log.info(
    `watching: pass-1 complete unique=${dedupResult.unique.length} selected=${selection.selected.length} highVolume=${selection.highVolume}`,
  );

  log.info("watching: pass-2 starting (contact sheets + interleave)");

  const batches = batchFramesForContactSheets(selection.selected, contactSheetBatchSize);
  /** @type {import('@melodic/video-digestion/frames/models.js').ContactSheet[]} */
  const contactSheets = [];

  for (let i = 0; i < batches.length; i++) {
    const batch = batches[i];
    const outputPath = `${contactSheetsDir}/sheet_${String(i + 1).padStart(3, "0")}.jpg`;
    const sheet = await runContactSheet(
      batch.map((frame) => frame.path),
      outputPath,
      {},
      { log },
    );
    if (sheet) contactSheets.push(sheet);
  }

  const interleavedTimeline = interleaveTranscriptAndFrames(cues, selection.selected);

  log.info(
    `watching: pass-2 complete sheets=${contactSheets.length} timeline=${interleavedTimeline.length}`,
  );

  const highVolume = isHighVolume({
    candidateCount: selection.candidateCount,
    targetMinFrames: coveragePlan.targetMinFrames,
    contactSheetCount: contactSheets.length,
    durationSec,
    densificationWindowCount: windows.length,
  });

  return {
    sceneFrames: sceneResult.frames,
    uniqueFrames: dedupResult.unique,
    densificationWindows: windows,
    coveragePlan,
    selectedFrames: selection.selected,
    contactSheets,
    interleavedTimeline,
    targetMinFrames: selection.targetMinFrames,
    highVolume,
    overCap: false,
    candidateCount: selection.candidateCount,
    durationSec,
  };
}
