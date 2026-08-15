/**
 * Convert selected caption VTT into cleaned timestamped transcript.txt.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { cleanAutoCaptions } from "@melodic/video-digestion/transcript/auto-caption-clean";
import { cleanManualCaptions } from "@melodic/video-digestion/transcript/manual-caption-clean";
import { formatTranscript } from "@melodic/video-digestion/transcript/vtt-parser";

import { primaryEntry } from "../adapters/adapter-contract.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";

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
 * Write the slice README (safe for metadata-only slices — the artifact list
 * documents the standard layout, present or pending).
 *
 * @param {object} options
 * @param {string} options.sliceDir
 * @param {string} options.videoTitle
 * @param {string} options.videoId
 * @param {string} options.sourceUrl
 * @param {{ writeFile?: typeof fs.writeFile }} [io]
 * @returns {Promise<string>} the README path
 */
export async function writeSliceReadme(
  { sliceDir, videoTitle, videoId, sourceUrl },
  { writeFile = fs.writeFile } = {},
) {
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
  return readmePath;
}

/**
 * Slice-relative transcript filename for an envelope entry. The PRIMARY entry
 * (the one watch orchestration covers — {@link primaryEntry}) keeps the
 * historical `transcript.txt` name every downstream consumer assumes is THE
 * transcript; other entries are suffixed with their 1-based envelope position
 * (`transcript-2.txt`, …).
 *
 * @param {number} entryIndex
 * @param {number} primaryEntryIndex
 * @returns {string}
 */
export function transcriptFilename(entryIndex, primaryEntryIndex) {
  return entryIndex === primaryEntryIndex ? "transcript.txt" : `transcript-${entryIndex + 1}.txt`;
}

/**
 * @typedef {Object} EnvelopeTranscriptEntry
 * @property {number} entryIndex
 * @property {string} transcriptPath
 * @property {number} cueCount
 * @property {number} paragraphCount
 * @property {boolean} cleanedAutoCaptions
 */

/**
 * @typedef {Object} EnvelopeTranscriptsResult
 * @property {number} entryCount - envelope arity (0..N)
 * @property {number} primaryEntryIndex - index of the primary entry (-1 for a 0-entry envelope)
 * @property {EnvelopeTranscriptEntry[]} transcripts - one row per caption-bearing entry
 * @property {number} captionlessEntryCount - entries that carried no selected caption
 */

/**
 * Consume an acquisition envelope into slice transcript artifacts. Handles all
 * arities: 0 entries writes the README only (a well-formed metadata-only
 * slice), 1 entry matches the historical single-transcript layout, N entries
 * write one transcript per caption-bearing entry with the PRIMARY entry owning
 * `transcript.txt` ({@link transcriptFilename}).
 *
 * @param {object} options
 * @param {string} options.sliceDir
 * @param {import('../adapters/adapter-contract.js').AcquisitionEnvelope} options.envelope
 * @param {string} options.sourceUrl
 * @param {string} options.sliceKey - the URL-authoritative slice key (also the
 *   README's recorded video id, so the README matches the slice directory even
 *   when the source metadata id diverges from the URL)
 * @param {object} [io]
 * @param {typeof fs.readFile} [io.readFile]
 * @param {typeof fs.writeFile} [io.writeFile]
 * @param {typeof fs.mkdir} [io.mkdir]
 * @returns {Promise<EnvelopeTranscriptsResult>}
 */
export async function writeEnvelopeTranscriptArtifacts(
  { sliceDir, envelope, sourceUrl, sliceKey },
  { readFile = fs.readFile, writeFile = fs.writeFile, mkdir = fs.mkdir } = {},
) {
  const { metadata, entries } = envelope;
  const primary = primaryEntry(envelope);
  const primaryEntryIndex = primary ? entries.indexOf(primary) : -1;

  await mkdir(sliceDir, { recursive: true });
  await writeSliceReadme(
    { sliceDir, videoTitle: metadata.title, videoId: sliceKey, sourceUrl },
    { writeFile },
  );

  /** @type {EnvelopeTranscriptEntry[]} */
  const transcripts = [];
  let captionlessEntryCount = 0;

  for (const [entryIndex, entry] of entries.entries()) {
    if (!entry.caption) {
      captionlessEntryCount += 1;
      continue;
    }
    const vttText = String(await readFile(entry.caption.path, "utf8"));
    const built = buildTranscriptText(vttText, entry.caption.isAutoCaption);
    await mkdir(lanePath(sliceDir, LANES.source), { recursive: true });
    const transcriptPath = lanePath(
      sliceDir,
      LANES.source,
      transcriptFilename(entryIndex, primaryEntryIndex),
    );
    await writeFile(transcriptPath, `${built.transcript}\n`, "utf8");
    transcripts.push({
      entryIndex,
      transcriptPath,
      cueCount: built.cueCount,
      paragraphCount: built.paragraphCount,
      cleanedAutoCaptions: built.cleanedAutoCaptions,
    });
  }

  return { entryCount: entries.length, primaryEntryIndex, transcripts, captionlessEntryCount };
}
