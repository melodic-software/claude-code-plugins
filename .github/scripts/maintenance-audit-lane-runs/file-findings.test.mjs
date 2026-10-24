// The judge's output is untrusted: write-findings keeps at most three
// well-formed findings and names what it dropped; the filer drops any finding
// with a failed claim before planning, and stamps each kept one with its
// fingerprint.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { droppedLine, prepareItems, writeAll } from "./file-findings.mjs";
import { planFiling } from "./findings.mjs";
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

test("one failed write is recorded and the rest still file", async () => {
  const calls = [];
  const call = async (method, path, body) => {
    calls.push(path);
    if (body?.title === "fix: rejected") throw new Error(`${method} ${path}: HTTP 422`);
    return { number: 100 + calls.length };
  };
  const plan = {
    file: [
      { fingerprint: "aaaa", finding: finding({ title: "fix: rejected" }) },
      { fingerprint: "bbbb", finding: finding() },
    ],
    comment: [{ number: 7 }],
    reopen: [],
  };
  const result = await writeAll({ plan, call, repo: "o/r", labels: [], runUrl: "u", wait: async () => {} });
  assert.equal(calls.length, 3);
  assert.deepEqual(result, {
    filed: [102],
    commented: [7],
    reopened: [],
    failed: [{ target: "aaaa", error: "POST /repos/o/r/issues: HTTP 422" }],
  });
});

test("a reopen comments with the checked claims, re-triages, then sets the state open as reopened", async () => {
  const calls = [];
  const call = async (method, path, body) => {
    calls.push([method, path, body]);
    return {};
  };
  const plan = { file: [], comment: [], reopen: [{ number: 12, fingerprint: "cccc", finding: finding() }] };
  const labels = ["needs-triage", "source: lane-sweep"];
  let waits = 0;
  const result = await writeAll({ plan, call, repo: "o/r", labels, runUrl: "https://run/1", wait: async () => waits++ });
  assert.deepEqual(result, { filed: [], commented: [], reopened: [12], failed: [] });
  assert.deepEqual(
    calls.map(([method, path]) => `${method} ${path}`),
    [
      "POST /repos/o/r/issues/12/comments",
      "POST /repos/o/r/issues/12/labels",
      "DELETE /repos/o/r/issues/12/labels/agent-ready",
      "PATCH /repos/o/r/issues/12",
    ],
  );
  assert.equal(waits, 4);
  assert.match(calls[0][2].body, /https:\/\/run\/1/);
  assert.match(calls[0][2].body, /```text\na\.yml:1: if: true\n```/);
  assert.deepEqual(calls[1][2], { labels });
  assert.deepEqual(calls[3][2], { state: "open", state_reason: "reopened" });
});

test("a reopen with no filing labels skips the label POST, and a 404 on agent-ready is not a failure", async () => {
  const calls = [];
  const call = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (method === "DELETE") throw Object.assign(new Error(`${method} ${path}: HTTP 404`), { status: 404 });
    return {};
  };
  const plan = { file: [], comment: [], reopen: [{ number: 12, fingerprint: "cccc", finding: finding() }] };
  const result = await writeAll({ plan, call, repo: "o/r", labels: [], runUrl: "u", wait: async () => {} });
  assert.deepEqual(result, { filed: [], commented: [], reopened: [12], failed: [] });
  assert.deepEqual(calls, [
    "POST /repos/o/r/issues/12/comments",
    "DELETE /repos/o/r/issues/12/labels/agent-ready",
    "PATCH /repos/o/r/issues/12",
  ]);
});

test("a failed label removal other than 404 is recorded and leaves the issue closed for the next run", async () => {
  const fp = "0123456789abcdef";
  const issue = { number: 12, state: "closed", state_reason: "completed", body: `x\n<!-- lane-sweep:fp=${fp} -->` };
  const calls = [];
  const call = async (method, path, body) => {
    calls.push(`${method} ${path}`);
    if (method === "DELETE") throw Object.assign(new Error(`${method} ${path}: HTTP 500`), { status: 500 });
    if (method === "PATCH") Object.assign(issue, body);
    return {};
  };
  const items = [{ fingerprint: fp, finding: finding() }];
  const plan = planFiling({ items, existing: [issue], openNumbers: new Set() });
  const result = await writeAll({ plan, call, repo: "o/r", labels: [], runUrl: "u", wait: async () => {} });
  assert.deepEqual(result.reopened, []);
  assert.deepEqual(result.failed, [{ target: "#12", error: "DELETE /repos/o/r/issues/12/labels/agent-ready: HTTP 500" }]);
  assert.ok(!calls.includes("PATCH /repos/o/r/issues/12"));
  assert.equal(issue.state, "closed");
  assert.equal(issue.body, `x\n<!-- lane-sweep:fp=${fp} -->`);
  assert.deepEqual(
    planFiling({ items, existing: [issue], openNumbers: new Set() }).reopen.map((r) => r.number),
    [12],
  );
});

test("a failed reopen comment skips its PATCH and is recorded", async () => {
  const calls = [];
  const call = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (method === "POST") throw new Error(`${method} ${path}: HTTP 500`);
    return {};
  };
  const plan = { file: [], comment: [], reopen: [{ number: 12, fingerprint: "cccc", finding: finding() }] };
  const result = await writeAll({ plan, call, repo: "o/r", labels: [], runUrl: "u", wait: async () => {} });
  assert.deepEqual(calls, ["POST /repos/o/r/issues/12/comments"]);
  assert.deepEqual(result.failed, [{ target: "#12", error: "POST /repos/o/r/issues/12/comments: HTTP 500" }]);
});
