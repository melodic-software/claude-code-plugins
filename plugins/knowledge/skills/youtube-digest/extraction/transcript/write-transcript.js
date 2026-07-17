/**
 * Convert selected caption VTT into cleaned timestamped transcript.txt.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { cleanAutoCaptions } from "@melodic/video-digestion/transcript/auto-caption-clean";
import { cleanManualCaptions } from "@melodic/video-digestion/transcript/manual-caption-clean";
import { formatTranscript } from "@melodic/video-digestion/transcript/vtt-parser";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/**
 * @typedef {Object} TranscriptWriteResult
 * @property {string} transcriptPath
 * @property {string} transcript
 * @property {number} cueCount
 * @property {number} paragraphCount
 * @property {boolean} cleanedAutoCaptions
 */

/**
 * Build transcript text from a caption file.
 *
 * @param {string} vttText
 * @param {boolean} isAutoCaption
 * @returns {{ transcript: string, cueCount: number, paragraphCount: number, cleanedAutoCaptions: boolean, cleanedManualCaptions: boolean }}
 */
export function buildTranscriptText(vttText, isAutoCaption) {
  let cleanedAutoCaptions = false;
  let cleanedManualCaptions = false;
  let cues;

  if (isAutoCaption) {
    const cleaned = cleanAutoCaptions(vttText);
    cues = cleaned.cues;
    cleanedAutoCaptions = true;
  } else {
    const cleaned = cleanManualCaptions(vttText);
    cues = cleaned.cues;
    cleanedManualCaptions = cleaned.cleanedManualCaptions;
  }

  const transcript = formatTranscript(cues);
  const paragraphCount = transcript ? transcript.split("\n\n").length : 0;

  return {
    transcript,
    cueCount: cues.length,
    paragraphCount,
    cleanedAutoCaptions,
    cleanedManualCaptions,
  };
}

/**
 * Write transcript artifacts into a video-digest slice directory.
 *
 * @param {object} options
 * @param {string} options.sliceDir - `.work/<video-slug>/`
 * @param {string} options.vttText
 * @param {boolean} options.isAutoCaption
 * @param {string} options.videoTitle
 * @param {string} options.videoId
 * @param {string} options.sourceUrl
 * @param {typeof fs.writeFile} [options.writeFile]
 * @param {typeof fs.mkdir} [options.mkdir]
 * @returns {Promise<TranscriptWriteResult>}
 */
export async function writeTranscriptArtifacts(
  { sliceDir, vttText, isAutoCaption, videoTitle, videoId, sourceUrl },
  { writeFile = fs.writeFile, mkdir = fs.mkdir } = {},
) {
  await mkdir(sliceDir, { recursive: true });

  const built = buildTranscriptText(vttText, isAutoCaption);
  const sourceDir = lanePath(sliceDir, LANES.source);
  await mkdir(sourceDir, { recursive: true });
  const transcriptPath = lanePath(sliceDir, LANES.source, "transcript.txt");
  await writeFile(transcriptPath, `${built.transcript}\n`, "utf8");

  const readmePath = path.join(sliceDir, "README.md");
  const readme = `# ${videoTitle}

Video id: \`${videoId}\`
Source: ${sourceUrl}

## Artifacts

- \`source/transcript.txt\` — cleaned timestamped transcript (\`[M:SS]\` paragraphs)
- \`key-frames/\` — curated visual frames (Phase 5+)
- \`recommendations/\` — synthesis notes (Phase 5+)

Bulk frames and source video stay in OS temp during the watch session; only curated \`key-frames/\` persist in the slice.
`;

  await writeFile(readmePath, readme, "utf8");

  return {
    transcriptPath,
    transcript: built.transcript,
    cueCount: built.cueCount,
    paragraphCount: built.paragraphCount,
    cleanedAutoCaptions: built.cleanedAutoCaptions,
  };
}
