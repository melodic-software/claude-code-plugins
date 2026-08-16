#!/usr/bin/env node
/**
 * CLI: acquire captions + write `.work/<video-slug>/transcript.txt`.
 *
 * Usage: node transcript/run-transcript.js <video-url> [--transcript-strategy <captions|captions+repair|asr>]
 *
 * Acquisition dispatches through the source-adapter registry; an unknown host
 * fails closed (non-zero exit) listing the supported sources. The transcript
 * strategy defaults per source (adapter `transcriptStrategy`); the flag is the
 * explicit pipeline override. A degraded transcript (e.g. captions absent and
 * the optional ASR toolchain not available) still exits 0, with the reason in
 * the `transcriptDegradation` output field.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { primaryEntry, UnsupportedSourceError } from "../adapters/adapter-contract.js";
import { acquireMedia, resolveSourceAdapter } from "../adapters/registry.js";
import { harvestMetadataLinks } from "../harvesting/harvest-links.js";
import { resolveWorkRoot } from "../lib/work-root.js";
import { deriveVideoSlug, resolveWorkSliceDir } from "./derive-video-slug.js";
import { parseTranscriptStrategyOverride } from "./transcript-strategy.js";
import { writeEnvelopeTranscriptArtifacts } from "./write-transcript.js";

/**
 * @param {string[]} argv
 */
export async function runTranscriptCli(argv) {
  const url = argv[2];
  if (!url || url.startsWith("--")) {
    writeStderr(
      "Usage: node transcript/run-transcript.js <video-url> [--transcript-strategy <captions|captions+repair|asr>]",
    );
    return 1;
  }
  const strategyArg = parseTranscriptStrategyOverride(argv);
  if (!strategyArg.ok) {
    writeStderr(strategyArg.error);
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

  const workDir = await fs.mkdtemp(path.join(os.tmpdir(), "video-extraction-"));

  try {
    /** @type {import('../adapters/adapter-contract.js').AcquireOutcome} */
    let acquisition;
    try {
      acquisition = await acquireMedia(url, { workDir, mode: "transcript" });
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

    const envelope = acquisition.data;
    const { metadata } = envelope;
    const sliceKey = adapter.extractSliceKey(url, metadata) ?? metadata.id;
    const videoSlug = deriveVideoSlug(metadata.title, sliceKey);
    const sliceDir = resolveWorkSliceDir(resolveWorkRoot(), videoSlug);

    const written = await writeEnvelopeTranscriptArtifacts({
      sliceDir,
      envelope,
      sourceUrl: url,
      sliceKey,
      transcriptStrategy: adapter.transcriptStrategy,
      strategyOverride: strategyArg.override,
      harvestedLinks: harvestMetadataLinks(metadata, adapter),
    });
    const primary = primaryEntry(envelope);
    const primaryTranscript =
      written.transcripts.find((entry) => entry.entryIndex === written.primaryEntryIndex) ??
      written.transcripts[0] ??
      null;

    writeStdout(
      JSON.stringify(
        {
          videoSlug,
          sliceDir,
          entryCount: written.entryCount,
          captionRung: primary?.caption?.rung ?? null,
          captionPath: primary?.caption?.path ?? null,
          metadataPath: primary?.metadataPath ?? null,
          transcriptPath: primaryTranscript?.transcriptPath ?? null,
          cueCount: primaryTranscript?.cueCount ?? 0,
          paragraphCount: primaryTranscript?.paragraphCount ?? 0,
          cleanedAutoCaptions: primaryTranscript?.cleanedAutoCaptions ?? false,
          transcriptStrategy: primaryTranscript?.strategy ?? null,
          transcriptDegradation: written.transcriptDegradation,
          videoDownloaded: envelope.entries.some((entry) => Boolean(entry.mediaPath)),
          transcripts: written.transcripts,
        },
        null,
        2,
      ),
    );

    return 0;
  } finally {
    await fs.rm(workDir, { recursive: true, force: true });
  }
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  runTranscriptCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
