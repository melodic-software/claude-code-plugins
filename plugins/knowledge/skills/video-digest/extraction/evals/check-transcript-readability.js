#!/usr/bin/env node
/**
 * Host verify script: transcript readability — size and repetition guards.
 *
 * Usage: node evals/check-transcript-readability.js <transcript.txt> [--max-bytes N]
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr } from "@melodic/video-digestion/shared/terminal";

const DEFAULT_MAX_BYTES = 25_600;
const MIN_PHRASE_WORDS = 4;
const MAX_CONSECUTIVE_PHRASE_REPEATS = 2;

const WORD_SPLIT = /\s+/;
const SPEAKER_PREFIX_RE = /^\[[^\]]+\]\s*/;

/**
 * @param {string} paragraph
 * @returns {number}
 */
export function maxConsecutivePhraseRepeats(paragraph) {
  const words = paragraph.split(WORD_SPLIT).filter(Boolean);
  if (words.length < MIN_PHRASE_WORDS * 2) return 0;

  let maxRepeats = 0;
  for (
    let phraseLen = MIN_PHRASE_WORDS;
    phraseLen <= Math.min(12, Math.floor(words.length / 2));
    phraseLen++
  ) {
    for (let start = 0; start + phraseLen <= words.length; start++) {
      const phrase = words.slice(start, start + phraseLen).join(" ");
      let repeats = 1;
      let offset = start + phraseLen;
      while (offset + phraseLen <= words.length) {
        const next = words.slice(offset, offset + phraseLen).join(" ");
        if (next !== phrase) break;
        repeats++;
        offset += phraseLen;
      }
      if (repeats > maxRepeats) maxRepeats = repeats;
    }
  }
  return maxRepeats;
}

/**
 * @param {string} transcript
 * @returns {{ maxRepeats: number, paragraphCount: number }}
 */
export function analyzeTranscriptReadability(transcript) {
  const paragraphs = transcript
    .split("\n\n")
    .map((block) => block.replace(SPEAKER_PREFIX_RE, "").trim())
    .filter(Boolean);

  let maxRepeats = 0;
  for (const paragraph of paragraphs) {
    maxRepeats = Math.max(maxRepeats, maxConsecutivePhraseRepeats(paragraph));
  }

  return { maxRepeats, paragraphCount: paragraphs.length };
}

/**
 * @param {string} transcriptPath
 * @param {object} [options]
 * @param {number} [options.maxBytes]
 * @returns {number}
 */
export function checkTranscriptReadability(transcriptPath, { maxBytes = DEFAULT_MAX_BYTES } = {}) {
  const transcript = fs.readFileSync(transcriptPath, "utf8");
  const byteLength = Buffer.byteLength(transcript, "utf8");

  if (byteLength > maxBytes) {
    writeStderr(`FAIL: transcript ${byteLength} bytes exceeds max ${maxBytes}`);
    return 1;
  }

  const { maxRepeats } = analyzeTranscriptReadability(transcript);
  if (maxRepeats > MAX_CONSECUTIVE_PHRASE_REPEATS) {
    writeStderr(
      `FAIL: paragraph has ${maxRepeats} consecutive identical ${MIN_PHRASE_WORDS}+-word phrases (max ${MAX_CONSECUTIVE_PHRASE_REPEATS})`,
    );
    return 1;
  }

  return 0;
}

const scriptPath = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
  const transcriptPath = process.argv[2];
  let maxBytes = DEFAULT_MAX_BYTES;
  const maxIdx = process.argv.indexOf("--max-bytes");
  if (maxIdx !== -1 && process.argv[maxIdx + 1]) {
    maxBytes = Number.parseInt(process.argv[maxIdx + 1], 10);
  }

  if (!transcriptPath) {
    writeStderr(
      "Usage: node evals/check-transcript-readability.js <transcript.txt> [--max-bytes N]\n",
    );
    process.exit(2);
  }

  process.exit(checkTranscriptReadability(transcriptPath, { maxBytes }));
}
