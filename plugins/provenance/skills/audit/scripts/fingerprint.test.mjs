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
