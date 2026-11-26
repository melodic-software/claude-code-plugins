#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { parseArgs } from "node:util";
import { pathToFileURL } from "node:url";

export const LOSS_DROP = 0.15;
export const GRADER_DROP = 2;
const SHA = /^[0-9a-f]{40}$/;
const CASE_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$/;

export const recordLines = (head, runId) => [`<!-- eval-pair verdict=no-loss validity=VALID head=${head} -->`, `<!-- eval-pair-run id=${runId} -->`];

const valid = (validity) => /^verdict: VALID(?: |$)/.test(String(validity ?? "").trimEnd().split("\n").at(-1) ?? "");

/**
 * Per case name: { runs, scores, passes: grader -> passing runs }, from
 * results.json's `with` arm, and the names more than one case carries, whose
 * results cannot be told apart.
 */
export function readArm(results) {
  const cases = new Map();
  const duplicates = new Set();
  for (const entry of results?.cases ?? []) {
    if (cases.has(String(entry?.name))) duplicates.add(String(entry?.name));
    const rows = Array.isArray(entry?.arms?.with) ? entry.arms.with : [];
    const passes = new Map();
    for (const row of rows) {
      for (const grader of row?.graders ?? []) {
        passes.set(grader.name, (passes.get(grader.name) ?? 0) + (grader.passed === true ? 1 : 0));
      }
    }
    cases.set(String(entry?.name), { runs: rows.length, scores: rows.map((row) => Number(row?.score) || 0), passes, cost: rows.reduce((sum, row) => sum + (Number(row?.costUsd) || 0), 0) });
  }
  return Object.assign(cases, { duplicates });
}

const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

/**
 * { verdict: "PASS" | "LOSS" | "VOID", reasons, cases: [{ name, before, after, verdict, lost }], blind, cost }
 * by result.py's rules: a case loses when its mean score falls by LOSS_DROP or
 * more, or any grader passes in GRADER_DROP or more fewer after runs.
 */
export function judge({ before, after, beforeValidity, afterValidity }) {
  const reasons = [];
  if (!valid(beforeValidity)) reasons.push("the before arm did not read VALID");
  if (!valid(afterValidity)) reasons.push("the after arm did not read VALID");
  const b = readArm(before);
  const a = readArm(after);
  const names = [...new Set([...b.keys(), ...a.keys()])].sort();
  if (names.length === 0) reasons.push("no case ran");
  if (b.duplicates.size > 0 || a.duplicates.size > 0) reasons.push("two cases share a name, so their results cannot be told apart");
  const cases = [];
  let blind = 0;
  let cost = 0;
  for (const name of names) {
    const sides = { before: b.get(name), after: a.get(name) };
    cost += (sides.before?.cost ?? 0) + (sides.after?.cost ?? 0);
    if (!sides.before?.runs || !sides.after?.runs) {
      reasons.push(`a case ran on one arm only`);
      cases.push({ name, verdict: "VOID", lost: [] });
      continue;
    }
    const graders = [...new Set([...sides.before.passes.keys(), ...sides.after.passes.keys()])];
    blind += graders.filter((g) => (sides.before.passes.get(g) ?? 0) === 0).length;
    const lost = graders.filter((g) => (sides.after.passes.get(g) ?? 0) <= (sides.before.passes.get(g) ?? 0) - GRADER_DROP);
    const before = mean(sides.before.scores);
    const after = mean(sides.after.scores);
    const loss = before - after >= LOSS_DROP - 1e-9 || lost.length > 0;
    cases.push({ name, before, after, runs: [sides.before.runs, sides.after.runs], verdict: loss ? "LOSS" : "PASS", lost });
  }
  const verdict = reasons.length > 0 ? "VOID" : cases.some((c) => c.verdict === "LOSS") ? "LOSS" : "PASS";
  return { verdict, reasons, cases, blind, cost };
}

/** The comment for `result`: the record lines only on PASS. */
export function comment(result, { base, head, runId, runUrl }) {
  const label = (name, i) => (CASE_NAME.test(name) ? `\`${name}\`` : `case ${i + 1}`);
  const rows = result.cases.map((c, i) =>
    c.verdict === "VOID"
      ? `| ${label(c.name, i)} | - | - | VOID |`
      : `| ${label(c.name, i)} | ${c.before.toFixed(3)} (${c.runs[0]} runs) | ${c.after.toFixed(3)} (${c.runs[1]} runs) | ${c.verdict}${c.lost.length ? `: ${c.lost.length} grader(s) pass ${GRADER_DROP} or more fewer after runs` : ""} |`,
  );
  return [
    `## Compare eval: ${result.verdict}`,
    "",
    `The same cases ran on the pull request's merge base \`${base}\` (before) and its head \`${head}\` (after), each as plugin text on the default branch's harness. Loss: a case's mean score falls by ${LOSS_DROP} or more, or a grader passes in ${GRADER_DROP} or more fewer after runs.`,
    "",
    "| Case | Before mean | After mean | Verdict |",
    "|---|---|---|---|",
    ...rows,
    "",
    ...result.reasons.map((reason) => `- VOID: ${reason}.`),
    `Graders that cannot show a loss (they failed in every before run): ${result.blind}.`,
    `Cost: ${result.cost.toFixed(2)} USD (the runs' costUsd).`,
    `Run: ${runUrl}`,
    "",
    "Posted by pr-run-plugin-evals.yml compare mode.",
    ...(result.verdict === "PASS" ? recordLines(head, runId) : []),
    "",
  ].join("\n");
}

export function main(argv = process.argv.slice(2)) {
  let values;
  try {
    ({ values } = parseArgs({ args: argv, options: Object.fromEntries(["before", "after", "base", "head", "run-id", "run-url", "out"].map((k) => [k, { type: "string" }])) }));
  } catch (error) {
    console.error(`compare-verdict: ${error.message}`);
    return 2;
  }
  if (!SHA.test(values.base ?? "") || !SHA.test(values.head ?? "") || !/^[1-9][0-9]{0,19}$/.test(values["run-id"] ?? "") || !/^https:\/\/\S+$/.test(values["run-url"] ?? "") || !values.before || !values.after || !values.out) {
    console.error("compare-verdict: --before, --after, --out, a 40-hex --base and --head, a numeric --run-id and an https --run-url are required");
    return 2;
  }
  let arms;
  try {
    const read = (dir) => ({ results: JSON.parse(readFileSync(join(dir, "results.json"), "utf8")), validity: readFileSync(join(dir, "validity.txt"), "utf8") });
    arms = { before: read(values.before), after: read(values.after) };
  } catch (error) {
    console.error(`compare-verdict: an arm did not read: ${error.message}`);
    return 2;
  }
  const result = judge({ before: arms.before.results, after: arms.after.results, beforeValidity: arms.before.validity, afterValidity: arms.after.validity });
  writeFileSync(values.out, comment(result, { base: values.base, head: values.head, runId: values["run-id"], runUrl: values["run-url"] }));
  console.log(`compare-verdict: ${result.verdict} cases=${result.cases.length} blind=${result.blind} cost=${result.cost.toFixed(2)}`);
  return result.verdict === "PASS" ? 0 : 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = main();
}
