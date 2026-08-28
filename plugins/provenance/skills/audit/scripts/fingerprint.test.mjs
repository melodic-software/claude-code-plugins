#!/usr/bin/env node
// Unit tests for fingerprint.mjs, the one pure module in this plugin.
//
// Written before the implementation, per the plan's TDD requirement. The first
// two cases are the binding S2 spike amendments: quotation stripping covers
// INLINE quotes and not only blockquotes, and verdicts are matched SPANS rather
// than whole-file containment, which dilutes a real match to noise on a
// real-sized file.

import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

import {
  stripQuoted,
  tokenize,
  shingles,
  containment,
  jaccard,
  matchedSpans,
  compare,
  DEFAULTS,
} from "./fingerprint.mjs";

const SELF_DIR = dirname(fileURLToPath(import.meta.url));
const MODULE = join(SELF_DIR, "fingerprint.mjs");

let PASS = 0;
let FAIL = 0;
const ok = (name) => {
  console.log(`ok: ${name}`);
  PASS += 1;
};
const fail = (name, detail) => {
  console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
  FAIL += 1;
};
const check = (name, cond, detail) => (cond ? ok(name) : fail(name, detail));

// --- fixture text -----------------------------------------------------------

// A distinctive upstream passage, reused across cases.
const UPSTREAM_SENTENCE =
  "Flowlite reads configuration from three locations, merged in order of increasing " +
  "precedence: the system file, the user file, and the project file in the repository " +
  "root. Keys set in a higher-precedence file override the same keys from lower-precedence " +
  "files; arrays are replaced wholesale, never merged element-wise.";

const SOURCE_TEXT = [
  "# Flowlite configuration reference",
  "",
  UPSTREAM_SENTENCE,
  "",
  "The runner.max_parallel key caps concurrent task execution and defaults to four.",
].join("\n");

// --- case: inline_quote_fixture ---------------------------------------------
// A properly quoted and cited excerpt must strip to nothing before shingling.
// A blockquote-only stripper would leave this text in and report a false match.
{
  const localInline = [
    "# Why we cap parallelism",
    "",
    "The vendor's reference puts it plainly: " +
      `"${UPSTREAM_SENTENCE}" ` +
      "(https://example.com/docs/flowlite, as of 2026-08-27; recheck on the next major).",
    "",
    "Our own runner pins parallelism to two because the fixtures share a sqlite file.",
  ].join("\n");

  const r = compare(localInline, SOURCE_TEXT);
  check(
    "inline_quote_fixture: straight inline quotes strip to zero matched spans",
    r.matched_spans.length === 0 && r.longest_span_words === 0,
    `got spans=${r.matched_spans.length} longest=${r.longest_span_words}`,
  );
  check(
    "inline_quote_fixture: separation rule does not fire on a cited quotation",
    r.separation.fired === false,
    `containment=${r.containment}`,
  );

  // The same passage with curly quotes must behave identically.
  const localCurly = localInline
    .replace(`"${UPSTREAM_SENTENCE}"`, `“${UPSTREAM_SENTENCE}”`);
  const rc = compare(localCurly, SOURCE_TEXT);
  check(
    "inline_quote_fixture: curly inline quotes strip identically",
    rc.matched_spans.length === 0 && rc.separation.fired === false,
    `got spans=${rc.matched_spans.length} fired=${rc.separation.fired}`,
  );
}

// --- case: span_dilution_fixture --------------------------------------------
// A real-sized local file with one planted copied span. Whole-file containment
// goes to noise; the matched span must still surface, with its line offsets.
{
  const filler = [];
  for (let i = 0; i < 120; i += 1) {
    filler.push(
      `Section ${i}: our own operational notes about queue draining, shard rebalancing, ` +
        `and the retry budget owned by team ${i % 7}, written for this repository alone.`,
    );
    filler.push("");
  }
  const head = filler.slice(0, 80).join("\n");
  const tail = filler.slice(80).join("\n");
  const localBig = `${head}\n${UPSTREAM_SENTENCE}\n${tail}`;
  const plantedLine = head.split("\n").length + 1;

  const r = compare(localBig, SOURCE_TEXT);

  check(
    "span_dilution_fixture: whole-file containment is diluted to noise",
    r.containment < DEFAULTS.min_containment,
    `containment=${r.containment} should be below ${DEFAULTS.min_containment}`,
  );
  check(
    "span_dilution_fixture: the planted span still surfaces",
    r.longest_span_words >= DEFAULTS.min_span_words,
    `longest_span_words=${r.longest_span_words}`,
  );
  check(
    "span_dilution_fixture: separation fires on the span, not the ratio",
    r.separation.fired === true,
    `fired=${r.separation.fired} containment=${r.containment} span=${r.longest_span_words}`,
  );
  check(
    "span_dilution_fixture: matched span carries local line offsets",
    r.matched_spans.length >= 1 &&
      Array.isArray(r.matched_spans[0].local_lines) &&
      r.matched_spans[0].local_lines[0] === plantedLine,
    `spans=${JSON.stringify(r.matched_spans.slice(0, 1))} expected first line ${plantedLine}`,
  );
}

// --- case: verbatim_copy ----------------------------------------------------
{
  const r = compare(UPSTREAM_SENTENCE, SOURCE_TEXT);
  check(
    "verbatim_copy: containment is high on a bare copied passage",
    r.containment >= 0.9,
    `containment=${r.containment}`,
  );
  check("verbatim_copy: separation fires", r.separation.fired === true);
}

// --- case: unrelated_text ---------------------------------------------------
{
  const r = compare(
    "Our deploy runbook tags the release, watches the canary for ten minutes, and " +
      "pages the service owner after two consecutive rollbacks.",
    SOURCE_TEXT,
  );
  check(
    "unrelated_text: no matched spans and no firing",
    r.matched_spans.length === 0 && r.separation.fired === false,
    `containment=${r.containment} spans=${r.matched_spans.length}`,
  );
}

// --- case: fence_and_blockquote_stripping -----------------------------------
{
  const local = [
    "Quoted upstream, fenced:",
    "",
    "```text",
    UPSTREAM_SENTENCE,
    "```",
    "",
    "> " + UPSTREAM_SENTENCE,
    "",
    "Our own conclusion follows from that.",
  ].join("\n");
  const r = compare(local, SOURCE_TEXT);
  check(
    "fence_and_blockquote_stripping: code fences and blockquotes strip out",
    r.matched_spans.length === 0,
    `spans=${r.matched_spans.length} longest=${r.longest_span_words}`,
  );
}

// --- case: wrapped_quote_fixture --------------------------------------------
// Hard-wrapped prose is ordinary markdown, so a quotation routinely opens on
// one line and closes on the next. Stripping per line left that excerpt in and
// reported it as overlap. Inline stripping now runs over the paragraph.
{
  const half = Math.floor(UPSTREAM_SENTENCE.length / 2);
  const wrapAt = UPSTREAM_SENTENCE.indexOf(" ", half);
  const wrapped =
    UPSTREAM_SENTENCE.slice(0, wrapAt) + "\n" + UPSTREAM_SENTENCE.slice(wrapAt + 1);

  const localWrapped = [
    "# Why we cap parallelism",
    "",
    `The vendor's reference puts it plainly: "${wrapped}"`,
    "(https://example.com/docs/flowlite, read 2026-08-27; recheck on the next major).",
    "",
    "Our own runner pins parallelism to two because the fixtures share a sqlite file.",
  ].join("\n");

  const r = compare(localWrapped, SOURCE_TEXT);
  check(
    "wrapped_quote_fixture: a quotation closing on the next line strips to nothing",
    r.matched_spans.length === 0 && r.longest_span_words === 0,
    `spans=${JSON.stringify(r.matched_spans)} longest=${r.longest_span_words}`,
  );
  check(
    "wrapped_quote_fixture: separation does not fire on a wrapped cited quotation",
    r.separation.fired === false && r.containment === 0,
    `fired=${r.separation.fired} containment=${r.containment}`,
  );

  const localCurly = localWrapped.replace(`"${wrapped}"`, `“${wrapped}”`);
  const rc = compare(localCurly, SOURCE_TEXT);
  check(
    "wrapped_quote_fixture: curly marks strip across the line break identically",
    rc.matched_spans.length === 0 && rc.separation.fired === false,
    `spans=${rc.matched_spans.length} fired=${rc.separation.fired}`,
  );

  check(
    "wrapped_quote_fixture: stripping preserves the line count exactly",
    stripQuoted(localWrapped).split("\n").length === localWrapped.split("\n").length,
    `${stripQuoted(localWrapped).split("\n").length} vs ${localWrapped.split("\n").length}`,
  );
}

// --- case: quote_cannot_escape_paragraph -------------------------------------
// The bound that makes paragraph-wide stripping safe. An opening mark with no
// partner in its own paragraph must stay put rather than pairing with a mark
// further down the document and swallowing everything between.
{
  const localBlank = [
    'An unpaired " quote mark opens here and never closes.',
    "It runs on to a second line of the very same paragraph.",
    "",
    `${UPSTREAM_SENTENCE} And then a stray " mark much later on.`,
  ].join("\n");
  const rb = compare(localBlank, SOURCE_TEXT);
  check(
    "quote_cannot_escape_paragraph: a blank line resets the open-quote state",
    rb.longest_span_words >= DEFAULTS.min_span_words,
    `longest=${rb.longest_span_words} containment=${rb.containment}`,
  );

  const localQuote = [
    'An unpaired " quote mark opens here and never closes.',
    "> a blockquote line sits between the two marks",
    `${UPSTREAM_SENTENCE} And then a stray " mark much later on.`,
  ].join("\n");
  check(
    "quote_cannot_escape_paragraph: a blockquote line resets the open-quote state",
    compare(localQuote, SOURCE_TEXT).longest_span_words >= DEFAULTS.min_span_words,
    `longest=${compare(localQuote, SOURCE_TEXT).longest_span_words}`,
  );

  const localFence = [
    'An unpaired " quote mark opens here and never closes.',
    "```text",
    "fenced material",
    "```",
    `${UPSTREAM_SENTENCE} And then a stray " mark much later on.`,
  ].join("\n");
  check(
    "quote_cannot_escape_paragraph: a fence delimiter resets the open-quote state",
    compare(localFence, SOURCE_TEXT).longest_span_words >= DEFAULTS.min_span_words,
    `longest=${compare(localFence, SOURCE_TEXT).longest_span_words}`,
  );

  const stripped = stripQuoted(localBlank);
  check(
    "quote_cannot_escape_paragraph: prose after the unpaired mark survives verbatim",
    stripped.includes("never closes") && stripped.includes("Flowlite reads configuration"),
    JSON.stringify(stripped.slice(0, 160)),
  );
}

// --- case: contraction_does_not_close_a_quote --------------------------------
// A single-quoted excerpt that wraps and contains a contraction. The apostrophe
// in "doesn't" is the first ' after the opening mark, so a naive forward search
// closes the quote there and leaves the rest of the excerpt in the token stream
// — the exact false positive paragraph-wide stripping exists to prevent, and it
// only became reachable once the pairing scope widened past one line.
{
  const withContraction = [
    "The upstream page is explicit about this:",
    "",
    "As documented, 'the runner retries twice with linear backoff and",
    "doesn't apply jitter unless the task opts in explicitly' which is the",
    "behavior we rely on.",
  ].join("\n");

  const stripped = stripQuoted(withContraction);
  check(
    "contraction_does_not_close_a_quote: the whole excerpt strips, not just its head",
    !stripped.includes("apply jitter unless the task opts in"),
    JSON.stringify(stripped.split("\n")[3]),
  );
  check(
    "contraction_does_not_close_a_quote: no orphaned closing mark survives",
    !stripped.includes("explicitly'"),
    JSON.stringify(stripped.split("\n")[3]),
  );
  check(
    "contraction_does_not_close_a_quote: unquoted prose after the excerpt survives",
    stripped.includes("behavior we rely on") && stripped.includes("upstream page is explicit"),
    JSON.stringify(stripped),
  );
  check(
    "contraction_does_not_close_a_quote: line count is preserved",
    stripQuoted(withContraction).split("\n").length === withContraction.split("\n").length,
    `${stripQuoted(withContraction).split("\n").length} vs ${withContraction.split("\n").length}`,
  );

  // The guard must not stop a genuine closer that merely follows a word, or an
  // excerpt containing a possessive would never close and would leak instead.
  const possessive = "A cited span 'covering the runner and the teams' rota' ends here.";
  check(
    "contraction_does_not_close_a_quote: a quote containing a possessive still closes",
    stripQuoted(possessive).includes("ends here") &&
      !stripQuoted(possessive).includes("covering the runner"),
    JSON.stringify(stripQuoted(possessive)),
  );
}

// --- case: possessive_after_markup_is_not_an_opening_quote -------------------
// The opening guard tested only for a word char before the mark, so a
// possessive following a closing backtick or paren — `Location`'s, (FILE.md)'s,
// which this repository's own prose is full of — read as an OPENING quote.
// That was bounded while the closing scan stopped at the next contraction; once
// pairing skipped word-internal apostrophes it ran to the next stray mark
// instead, blanking whole paragraphs of original prose. Measured across tracked
// markdown, that reached 16,031 characters in one file. Over-stripping hides
// real copies, so this is the false-negative direction and the worse one.
{
  const possessiveAfterMarkup = [
    "The rule is contained to `Location`'s file, but the runner still applies it.",
    "A downstream consumer's rota is unaffected and the schedule stays fixed.",
    "This whole paragraph is original prose that no upstream page ever carried.",
    "It ends with a body line quoting a `'trigger phrase'` from the catalog.",
  ].join("\n");

  const stripped = stripQuoted(possessiveAfterMarkup);
  check(
    "possessive_after_markup_is_not_an_opening_quote: original prose survives",
    stripped.includes("original prose that no upstream page ever carried") &&
      stripped.includes("rota is unaffected"),
    JSON.stringify(stripped),
  );
  check(
    "possessive_after_markup_is_not_an_opening_quote: a parenthesized possessive is not an opener",
    stripQuoted("See (FILE.md)'s note; the rest of this line is original prose.").includes(
      "the rest of this line is original prose",
    ),
    JSON.stringify(stripQuoted("See (FILE.md)'s note; the rest of this line is original prose.")),
  );
  check(
    "possessive_after_markup_is_not_an_opening_quote: a real opening quote still opens",
    !stripQuoted("Cited as 'the runner retries twice' in the note.").includes(
      "the runner retries twice",
    ),
    JSON.stringify(stripQuoted("Cited as 'the runner retries twice' in the note.")),
  );
  check(
    "possessive_after_markup_is_not_an_opening_quote: line count is preserved",
    stripped.split("\n").length === possessiveAfterMarkup.split("\n").length,
    `${stripped.split("\n").length} vs ${possessiveAfterMarkup.split("\n").length}`,
  );
}

// --- case: wrapped_quote_line_numbering --------------------------------------
// Spans report local line offsets and the fix flow edits against them, so a
// wrapped quotation earlier in the file must not shift what comes after it.
{
  const half = Math.floor(UPSTREAM_SENTENCE.length / 2);
  const wrapAt = UPSTREAM_SENTENCE.indexOf(" ", half);
  const lines = [
    "# Notes",
    "",
    `Quoted upstream: "${UPSTREAM_SENTENCE.slice(0, wrapAt)}`,
    `${UPSTREAM_SENTENCE.slice(wrapAt + 1)}" (https://example.com/docs/flowlite).`,
    "",
    "Our own paragraph sits between the quotation and the planted copy below.",
    "",
    UPSTREAM_SENTENCE,
    "",
    "Trailing prose of our own.",
  ];
  const local = lines.join("\n");
  const plantedLine = 8;

  check(
    "wrapped_quote_line_numbering: stripQuoted returns the same number of lines",
    stripQuoted(local).split("\n").length === lines.length,
    `${stripQuoted(local).split("\n").length} vs ${lines.length}`,
  );

  const r = compare(local, SOURCE_TEXT);
  check(
    "wrapped_quote_line_numbering: the planted copy keeps its true line offset",
    r.matched_spans.length === 1 && r.matched_spans[0].local_lines[0] === plantedLine,
    JSON.stringify(r.matched_spans),
  );
}

// --- case: stripQuoted_unit -------------------------------------------------
{
  const stripped = stripQuoted('Lead in "quoted words here" and trailing text.');
  check(
    "stripQuoted_unit: removes the quoted span, keeps the surrounding prose",
    !stripped.includes("quoted words here") &&
      stripped.includes("Lead in") &&
      stripped.includes("trailing text"),
    JSON.stringify(stripped),
  );

  const unbalanced = stripQuoted('An unpaired " quote mark should not eat the rest.');
  check(
    "stripQuoted_unit: an unpaired quote does not swallow the remainder",
    unbalanced.includes("should not eat the rest"),
    JSON.stringify(unbalanced),
  );
}

// --- case: tokenize_line_tracking -------------------------------------------
{
  const toks = tokenize("alpha beta\ngamma delta");
  check(
    "tokenize_line_tracking: tokens carry 1-based line numbers",
    toks.length === 4 && toks[0].line === 1 && toks[3].line === 2,
    JSON.stringify(toks),
  );
}

// --- case: shingle_and_set_metrics ------------------------------------------
{
  const a = shingles(tokenize("one two three four five six"), 5);
  const b = shingles(tokenize("one two three four five six"), 5);
  check("shingle_and_set_metrics: k=5 over six words yields two shingles", a.size === 2, `${a.size}`);
  check("shingle_and_set_metrics: identical texts are fully contained", containment(a, b) === 1);
  check("shingle_and_set_metrics: identical texts have jaccard 1", jaccard(a, b) === 1);
  check(
    "shingle_and_set_metrics: empty local set is contained 0, never NaN",
    containment(new Set(), b) === 0,
  );
}

// --- case: matchedSpans_merges_runs ------------------------------------------
{
  const local = tokenize(UPSTREAM_SENTENCE);
  const src = shingles(tokenize(SOURCE_TEXT), 5);
  const spans = matchedSpans(local, src, 5);
  check(
    "matchedSpans_merges_runs: one contiguous run becomes one span",
    spans.length === 1 && spans[0].words > 20,
    JSON.stringify(spans),
  );
}

// --- case: cli_json ----------------------------------------------------------
{
  const dir = mkdtempSync(join(tmpdir(), "provenance-fp-"));
  try {
    const localPath = join(dir, "local.md");
    const sourcePath = join(dir, "source.md");
    writeFileSync(localPath, UPSTREAM_SENTENCE);
    writeFileSync(sourcePath, SOURCE_TEXT);
    const out = execFileSync(
      process.execPath,
      [MODULE, "compare", "--local", localPath, "--source", sourcePath, "--json"],
      { encoding: "utf8" },
    );
    const parsed = JSON.parse(out);
    check(
      "cli_json: emits the contract fields on stdout",
      typeof parsed.containment === "number" &&
        typeof parsed.jaccard === "number" &&
        typeof parsed.longest_span_words === "number" &&
        Array.isArray(parsed.matched_spans) &&
        typeof parsed.separation?.fired === "boolean" &&
        typeof parsed.separation?.rule === "string",
      out.slice(0, 200),
    );
  } catch (err) {
    fail("cli_json: CLI invocation failed", String(err.message ?? err).slice(0, 300));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// --- case: cli_missing_arg_exits_nonzero -------------------------------------
{
  let exitCode = 0;
  try {
    execFileSync(process.execPath, [MODULE, "compare", "--local"], {
      encoding: "utf8",
      stdio: "pipe",
    });
  } catch (err) {
    exitCode = err.status ?? 1;
  }
  check(
    "cli_missing_arg_exits_nonzero: operational failure is non-zero",
    exitCode !== 0,
    `exit=${exitCode}`,
  );
}

console.log("");
console.log(`Passed: ${PASS}  Failed: ${FAIL}`);
process.exit(FAIL === 0 ? 0 : 1);
