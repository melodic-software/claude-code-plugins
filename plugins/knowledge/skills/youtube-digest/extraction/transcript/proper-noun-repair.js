/**
 * Proper-noun repair over platform-ASR captions (T5 posture (v), the
 * `captions+repair` strategy).
 *
 * Platform ASR corrupts exactly the proper nouns downstream research and
 * synthesis depend on ("Clawed code" for "Claude Code"); the post's own text
 * (yt-dlp `description` = the full post body) and its harvested links carry
 * the correctly-spelled forms because the author typed them. That per-post
 * vocabulary is the repair lexicon.
 *
 * The repair is deterministic and deliberately conservative: a run of cue
 * words is replaced only when it equals a lexicon term after normalization
 * (case/punctuation-insensitive — restores the author's casing), or when it
 * sits within a small length-scaled Damerau-Levenshtein distance of EXACTLY
 * one term (mishearing repair). Ambiguity or distance beyond the bound keeps
 * the ASR text.
 */

/** @import { HarvestedLink } from '../harvesting/models.js' */

/** Words never treated as proper-noun evidence on their own. */
const STOPWORDS = new Set([
  "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from", "has",
  "have", "he", "her", "his", "i", "if", "in", "is", "it", "its", "of", "on",
  "or", "our", "she", "so", "that", "the", "their", "them", "these", "they",
  "this", "to", "was", "we", "were", "what", "when", "where", "which", "who",
  "will", "with", "you", "your",
]);

/** Link path segments that carry no vocabulary. */
const LINK_SEGMENT_NOISE = new Set(["www", "index", "html", "status", "watch"]);

const TERM_MAX_LENGTH = 60;

/**
 * Lowercase and strip every non-alphanumeric character — the comparison key
 * under which "Claude Code", "claude-code", and "clawed code" become
 * comparable word-run keys.
 *
 * @param {string} text
 * @returns {string}
 */
function normalizeKey(text) {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, "");
}

/**
 * @param {string} token - raw whitespace-delimited token
 * @returns {string} token with surrounding punctuation stripped (internal
 *   `-_.@#&+` kept — they are part of handles, slugs, and version names)
 */
function stripEdgePunctuation(token) {
  return token.replace(/^[^A-Za-z0-9@#]+/, "").replace(/[^A-Za-z0-9+]+$/, "");
}

/**
 * @param {string} word
 * @returns {boolean} the word alone is proper-noun-shaped evidence
 */
function isProperNounShaped(word) {
  if (word.length < 2 || word.length > TERM_MAX_LENGTH) return false;
  if (word.startsWith("@") || word.startsWith("#")) return true;
  if (/[A-Za-z]/.test(word) && /\d/.test(word)) return true; // large-v3, GPT-5
  if (/^[A-Z]{2,}$/.test(word)) return true; // API, NPX
  if (/[a-z][A-Z]/.test(word)) return true; // CamelCase / mixed: GitHub, npX
  if (/^[A-Z][a-z'’-]+$/.test(word) && word.length >= 3) {
    return !STOPWORDS.has(word.toLowerCase());
  }
  return false;
}

/**
 * Build the repair lexicon from the post text and its harvested links.
 * Description terms win over link-derived terms on a key collision (the
 * author's casing beats a lowercased URL slug).
 *
 * @param {string} description - the post text (yt-dlp `description`)
 * @param {readonly HarvestedLink[]} [harvestedLinks]
 * @returns {string[]} lexicon terms, single words and multi-word phrases
 */
export function buildRepairLexicon(description, harvestedLinks = []) {
  /** @type {Map<string, string>} */
  const byKey = new Map();
  /** @param {string} term */
  const add = (term) => {
    const key = normalizeKey(term);
    if (key.length < 2 || term.length > TERM_MAX_LENGTH) return;
    if (!byKey.has(key)) byKey.set(key, term);
  };

  const tokens = (description ?? "")
    .split(/\s+/)
    .map(stripEdgePunctuation)
    .filter(Boolean);

  // Runs of consecutive capitalized words form phrases ("Claude Code") — the
  // multi-word shape single-token extraction misses. Phrases go in FIRST so
  // the author's spaced phrasing wins a key collision with a compacted form
  // of the same name (e.g. the "#ClaudeCode" hashtag).
  /** @type {string[]} */
  let run = [];
  const flushRun = () => {
    if (run.length >= 2) add(run.join(" "));
    run = [];
  };
  for (const token of tokens) {
    if (/^[A-Z][A-Za-z0-9'’.-]*$/.test(token) && !STOPWORDS.has(token.toLowerCase())) {
      run.push(token);
    } else {
      flushRun();
    }
  }
  flushRun();

  for (const token of tokens) {
    if (isProperNounShaped(token)) {
      add(token.replace(/^[@#]/, ""));
    }
  }

  for (const link of harvestedLinks) {
    /** @type {URL} */
    let parsed;
    try {
      parsed = new URL(link.url);
    } catch {
      continue;
    }
    const hostLabels = parsed.hostname.toLowerCase().split(".");
    for (const label of hostLabels.slice(0, -1)) {
      if (label.length >= 3 && !LINK_SEGMENT_NOISE.has(label)) add(label);
    }
    for (const rawSegment of parsed.pathname.split("/")) {
      let segment;
      try {
        segment = decodeURIComponent(rawSegment);
      } catch {
        segment = rawSegment;
      }
      if (
        segment.length >= 3 &&
        /^[A-Za-z0-9_.-]+$/.test(segment) &&
        !/^\d+$/.test(segment) &&
        !LINK_SEGMENT_NOISE.has(segment.toLowerCase())
      ) {
        add(segment);
      }
    }
  }

  return [...byKey.values()];
}

/**
 * Optimal-string-alignment (Damerau-Levenshtein with adjacent transposition)
 * distance — transpositions are the dominant ASR-mishearing edit shape
 * ("clawed"/"claude" is 2 with transposition, 3 without).
 *
 * @param {string} a
 * @param {string} b
 * @returns {number}
 */
export function osaDistance(a, b) {
  const rows = a.length + 1;
  const cols = b.length + 1;
  /** @type {number[][]} */
  const dp = Array.from({ length: rows }, () => new Array(cols).fill(0));
  for (let i = 0; i < rows; i += 1) dp[i][0] = i;
  for (let j = 0; j < cols; j += 1) dp[0][j] = j;
  for (let i = 1; i < rows; i += 1) {
    for (let j = 1; j < cols; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      dp[i][j] = Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        dp[i][j] = Math.min(dp[i][j], dp[i - 2][j - 2] + 1);
      }
    }
  }
  return dp[rows - 1][cols - 1];
}

/**
 * Length-scaled fuzzy-match bound. Short keys must match exactly — fuzzy
 * repair on short words is where false positives live.
 *
 * @param {number} keyLength - normalized key length
 * @returns {number}
 */
function fuzzyThreshold(keyLength) {
  if (keyLength < 5) return 0;
  if (keyLength <= 8) return 1;
  if (keyLength <= 12) return 2;
  return 3;
}

/**
 * @typedef {Object} LexiconEntry
 * @property {string} term - replacement text (author's spelling)
 * @property {string} key - normalized comparison key
 * @property {number} wordCount
 */

/**
 * @param {readonly string[]} lexicon
 * @returns {LexiconEntry[]}
 */
function compileLexicon(lexicon) {
  /** @type {LexiconEntry[]} */
  const entries = [];
  for (const term of lexicon) {
    const key = normalizeKey(term);
    if (key.length >= 2) {
      entries.push({ term, key, wordCount: term.split(/\s+/).length });
    }
  }
  return entries;
}

/**
 * @typedef {Object} RepairResult
 * @property {string} text
 * @property {number} replacementCount
 */

/**
 * Repair one text against a compiled lexicon.
 *
 * @param {string} text
 * @param {LexiconEntry[]} entries
 * @param {number} maxWordCount
 * @returns {RepairResult}
 */
function repairTextCompiled(text, entries, maxWordCount) {
  // Split preserving whitespace so reconstruction is byte-faithful outside
  // replaced spans.
  const parts = text.split(/(\s+)/);
  /** @type {number[]} */
  const wordIndexes = [];
  for (let i = 0; i < parts.length; i += 1) {
    if (parts[i] && !/^\s+$/.test(parts[i])) wordIndexes.push(i);
  }

  let replacementCount = 0;
  let wordPos = 0;
  while (wordPos < wordIndexes.length) {
    let advanced = false;
    for (let size = Math.min(maxWordCount, wordIndexes.length - wordPos); size >= 1; size -= 1) {
      const firstPart = wordIndexes[wordPos];
      const lastPart = wordIndexes[wordPos + size - 1];
      const windowText = parts.slice(firstPart, lastPart + 1).join("");
      const core = stripEdgePunctuation(windowText);
      if (!core) continue;
      const windowKey = normalizeKey(core);
      if (windowKey.length < 4) continue; // never fuzzy/case-rewrite tiny fragments

      /** @type {LexiconEntry|null} */
      let exact = null;
      /** @type {LexiconEntry[]} */
      const fuzzy = [];
      for (const entry of entries) {
        if (entry.key === windowKey) {
          exact = entry;
          break;
        }
        const bound = fuzzyThreshold(entry.key.length);
        if (
          bound > 0 &&
          Math.abs(entry.key.length - windowKey.length) <= bound &&
          osaDistance(entry.key, windowKey) <= bound
        ) {
          fuzzy.push(entry);
        }
      }
      const match = exact ?? (fuzzy.length === 1 ? fuzzy[0] : null);
      if (!match) continue;
      if (core === match.term) {
        // Already the author's spelling — consume the window unrepaired so an
        // inner word is not re-judged against a shorter term.
        wordPos += size;
        advanced = true;
        break;
      }

      const prefixEnd = windowText.indexOf(core);
      const prefix = windowText.slice(0, prefixEnd);
      const suffix = windowText.slice(prefixEnd + core.length);
      parts[firstPart] = `${prefix}${match.term}${suffix}`;
      for (let i = firstPart + 1; i <= lastPart; i += 1) parts[i] = "";
      replacementCount += 1;
      wordPos += size;
      advanced = true;
      break;
    }
    if (!advanced) wordPos += 1;
  }

  return { text: parts.join(""), replacementCount };
}

/**
 * Repair a single text against the lexicon.
 *
 * @param {string} text
 * @param {readonly string[]} lexicon
 * @returns {RepairResult}
 */
export function repairProperNouns(text, lexicon) {
  const entries = compileLexicon(lexicon);
  if (entries.length === 0) return { text, replacementCount: 0 };
  const maxWordCount = Math.max(...entries.map((entry) => entry.wordCount));
  return repairTextCompiled(text, entries, maxWordCount);
}

/**
 * Repair every cue's text; timestamps are untouched.
 *
 * @template {{ text: string }} T
 * @param {readonly T[]} cues
 * @param {readonly string[]} lexicon
 * @returns {{ cues: T[], replacementCount: number }}
 */
export function repairCues(cues, lexicon) {
  const entries = compileLexicon(lexicon);
  if (entries.length === 0) {
    return { cues: [...cues], replacementCount: 0 };
  }
  const maxWordCount = Math.max(...entries.map((entry) => entry.wordCount));
  let replacementCount = 0;
  const repaired = cues.map((cue) => {
    const result = repairTextCompiled(cue.text, entries, maxWordCount);
    replacementCount += result.replacementCount;
    return result.text === cue.text ? cue : { ...cue, text: result.text };
  });
  return { cues: repaired, replacementCount };
}
