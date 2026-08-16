#!/usr/bin/env node
/**
 * CLI: acquire captions + write `.work/<video-slug>/transcript.txt`.
 *
 * Usage: node transcript/run-transcript.js <youtube-url>
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { isMainModule } from "../lib/cli-entrypoint.js";
import { resolveWorkRoot } from "../lib/work-root.js";
import { acquireYouTubeMedia } from "../acquisition/acquire.js";
import { deriveVideoSlug, resolveWorkSliceDir } from "./derive-video-slug.js";
import { writeTranscriptArtifacts } from "./write-transcript.js";

/**
 * @param {string[]} argv
 */
export async function runTranscriptCli(argv) {
  const url = argv[2];
  if (!url) {
    writeStderr("Usage: node transcript/run-transcript.js <youtube-url>");
    return 1;
  }

  const workDir = await fs.mkdtemp(path.join(os.tmpdir(), "youtube-extraction-"));

  try {
    const acquisition = await acquireYouTubeMedia(url, { workDir, mode: "transcript" });
    if (!acquisition.success || !acquisition.data) {
      writeStderr(acquisition.error ?? "Acquisition failed");
      return 1;
    }

    const { artifacts, metadata, caption } = acquisition.data;
    const vttText = await fs.readFile(caption.path, "utf8");
    const videoSlug = deriveVideoSlug(metadata.title, metadata.id);
    const sliceDir = resolveWorkSliceDir(resolveWorkRoot(), videoSlug);

    const written = await writeTranscriptArtifacts({
      sliceDir,
      vttText,
      isAutoCaption: caption.isAutoCaption,
      videoTitle: metadata.title,
      videoId: metadata.id,
      sourceUrl: url,
    });

    writeStdout(
      JSON.stringify(
        {
          videoSlug,
          sliceDir,
          captionRung: caption.rung,
          captionPath: caption.path,
          metadataPath: artifacts.metadataPath,
          transcriptPath: written.transcriptPath,
          cueCount: written.cueCount,
          paragraphCount: written.paragraphCount,
          cleanedAutoCaptions: written.cleanedAutoCaptions,
          videoDownloaded: Boolean(artifacts.videoPath),
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

if (isMainModule(import.meta.url)) {
  runTranscriptCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
