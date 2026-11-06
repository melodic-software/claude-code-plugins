// Expected verdicts come from /evals:plugin-eval's reference/ci.md parser: a
// partial document, a run with skippedPaidGraders or a non-null error, and a
// two-arm case with no delta are each NOT COMPARABLE, never a score. The
// single-arm-by-design rule (context.history_file set, no without-arm key) is
// run-validity.py's row count rule.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { summarize, verdicts } from "./summarize.mjs";

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

test("a run that dispatches one of the plugin's agents counts as fired", () => {
  const doc = JSON.parse(readFileSync(fixture("scored.json"), "utf8"));
  doc.cases[0].arms.with = [{ ...doc.cases[0].arms.with[1], tracePath: "traces/with-agent.jsonl" }];
  const out = spawnSync(process.execPath, ["--input-type=module", "-e", `
    import { summarize } from ${JSON.stringify(join(HERE, "summarize.mjs"))};
    console.log(summarize(${JSON.stringify(doc)}, { plugin: "testing", base: ${JSON.stringify(join(HERE, "fixtures"))} }).text);
  `], { encoding: "utf8" });
  assert.match(out.stdout, /- writes-a-test: skill loaded: yes; fired in 1 of 1 runs with a kept trace \(1 runs\)$/m);
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

const HISTORY_YAML = "name: writes-a-test\ncontext:\n  scaffold_script: scaffold.sh\n  history_file: secret-history.jsonl\n";
const singleArmDoc = (score) => {
  const doc = JSON.parse(readFileSync(fixture("scored.json"), "utf8"));
  delete doc.cases[0].arms.without;
  delete doc.cases[0].aggregates.delta;
  delete doc.cases[0].aggregates.scoreWithout;
  doc.cases[0].aggregates.score = score;
  return doc;
};
const judged = (doc, yaml) => {
  const [row] = verdicts(doc, { caseYaml: () => yaml });
  return [row.verdict, row.score, row.reason];
};

test("a history_file case with no without-arm key is scored alone against the threshold", () => {
  assert.deepEqual(judged(singleArmDoc(1), HISTORY_YAML), ["PASS", 1, "ran single-arm by design (context.history_file), so no delta: score 1.00 against threshold 0.80"]);
  assert.deepEqual(judged(singleArmDoc(0.5), HISTORY_YAML), ["FAIL", 0.5, "ran single-arm by design (context.history_file), so no delta: score 0.50 against threshold 0.80"]);
  assert.equal(judged(singleArmDoc(1), "context: { history_file: h.jsonl }  # flow\n")[0], "PASS");
});

test("a case not single-arm by design keeps the no-delta NOT COMPARABLE", () => {
  const emptyWithout = singleArmDoc(1);
  emptyWithout.cases[0].arms.without = [];
  for (const [doc, yaml, why] of [
    [emptyWithout, HISTORY_YAML, "an empty without-arm"],
    [singleArmDoc(1), "context:\n  scaffold_script: scaffold.sh\n", "no history_file"],
    [singleArmDoc(1), null, "no case.yaml"],
    [singleArmDoc(1), "context:\n  history_file:\n    nested: x\n", "an empty value continued below"],
    [singleArmDoc(1), "# history_file: h.jsonl\ncontext:\n  scaffold_script: s.sh\n", "a commented mention"],
    [singleArmDoc(1), "history_file: h.jsonl\n", "the key outside context"],
  ]) {
    assert.deepEqual(judged(doc, yaml), ["NOT COMPARABLE", null, "the arms are not comparable: the case carries no delta"], why);
  }
});

test("a single-arm-by-design case with an errored run is still NOT COMPARABLE", () => {
  const doc = singleArmDoc(1);
  doc.cases[0].arms.with[0].error = "timeout";
  assert.deepEqual(judged(doc, HISTORY_YAML).slice(0, 2), ["NOT COMPARABLE", null]);
});

test("summarize reads case.yaml at <suite.root>/<dir>, a relative root against the result's directory", () => {
  const dir = mkdtempSync(join(tmpdir(), "summarize-"));
  try {
    mkdirSync(join(dir, "plugin", "evals", "with-history"), { recursive: true });
    mkdirSync(join(dir, "plugin", "evals", "no-yaml"), { recursive: true });
    writeFileSync(join(dir, "plugin", "evals", "with-history", "case.yaml"), HISTORY_YAML);
    const doc = singleArmDoc(1);
    doc.suite.root = "plugin";
    const text = (caseDir) => {
      doc.cases[0].dir = caseDir;
      return summarize(doc, { plugin: "testing", base: dir }).text;
    };
    assert.match(text("evals/with-history"), /\| PASS: ran single-arm by design/);
    assert.match(text("evals/no-yaml"), /\| NOT COMPARABLE: the arms are not comparable: the case carries no delta \|/);
    assert.match(text("evals/absent-dir"), /Result: NOT COMPARABLE$/m);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("--redact keeps a single-arm-by-design case's name and history_file out of the summary", () => {
  const { text, result } = summarize(singleArmDoc(1), { plugin: "testing", base: join(HERE, "fixtures"), redact: true, caseYaml: () => HISTORY_YAML });
  assert.equal(result, "PASS");
  assert.match(text, /\| case 1 \| 1\.00 \| – \| – \| PASS: ran single-arm by design/);
  assert.doesNotMatch(text, /writes-a-test|secret-history/);
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

test("--annotation writes one escaped ::error naming each case that is not PASS", () => {
  const dir = mkdtempSync(join(tmpdir(), "summarize-"));
  try {
    const file = join(dir, "annotation.txt");
    const errored = run(fixture("errored.json"), "--plugin", "x,y:z", "--annotation", file);
    assert.equal(errored.status, 1, errored.stderr);
    const text = readFileSync(file, "utf8");
    assert.equal(text.split("\n").filter(Boolean).length, 1);
    assert.match(text, /^::error title=Plugin eval verdict%3A x%2Cy%3Az::NOT COMPARABLE\. NOT COMPARABLE: writes-a-test \(with-arm run 1 errored: timeout\)\n$/);
    const redacted = run(fixture("errored.json"), "--redact", "--annotation", file);
    assert.equal(redacted.status, 1);
    assert.match(readFileSync(file, "utf8"), /NOT COMPARABLE: case 1 \(with-arm run 1 errored: \(redacted\)\)/);
    const scored = run(fixture("scored.json"), "--annotation", file);
    assert.equal(scored.status, 0, scored.stderr);
    assert.equal(readFileSync(file, "utf8"), "");
    assert.equal(run(fixture("scored.json"), "--annotation").status, 2);
    // An unreadable result writes no file, so the step reports the suite as not run.
    const missing = join(dir, "unread.txt");
    assert.equal(run(fixture("absent.json"), "--annotation", missing).status, 2);
    assert.equal(existsSync(missing), false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("an annotation's line breaks and percent signs are escaped", () => {
  const { annotation } = summarize({ cases: [{ name: "a\nb", aggregates: {}, arms: { with: [{ error: "50%\r\n::warning::x" }] } }] }, { plugin: "p" });
  assert.equal(annotation.split("\n").length, 1);
  assert.match(annotation, /a%0Ab \(with-arm run 1 errored: 50%25%0D%0A::warning::x\)$/);
});
