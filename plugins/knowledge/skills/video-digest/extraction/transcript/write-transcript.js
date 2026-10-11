/**
 * Convert acquired captions (or the optional ASR rung's output) into cleaned
 * timestamped transcript.txt artifacts, per the resolved transcript strategy.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { cleanAutoCaptions } from "@melodic/video-digestion/transcript/auto-caption-clean";
import {
  cleanManualCaptions,
  stripCaptionHtmlEntities,
} from "@melodic/video-digestion/transcript/manual-caption-clean";
import { formatTimestamp, formatTranscript } from "@melodic/video-digestion/transcript/vtt-parser";

import { primaryEntry } from "../adapters/adapter-contract.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";
import { detectAsrCapability, runAsrTranscription } from "./asr-transcribe.js";
import { buildRepairLexicon, repairCues } from "./proper-noun-repair.js";
import { resolveTranscriptStrategy } from "./transcript-strategy.js";

/** @import { TranscriptStrategy } from '../adapters/adapter-contract.js' */
/** @import { HarvestedLink } from '../harvesting/models.js' */

/**
 * Paragraph count of a formatted transcript: {@link formatTranscript} joins
 * timestamped paragraphs with a blank line, and empty text has none. Shared by
 * the caption and ASR routes so the two cannot drift.
 *
 * @param {string} transcript
 * @returns {number}
 */
function countParagraphs(transcript) {
  return transcript ? transcript.split("\n\n").length : 0;
}

const BOUNDARY_REPEAT_MIN_WORDS = 3;
const BOUNDARY_CARRY_OVER_WORDS = 2;
const BOUNDARY_REPEAT_MAX_WORDS = 12;
const PARAGRAPH_STAMP = /^(\[[^\]]*\]\s*)([\s\S]*)$/;

/** @param {string} text */
function tokens(text) {
  return text.split(/\s+/).filter(Boolean);
}

/** @param {string} word */
function comparableWord(word) {
  return word.toLowerCase().replace(/[^\p{L}\p{N}']/gu, "");
}

/**
 * The lexical words of `text`: punctuation-only tokens such as `>>` are not
 * words, so they never count toward a run's length.
 *
 * @param {string} text
 */
function words(text) {
  return tokens(text).filter((token) => comparableWord(token) !== "");
}

/** @param {string[]} run */
function comparableRun(run) {
  return run.map(comparableWord).join(" ");
}

/**
 * True when a cue opening the paragraph stamped `stamp` carries `run` over
 * from the cue before it: the two cues overlap in time, or the opening cue
 * starts with the previous cue's closing words verbatim (a rolling caption).
 *
 * @param {string} stamp - the paragraph's `[M:SS]`
 * @param {string[]} run - the paragraph's leading words
 * @param {readonly { startSec: number, endSec: number, text: string }[]} cues
 */
function carriesOverFromPreviousCue(stamp, run, cues) {
  const head = run.join(" ");
  for (let index = 1; index < cues.length; index++) {
    const cue = cues[index];
    if (`[${formatTimestamp(cue.startSec)}]` !== stamp) continue;
    const previous = cues[index - 1];
    const cueWords = words(cue.text);
    if (cueWords.slice(0, run.length).join(" ") !== head) continue;
    if (previous.endSec > cue.startSec) return true;
    if (words(previous.text).slice(-run.length).join(" ") === head) return true;
  }
  return false;
}

/**
 * Drop the words a paragraph opens with when they repeat the previous
 * paragraph's closing words, the longest run first: 3 to 12 words compared
 * case- and punctuation-insensitively, or 2 words when the opening cue carries
 * them over from the cue before it ({@link carriesOverFromPreviousCue}). A
 * rolling auto caption carries its tail into the next cue, and the vendor
 * formatter only drops overlaps of 3 or more words it matches ignoring case
 * alone. A two-word repeat the speaker actually said ("very good." / "Very
 * good question") stays. A paragraph always keeps at least one word.
 *
 * @param {string} transcript - paragraphs joined by a blank line, each `[M:SS] text`
 * @param {readonly { startSec: number, endSec: number, text: string }[]} cues - the
 *   cues the transcript was formatted from
 * @returns {string}
 */
export function dropParagraphBoundaryRepeats(transcript, cues) {
  const paragraphs = transcript.split("\n\n");
  for (let index = 1; index < paragraphs.length; index++) {
    const current = PARAGRAPH_STAMP.exec(paragraphs[index]);
    const previous = PARAGRAPH_STAMP.exec(paragraphs[index - 1]);
    if (!current || !previous) continue;
    const previousWords = words(previous[2]);
    const currentTokens = tokens(current[2]);
    const wordAt = currentTokens.flatMap((token, at) => (comparableWord(token) ? [at] : []));
    const currentWords = wordAt.map((at) => currentTokens[at]);
    const longest = Math.min(
      BOUNDARY_REPEAT_MAX_WORDS,
      previousWords.length,
      currentWords.length - 1,
    );
    for (let length = longest; length >= BOUNDARY_CARRY_OVER_WORDS; length--) {
      const run = currentWords.slice(0, length);
      if (comparableRun(previousWords.slice(-length)) !== comparableRun(run)) continue;
      if (
        length < BOUNDARY_REPEAT_MIN_WORDS &&
        !carriesOverFromPreviousCue(current[1].trim(), run, cues)
      ) {
        continue;
      }
      // Keep punctuation-only tokens before the dropped words (a `>>` speaker
      // marker); drop any between them.
      const kept = [
        ...currentTokens.slice(0, wordAt[0]),
        ...currentTokens.slice(wordAt[length - 1] + 1),
      ];
      paragraphs[index] = current[1] + kept.join(" ");
      break;
    }
  }
  return paragraphs.join("\n\n");
}

/**
 * Build transcript text from a caption file.
 *
 * @param {string} vttText
 * @param {boolean} isAutoCaption
 * @param {{ repairLexicon?: readonly string[] | null }} [options] - a non-empty
 *   `repairLexicon` applies proper-noun repair over the cleaned cues (the
 *   `captions+repair` strategy)
 * @returns {{ transcript: string, cueCount: number, paragraphCount: number, cleanedAutoCaptions: boolean, cleanedManualCaptions: boolean, repairedTermCount: number }}
 */
export function buildTranscriptText(vttText, isAutoCaption, { repairLexicon = null } = {}) {
  let cleanedManualCaptions = false;
  let cues;

  if (isAutoCaption) {
    // Decode after parsing: the cleaner's VTT output must keep `&lt;` escaped.
    cues = cleanAutoCaptions(vttText)
      .cues.map((cue) => ({ ...cue, text: stripCaptionHtmlEntities(cue.text) }))
      .filter((cue) => cue.text.length > 0);
  } else {
    const cleaned = cleanManualCaptions(vttText);
    cues = cleaned.cues;
    cleanedManualCaptions = cleaned.cleanedManualCaptions;
  }

  let repairedTermCount = 0;
  if (repairLexicon && repairLexicon.length > 0) {
    const repaired = repairCues(cues, repairLexicon);
    cues = repaired.cues;
    repairedTermCount = repaired.replacementCount;
  }

  const formatted = formatTranscript(cues);
  const transcript = isAutoCaption ? dropParagraphBoundaryRepeats(formatted, cues) : formatted;

  return {
    transcript,
    cueCount: cues.length,
    paragraphCount: countParagraphs(transcript),
    cleanedAutoCaptions: isAutoCaption,
    cleanedManualCaptions,
    repairedTermCount,
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
 * @property {TranscriptStrategy} strategy - the strategy that produced this transcript
 * @property {number} repairedTermCount - proper-noun repairs applied (`captions+repair`)
 */

/**
 * @typedef {Object} EnvelopeEntryDegradation
 * @property {number} entryIndex
 * @property {string} reason
 */

/**
 * @typedef {Object} EnvelopeTranscriptsResult
 * @property {number} entryCount - envelope arity (0..N)
 * @property {number} primaryEntryIndex - index of the primary entry (-1 for a 0-entry envelope)
 * @property {EnvelopeTranscriptEntry[]} transcripts - one row per transcript-bearing entry
 * @property {number} captionlessEntryCount - entries that carried no selected caption
 * @property {string|null} transcriptDegradation - NAMED provenance field (T5):
 *   the primary entry's transcript-strategy degradation reason (first degraded
 *   entry when the primary is clean), else the primary caption's
 *   `provenanceNote`; null when nothing degraded. Set whenever a transcript
 *   could not be produced the way the strategy wanted, never a silent skip.
 * @property {EnvelopeEntryDegradation[]} entryDegradations - every per-entry degradation
 */

/**
 * Consume an acquisition envelope into slice transcript artifacts. Handles all
 * arities: 0 entries writes the README only (a well-formed metadata-only
 * slice), 1 entry matches the historical single-transcript layout, N entries
 * write one transcript per transcript-bearing entry with the PRIMARY entry
 * owning `transcript.txt` ({@link transcriptFilename}).
 *
 * Per entry, the transcript strategy resolves from the adapter default and the
 * explicit pipeline override ({@link resolveTranscriptStrategy}): captions are
 * consumed as before, `captions+repair` layers proper-noun repair (lexicon =
 * post text + harvested links), and the `asr` rung runs the optional local
 * toolchain — detected at runtime, never auto-installed. A degraded entry
 * (no transcript producible) is recorded in `transcriptDegradation`.
 *
 * @param {object} options
 * @param {string} options.sliceDir
 * @param {import('../adapters/adapter-contract.js').AcquisitionEnvelope} options.envelope
 * @param {string} options.sourceUrl
 * @param {string} options.sliceKey - the URL-authoritative slice key (also the
 *   README's recorded video id, so the README matches the slice directory even
 *   when the source metadata id diverges from the URL)
 * @param {TranscriptStrategy} [options.transcriptStrategy] - the adapter's
 *   declared per-source default (defaults to `captions`, the historical behavior)
 * @param {TranscriptStrategy|null} [options.strategyOverride] - explicit
 *   pipeline override; wins over the adapter default
 * @param {readonly HarvestedLink[]} [options.harvestedLinks] - harvested links
 *   feeding the proper-noun repair lexicon
 * @param {object} [io]
 * @param {typeof fs.readFile} [io.readFile]
 * @param {typeof fs.writeFile} [io.writeFile]
 * @param {typeof fs.mkdir} [io.mkdir]
 * @param {typeof detectAsrCapability} [io.detectAsr]
 * @param {typeof runAsrTranscription} [io.runAsr]
 * @returns {Promise<EnvelopeTranscriptsResult>}
 */
// biome-ignore lint/complexity/noExcessiveCognitiveComplexity: single walk over the envelope's strategy arities; splitting would scatter the seam
export async function writeEnvelopeTranscriptArtifacts(
  {
    sliceDir,
    envelope,
    sourceUrl,
    sliceKey,
    transcriptStrategy = "captions",
    strategyOverride = null,
    harvestedLinks = [],
  },
  {
    readFile = fs.readFile,
    writeFile = fs.writeFile,
    mkdir = fs.mkdir,
    detectAsr = detectAsrCapability,
    runAsr = runAsrTranscription,
  } = {},
) {
  const { metadata, entries } = envelope;
  const primary = primaryEntry(envelope);
  const primaryEntryIndex = primary ? entries.indexOf(primary) : -1;

  await mkdir(sliceDir, { recursive: true });
  await writeSliceReadme(
    { sliceDir, videoTitle: metadata.title, videoId: sliceKey, sourceUrl },
    { writeFile },
  );

  // The ASR toolchain probe spawns interpreters — run it only when some entry
  // could actually take the ASR rung (caption-less media, or an explicit
  // asr request).
  const requested = strategyOverride ?? transcriptStrategy;
  const needAsrProbe =
    requested === "asr" || entries.some((entry) => !entry.caption && entry.mediaPath);
  const asrDetection = needAsrProbe ? await detectAsr() : null;

  // The adapter default can also resolve as the asr-unavailable fallback, so
  // the lexicon is built whenever either route can reach `captions+repair`.
  const repairLexicon =
    requested === "captions+repair" || transcriptStrategy === "captions+repair"
      ? buildRepairLexicon(metadata.description, harvestedLinks)
      : null;

  /** @type {EnvelopeTranscriptEntry[]} */
  const transcripts = [];
  /** @type {EnvelopeEntryDegradation[]} */
  const entryDegradations = [];
  let captionlessEntryCount = 0;

  for (const [entryIndex, entry] of entries.entries()) {
    if (!entry.caption) {
      captionlessEntryCount += 1;
    }
    const plan = resolveTranscriptStrategy({
      adapterDefault: transcriptStrategy,
      override: strategyOverride,
      captionPresent: Boolean(entry.caption),
      mediaAvailable: Boolean(entry.mediaPath),
      asrAvailable: Boolean(asrDetection?.available),
    });
    if (plan.degradation) {
      entryDegradations.push({ entryIndex, reason: plan.degradation });
    }
    if (!plan.strategy) {
      continue;
    }

    /** @type {{ transcript: string, cueCount: number, paragraphCount: number, cleanedAutoCaptions: boolean, repairedTermCount: number }} */
    let built;
    if (plan.strategy === "asr") {
      const asr = await runAsr({
        mediaPath: entry.mediaPath,
        python: /** @type {string} */ (asrDetection?.python),
      });
      if (!asr.success || !asr.cues) {
        // An ASR failure degrades the entry explicitly rather than failing the
        // digest — same posture as capability absence, never silent.
        entryDegradations.push({
          entryIndex,
          reason: asr.error ?? "ASR transcription failed",
        });
        continue;
      }
      const transcript = formatTranscript(asr.cues);
      built = {
        transcript,
        cueCount: asr.cues.length,
        paragraphCount: countParagraphs(transcript),
        cleanedAutoCaptions: false,
        repairedTermCount: 0,
      };
    } else {
      const caption = /** @type {NonNullable<typeof entry.caption>} */ (entry.caption);
      const vttText = String(await readFile(caption.path, "utf8"));
      built = buildTranscriptText(vttText, caption.isAutoCaption, {
        repairLexicon: plan.strategy === "captions+repair" ? repairLexicon : null,
      });
    }

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
      strategy: plan.strategy,
      repairedTermCount: built.repairedTermCount,
    });
  }

  const primaryDegradation =
    entryDegradations.find((entry) => entry.entryIndex === primaryEntryIndex) ??
    entryDegradations[0] ??
    null;

  return {
    entryCount: entries.length,
    primaryEntryIndex,
    transcripts,
    captionlessEntryCount,
    transcriptDegradation: primaryDegradation?.reason ?? primary?.caption?.provenanceNote ?? null,
    entryDegradations,
  };
}
