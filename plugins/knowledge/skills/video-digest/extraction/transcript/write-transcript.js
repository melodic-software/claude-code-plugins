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
import {
  formatTimestamp,
  formatTranscript,
  parseVttSegment,
} from "@melodic/video-digestion/transcript/vtt-parser";

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

/** @typedef {{ startSec: number, endSec: number, text: string }} WatchCue */

/**
 * @param {{ startSec: number, endSec: number, text: string }} cue
 * @returns {WatchCue}
 */
function toWatchCue(cue) {
  return { startSec: cue.startSec, endSec: cue.endSec, text: cue.text };
}

const BOUNDARY_REPEAT_MIN_WORDS = 2;
const BOUNDARY_REPEAT_MAX_WORDS = 12;
const PARAGRAPH_STAMP = /^(\[[^\]]*\]\s*)([\s\S]*)$/;

/** @param {string} text */
function tokens(text) {
  return text.split(/\s+/).filter(Boolean);
}

/** @param {string} word */
function comparableWord(word) {
  // Apostrophes in any form (', ’, ʼ) drop out, so don't, don’t and dont match.
  // Only sentence punctuation at either end goes, so C++. and C# stay distinct.
  const plain = word.toLowerCase().replace(/['\u2019\u02BC]/g, "");
  let start = 0;
  let end = plain.length;
  while (start < end && EDGE_PUNCTUATION.has(plain[start])) start++;
  while (end > start && EDGE_PUNCTUATION.has(plain[end - 1])) end--;
  return plain.slice(start, end);
}

/**
 * Sentence punctuation (quotes, brackets, ellipses) trimmed from a word's ends
 * by a scan rather than a regex, so a long punctuation run costs linear time.
 * Hyphens and dashes stay, so C-- and C never compare equal.
 */
const EDGE_PUNCTUATION = new Set('.,;:!?"\u2018\u201a\u201c\u201d\u201e\u2039\u203a\u00ab\u00bb()[]{}\u2026');

/**
 * The lexical words of `text`: punctuation-only tokens such as `>>` are not
 * words, so they never count toward a run's length.
 *
 * @param {string} text
 */
function words(text) {
  return tokens(text).filter(isWord);
}

/** @param {string} token - a word holds at least one letter or digit */
function isWord(token) {
  return /[\p{L}\p{N}]/u.test(token);
}

/** @param {string[]} run */
function comparableRun(run) {
  return run.map(comparableWord).join(" ");
}

/**
 * True when the cue opening the paragraph stamped `stamp` carries `run` over
 * from the cue before it: the two cues overlap in time, or the opening cue
 * starts with the previous cue's closing words verbatim (a rolling caption).
 * False whenever the opening cue cannot be identified exactly.
 *
 * @param {string} stamp - the paragraph's `[M:SS]`
 * @param {string[]} run - the paragraph's leading words
 * @param {readonly { startSec: number, endSec: number, text: string }[]} cues
 */
function carriesOverFromPreviousCue(stamp, run, cues) {
  // The paragraph stamp floors the opening cue's start to the second, so it
  // identifies the opener only when exactly one cue starts in that second.
  // With several, the evidence is ambiguous and the words stay.
  const openers = cues.flatMap((cue, at) =>
    `[${formatTimestamp(cue.startSec)}]` === stamp ? [at] : [],
  );
  if (openers.length !== 1 || openers[0] === 0) return false;
  const cue = cues[openers[0]];
  const previous = cues[openers[0] - 1];
  const head = run.join(" ");
  if (words(cue.text).slice(0, run.length).join(" ") !== head) return false;
  return (
    previous.endSec > cue.startSec || words(previous.text).slice(-run.length).join(" ") === head
  );
}

/**
 * Drop the words a paragraph opens with when they repeat the previous
 * paragraph's closing words, the longest run first: 2 to 12 words compared
 * case- and punctuation-insensitively, and only when the opening cue carries
 * them over from the cue before it ({@link carriesOverFromPreviousCue}). A
 * rolling auto caption carries its tail into the next cue, and the vendor
 * formatter only drops overlaps of 3 or more words it matches ignoring case
 * alone. A repeat the speaker actually said ("very good." / "Very good
 * question", "I don't know." / "I don't know why.") stays. A paragraph always
 * keeps at least one word.
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
    const wordAt = currentTokens.flatMap((token, at) => (isWord(token) ? [at] : []));
    const currentWords = wordAt.map((at) => currentTokens[at]);
    const longest = Math.min(
      BOUNDARY_REPEAT_MAX_WORDS,
      previousWords.length,
      currentWords.length - 1,
    );
    for (let length = longest; length >= BOUNDARY_REPEAT_MIN_WORDS; length--) {
      const run = currentWords.slice(0, length);
      if (comparableRun(previousWords.slice(-length)) !== comparableRun(run)) continue;
      // Every match, whatever its length, needs cue-level carry-over evidence:
      // a speaker may genuinely repeat several words ("I don't know." / "I
      // don't know why.").
      if (!carriesOverFromPreviousCue(current[1].trim(), run, cues)) continue;
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
 * Write the slice README. The artifact list names the transcript files that
 * were written; a post with no video entries says so instead of listing a
 * transcript that does not exist.
 *
 * @param {object} options
 * @param {string} options.sliceDir
 * @param {string} options.videoTitle
 * @param {string} options.videoId
 * @param {string} options.sourceUrl
 * @param {readonly string[]} [options.transcriptFiles] - slice-relative
 *   transcript paths actually written (default: the primary `source/transcript.txt`)
 * @param {boolean} [options.noVideoEntries] - the acquisition produced 0 entries
 * @param {{ writeFile?: typeof fs.writeFile }} [io]
 * @returns {Promise<string>} the README path
 */
export async function writeSliceReadme(
  {
    sliceDir,
    videoTitle,
    videoId,
    sourceUrl,
    transcriptFiles = ["source/transcript.txt"],
    noVideoEntries = false,
  },
  { writeFile = fs.writeFile } = {},
) {
  let transcriptLines = transcriptFiles
    .map((file) => `- \`${file}\` — cleaned timestamped transcript (\`[M:SS]\` paragraphs)\n`)
    .join("");
  if (noVideoEntries) {
    transcriptLines = "- No video entries were found in this post, so no transcript was written\n";
  } else if (transcriptFiles.length === 0) {
    transcriptLines = "- No transcript was written (see the run's transcript degradation)\n";
  }
  const readmePath = path.join(sliceDir, "README.md");
  const readme = `# ${videoTitle}

Video id: \`${videoId}\`
Source: ${sourceUrl}

## Artifacts

${transcriptLines}- \`key-frames/\` — curated visual frames (Phase 5+)
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
 * @property {WatchCue[]} cues - the cues the transcript was built from (parsed
 *   caption cues, or the ASR cues), the input to watching's frame densification
 * @property {number} cueCount
 * @property {number} paragraphCount
 * @property {boolean} cleanedAutoCaptions
 * @property {TranscriptStrategy} strategy - the strategy that produced this transcript
 * @property {number} repairedTermCount - proper-noun repairs applied (`captions+repair` and `asr`)
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
 * title + post text + harvested links), and the `asr` rung runs the optional
 * local toolchain, its cues repaired with the same lexicon — detected at
 * runtime, never auto-installed. A degraded entry
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

  // The ASR toolchain probe spawns interpreters — run it only when some entry
  // could actually take the ASR rung (caption-less media, or an explicit
  // asr request).
  const requested = strategyOverride ?? transcriptStrategy;
  const needAsrProbe =
    requested === "asr" || entries.some((entry) => !entry.caption && entry.mediaPath);
  const asrDetection = needAsrProbe ? await detectAsr() : null;

  // Every strategy gets the lexicon, repair-only: captions+repair and ASR cues
  // are repaired against it. It is never fed to ASR as an initial prompt (the
  // probe in reference/sources/x.md showed no gain and a worse hallucination).
  const repairLexicon = buildRepairLexicon(metadata.description, harvestedLinks, metadata.title);

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

    /** @type {{ transcript: string, sourceCues: WatchCue[], cueCount: number, paragraphCount: number, cleanedAutoCaptions: boolean, repairedTermCount: number }} */
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
      const repaired = repairCues(asr.cues, repairLexicon);
      const transcript = formatTranscript(repaired.cues);
      built = {
        transcript,
        sourceCues: asr.cues.map(toWatchCue),
        cueCount: repaired.cues.length,
        paragraphCount: countParagraphs(transcript),
        cleanedAutoCaptions: false,
        repairedTermCount: repaired.replacementCount,
      };
    } else {
      const caption = /** @type {NonNullable<typeof entry.caption>} */ (entry.caption);
      const vttText = String(await readFile(caption.path, "utf8"));
      built = {
        ...buildTranscriptText(vttText, caption.isAutoCaption, {
          repairLexicon: plan.strategy === "captions+repair" ? repairLexicon : null,
        }),
        // The raw parsed caption cues, as watching always received them.
        sourceCues: parseVttSegment(vttText).map(toWatchCue),
      };
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
      cues: built.sourceCues,
      cueCount: built.cueCount,
      paragraphCount: built.paragraphCount,
      cleanedAutoCaptions: built.cleanedAutoCaptions,
      strategy: plan.strategy,
      repairedTermCount: built.repairedTermCount,
    });
  }

  // Written last so the Artifacts list names only transcripts that exist.
  await writeSliceReadme(
    {
      sliceDir,
      videoTitle: metadata.title,
      videoId: sliceKey,
      sourceUrl,
      transcriptFiles: transcripts.map((entry) =>
        path.relative(sliceDir, entry.transcriptPath).split(path.sep).join("/"),
      ),
      noVideoEntries: entries.length === 0,
    },
    { writeFile },
  );

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
