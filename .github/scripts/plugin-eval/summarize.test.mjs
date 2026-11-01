// Expected verdicts come from /evals:plugin-eval's reference/ci.md parser: a
// partial document, a run with skippedPaidGraders or a non-null error, and a
// two-arm case with no delta are each NOT COMPARABLE, never a score.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { verdicts } from "./summarize.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const fixture = (name) => join(HERE, "fixtures", name);
const run = (...args) => spawnSync(process.execPath, [join(HERE, "summarize.mjs"), ...args], { encoding: "utf8" });

test("a scored case prints its with, without and delta and PASS", () => {
  const out = run(fixture("scored.json"));
  assert.equal(out.status, 0, out.stderr);
  assert.match(out.stdout, /\| writes-a-test \| 1\.00 \| 0\.50 \| \+0\.50 \| PASS: score 1\.00 against threshold 0\.80 \|/);
  assert.doesNotMatch(out.stdout, /NOT COMPARABLE/);
  assert.match(out.stdout, /Result: PASS$/m);
});

for (const [name, reason] of [
  ["partial.json", /partial: cost_ceiling/],
  ["skipped-paid-graders.json", /without-arm run 2 skipped its paid graders/],
  ["errored.json", /with-arm run 1 errored: timeout/],
]) {
  test(`${name} prints NOT COMPARABLE and no score`, () => {
    const out = run(fixture(name));
    assert.equal(out.status, 1, out.stderr);
    const row = out.stdout.split("\n").find((line) => line.startsWith("| writes-a-test |"));
    assert.match(row, /\| – \| – \| – \| NOT COMPARABLE: /);
    assert.match(row, reason);
    assert.match(out.stdout, /Result: NOT COMPARABLE$/m);
  });
}

test("the health line reads whether the skill loaded and how many with-arm runs fired it", () => {
  const out = run(fixture("scored.json"));
  assert.match(out.stdout, /- writes-a-test: skill loaded: yes; fired in 1 of 2 runs with a kept trace \(2 runs\)/);
});

test("a prompt that slash-invokes a loaded plugin skill counts as fired with no Skill call", () => {
  const doc = JSON.parse(readFileSync(fixture("scored.json"), "utf8"));
  doc.cases[0].promptMarkdown = "/testing:write add a test for add()";
  doc.cases[0].arms.with = [doc.cases[0].arms.with[1]];
  const text = (plugin) => spawnSync(process.execPath, ["--input-type=module", "-e", `
    import { summarize } from ${JSON.stringify(join(HERE, "summarize.mjs"))};
    console.log(summarize(${JSON.stringify(doc)}, { plugin: ${JSON.stringify(plugin)}, base: ${JSON.stringify(join(HERE, "fixtures"))} }).text);
  `], { encoding: "utf8" }).stdout;
  assert.match(text("testing"), /- writes-a-test: skill loaded: yes; fired in 1 of 1 runs with a kept trace \(1 runs; the prompt slash-invokes testing:write\)/);
  assert.match(text("other"), /- writes-a-test: skill loaded: no; fired in 0 of 1 runs with a kept trace \(1 runs\)$/m);
});

test("with no kept trace the health line says so rather than reporting zero", () => {
  const doc = JSON.parse(readFileSync(fixture("scored.json"), "utf8"));
  for (const r of doc.cases[0].arms.with) r.tracePath = "traces/deleted-by-the-runner.jsonl";
  const out = spawnSync(process.execPath, ["--input-type=module", "-e", `
    import { summarize } from ${JSON.stringify(join(HERE, "summarize.mjs"))};
    console.log(summarize(${JSON.stringify(doc)}, { base: ${JSON.stringify(join(HERE, "fixtures"))} }).text);
  `], { encoding: "utf8" });
  assert.match(out.stdout, /skill loaded: unknown \(no kept trace lists skills\); no kept trace of 2 runs/);
});

test("a two-arm case with no delta and no flagged run is NOT COMPARABLE", () => {
  const doc = JSON.parse(readFileSync(fixture("scored.json"), "utf8"));
  delete doc.cases[0].aggregates.delta;
  assert.equal(verdicts(doc)[0].verdict, "NOT COMPARABLE");
});

test("under --ablation none a case needs no delta and is judged on its score", () => {
  const doc = JSON.parse(readFileSync(fixture("scored.json"), "utf8"));
  doc.suite.ablation = "none";
  delete doc.cases[0].arms.without;
  delete doc.cases[0].aggregates.delta;
  doc.cases[0].aggregates.score = 0.5;
  assert.deepEqual([verdicts(doc)[0].verdict, verdicts(doc)[0].score], ["FAIL", 0.5]);
});

test("a result with no case is not a pass", () => {
  const doc = JSON.parse(readFileSync(fixture("scored.json"), "utf8"));
  doc.cases = [];
  assert.deepEqual(verdicts(doc), []);
});

test("a missing or unreadable result is a usage error", () => {
  assert.equal(run(fixture("absent.json")).status, 2);
  assert.equal(run().status, 2);
  assert.equal(run(fixture("scored.json"), "--plugin").status, 2);
});

test("--redact prints no case name, error or partial reason, and keeps the verdict", () => {
  const errored = run(fixture("errored.json"), "--redact");
  assert.equal(errored.status, 1);
  assert.doesNotMatch(errored.stdout, /timeout/);
  assert.match(errored.stdout, /\| case 1 \|.*with-arm run 1 errored: \(redacted\)/);
  const partial = run(fixture("partial.json"), "--plugin", "x", "--redact");
  assert.doesNotMatch(partial.stdout, /cost_ceiling/);
  const scored = run(fixture("scored.json"), "--redact");
  assert.equal(scored.status, 0, scored.stderr);
  assert.doesNotMatch(scored.stdout, /writes-a-test/);
  assert.match(scored.stdout, /Result: PASS$/m);
});
