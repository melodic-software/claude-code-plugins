#!/usr/bin/env node
/**
 * CLI: acquire captions + write `.work/<video-slug>/transcript.txt`.
 *
 * Usage: node transcript/run-transcript.js <video-url>
 *
 * Acquisition dispatches through the source-adapter registry; an unknown host
 * fails closed (non-zero exit) listing the supported sources.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { singleEntry, UnsupportedSourceError } from "../adapters/adapter-contract.js";
import { resolveSourceAdapter } from "../adapters/registry.js";
import { acquireMedia } from "../acquisition/acquire.js";
import { resolveWorkRoot } from "../lib/work-root.js";
import { deriveVideoSlug, resolveWorkSliceDir } from "./derive-video-slug.js";
import { writeEnvelopeTranscriptArtifacts } from "./write-transcript.js";

/**
 * @param {string[]} argv
 */
export async function runTranscriptCli(argv) {
  const url = argv[2];
  if (!url) {
    writeStderr("Usage: node transcript/run-transcript.js <video-url>");
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

  const workDir = await fs.mkdtemp(path.join(os.tmpdir(), "youtube-extraction-"));

  try {
    const acquisition = await acquireMedia(url, { workDir, mode: "transcript" });
    if (!acquisition.success || !acquisition.data) {
      writeStderr(acquisition.error ?? "Acquisition failed");
      return 1;
    }

    const envelope = acquisition.data;
    const { metadata } = envelope;
    const sliceKey = adapter.extractSliceKey(url, metadata) ?? metadata.id;
    const videoSlug = deriveVideoSlug(metadata.title, sliceKey);
    const sliceDir = resolveWorkSliceDir(resolveWorkRoot(), videoSlug);

    const written = await writeEnvelopeTranscriptArtifacts({ sliceDir, envelope, sourceUrl: url });
    const primary = singleEntry(envelope);
    const primaryTranscript =
      written.transcripts.find((entry) => entry.entryIndex === 0) ?? null;

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
