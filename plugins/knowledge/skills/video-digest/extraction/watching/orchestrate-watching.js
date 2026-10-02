/**
 * Two-pass watching orchestration: scene-detect → coverage plan → anchors → dedup → contact sheets.
 */

import { createContactSheet } from "@melodic/video-digestion/frames/contact-sheet";
import { deduplicateFrames } from "@melodic/video-digestion/frames/dedup";
import { extractSceneFrames } from "@melodic/video-digestion/frames/scene-detect";
import { probeVideoDuration } from "@melodic/video-digestion/media/ffprobe-duration";
import { createLogger } from "@melodic/video-digestion/shared/logger";

import {
  cueAnchorTimestamps,
  densificationAnchorTimestamps,
  gapFillTimestamps,
  planFrameCoverage,
  stratifiedSampleTimestamps,
} from "./compute-coverage-plan.js";
import { extractAnchorFrames } from "./extract-anchor-frames.js";
import { isHighVolume, selectFramesForCoverage } from "./frame-budget.js";
import { mergeFrameCandidates } from "./merge-frame-candidates.js";
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
 * @property {number} [maxFrameGapSec] - Overrides the coverage plan's maximum gap between timed frames
 */

/**
 * Run the deterministic two-pass watching pipeline.
 *
 * Frames keep the times scene detection measured or estimated and the exact
 * times anchors were extracted at; a frame with neither stays untimed (`null`).
 * After the second dedup, every stretch longer than the plan's `maxFrameGapSec`
 * between timed frames gets anchor frames; untimed frames never count as coverage.
 *
 * @param {OrchestrateWatchingOptions} options
 * @param {object} [deps]
 * @param {typeof extractSceneFrames} [deps.extractSceneFrames]
 * @param {typeof deduplicateFrames} [deps.deduplicateFrames]
 * @param {typeof createContactSheet} [deps.createContactSheet]
 * @param {typeof probeVideoDuration} [deps.probeVideoDuration]
 * @param {typeof extractAnchorFrames} [deps.extractAnchorFrames]
 * @param {import('@melodic/video-digestion/shared/logger').PipelineLogger} [deps.log]
 * @returns {Promise<WatchingSelectionState>}
 */
export async function orchestrateWatching(
  { videoPath, framesDir, contactSheetsDir, cues, contactSheetBatchSize = 16, maxFrameGapSec },
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
  const durationSec = probe?.durationSec ?? cues.at(-1)?.endSec ?? 0;

  const sceneResult = await runSceneDetect(videoPath, framesDir, {}, { log });
  const sceneDedup = await runDedup(sceneResult.frames, {}, { log });

  const { windows, coveragePlan } = planFrameCoverage(cues, {
    durationSec,
    sceneCandidateCount: sceneDedup.unique.length,
    maxFrameGapSec,
  });

  /** @type {number[]} */
  const anchorTimestamps = [
    ...densificationAnchorTimestamps(windows),
    ...cueAnchorTimestamps(cues),
  ];

  if (coveragePlan.forceStratifiedPass) {
    anchorTimestamps.push(
      ...stratifiedSampleTimestamps(durationSec, coveragePlan.stratifiedIntervalSec),
    );
  }

  log.info(`watching: anchor extraction starting count=${anchorTimestamps.length}`);
  const anchorFrames = await runAnchorExtract(videoPath, framesDir, anchorTimestamps, { log });
  const mergedCandidates = mergeFrameCandidates([
    ...sceneDedup.unique,
    ...anchorFrames.map((frame) => ({
      ...frame,
      timestampSource: /** @type {const} */ ("anchor"),
    })),
  ]);
  const dedupResult = await runDedup(mergedCandidates, {}, { log });

  // Gaps are measured over every timed frame examined, before dedup: a frame dedup dropped
  // still shows the screen at that time, so a static stretch is covered, not a gap to refill.
  const fillTimestamps = gapFillTimestamps(
    [...sceneResult.frames, ...anchorFrames].flatMap(({ timestampSec }) =>
      timestampSec != null && Number.isFinite(timestampSec) ? [timestampSec] : [],
    ),
    durationSec,
    coveragePlan.maxFrameGapSec,
  );
  /** @type {import('@melodic/video-digestion/frames/models').FrameCandidate[]} */
  let uniqueFrames = dedupResult.unique;
  if (fillTimestamps.length > 0) {
    log.info(`watching: gap-fill extraction starting count=${fillTimestamps.length}`);
    const fillFrames = await runAnchorExtract(videoPath, framesDir, fillTimestamps, { log });
    uniqueFrames = mergeFrameCandidates([
      ...dedupResult.unique,
      ...fillFrames.map((frame) => ({
        ...frame,
        timestampSource: /** @type {const} */ ("anchor"),
      })),
    ]);
  }

  const selection = selectFramesForCoverage(uniqueFrames, {
    windows,
    targetMinFrames: coveragePlan.targetMinFrames,
    durationSec,
  });

  log.info(
    `watching: pass-1 complete unique=${uniqueFrames.length} selected=${selection.selected.length} highVolume=${selection.highVolume}`,
  );

  log.info("watching: pass-2 starting (contact sheets + interleave)");

  const batches = batchFramesForContactSheets(selection.selected, contactSheetBatchSize);
  /** @type {import('@melodic/video-digestion/frames/models').ContactSheet[]} */
  const contactSheets = [];

  for (const [i, batch] of batches.entries()) {
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
    uniqueFrames,
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
