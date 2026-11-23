#!/usr/bin/env node

import { mkdtempSync, writeFileSync, rmSync, readdirSync, readFileSync } from "node:fs";
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
  localTokens,
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

  const localCurly = localInline
    .replace(`"${UPSTREAM_SENTENCE}"`, `“${UPSTREAM_SENTENCE}”`);
  const rc = compare(localCurly, SOURCE_TEXT);
  check(
    "inline_quote_fixture: curly inline quotes strip identically",
    rc.matched_spans.length === 0 && rc.separation.fired === false,
    `got spans=${rc.matched_spans.length} fired=${rc.separation.fired}`,
  );
}

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

{
  const r = compare(UPSTREAM_SENTENCE, SOURCE_TEXT);
  check(
    "verbatim_copy: containment is high on a bare copied passage",
    r.containment >= 0.9,
    `containment=${r.containment}`,
  );
  check("verbatim_copy: separation fires", r.separation.fired === true);
}

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

  const strippedWrapped = stripQuoted(localWrapped);
  check(
    "wrapped_quote_fixture: stripping preserves the line count exactly",
    strippedWrapped.split("\n").length === localWrapped.split("\n").length,
    `${strippedWrapped.split("\n").length} vs ${localWrapped.split("\n").length}`,
  );
}

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
  const rq = compare(localQuote, SOURCE_TEXT);
  check(
    "quote_cannot_escape_paragraph: a blockquote line resets the open-quote state",
    rq.longest_span_words >= DEFAULTS.min_span_words,
    `longest=${rq.longest_span_words}`,
  );

  const localFence = [
    'An unpaired " quote mark opens here and never closes.',
    "```text",
    "fenced material",
    "```",
    `${UPSTREAM_SENTENCE} And then a stray " mark much later on.`,
  ].join("\n");
  const rf = compare(localFence, SOURCE_TEXT);
  check(
    "quote_cannot_escape_paragraph: a fence delimiter resets the open-quote state",
    rf.longest_span_words >= DEFAULTS.min_span_words,
    `longest=${rf.longest_span_words}`,
  );

  const stripped = stripQuoted(localBlank);
  check(
    "quote_cannot_escape_paragraph: prose after the unpaired mark survives verbatim",
    stripped.includes("never closes") && stripped.includes("Flowlite reads configuration"),
    JSON.stringify(stripped.slice(0, 160)),
  );
}

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
    stripped.split("\n").length === withContraction.split("\n").length,
    `${stripped.split("\n").length} vs ${withContraction.split("\n").length}`,
  );

  const possessive = stripQuoted(
    "A cited span 'covering the runner and the teams' rota' ends here.",
  );
  check(
    "contraction_does_not_close_a_quote: a quote containing a possessive still closes",
    possessive.includes("ends here") && !possessive.includes("covering the runner"),
    JSON.stringify(possessive),
  );
}

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
  const parenPossessive = stripQuoted(
    "See (FILE.md)'s note; the rest of this line is original prose.",
  );
  check(
    "possessive_after_markup_is_not_an_opening_quote: a parenthesized possessive is not an opener",
    parenPossessive.includes("the rest of this line is original prose"),
    JSON.stringify(parenPossessive),
  );
  const realOpener = stripQuoted("Cited as 'the runner retries twice' in the note.");
  check(
    "possessive_after_markup_is_not_an_opening_quote: a real opening quote still opens",
    !realOpener.includes("the runner retries twice"),
    JSON.stringify(realOpener),
  );
  check(
    "possessive_after_markup_is_not_an_opening_quote: line count is preserved",
    stripped.split("\n").length === possessiveAfterMarkup.split("\n").length,
    `${stripped.split("\n").length} vs ${possessiveAfterMarkup.split("\n").length}`,
  );
}

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

  const strippedLocal = stripQuoted(local);
  check(
    "wrapped_quote_line_numbering: stripQuoted returns the same number of lines",
    strippedLocal.split("\n").length === lines.length,
    `${strippedLocal.split("\n").length} vs ${lines.length}`,
  );

  const r = compare(local, SOURCE_TEXT);
  check(
    "wrapped_quote_line_numbering: the planted copy keeps its true line offset",
    r.matched_spans.length === 1 && r.matched_spans[0].local_lines[0] === plantedLine,
    JSON.stringify(r.matched_spans),
  );
}

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

{
  const toks = tokenize("alpha beta\ngamma delta");
  check(
    "tokenize_line_tracking: tokens carry 1-based line numbers",
    toks.length === 4 && toks[0].line === 1 && toks[3].line === 2,
    JSON.stringify(toks),
  );
}

{
  const urlOnly = tokenize("https://example.com/docs/en/flowlite/configuration-reference.md");
  check(
    "url_tokens_count_zero_words: a URL-only line counts zero words",
    urlOnly.length === 0,
    JSON.stringify(urlOnly),
  );
  const around = tokenize("See <https://example.com/docs/flowlite>, or [the page](https://example.com/a/b).");
  check(
    "url_tokens_count_zero_words: the words around a URL still count",
    around.map((t) => t.word).join(" ") === "see or the page",
    JSON.stringify(around),
  );
  const citation = "- https://example.com/docs/en/build-with-flowlite/configuring-the-cache-and-the-runner";
  const r = compare(citation, `${SOURCE_TEXT}\n\n${citation}`);
  check(
    "url_tokens_count_zero_words: a URL shared with the source is no matched span",
    r.matched_spans.length === 0 && r.local_shingles === 0 && r.separation.fired === false,
    JSON.stringify(r),
  );
}

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

const lineOf = (text, needle) =>
  text.split("\n").findIndex((line) => line.includes(needle)) + 1;
{
  const local = JSON.stringify(
    {
      skill_name: "flowlite-config",
      evals: [
        { id: 1, prompt: "Where does Flowlite read its configuration?", expected_output: UPSTREAM_SENTENCE },
      ],
    },
    null,
    2,
  );
  const r = compare(local, SOURCE_TEXT);
  check(
    "json_value_copy: a verbatim copy in a string value fires",
    r.separation.fired === true && r.longest_span_words >= DEFAULTS.min_span_words,
    `fired=${r.separation.fired} longest=${r.longest_span_words}`,
  );
  check(
    "json_value_copy: the matched span reports the JSON file's own line",
    r.matched_spans.length === 1 &&
      r.matched_spans[0].local_lines[0] === lineOf(local, "expected_output") &&
      r.matched_spans[0].local_lines[1] === lineOf(local, "expected_output"),
    `spans=${JSON.stringify(r.matched_spans)} expected line ${lineOf(local, "expected_output")}`,
  );

  const rb = compare(`﻿${local}`, SOURCE_TEXT);
  check(
    "json_value_copy: a byte-order mark does not send the file down the text path",
    rb.separation.fired === true &&
      JSON.stringify(rb.matched_spans) === JSON.stringify(r.matched_spans),
    `spans=${JSON.stringify(rb.matched_spans)}`,
  );
}

{
  const unrelated = JSON.stringify({
    prompt: "Our deploy runbook tags the release and watches the canary for ten minutes.",
    expected_output: "The service owner is paged after two consecutive rollbacks.",
  });
  const ru = compare(unrelated, SOURCE_TEXT);
  check(
    "json_unrelated_and_keys: unrelated values do not fire",
    ru.matched_spans.length === 0 && ru.separation.fired === false,
    `containment=${ru.containment} spans=${ru.matched_spans.length}`,
  );

  const keyed = JSON.stringify({ [UPSTREAM_SENTENCE]: "ok" });
  const rk = compare(keyed, SOURCE_TEXT);
  check(
    "json_unrelated_and_keys: a key holding source text is not measured",
    rk.local_shingles === 0 && rk.separation.fired === false,
    `local_shingles=${rk.local_shingles} fired=${rk.separation.fired}`,
  );
}

{
  const local = JSON.stringify(
    ["```text\nan example whose fence never closes", UPSTREAM_SENTENCE],
    null,
    2,
  );
  const r = compare(local, SOURCE_TEXT);
  check(
    "json_values_strip_on_their_own: an unclosed fence does not blank the next value",
    r.separation.fired === true &&
      r.matched_spans.length === 1 &&
      r.matched_spans[0].local_lines[0] === lineOf(local, "Flowlite reads"),
    `spans=${JSON.stringify(r.matched_spans)}`,
  );

  const quoted = JSON.stringify({
    expected_output: `The vendor puts it plainly: "${UPSTREAM_SENTENCE}" (https://example.com/docs/flowlite).`,
  });
  const rq = compare(quoted, SOURCE_TEXT);
  check(
    "json_values_strip_on_their_own: a quoted excerpt inside a value still strips",
    rq.matched_spans.length === 0 && rq.separation.fired === false,
    `spans=${rq.matched_spans.length} containment=${rq.containment}`,
  );
}

{
  const sameAsTextPath = (text) =>
    JSON.stringify(localTokens(text)) === JSON.stringify(tokenize(stripQuoted(text)));

  check(
    "text_path_unchanged: a bare JSON scalar takes the text path",
    sameAsTextPath(JSON.stringify(UPSTREAM_SENTENCE)) && sameAsTextPath("42"),
  );
  check(
    "text_path_unchanged: malformed JSON takes the text path",
    sameAsTextPath(`{"expected_output": "${UPSTREAM_SENTENCE}",`),
  );

  const goldenDir = join(SELF_DIR, "..", "evals", "fixtures", "golden");
  const cases = readdirSync(goldenDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);
  const changed = cases.filter((name) => {
    const caseText = readFileSync(join(goldenDir, name, "case.md"), "utf8");
    return !sameAsTextPath(caseText);
  });
  check(
    "text_path_unchanged: every golden case.md tokenizes as before",
    cases.length > 0 && changed.length === 0,
    `cases=${cases.length} changed=${changed.join(", ")}`,
  );
}

{
  const dir = mkdtempSync(join(tmpdir(), "attribution-fp-"));
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
