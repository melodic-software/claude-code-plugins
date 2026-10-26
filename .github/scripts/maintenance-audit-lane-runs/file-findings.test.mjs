// The judge's output is untrusted: write-findings keeps at most three
// well-formed findings and names what it dropped; the filer drops any finding
// with a failed claim before planning, stamps each kept one with its
// fingerprint, and writes them into one rolling digest issue.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { createBudget } from "./collect.mjs";
import { droppedLine, listSweepIssues, prepareItems, writeDigest } from "./file-findings.mjs";
import { planDigest } from "./findings.mjs";
import { parseJudgeOutput } from "./write-findings.mjs";

const finding = (over = {}) => ({
  slice: "D",
  title: "fix(ci): skip the dispatch runner for a skipped review",
  problem: "p",
  root_cause: "r",
  proposed_fix: "f",
  workflow: ".github/workflows/pr-feedback-dispatch.yml",
  job: "dispatch",
  signature: "skipped upstream run started a runner",
  evidence: [{ path: "a.yml", line: 1, quote: "if: true" }],
  covered_by: null,
  ...over,
});

test("the judge's output keeps at most three well-formed findings", () => {
  const text = JSON.stringify({
    findings: [finding(), finding({ slice: "Z" }), finding(), finding(), finding()],
  });
  const { findings, dropped } = parseJudgeOutput(text);
  assert.equal(findings.length, 3);
  assert.deepEqual(dropped, [
    { index: 1, reason: "slice" },
    { index: 4, reason: "over-limit" },
  ]);
  assert.deepEqual(parseJudgeOutput("not json"), {
    findings: [],
    dropped: [{ index: null, reason: "unparsable" }],
  });
  assert.deepEqual(parseJudgeOutput('{"findings": 3}').dropped, [{ index: null, reason: "unparsable" }]);
});

test("write-findings reads the launcher's structured-output file, and an empty path as unparsable", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "lane-sweep-write-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const script = fileURLToPath(new URL("./write-findings.mjs", import.meta.url));
  const write = (file) => {
    const out = join(dir, "out", "findings.json");
    const run = spawnSync(process.execPath, [script], {
      env: { PATH: process.env.PATH, STRUCTURED_OUTPUT_FILE: file, UNIT_ID: "d1", FINDINGS_PATH: out },
      encoding: "utf8",
    });
    assert.equal(run.status, 0, run.stderr);
    return JSON.parse(readFileSync(out, "utf8"));
  };
  const structured = join(dir, "structured.json");
  writeFileSync(structured, JSON.stringify({ findings: [finding()] }));
  assert.deepEqual(write(structured), { unit: "d1", findings: [finding()], dropped: [] });
  assert.deepEqual(write(""), { unit: "d1", findings: [], dropped: [{ index: null, reason: "unparsable" }] });
});

test("a finding with any failed claim is dropped before planning", (t) => {
  const base = mkdtempSync(join(tmpdir(), "lane-sweep-file-"));
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = mkdtempSync(join(tmpdir(), "lane-sweep-findings-"));
  t.after(() => {
    rmSync(base, { recursive: true, force: true });
    rmSync(dir, { recursive: true, force: true });
  });
  const units = writeUnits([dUnit()]);
  t.after(() => rmSync(units, { recursive: true, force: true }));
  mkdirSync(join(dir, "findings-d1"));
  writeFileSync(
    join(dir, "findings-d1", "findings.json"),
    JSON.stringify({
      unit: "d1",
      findings: [
        finding(),
        finding({
          evidence: [
            { path: "a.yml", line: 1, quote: "if: true" },
            { path: "a.yml", line: 1, quote: "if: false" },
          ],
        }),
      ],
    }),
  );
  const { items, dropped } = prepareItems({ findingsDir: dir, unitsDir: units, baseDir: base });
  assert.equal(items.length, 1);
  assert.match(items[0].fingerprint, /^[0-9a-f]{16}$/);
  assert.deepEqual(dropped, [{ unit: "d1", title: finding().title, reason: "a.yml:1 quote-not-on-line" }]);
});

const dUnit = () => ({
  id: "d1",
  slice: "D",
  workflow: ".github/workflows/pr-feedback-dispatch.yml",
  sampled_success_runs: [{ id: 5, jobs: [{ name: "dispatch" }, { name: "label" }] }],
});
const aUnit = () => ({
  id: "a1",
  slice: "A",
  workflow: ".github/workflows/pr-ci.yml",
  runs: [{ id: 9, failed_jobs: [{ name: "lint" }] }],
});

function writeUnits(units) {
  const dir = mkdtempSync(join(tmpdir(), "lane-sweep-units-"));
  for (const unit of units) writeFileSync(join(dir, `${unit.id}.json`), JSON.stringify(unit));
  return dir;
}

// One finding per unit through prepareItems; returns what survived and what was dropped.
function prepareOne(t, unitData, over) {
  const base = mkdtempSync(join(tmpdir(), "lane-sweep-file-"));
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = mkdtempSync(join(tmpdir(), "lane-sweep-findings-"));
  const units = writeUnits([unitData]);
  t.after(() => {
    for (const d of [base, dir, units]) rmSync(d, { recursive: true, force: true });
  });
  mkdirSync(join(dir, `findings-${unitData.id}`));
  writeFileSync(
    join(dir, `findings-${unitData.id}`, "findings.json"),
    JSON.stringify({ unit: unitData.id, findings: [finding(over)] }),
  );
  return prepareItems({ findingsDir: dir, unitsDir: units, baseDir: base });
}

test("a finding naming another workflow than its unit's is dropped", (t) => {
  const { items, dropped } = prepareOne(t, dUnit(), { workflow: ".github/workflows/pr-other.yml" });
  assert.equal(items.length, 0);
  assert.deepEqual(dropped, [{ unit: "d1", title: finding().title, reason: "workflow-not-unit" }]);
});

test("a finding naming a job absent from its unit is dropped", (t) => {
  const { items, dropped } = prepareOne(t, dUnit(), { job: "deploy" });
  assert.equal(items.length, 0);
  assert.deepEqual(dropped, [{ unit: "d1", title: finding().title, reason: "job-not-in-unit" }]);
});

test("a finding naming a slice other than its unit's is dropped", (t) => {
  const { items, dropped } = prepareOne(t, aUnit(), { slice: "C", workflow: ".github/workflows/pr-ci.yml", job: "lint" });
  assert.equal(items.length, 0);
  assert.deepEqual(dropped, [{ unit: "a1", title: finding().title, reason: "slice-not-unit" }]);
});

test("a finding that matches its unit's workflow and job passes", (t) => {
  const d = prepareOne(t, dUnit(), { job: "label" });
  assert.equal(d.items.length, 1);
  assert.deepEqual(d.dropped, []);
  const a = prepareOne(t, aUnit(), { slice: "A", workflow: ".github/workflows/pr-ci.yml", job: "lint" });
  assert.equal(a.items.length, 1);
  assert.deepEqual(a.dropped, []);
});

test("a unit whose data lists no jobs binds the workflow but not the job", (t) => {
  const noGreen = { ...dUnit(), sampled_success_runs: [] };
  const d = prepareOne(t, noGreen, { job: "anything" });
  assert.equal(d.items.length, 1);
  assert.deepEqual(d.dropped, []);
  const other = prepareOne(t, noGreen, { workflow: ".github/workflows/pr-other.yml" });
  assert.deepEqual(other.dropped, [{ unit: "d1", title: finding().title, reason: "workflow-not-unit" }]);
  const a = prepareOne(t, { ...aUnit(), runs: [{ id: 9, failed_jobs: [] }] }, {
    slice: "A",
    workflow: ".github/workflows/pr-ci.yml",
    job: "build",
  });
  assert.equal(a.items.length, 1);
  assert.deepEqual(a.dropped, []);
});

test("a finding whose unit file is missing is dropped", (t) => {
  const base = mkdtempSync(join(tmpdir(), "lane-sweep-file-"));
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = mkdtempSync(join(tmpdir(), "lane-sweep-findings-"));
  const units = writeUnits([]);
  t.after(() => {
    for (const d of [base, dir, units]) rmSync(d, { recursive: true, force: true });
  });
  mkdirSync(join(dir, "findings-d1"));
  writeFileSync(join(dir, "findings-d1", "findings.json"), JSON.stringify({ unit: "d1", findings: [finding()] }));
  const { items, dropped } = prepareItems({ findingsDir: dir, unitsDir: units, baseDir: base });
  assert.equal(items.length, 0);
  assert.deepEqual(dropped, [{ unit: "d1", title: finding().title, reason: "unit-unreadable" }]);
});

test("a dropped line renders the title and reason inert on one line", () => {
  const line = droppedLine({
    unit: "a1",
    title: "fix: `x` <b>@octocat</b>",
    reason: "[approve here](https://evil.example)\n## Action required <img> `y` @octocat:1 bad-path",
  });
  assert.equal(line.split("\n").length, 1);
  assert.doesNotMatch(line, /[<`]|(?<!\\)\]\(|https:\/\/|@[A-Za-z]/);
  assert.match(line, /^- dropped \(a1\) fix: x &lt;b>@​octocat&lt;\/b>: /);
});

test("prepareItems is complete only when every unit has a parsed findings file", (t) => {
  const base = mkdtempSync(join(tmpdir(), "lane-sweep-file-"));
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = mkdtempSync(join(tmpdir(), "lane-sweep-findings-"));
  const units = mkdtempSync(join(tmpdir(), "lane-sweep-units-"));
  t.after(() => {
    for (const d of [base, dir, units]) rmSync(d, { recursive: true, force: true });
  });
  const unit = (id, extra = {}) => {
    mkdirSync(join(dir, `findings-${id}`));
    writeFileSync(join(dir, `findings-${id}`, "findings.json"), JSON.stringify({ unit: id, findings: [finding()], ...extra }));
  };
  writeFileSync(join(units, "a1.json"), "{}");
  writeFileSync(join(units, "d2.json"), "{}");
  unit("a1");
  assert.equal(prepareItems({ findingsDir: dir, baseDir: base, unitsDir: units }).complete, false);
  unit("d2");
  assert.equal(prepareItems({ findingsDir: dir, baseDir: base, unitsDir: units }).complete, true);
  writeFileSync(join(dir, "findings-d2", "findings.json"), JSON.stringify({ unit: "d2", findings: [], dropped: [{ index: null, reason: "unparsable" }] }));
  assert.equal(prepareItems({ findingsDir: dir, baseDir: base, unitsDir: units }).complete, false);
  writeFileSync(join(dir, "findings-d2", "findings.json"), "not json");
  assert.equal(prepareItems({ findingsDir: dir, baseDir: base, unitsDir: units }).complete, false);
});

test("prepareItems is not complete when the collector read part of a window or stopped early", (t) => {
  const base = mkdtempSync(join(tmpdir(), "lane-sweep-file-"));
  const dir = mkdtempSync(join(tmpdir(), "lane-sweep-findings-"));
  const out = mkdtempSync(join(tmpdir(), "lane-sweep-units-"));
  t.after(() => {
    for (const d of [base, dir, out]) rmSync(d, { recursive: true, force: true });
  });
  const units = join(out, "units");
  const status = join(out, "collect-status.json");
  mkdirSync(units);
  mkdirSync(join(dir, "findings-a1"));
  writeFileSync(join(dir, "findings-a1", "findings.json"), JSON.stringify({ unit: "a1", findings: [] }));
  writeFileSync(join(units, "a1.json"), JSON.stringify({ window_complete: true }));
  writeFileSync(status, JSON.stringify({ complete: true }));
  const run = () => prepareItems({ findingsDir: dir, baseDir: base, unitsDir: units, statusPath: status }).complete;
  assert.equal(run(), true);
  writeFileSync(join(units, "a1.json"), JSON.stringify({ window_complete: false }));
  assert.equal(run(), false);
  writeFileSync(join(units, "a1.json"), JSON.stringify({ window_complete: true }));
  writeFileSync(status, JSON.stringify({ complete: false, truncated: "stopped at unit d2: call budget" }));
  assert.equal(run(), false);
  rmSync(status);
  assert.equal(run(), false);
});

const FP = "0123456789abcdef";
const store = (issues = []) => {
  const calls = [];
  const call = async (method, path, body) => {
    calls.push([method, path, body]);
    if (method === "POST" && path.endsWith("/issues")) {
      const issue = { number: 100 + issues.length, state: "open", state_reason: null, ...body, labels: [...body.labels] };
      issues.push(issue);
      return issue;
    }
    const issue = issues.find((i) => i.number === Number(/issues\/(\d+)/.exec(path)[1]));
    if (method === "PATCH") Object.assign(issue, body);
    if (method === "DELETE") {
      if (!issue.labels.includes("agent-ready")) throw Object.assign(new Error(`DELETE ${path}: HTTP 404`), { status: 404 });
      issue.labels = issue.labels.filter((l) => l !== "agent-ready");
    }
    return {};
  };
  return { issues, calls, call };
};
const run = async (s, items, extra = {}) => {
  const plan = planDigest({ items, existing: s.issues, openNumbers: new Set(), ...extra });
  return writeDigest({ plan, call: s.call, repo: "o/r", labels: ["source: lane-sweep"], runUrl: "https://run/1", wait: async () => {} });
};
const nothing = { filed: [], updated: [], reopened: [], failed: [] };

test("the sweep files one digest, rewrites it in place on a change, and closes it when no finding is left", async () => {
  const s = store();
  const a = { fingerprint: FP, finding: finding() };
  const b = { fingerprint: "fedcba9876543210", finding: finding({ title: "fix(ci): another" }) };
  assert.deepEqual(await run(s, [a]), { ...nothing, filed: [100] });
  assert.deepEqual(s.issues[0].labels, ["source: lane-sweep"]);
  assert.equal(s.issues[0].title, "Lane sweep: open findings");

  const before = s.calls.length;
  assert.deepEqual(await run(s, [a]), nothing);
  assert.equal(s.calls.length, before);

  s.issues[0].labels.push("agent-ready");
  assert.deepEqual(await run(s, [b]), { ...nothing, updated: [100] });
  assert.equal(s.issues.length, 1);
  assert.deepEqual(
    s.calls.slice(-3).map(([m, p]) => `${m} ${p}`),
    ["POST /repos/o/r/issues/100/comments", "DELETE /repos/o/r/issues/100/labels/agent-ready", "PATCH /repos/o/r/issues/100"],
  );
  assert.deepEqual(s.issues[0].labels, ["source: lane-sweep"]);
  assert.match(s.calls.at(-3)[2].body, /New:\n\n- fix\(ci\): another/);
  assert.match(s.calls.at(-3)[2].body, /No longer seen:\n\n- fix\(ci\): skip the dispatch/);
  assert.ok(!s.issues[0].body.includes(FP), "the fixed finding dropped off");

  assert.deepEqual(await run(s, []), { ...nothing, updated: [100] });
  assert.equal(s.issues[0].state, "closed");
  assert.deepEqual(await run(s, []), nothing);

  assert.deepEqual(await run(s, [a]), { ...nothing, reopened: [100] });
  assert.equal(s.issues[0].state, "open");
  assert.equal(s.issues.length, 1);
});

test("a sweep missing a unit's findings carries the earlier entries over", async () => {
  const s = store();
  const a = { fingerprint: FP, finding: finding() };
  const b = { fingerprint: "fedcba9876543210", finding: finding({ title: "fix(ci): another" }) };
  await run(s, [a]);
  assert.deepEqual(await run(s, [b], { complete: false }), { ...nothing, updated: [100] });
  assert.ok(s.issues[0].body.includes(FP));
  assert.ok(s.issues[0].body.includes("fedcba9876543210"));
  const before = s.calls.length;
  assert.deepEqual(await run(s, [], { complete: false }), nothing);
  assert.equal(s.calls.length, before);
});

test("a failed agent-ready removal other than 404 skips the PATCH and leaves the old state to retry", async () => {
  const s = store();
  await run(s, [{ fingerprint: FP, finding: finding() }]);
  const old = s.issues[0].body;
  const items = [{ fingerprint: "fedcba9876543210", finding: finding() }];
  const failing = async (method, path, body) => {
    if (method === "DELETE") throw Object.assign(new Error(`DELETE ${path}: HTTP 500`), { status: 500 });
    return s.call(method, path, body);
  };
  const plan = planDigest({ items, existing: s.issues, openNumbers: new Set() });
  const result = await writeDigest({ plan, call: failing, repo: "o/r", labels: [], runUrl: "u", wait: async () => {} });
  assert.deepEqual(result.failed, [{ target: "#100", error: "DELETE /repos/o/r/issues/100/labels/agent-ready: HTTP 500" }]);
  assert.equal(s.issues[0].body, old);
  assert.equal(planDigest({ items, existing: s.issues, openNumbers: new Set() }).action, "update");
});

test("a failed filing is recorded", async () => {
  const call = async (method, path) => {
    throw new Error(`${method} ${path}: HTTP 422`);
  };
  const plan = planDigest({ items: [{ fingerprint: FP, finding: finding() }], existing: [], openNumbers: new Set() });
  const result = await writeDigest({ plan, call, repo: "o/r", labels: [], runUrl: "u", wait: async () => {} });
  assert.deepEqual(result, { ...nothing, failed: [{ target: "digest", error: "POST /repos/o/r/issues: HTTP 422" }] });
});

// Only the sweep's own issues can be adopted as the digest or rewritten: the
// listing names github-actions[bot] as creator, and a body the sweep did not
// write is dropped.
test("listSweepIssues lists only github-actions[bot]'s digest and finding issues, at most ten pages", async () => {
  const paths = [];
  const digest = { number: 1, body: "<!-- lane-sweep-digest -->\nx" };
  const call = async (method, path) => {
    paths.push(path);
    return [digest, { number: 2, body: "unrelated" }, { number: 3, pull_request: {}, body: digest.body }, ...Array.from({ length: 97 }, (_, i) => ({ number: 10 + i, body: "y" }))];
  };
  assert.deepEqual((await listSweepIssues({ call, repo: "o/r" })).map((i) => i.number), Array(10).fill(1));
  assert.equal(paths.length, 10);
  for (const path of paths) assert.equal(new URL(path, "https://x").searchParams.get("creator"), "github-actions[bot]");
});

// The 50-call budget is a hard stop: spend() throws before the request, and
// the throw ends the write before the PATCH that carries the new state.
test("a budget spent mid-rewrite stops before the PATCH and reports the failure", async () => {
  const s = store([{ number: 100, state: "open", state_reason: null, labels: [], body: "" }]);
  const budget = createBudget(1);
  const call = async (...args) => {
    budget.spend();
    return s.call(...args);
  };
  const plan = { action: "update", number: 100, entries: [{ fingerprint: FP, tracked: null, title: "t", text: "x" }], added: [], dropped: [] };
  const done = await writeDigest({ plan, call, repo: "o/r", labels: [], runUrl: "https://run/1", wait: async () => {} });
  assert.deepEqual(done.failed, [{ target: "#100", error: "call budget of 1 reached" }]);
  assert.deepEqual(s.calls.map(([m]) => m), ["POST"], "no DELETE, no PATCH");
});
