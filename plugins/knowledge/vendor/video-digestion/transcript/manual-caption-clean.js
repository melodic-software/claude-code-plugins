/**
 * YouTube manual-caption cleaning — progressive merge + rolling duplicate collapse.
 */

import {
  mergeProgressiveCaptionCues,
  shouldCleanProgressiveCaptions,
} from "./progressive-cue-merge.js";
import { deduplicateCues, parseVttSegment } from "./vtt-parser.js";

/** @typedef {import('./vtt-parser.js').VttCue} VttCue */

const WHITESPACE_RUN = /\s+/g;
const HTML_ENTITY = /&(?:nbsp|amp|lt|gt|quot|#39);/gi;

/**
 * @param {string} text
 * @returns {string}
 */
export function stripCaptionHtmlEntities(text) {
  return text
    .replaceAll("&nbsp;", " ")
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replace(HTML_ENTITY, " ")
    .replace(WHITESPACE_RUN, " ")
    .trim();
}

/**
 * @param {string} text
 * @returns {string}
 */
export function collapseConsecutiveDuplicateWords(text) {
  const words = text.split(WHITESPACE_RUN).filter(Boolean);
  if (words.length === 0) return "";

  /** @type {string[]} */
  const collapsed = [];
  for (const word of words) {
    if (collapsed.length === 0 || collapsed[collapsed.length - 1] !== word) {
      collapsed.push(word);
    }
  }
  return collapsed.join(" ");
}

/**
 * @param {string} text
 * @returns {string}
 */
export function collapseRollingDuplicatePhrases(text) {
  const normalized = collapseConsecutiveDuplicateWords(stripCaptionHtmlEntities(text));
  if (!normalized) return "";

  const words = normalized.split(" ");
  if (words.length < 6) return normalized;

  for (let phraseLen = Math.min(12, Math.floor(words.length / 2)); phraseLen >= 3; phraseLen--) {
    for (let start = 0; start + phraseLen * 2 <= words.length; start++) {
      const first = words.slice(start, start + phraseLen).join(" ");
      const second = words.slice(start + phraseLen, start + phraseLen * 2).join(" ");
      if (first === second) {
        const collapsed = [
          ...words.slice(0, start + phraseLen),
          ...words.slice(start + phraseLen * 2),
        ];
        return collapseRollingDuplicatePhrases(collapsed.join(" "));
      }
    }
  }

  return normalized;
}

/**
 * @param {VttCue[]} cues
 * @returns {VttCue[]}
 */
function applyPhraseCollapse(cues) {
  return cues.map((cue) => ({
    ...cue,
    text: collapseRollingDuplicatePhrases(cue.text),
  }));
}

/**
 * @param {string} vttText
 * @returns {{ cues: VttCue[], cleanedManualCaptions: boolean, progressiveMergeApplied: boolean }}
 */
export function cleanManualCaptions(vttText) {
  const inputCues = parseVttSegment(vttText);
  const progressiveMergeApplied = shouldCleanProgressiveCaptions(vttText);
  const merged = progressiveMergeApplied ? mergeProgressiveCaptionCues(inputCues) : inputCues;

  const collapsed = applyPhraseCollapse(merged);
  const cues = deduplicateCues(collapsed.filter((cue) => cue.text.length > 0));

  return {
    cues,
    cleanedManualCaptions: true,
    progressiveMergeApplied,
  };
}

export { shouldCleanProgressiveCaptions as shouldCleanManualCaptions };
