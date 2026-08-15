#!/usr/bin/env node
/**
 * CLI: acquire + transcript + watching selection + harvest for `/youtube-digest watch`.
 *
 * Usage: node watch/run-watch.js <video-url> [--skip-research] [--target <repo>] [--recover <slice-dir>]
 *
 * Acquisition dispatches through the source-adapter registry (unknown host
 * fails closed, non-zero exit, listing supported sources) and consumes the
 * 0..N result envelope: a 0-media envelope produces a well-formed text-only
 * slice (transcript/watching/vision recorded as skipped); visual watching
 * covers the primary media entry, with envelope arity recorded in watch state
 * (`entryCount`) and every caption-bearing entry's transcript written.
 *
 * Vision absorption, research, and synthesis run in the skill session (not this script).
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";
import { parseVttSegment } from "@melodic/video-digestion/transcript/vtt-parser";

import { UnsupportedSourceError } from "../adapters/adapter-contract.js";
import { resolveSourceAdapter } from "../adapters/registry.js";
import { acquireMedia } from "../acquisition/acquire.js";
import { harvestMetadataLinks } from "../harvesting/harvest-links.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";
import { resolveWorkRoot } from "../lib/work-root.js";
import { deriveVideoSlug, resolveWorkSliceDir } from "../transcript/derive-video-slug.js";
import { writeEnvelopeTranscriptArtifacts } from "../transcript/write-transcript.js";
import { orchestrateWatching } from "../watching/orchestrate-watching.js";
import { writeWatchingManifest } from "../watching/write-watching-manifest.js";
import { detectRecoverableBootstrap } from "./detect-recoverable-bootstrap.js";
import { postBootstrapSlice } from "./post-bootstrap-slice.js";
import { recoverWatchBootstrapCli } from "./recover-watch-bootstrap.js";
import {
  continuationPromptPath,
  createWatchState,
  markPhaseComplete,
  writeContinuationPrompt,
  writeWatchState,
} from "./watch-state.js";

/**
 * @param {string[]} argv
 */
// biome-ignore lint/complexity/noExcessiveCognitiveComplexity: single CLI pipeline walk over the 0..N envelope arities
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

  const workDir = await fs.mkdtemp(path.join(os.tmpdir(), "youtube-extraction-"));
  const framesDir = await fs.mkdtemp(path.join(os.tmpdir(), "youtube-frames-"));
  const sheetsDir = await fs.mkdtemp(path.join(os.tmpdir(), "youtube-sheets-"));

  try {
    const acquisition = await acquireMedia(url, { workDir, mode: "full" });
    if (!acquisition.success || !acquisition.data) {
      writeStderr(acquisition.error ?? "Acquisition failed");
      return 1;
    }

    const envelope = acquisition.data;
    const { metadata, entries } = envelope;
    const sliceKey = adapter.extractSliceKey(url, metadata) ?? metadata.id;
    const videoSlug = deriveVideoSlug(metadata.title, sliceKey);
    const sliceDir = resolveWorkSliceDir(resolveWorkRoot(), videoSlug);
    const primary = entries.find((entry) => Boolean(entry.mediaPath)) ?? null;

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

    const written = await writeEnvelopeTranscriptArtifacts({ sliceDir, envelope, sourceUrl: url });
    const primaryIndex = primary ? entries.indexOf(primary) : -1;
    const primaryTranscript =
      written.transcripts.find((entry) => entry.entryIndex === primaryIndex) ??
      written.transcripts[0] ??
      null;
    state = markPhaseComplete(
      state,
      "transcript",
      primaryTranscript
        ? {
            paragraphCount: primaryTranscript.paragraphCount,
            cueCount: primaryTranscript.cueCount,
            transcriptCount: written.transcripts.length,
          }
        : { skipped: true, reason: "no caption-bearing entries" },
    );

    /** @param {import('./watch-state.js').WatchState} current */
    const finishSlice = async (current) => {
      const harvestedLinks = harvestMetadataLinks(metadata, adapter);
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
      const continuationPrompt = await writeContinuationPrompt(sliceDir, next);

      let postBootstrap = null;
      try {
        postBootstrap = postBootstrapSlice(sliceDir);
      } catch (postBootstrapError) {
        writeStderr(
          `WARN: post-bootstrap skipped: ${postBootstrapError instanceof Error ? postBootstrapError.message : String(postBootstrapError)}`,
        );
      }

      return { state: next, harvestedLinks, harvestPath, continuationPrompt, postBootstrap };
    };

    if (!primary) {
      // 0-media envelope: well-formed text-only slice — watching/vision cannot
      // run without media, recorded as skipped so resume advances past them.
      state = markPhaseComplete(state, "watching", { skipped: true, reason: "no media entries" });
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
            harvestedLinkCount: finished.harvestedLinks.length,
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
    await writeWatchState(sliceDir, state);

    const watching = await orchestrateWatching({
      videoPath: primary.mediaPath,
      framesDir,
      contactSheetsDir: sheetsDir,
      cues,
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
          harvestedLinkCount: finished.harvestedLinks.length,
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
  } finally {
    // Temp dirs retained for vision reads in the same session; regen via run-watch when missing.
  }
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  runWatchCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
