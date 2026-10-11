#!/usr/bin/env node
/**
 * CLI: acquire + transcript + watching selection + harvest for `/video-digest watch`.
 *
 * Usage: node watch/run-watch.js <video-url> [--skip-research] [--target <repo>]
 *   [--recover <slice-dir>] [--transcript-strategy <captions|captions+repair|asr>]
 *   [--max-frame-gap-sec <sec>]
 *
 * Acquisition dispatches through the source-adapter registry (unknown host
 * fails closed, non-zero exit, listing supported sources) and consumes the
 * 0..N result envelope: a 0-media envelope produces a well-formed text-only
 * slice (transcript/watching/vision recorded as skipped); visual watching
 * covers the primary media entry, with envelope arity recorded in watch state
 * (`entryCount`) and every transcript-bearing entry's transcript written. The
 * transcript strategy defaults per source (adapter `transcriptStrategy`); the
 * flag is the explicit pipeline override, and a degraded transcript surfaces
 * in the `transcriptDegradation` provenance field (watch.json + output),
 * never silently. `--max-frame-gap-sec` overrides the coverage plan's longest
 * allowed stretch between timed frames (`MAX_FRAME_GAP_SEC` by default); the
 * effective value is recorded in watch.json so `--recover` plans with it too.
 *
 * Vision absorption, research, and synthesis run in the skill session (not this script).
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";
import { parseVttSegment } from "@melodic/video-digestion/transcript/vtt-parser";

import {
  primaryEntry,
  sourceMetadataSubset,
  UnsupportedSourceError,
} from "../adapters/adapter-contract.js";
import { acquireMedia, resolveSourceAdapter } from "../adapters/registry.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";
import { resolveWorkRoot } from "../lib/work-root.js";
import { deriveVideoSlug, resolveWorkSliceDir } from "../transcript/derive-video-slug.js";
import { parseTranscriptStrategyOverride } from "../transcript/transcript-strategy.js";
import { writeEnvelopeTranscriptArtifacts } from "../transcript/write-transcript.js";
import {
  MAX_FRAME_GAP_SEC,
  parseMaxFrameGapSecOverride,
} from "../watching/compute-coverage-plan.js";
import { orchestrateWatching } from "../watching/orchestrate-watching.js";
import { writeWatchingManifest } from "../watching/write-watching-manifest.js";
import { detectRecoverableBootstrap } from "./detect-recoverable-bootstrap.js";
import { postBootstrapSlice } from "./post-bootstrap-slice.js";
import { recoverWatchBootstrapCli } from "./recover-watch-bootstrap.js";
import {
  continuationPromptPath,
  createWatchState,
  markPhaseComplete,
  removeRecordedTempSessionDirs,
  writeContinuationPrompt,
  writeWatchState,
} from "./watch-state.js";

/**
 * @param {string[]} argv
 */
export async function runWatchCli(argv) {
  const recoverIndex = argv.indexOf("--recover");
  if (recoverIndex !== -1) {
    const sliceDir = argv[recoverIndex + 1];
    if (!sliceDir) {
      writeStderr("Usage: node watch/run-watch.js --recover <slice-dir>");
      return 1;
    }
    const detection = detectRecoverableBootstrap(sliceDir);
    if (!detection.recoverable || !detection.tempSession) {
      writeStderr(`Cannot recover: ${detection.reason}`);
      return 1;
    }
    const { workDir, framesDir, contactSheetsDir } = detection.tempSession;
    // recoverWatchBootstrapCli reads its four args from argv[2..5] (process.argv
    // convention: [node, script, ...args]). The two leading placeholders align
    // the real args to positions 2-5.
    return recoverWatchBootstrapCli([
      "node",
      "recover-watch-bootstrap.js",
      sliceDir,
      workDir ?? "",
      framesDir ?? "",
      contactSheetsDir ?? "",
    ]);
  }

  const url = argv[2];
  if (!url || url.startsWith("--")) {
    writeStderr(
      "Usage: node watch/run-watch.js <video-url> [--skip-research] [--target <repo>] [--recover <slice-dir>]",
    );
    return 1;
  }

  /** @type {import('../adapters/adapter-contract.js').SourceAdapter} */
  let adapter;
  try {
    adapter = resolveSourceAdapter(url);
  } catch (error) {
    if (error instanceof UnsupportedSourceError) {
      writeStderr(error.message);
      return 1;
    }
    throw error;
  }

  const skipResearch = argv.includes("--skip-research");
  const targetIndex = argv.indexOf("--target");
  if (targetIndex !== -1 && !argv[targetIndex + 1]) {
    writeStderr("`--target` requires a value");
    return 1;
  }
  const target = targetIndex !== -1 ? argv[targetIndex + 1] : undefined;
  const strategyArg = parseTranscriptStrategyOverride(argv);
  if (!strategyArg.ok) {
    writeStderr(strategyArg.error);
    return 1;
  }
  const maxFrameGapArg = parseMaxFrameGapSecOverride(argv);
  if (!maxFrameGapArg.ok) {
    writeStderr(maxFrameGapArg.error);
    return 1;
  }
  const maxFrameGapSec = maxFrameGapArg.override ?? MAX_FRAME_GAP_SEC;

  // Until watch.json records the temp dirs, nothing else points at them, so a
  // failure removes the ones this run made. Once recorded, --recover needs them.
  /** @type {TempDirs} */
  const temp = { dirs: {}, recorded: false };
  try {
    return await watchUrl({ url, adapter, skipResearch, target, strategyArg, maxFrameGapSec, temp });
  } finally {
    if (!temp.recorded) await removeRecordedTempSessionDirs(temp.dirs, "watch");
  }
}

/**
 * @typedef {Object} TempDirs
 * @property {{ workDir?: string, framesDir?: string, contactSheetsDir?: string }} dirs - created by this run
 * @property {boolean} recorded - true once watch.json holds them as tempSession
 */

/**
 * @param {{
 *   url: string,
 *   adapter: import('../adapters/adapter-contract.js').SourceAdapter,
 *   skipResearch: boolean,
 *   target: string|undefined,
 *   strategyArg: { override: import('../adapters/adapter-contract.js').TranscriptStrategy | null },
 *   maxFrameGapSec: number,
 *   temp: TempDirs,
 * }} options
 */
async function watchUrl({ url, adapter, skipResearch, target, strategyArg, maxFrameGapSec, temp }) {
  // Temp dirs retained for vision reads in the same session; regen via run-watch when missing.
  const workDir = await fs.mkdtemp(path.join(os.tmpdir(), "video-extraction-"));
  temp.dirs.workDir = workDir;
  const framesDir = await fs.mkdtemp(path.join(os.tmpdir(), "video-frames-"));
  temp.dirs.framesDir = framesDir;
  const sheetsDir = await fs.mkdtemp(path.join(os.tmpdir(), "video-sheets-"));
  temp.dirs.contactSheetsDir = sheetsDir;

  /** @type {import('../adapters/adapter-contract.js').AcquireOutcome} */
  let acquisition;
  writeStderr("watch: acquire start");
  try {
    acquisition = await acquireMedia(url, { workDir, mode: "full" });
  } catch (error) {
    if (error instanceof UnsupportedSourceError) {
      writeStderr(error.message);
      return 1;
    }
    throw error;
  }
  if (!acquisition.success || !acquisition.data) {
    writeStderr(acquisition.error ?? "Acquisition failed");
    return 1;
  }
  writeStderr("watch: acquire end");

  const envelope = acquisition.data;
  const { metadata, entries } = envelope;
  const sliceKey = adapter.extractSliceKey(url, metadata) ?? metadata.id;
  const videoSlug = deriveVideoSlug(metadata.title, sliceKey);
  const sliceDir = resolveWorkSliceDir(resolveWorkRoot(), videoSlug);
  const primary = primaryEntry(envelope);

  const tempSession = {
    workDir,
    framesDir,
    contactSheetsDir: sheetsDir,
    acquiredAt: new Date().toISOString(),
  };

  let state = createWatchState({
    videoId: metadata.id,
    videoSlug,
    sourceUrl: url,
    title: metadata.title,
    target,
    sourceMetadata: sourceMetadataSubset(metadata),
    maxFrameGapSec,
  });
  state.tempSession = tempSession;
  state.status = "acquiring";
  state.skipResearch = skipResearch;
  state = markPhaseComplete(state, "acquire", {
    entryCount: entries.length,
    videoDownloaded: Boolean(primary?.mediaPath),
    captionRung: primary?.caption?.rung ?? null,
    ...(envelope.acquireMetrics ?? {}),
  });

  const harvestedLinks = adapter.harvestLinks(metadata);
  const transcriptStrategyLabel = strategyArg.override ?? adapter.transcriptStrategy;
  writeStderr(`watch: transcript start (strategy: ${transcriptStrategyLabel})`);
  const written = await writeEnvelopeTranscriptArtifacts({
    sliceDir,
    envelope,
    sourceUrl: url,
    sliceKey,
    transcriptStrategy: adapter.transcriptStrategy,
    strategyOverride: strategyArg.override,
    harvestedLinks,
  });
  const primaryTranscript =
    written.transcripts.find((entry) => entry.entryIndex === written.primaryEntryIndex) ??
    written.transcripts[0] ??
    null;
  const degradationMetric = written.transcriptDegradation
    ? { transcriptDegradation: written.transcriptDegradation }
    : {};
  const appliedTranscriptStrategy = primaryTranscript?.strategy ?? transcriptStrategyLabel;
  writeStderr(`watch: transcript end (strategy: ${appliedTranscriptStrategy})`);
  state = markPhaseComplete(
    state,
    "transcript",
    primaryTranscript
      ? {
          paragraphCount: primaryTranscript.paragraphCount,
          cueCount: primaryTranscript.cueCount,
          transcriptCount: written.transcripts.length,
          transcriptStrategy: primaryTranscript.strategy,
          ...degradationMetric,
        }
      : {
          skipped: true,
          reason: "no transcript-bearing entries",
          ...degradationMetric,
        },
  );

  /** @param {import('./watch-state.js').WatchState} current */
  const finishSlice = async (current) => {
    await fs.mkdir(lanePath(sliceDir, LANES.source), { recursive: true });
    const harvestPath = lanePath(sliceDir, LANES.source, "harvested-links.json");
    await fs.writeFile(harvestPath, `${JSON.stringify(harvestedLinks, null, 2)}\n`, "utf8");
    let next = markPhaseComplete(current, "harvest", { linkCount: harvestedLinks.length });

    // Record the skip in the phase map so resume (which derives nextPhase from
    // watch.json alone) advances past research instead of re-routing into it.
    if (skipResearch) {
      next = markPhaseComplete(next, "research", { skipped: true });
    }

    await writeWatchState(sliceDir, next);
    temp.recorded = true;
    const continuationPrompt = await writeContinuationPrompt(sliceDir, next);

    let postBootstrap = null;
    try {
      postBootstrap = postBootstrapSlice(sliceDir);
    } catch (postBootstrapError) {
      writeStderr(
        `WARN: post-bootstrap skipped: ${postBootstrapError instanceof Error ? postBootstrapError.message : String(postBootstrapError)}`,
      );
    }

    return { state: next, harvestPath, continuationPrompt, postBootstrap };
  };

  if (!primary?.mediaPath) {
    // 0-media envelope: well-formed text-only slice — watching/vision cannot
    // run without media, recorded as skipped so resume advances past them.
    writeStderr("watch: watching start");
    state = markPhaseComplete(state, "watching", { skipped: true, reason: "no media entries" });
    writeStderr("watch: watching end (skipped: no media entries)");
    state = markPhaseComplete(state, "vision", { skipped: true, reason: "no media entries" });
    state.status = "researching";
    const finished = await finishSlice(state);
    state = finished.state;

    writeStdout(
      JSON.stringify(
        {
          videoSlug,
          sliceDir,
          status: state.status,
          entryCount: entries.length,
          textOnly: true,
          transcriptStrategy: primaryTranscript?.strategy ?? null,
          transcriptDegradation: written.transcriptDegradation,
          harvestedLinkCount: harvestedLinks.length,
          skipResearch,
          tempSession,
          harvestPath: finished.harvestPath,
          continuationPromptPath: continuationPromptPath(sliceDir),
          nextStep: "Continue skill research/synthesis per SKILL.md watch protocol (no media)",
          continuationPrompt: finished.continuationPrompt,
          postBootstrap: finished.postBootstrap,
        },
        null,
        2,
      ),
    );

    return 0;
  }

  const vttText = primary.caption ? await fs.readFile(primary.caption.path, "utf8") : "";
  const cues = (vttText ? parseVttSegment(vttText) : []).map((cue) => ({
    startSec: cue.startSec,
    endSec: cue.endSec,
    text: cue.text,
  }));

  // Persist state + tempSession before the long extraction phase so an
  // interrupt during ffmpeg/contact-sheet work leaves a watch.json that
  // detectRecoverableBootstrap can discover (it requires the file to exist).
  state.status = "watching";
  writeStderr("watch: watching start");
  await writeWatchState(sliceDir, state);
  temp.recorded = true;

  const watching = await orchestrateWatching({
    videoPath: primary.mediaPath,
    framesDir,
    contactSheetsDir: sheetsDir,
    cues,
    maxFrameGapSec,
  });

  state.status = "vision";
  state.frameSelection = {
    selectedCount: watching.selectedFrames.length,
    targetMinFrames: watching.targetMinFrames ?? 0,
    highVolume: watching.highVolume ?? false,
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
    highVolume: watching.highVolume ?? false,
    densificationWindows: watching.densificationWindows.length,
    frameCount: manifest.frameCount,
    contactSheetCount: manifest.contactSheetCount,
    targetMinFrames: watching.targetMinFrames ?? 0,
  });
  writeStderr("watch: watching end");

  const finished = await finishSlice(state);
  state = finished.state;

  writeStdout(
    JSON.stringify(
      {
        videoSlug,
        sliceDir,
        status: state.status,
        entryCount: entries.length,
        highVolume: watching.highVolume ?? false,
        selectedCount: watching.selectedFrames.length,
        targetMinFrames: watching.targetMinFrames ?? 0,
        transcriptStrategy: primaryTranscript?.strategy ?? null,
        transcriptDegradation: written.transcriptDegradation,
        harvestedLinkCount: harvestedLinks.length,
        skipResearch,
        tempSession,
        framesDir,
        contactSheetsDir: sheetsDir,
        sliceArtifactPaths: manifest,
        harvestPath: finished.harvestPath,
        continuationPromptPath: continuationPromptPath(sliceDir),
        nextStep: "Continue skill vision absorption per SKILL.md watch protocol",
        continuationPrompt: finished.continuationPrompt,
        postBootstrap: finished.postBootstrap,
      },
      null,
      2,
    ),
  );

  return 0;
}

if (isMainModule(import.meta.url)) {
  runWatchCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
