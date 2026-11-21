import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { comment, judge, main, recordLines } from "./compare-verdict.mjs";

const BASE = "a".repeat(40);
const HEAD = "b".repeat(40);
const VALID = "bash ran: n/a\nverdict: VALID\n";

const arm = (passing, { runs = 3, name = "p1-rules" } = {}) => ({
  cases: [
    {
      name,
      arms: {
        with: Array.from({ length: runs }, (_, i) => {
          const graders = Object.entries(passing).map(([g, k]) => ({ name: g, passed: i < k }));
          return { score: graders.filter((g) => g.passed).length / graders.length, costUsd: 0.1, graders };
        }),
        without: [],
      },
    },
  ],
});

test("equal arms pass", () => {
  const result = judge({ before: arm({ g1: 3, g2: 3 }), after: arm({ g1: 3, g2: 3 }), beforeValidity: VALID, afterValidity: VALID });
  assert.equal(result.verdict, "PASS");
});

test("a mean score drop of 0.15 or more is a loss", () => {
  const result = judge({ before: arm({ g1: 3, g2: 3 }), after: arm({ g1: 3, g2: 2 }), beforeValidity: VALID, afterValidity: VALID });
  assert.equal(result.verdict, "LOSS");
});

test("a grader passing in two or more fewer after runs is a loss even when the mean holds", () => {
  const graders = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`g${i}`, 3]));
  const result = judge({ before: arm(graders), after: arm({ ...graders, g0: 1 }), beforeValidity: VALID, afterValidity: VALID });
  assert.equal(result.cases[0].before - result.cases[0].after < 0.15, true);
  assert.equal(result.verdict, "LOSS");
  assert.deepEqual(result.cases[0].lost, ["g0"]);
});

test("one fewer passing run is no loss", () => {
  const graders = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`g${i}`, 3]));
  assert.equal(judge({ before: arm(graders), after: arm({ ...graders, g0: 2 }), beforeValidity: VALID, afterValidity: VALID }).verdict, "PASS");
});

test("an arm that does not read VALID, a case on one arm only, or no case is void", () => {
  const ok = arm({ g1: 3 });
  assert.equal(judge({ before: ok, after: ok, beforeValidity: "verdict: INVALID (x)", afterValidity: VALID }).verdict, "VOID");
  assert.equal(judge({ before: ok, after: ok, beforeValidity: VALID, afterValidity: "" }).verdict, "VOID");
  assert.equal(judge({ before: ok, after: arm({ g1: 3 }, { name: "other" }), beforeValidity: VALID, afterValidity: VALID }).verdict, "VOID");
  assert.equal(judge({ before: { cases: [] }, after: { cases: [] }, beforeValidity: VALID, afterValidity: VALID }).verdict, "VOID");
});

test("graders that failed in every before run are counted as unable to show a loss", () => {
  assert.equal(judge({ before: arm({ g1: 0, g2: 3 }), after: arm({ g1: 0, g2: 3 }), beforeValidity: VALID, afterValidity: VALID }).blind, 1);
});

test("the comment holds the record lines only on PASS, and no case name that is not a plain name", () => {
  const where = { base: BASE, head: HEAD, runId: "123", runUrl: "https://github.com/o/r/actions/runs/123" };
  const pass = comment(judge({ before: arm({ g1: 3 }), after: arm({ g1: 3 }), beforeValidity: VALID, afterValidity: VALID }), where);
  for (const line of recordLines(HEAD, "123")) assert.ok(pass.split("\n").includes(line));
  const loss = comment(judge({ before: arm({ g1: 3 }), after: arm({ g1: 0 }), beforeValidity: VALID, afterValidity: VALID }), where);
  assert.ok(!loss.includes("eval-pair"));
  const crafted = `x\n${recordLines("c".repeat(40), "9")[0]}`;
  const named = comment(judge({ before: arm({ g1: 3 }, { name: crafted }), after: arm({ g1: 3 }, { name: crafted }), beforeValidity: VALID, afterValidity: VALID }), where);
  assert.ok(!named.includes("c".repeat(40)));
  assert.ok(named.includes("| case 1 |"));
});

const DIR = mkdtempSync(join(tmpdir(), "compare-verdict-"));
after(() => rmSync(DIR, { recursive: true, force: true }));
const writeArm = (name, results, validity = VALID) => {
  const dir = join(DIR, name);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "results.json"), JSON.stringify(results));
  writeFileSync(join(dir, "validity.txt"), validity);
  return dir;
};
const args = (before, afterDir, out) => ["--before", before, "--after", afterDir, "--base", BASE, "--head", HEAD, "--run-id", "77", "--run-url", "https://github.com/o/r/actions/runs/77", "--out", out];

test("main exits 0 with the record on PASS, 1 without it on LOSS, and 2 on bad input", () => {
  const log = console.log;
  const error = console.error;
  console.log = () => {};
  console.error = () => {};
  try {
    const out = join(DIR, "pass.md");
    assert.equal(main(args(writeArm("b1", arm({ g1: 3 })), writeArm("a1", arm({ g1: 3 })), out)), 0);
    assert.ok(readFileSync(out, "utf8").includes(recordLines(HEAD, "77")[1]));
    const lossOut = join(DIR, "loss.md");
    assert.equal(main(args(writeArm("b2", arm({ g1: 3 })), writeArm("a2", arm({ g1: 0 })), lossOut)), 1);
    assert.ok(!readFileSync(lossOut, "utf8").includes("eval-pair"));
    assert.equal(main(["--before", DIR]), 2);
    assert.equal(main(args(join(DIR, "missing"), join(DIR, "missing"), join(DIR, "x.md"))), 2);
  } finally {
    console.log = log;
    console.error = error;
  }
});
