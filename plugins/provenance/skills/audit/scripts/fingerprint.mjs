#!/usr/bin/env node
// Reasoning-free fingerprint compare of two concrete texts.
//
// This module never decides whether a passage is a copy. It reports lexical
// overlap between a local passage and an already-fetched source, and the audit
// flow maps that evidence to a tier. Nothing here reads config files, fetches
// anything, or judges attribution.
//
// Two behaviors are contract, not implementation detail (spike S2):
//
//   1. Quotation and fence stripping runs INSIDE this module, over the LOCAL
//      text, before shingling, and covers inline quotation marks as well as
//      blockquotes and code fences. A properly quoted and cited excerpt must
//      not read as a copy, and a rubric-layer carve-out would arrive too late.
//   2. Verdicts are matched SPANS with local line offsets. Whole-file
//      containment dilutes a real 27-word match to noise on a real-sized file,
//      so the separation rule fires on either measure and the spans are what
//      the fix step edits against.
//
// Contract: docs/topics/copied-external-content/design/type-inventory.md.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/** Defaults the audit flow overrides from the consuming repo's config. */
export const DEFAULTS = Object.freeze({
  k: 5,
  min_containment: 0.3,
  min_span_words: 15,
});

const OPENING_TO_CLOSING = new Map([
  ['"', '"'],
  ["“", "”"],
  ["'", "'"],
  ["‘", "’"],
]);

/**
 * Remove quoted spans from a text: fenced blocks, blockquote lines, and inline
 * quotations. An unpaired opening mark is left alone rather than swallowing the
 * remainder of the line.
 */
export function stripQuoted(text) {
  const lines = String(text).split("\n");
  const out = [];
  let inFence = false;

  for (const line of lines) {
    if (/^\s*(```|~~~)/.test(line)) {
      inFence = !inFence;
      out.push("");
      continue;
    }
    if (inFence || /^\s*>/.test(line)) {
      out.push("");
      continue;
    }
    out.push(stripInlineQuotes(line));
  }

  return out.join("\n");
}

function stripInlineQuotes(line) {
  let result = "";
  let i = 0;

  while (i < line.length) {
    const char = line[i];
    const closing = OPENING_TO_CLOSING.get(char);

    if (closing === undefined) {
      result += char;
      i += 1;
      continue;
    }

    // An apostrophe inside a word (don't, teams') is not a quotation mark.
    if ((char === "'" || char === "‘") && /\w/.test(line[i - 1] ?? "")) {
      result += char;
      i += 1;
      continue;
    }

    const end = line.indexOf(closing, i + 1);
    if (end === -1) {
      // Unpaired: keep the mark and the rest of the line.
      result += char;
      i += 1;
      continue;
    }

    // Drop the quoted span, leaving a separator so words do not fuse.
    result += " ";
    i = end + 1;
  }

  return result;
}

/** Split text into `{word, line}` tokens, normalized, with 1-based line numbers. */
export function tokenize(text) {
  const tokens = [];
  const lines = String(text).split("\n");

  for (let index = 0; index < lines.length; index += 1) {
    const normalized = lines[index]
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, " ")
      .split(/\s+/)
      .filter(Boolean);
    for (const word of normalized) {
      tokens.push({ word, line: index + 1 });
    }
  }

  return tokens;
}

/** Build the set of k-word shingles over a token list. */
export function shingles(tokens, k = DEFAULTS.k) {
  const set = new Set();
  for (let i = 0; i + k <= tokens.length; i += 1) {
    set.add(
      tokens
        .slice(i, i + k)
        .map((t) => t.word)
        .join(" "),
    );
  }
  return set;
}

/** Fraction of A's shingles present in B. Empty A is 0, never NaN. */
export function containment(a, b) {
  if (a.size === 0) return 0;
  let hits = 0;
  for (const shingle of a) {
    if (b.has(shingle)) hits += 1;
  }
  return round(hits / a.size);
}

/** Symmetric overlap. Reported for context; the separation rule does not use it. */
export function jaccard(a, b) {
  if (a.size === 0 && b.size === 0) return 0;
  let intersection = 0;
  for (const shingle of a) {
    if (b.has(shingle)) intersection += 1;
  }
  const union = a.size + b.size - intersection;
  return union === 0 ? 0 : round(intersection / union);
}

/**
 * Contiguous runs of local shingles found in the source set, merged into spans
 * carrying local line offsets and a word count.
 */
export function matchedSpans(localTokens, sourceSet, k = DEFAULTS.k) {
  const spans = [];
  let runStart = -1;
  let runEnd = -1;

  const closeRun = () => {
    if (runStart === -1) return;
    const firstToken = localTokens[runStart];
    const lastToken = localTokens[runEnd + k - 1];
    spans.push({
      local_lines: [firstToken.line, lastToken.line],
      words: runEnd + k - runStart,
    });
    runStart = -1;
    runEnd = -1;
  };

  for (let i = 0; i + k <= localTokens.length; i += 1) {
    const shingle = localTokens
      .slice(i, i + k)
      .map((t) => t.word)
      .join(" ");
    if (sourceSet.has(shingle)) {
      if (runStart === -1) runStart = i;
      runEnd = i;
    } else {
      closeRun();
    }
  }
  closeRun();

  return spans;
}

/**
 * Compare a local passage against a source text.
 *
 * The local text is quote-stripped first; the source is not, because the
 * question is what the LOCAL surface reproduces.
 */
export function compare(localText, sourceText, options = {}) {
  const k = options.k ?? DEFAULTS.k;
  const minContainment = options.min_containment ?? DEFAULTS.min_containment;
  const minSpanWords = options.min_span_words ?? DEFAULTS.min_span_words;

  const localTokens = tokenize(stripQuoted(localText));
  const sourceTokens = tokenize(sourceText);

  const localSet = shingles(localTokens, k);
  const sourceSet = shingles(sourceTokens, k);

  const spans = matchedSpans(localTokens, sourceSet, k);
  const longestSpanWords = spans.reduce((max, span) => Math.max(max, span.words), 0);
  const containmentValue = containment(localSet, sourceSet);

  return {
    k,
    local_shingles: localSet.size,
    containment: containmentValue,
    jaccard: jaccard(localSet, sourceSet),
    longest_span_words: longestSpanWords,
    matched_spans: spans,
    separation: {
      rule: `containment>=${minContainment}||span>=${minSpanWords}`,
      fired: containmentValue >= minContainment || longestSpanWords >= minSpanWords,
    },
  };
}

function round(value) {
  return Math.round(value * 1000) / 1000;
}

// --- CLI --------------------------------------------------------------------

const USAGE = `Usage: fingerprint.mjs compare --local FILE --source FILE [--json]

Reports lexical overlap between a local passage and a fetched source. Local
text is quote-stripped (fences, blockquotes, inline quotations) before
shingling. Exits 0 on a clean comparison whether or not the separation rule
fires; non-zero only on operational failure.

Options:
  --local FILE       the repository file or extracted passage
  --source FILE      the already-fetched source text
  --json             emit JSON (default; kept explicit for callers)
  --k N              shingle size (default ${DEFAULTS.k})
  --min-containment  separation threshold (default ${DEFAULTS.min_containment})
  --min-span-words   separation threshold (default ${DEFAULTS.min_span_words})
`;

function parseArgs(argv) {
  const args = { json: true };
  let i = 0;

  if (argv[i] === "compare") i += 1;
  else if (argv[i] === "--help" || argv[i] === "-h") return { help: true };
  else throw new Error(`unknown command: ${argv[i] ?? "(none)"}`);

  const needsValue = (flag) => {
    const value = argv[i + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`${flag} requires a value`);
    }
    i += 2;
    return value;
  };

  while (i < argv.length) {
    switch (argv[i]) {
      case "--local":
        args.local = needsValue("--local");
        break;
      case "--source":
        args.source = needsValue("--source");
        break;
      case "--json":
        args.json = true;
        i += 1;
        break;
      case "--k":
        args.k = Number(needsValue("--k"));
        break;
      case "--min-containment":
        args.min_containment = Number(needsValue("--min-containment"));
        break;
      case "--min-span-words":
        args.min_span_words = Number(needsValue("--min-span-words"));
        break;
      case "--help":
      case "-h":
        return { help: true };
      default:
        throw new Error(`unknown option: ${argv[i]}`);
    }
  }

  if (!args.local) throw new Error("--local is required");
  if (!args.source) throw new Error("--source is required");
  return args;
}

function main(argv) {
  let args;
  try {
    args = parseArgs(argv);
  } catch (err) {
    process.stderr.write(`${err.message}\n\n${USAGE}`);
    return 2;
  }

  if (args.help) {
    process.stdout.write(USAGE);
    return 0;
  }

  let localText;
  let sourceText;
  try {
    localText = readFileSync(args.local, "utf8");
    sourceText = readFileSync(args.source, "utf8");
  } catch (err) {
    process.stderr.write(`cannot read input: ${err.message}\n`);
    return 2;
  }

  const result = compare(localText, sourceText, args);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
