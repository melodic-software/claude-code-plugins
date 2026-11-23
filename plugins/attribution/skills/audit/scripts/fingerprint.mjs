#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

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

export function stripQuoted(text) {
  const lines = String(text).split("\n");
  const out = new Array(lines.length);
  let inFence = false;
  let paragraph = [];

  const flushParagraph = () => {
    if (paragraph.length === 0) return;
    const stripped = stripInlineQuotes(
      paragraph.map((index) => lines[index]).join("\n"),
    ).split("\n");
    for (let j = 0; j < paragraph.length; j += 1) out[paragraph[j]] = stripped[j];
    paragraph = [];
  };

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];

    if (/^\s*(```|~~~)/.test(line)) {
      flushParagraph();
      inFence = !inFence;
      out[i] = "";
      continue;
    }
    if (inFence || /^\s*>/.test(line)) {
      flushParagraph();
      out[i] = "";
      continue;
    }
    if (/^\s*$/.test(line)) {
      flushParagraph();
      out[i] = line;
      continue;
    }

    paragraph.push(i);
  }
  flushParagraph();

  return out.join("\n");
}

function blankSpan(span) {
  return span.replace(/[^\n]/g, " ");
}

function findClosing(block, closing, from) {
  const apostrophe = closing === "'" || closing === "’";
  let at = block.indexOf(closing, from);
  while (at !== -1) {
    const wordInternal =
      apostrophe && /\w/.test(block[at - 1] ?? "") && /\w/.test(block[at + 1] ?? "");
    if (!wordInternal) return at;
    at = block.indexOf(closing, at + 1);
  }
  return -1;
}

function stripInlineQuotes(block) {
  let result = "";
  let i = 0;

  while (i < block.length) {
    const char = block[i];
    const closing = OPENING_TO_CLOSING.get(char);

    const prev = block[i - 1];
    const opens =
      closing !== undefined &&
      ((char !== "'" && char !== "‘") || prev === undefined || /[\s([{<]/.test(prev));

    const end = opens ? findClosing(block, closing, i + 1) : -1;
    if (end === -1) {
      result += char;
      i += 1;
      continue;
    }

    result += blankSpan(block.slice(i, end + 1));
    i = end + 1;
  }

  return result;
}

const URL_RUN = /\b[a-z][a-z0-9+.-]*:\/\/\S+/g;

export function tokenize(text) {
  const tokens = [];
  const lines = String(text).split("\n");

  for (let index = 0; index < lines.length; index += 1) {
    const normalized = lines[index]
      .toLowerCase()
      .replace(URL_RUN, " ")
      .replace(/[^a-z0-9\s]/g, " ")
      .split(/\s+/)
      .filter(Boolean);
    for (const word of normalized) {
      tokens.push({ word, line: index + 1 });
    }
  }

  return tokens;
}

export function localTokens(text) {
  return jsonValueTokens(text) ?? tokenize(stripQuoted(text));
}

const KEY_COLON = /\s*:/y;

function jsonValueTokens(text) {
  let parsed;
  try {
    parsed = JSON.parse(text.replace(/^﻿/, ""));
  } catch {
    return null;
  }
  if (parsed === null || typeof parsed !== "object") return null;

  const tokens = [];
  let line = 1;
  for (let i = 0; i < text.length; i += 1) {
    if (text[i] === "\n") line += 1;
    if (text[i] !== '"') continue;

    let end = i + 1;
    while (text[end] !== '"') end += text[end] === "\\" ? 2 : 1;
    const literal = text.slice(i, end + 1);
    i = end;

    KEY_COLON.lastIndex = end + 1;
    if (KEY_COLON.test(text)) continue;
    for (const { word } of tokenize(stripQuoted(JSON.parse(literal)))) {
      tokens.push({ word, line });
    }
  }
  return tokens;
}

function shingleAt(tokens, i, k) {
  return tokens
    .slice(i, i + k)
    .map((t) => t.word)
    .join(" ");
}

export function shingles(tokens, k = DEFAULTS.k) {
  const set = new Set();
  for (let i = 0; i + k <= tokens.length; i += 1) set.add(shingleAt(tokens, i, k));
  return set;
}

function sharedCount(a, b) {
  let shared = 0;
  for (const shingle of a) {
    if (b.has(shingle)) shared += 1;
  }
  return shared;
}

export function containment(a, b) {
  if (a.size === 0) return 0;
  return round(sharedCount(a, b) / a.size);
}

export function jaccard(a, b) {
  const shared = sharedCount(a, b);
  const union = a.size + b.size - shared;
  return union === 0 ? 0 : round(shared / union);
}

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
    if (sourceSet.has(shingleAt(localTokens, i, k))) {
      if (runStart === -1) runStart = i;
      runEnd = i;
    } else {
      closeRun();
    }
  }
  closeRun();

  return spans;
}

export function compare(localText, sourceText, options = {}) {
  const k = options.k ?? DEFAULTS.k;
  const minContainment = options.min_containment ?? DEFAULTS.min_containment;
  const minSpanWords = options.min_span_words ?? DEFAULTS.min_span_words;

  const local = localTokens(localText);
  const sourceTokens = tokenize(sourceText);

  const localSet = shingles(local, k);
  const sourceSet = shingles(sourceTokens, k);

  const spans = matchedSpans(local, sourceSet, k);
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

const USAGE = `Usage: fingerprint.mjs compare --local FILE --source FILE [--json]

Reports lexical overlap between a local passage and a fetched source. Local
text is quote-stripped (fences, blockquotes, inline quotations) before
shingling; a JSON object or array is measured by its string values, each
stripped on its own, never its keys. A URL in either text counts as no
words. Exits 0 on a clean comparison whether
or not the separation rule fires; non-zero only on operational failure.

Options:
  --local FILE       the repository file or extracted passage
  --source FILE      the already-fetched source text
  --json             emit JSON (default; kept explicit for callers)
  --k N              shingle size (default ${DEFAULTS.k})
  --min-containment  separation threshold (default ${DEFAULTS.min_containment})
  --min-span-words   separation threshold (default ${DEFAULTS.min_span_words})
`;

const VALUE_OPTIONS = new Map([
  ["--local", ["local", String]],
  ["--source", ["source", String]],
  ["--k", ["k", Number]],
  ["--min-containment", ["min_containment", Number]],
  ["--min-span-words", ["min_span_words", Number]],
]);

function parseArgs(argv) {
  const args = { json: true };
  let i = 0;

  if (argv[i] === "compare") i += 1;
  else if (argv[i] === "--help" || argv[i] === "-h") return { help: true };
  else throw new Error(`unknown command: ${argv[i] ?? "(none)"}`);

  while (i < argv.length) {
    const flag = argv[i];
    const option = VALUE_OPTIONS.get(flag);
    if (option) {
      const value = argv[i + 1];
      if (value === undefined || value.startsWith("--")) {
        throw new Error(`${flag} requires a value`);
      }
      const [key, parse] = option;
      args[key] = parse(value);
      i += 2;
    } else if (flag === "--json") {
      i += 1;
    } else if (flag === "--help" || flag === "-h") {
      return { help: true };
    } else {
      throw new Error(`unknown option: ${flag}`);
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
