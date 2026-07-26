#!/usr/bin/env node
/**
 * CLI: acquire + transcript + watching selection + harvest for `/youtube-digest watch`.
 *
 * Usage: node watch/run-watch.js <youtube-url> [--skip-research] [--target <repo>] [--recover <slice-dir>]
 *
 * Vision absorption, research, and synthesis run in the skill session (not this script).
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";
import { parseVttSegment } from "@melodic/video-digestion/transcript/vtt-parser";

import { acquireYouTubeMedia } from "../acquisition/acquire.js";
import { harvestMetadataLinks } from "../harvesting/harvest-links.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";
import { resolveWorkRoot } from "../lib/work-root.js";
import { deriveVideoSlug, resolveWorkSliceDir } from "../transcript/derive-video-slug.js";
import { writeTranscriptArtifacts } from "../transcript/write-transcript.js";
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
      "Usage: node watch/run-watch.js <youtube-url> [--skip-research] [--target <repo>] [--recover <slice-dir>]",
    );
    return 1;
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
    const acquisition = await acquireYouTubeMedia(url, { workDir, mode: "full" });
    if (!acquisition.success || !acquisition.data) {
      writeStderr(acquisition.error ?? "Acquisition failed");
      return 1;
    }

    const { artifacts, metadata, caption } = acquisition.data;
    const videoSlug = deriveVideoSlug(metadata.title, metadata.id);
    const sliceDir = resolveWorkSliceDir(resolveWorkRoot(), videoSlug);

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
      videoDownloaded: Boolean(artifacts.videoPath),
      captionRung: caption.rung,
      ...(acquisition.data.acquireMetrics ?? {}),
    });

    const vttText = await fs.readFile(caption.path, "utf8");
    const written = await writeTranscriptArtifacts({
      sliceDir,
      vttText,
      isAutoCaption: caption.isAutoCaption,
      videoTitle: metadata.title,
      videoId: metadata.id,
      sourceUrl: url,
    });
    state = markPhaseComplete(state, "transcript", {
      paragraphCount: written.paragraphCount,
      cueCount: written.cueCount,
    });

    const cues = parseVttSegment(vttText).map((cue) => ({
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
      videoPath: artifacts.videoPath,
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

    const harvestedLinks = harvestMetadataLinks(metadata);
    await fs.mkdir(lanePath(sliceDir, LANES.source), { recursive: true });
    const harvestPath = lanePath(sliceDir, LANES.source, "harvested-links.json");
    await fs.writeFile(harvestPath, `${JSON.stringify(harvestedLinks, null, 2)}\n`, "utf8");
    state = markPhaseComplete(state, "harvest", { linkCount: harvestedLinks.length });

    // Record the skip in the phase map so resume (which derives nextPhase from
    // watch.json alone) advances past research instead of re-routing into it.
    if (skipResearch) {
      state = markPhaseComplete(state, "research", { skipped: true });
    }

    await writeWatchState(sliceDir, state);
    const continuationPrompt = await writeContinuationPrompt(sliceDir, state);

    let postBootstrap = null;
    try {
      postBootstrap = postBootstrapSlice(sliceDir);
    } catch (postBootstrapError) {
      writeStderr(
        `WARN: post-bootstrap skipped: ${postBootstrapError instanceof Error ? postBootstrapError.message : String(postBootstrapError)}`,
      );
    }

    writeStdout(
      JSON.stringify(
        {
          videoSlug,
          sliceDir,
          status: state.status,
          highVolume: watching.highVolume ?? false,
          selectedCount: watching.selectedFrames.length,
          targetMinFrames: watching.targetMinFrames ?? 0,
          harvestedLinkCount: harvestedLinks.length,
          skipResearch,
          tempSession,
          framesDir,
          contactSheetsDir: sheetsDir,
          sliceArtifactPaths: manifest,
          harvestPath,
          continuationPromptPath: continuationPromptPath(sliceDir),
          nextStep: "Continue skill vision absorption per SKILL.md watch protocol",
          continuationPrompt,
          postBootstrap,
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
