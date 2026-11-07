// The judge's output is untrusted: write-findings keeps at most three
// well-formed findings and names what it dropped; the filer drops any finding
// with a failed claim before planning, stamps each kept one with its
// fingerprint, and writes them into one rolling digest issue.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { createBudget } from "./collect.mjs";
import * as fileFindings from "./file-findings.mjs";
import { droppedLine, listSweepIssues, prepareItems, writeDigest } from "./file-findings.mjs";
import { planDigest, renderDigest, renderEntry } from "./findings.mjs";
import { parseJudgeOutput } from "./write-findings.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { statusWriter } from "../../actions/resolve-config/write-status.mjs";

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
  const dir = tempDir("lane-sweep-write-");
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
  const base = tempDir("lane-sweep-file-");
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = tempDir("lane-sweep-findings-");
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
  const dir = tempDir("lane-sweep-units-");
  for (const unit of units) writeFileSync(join(dir, `${unit.id}.json`), JSON.stringify(unit));
  return dir;
}

// One finding per unit through prepareItems; returns what survived and what was dropped.
function prepareOne(t, unitData, over) {
  const base = tempDir("lane-sweep-file-");
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = tempDir("lane-sweep-findings-");
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

test("a finding naming a job absent from its A unit's failed jobs is dropped", (t) => {
  const { items, dropped } = prepareOne(t, aUnit(), { slice: "A", workflow: ".github/workflows/pr-ci.yml", job: "deploy" });
  assert.equal(items.length, 0);
  assert.deepEqual(dropped, [{ unit: "a1", title: finding().title, reason: "job-not-in-unit" }]);
});

test("a workflow-level finding on a D unit with green samples is kept", (t) => {
  const { items, dropped } = prepareOne(t, dUnit(), { job: "deploy", signature: "duplicate runs for one head" });
  assert.equal(items.length, 1);
  assert.deepEqual(dropped, []);
});

test("a finding naming a slice other than its unit's is dropped", (t) => {
  const { items, dropped } = prepareOne(t, aUnit(), { slice: "C", workflow: ".github/workflows/pr-ci.yml", job: "lint" });
  assert.equal(items.length, 0);
  assert.deepEqual(dropped, [{ unit: "a1", title: finding().title, reason: "slice-not-unit" }]);
});

test("a finding that matches its unit's workflow, and an A unit's failed job, passes", (t) => {
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
  const base = tempDir("lane-sweep-file-");
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = tempDir("lane-sweep-findings-");
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

test("a lone findings artifact downloaded straight into the directory is read", (t) => {
  const base = tempDir("lane-sweep-file-");
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = tempDir("lane-sweep-findings-");
  const units = writeUnits([]);
  t.after(() => {
    for (const d of [base, dir, units]) rmSync(d, { recursive: true, force: true });
  });
  writeFileSync(join(dir, "findings.json"), JSON.stringify({ unit: "d1", findings: [finding()] }));
  const { dropped } = prepareItems({ findingsDir: dir, unitsDir: units, baseDir: base });
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
  const base = tempDir("lane-sweep-file-");
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = tempDir("lane-sweep-findings-");
  const units = tempDir("lane-sweep-units-");
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
  const base = tempDir("lane-sweep-file-");
  const dir = tempDir("lane-sweep-findings-");
  const out = tempDir("lane-sweep-units-");
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

// An earlier digest holding three entries the new sweep does not see: one
// whose Where block names pr-verify-capture.yml, one naming pr-merge.yml,
// and one tracked elsewhere, which has no Where block. The sweep is run
// through prepareItems and planDigest as main() wires them.
const CAPTURE = ".github/workflows/pr-verify-capture.yml";
const MERGE = ".github/workflows/pr-merge.yml";
const E_CAPTURE = "00000000000000e1";
const E_MERGE = "00000000000000e2";
const E_TRACKED = "00000000000000e3";
const E_C = "00000000000000e4";
function carrySweep(t, { status, units, findings }) {
  const base = tempDir("lane-sweep-file-");
  const dir = tempDir("lane-sweep-findings-");
  const out = tempDir("lane-sweep-units-");
  t.after(() => {
    for (const d of [base, dir, out]) rmSync(d, { recursive: true, force: true });
  });
  const unitsDir = join(out, "units");
  mkdirSync(unitsDir);
  for (const unit of units) writeFileSync(join(unitsDir, `${unit.id}.json`), JSON.stringify(unit));
  for (const [name, data] of Object.entries(findings)) {
    mkdirSync(join(dir, name));
    writeFileSync(join(dir, name, "findings.json"), typeof data === "string" ? data : JSON.stringify(data));
  }
  const statusPath = join(out, "collect-status.json");
  if (status !== undefined) writeFileSync(statusPath, JSON.stringify(status));
  const prepared = prepareItems({ findingsDir: dir, baseDir: base, unitsDir, statusPath });
  const earlier = [
    [E_CAPTURE, { slice: "A", workflow: CAPTURE, job: "capture" }, null],
    [E_MERGE, { slice: "A", workflow: MERGE, job: "merge" }, null],
    [E_TRACKED, { slice: "A", workflow: MERGE, job: "merge" }, 9000],
    [E_C, { slice: "C", workflow: ".github/workflows/pr-ci.yml", job: "pr" }, null],
  ].map(([fp, over, tracked]) => ({ fingerprint: fp, tracked, title: "t", text: renderEntry({ fingerprint: fp, finding: finding(over), tracked }) }));
  const digestIssue = { number: 50, state: "open", state_reason: null, body: renderDigest(earlier, "https://run/0") };
  const plan = planDigest({
    items: prepared.items,
    existing: [digestIssue],
    openNumbers: new Set(),
    complete: prepared.complete,
    carry: prepared.carry,
  });
  return {
    complete: prepared.complete,
    kept: plan.entries.map((e) => e.fingerprint).sort(),
    dropped: plan.dropped.map((e) => e.fingerprint).sort(),
    reasons: Object.fromEntries((plan.carried ?? []).map((c) => [c.fingerprint, c.reason])),
    plan,
  };
}
const ciUnit = { id: "a1", slice: "A", workflow: ".github/workflows/pr-ci.yml" };
const readA1 = { "findings-a1": { unit: "a1", findings: [] } };

test("a partly read workflow carries only the unseen entries naming it; a fully read one drops", (t) => {
  const sweep = carrySweep(t, {
    status: { complete: false, truncated: null, partial: [MERGE] },
    units: [ciUnit],
    findings: readA1,
  });
  assert.equal(sweep.complete, false);
  assert.ok(sweep.dropped.includes(E_CAPTURE), "the pr-verify-capture.yml entry drops: that workflow was read in full");
  assert.ok(sweep.kept.includes(E_MERGE), "the pr-merge.yml entry carries: that workflow was read in part");
  assert.ok(sweep.kept.includes(E_TRACKED), "an entry naming no workflow carries");
  assert.deepEqual(sweep.kept, [E_MERGE, E_TRACKED]);
  assert.deepEqual(sweep.dropped, [E_CAPTURE, E_C]);
  assert.deepEqual(sweep.reasons, { [E_MERGE]: "partial-window", [E_TRACKED]: "no-workflow" });
  assert.equal(
    fileFindings.carriedNote(sweep.plan.carried),
    "2 earlier entries carried over: 1 partial-window, 1 no-workflow",
  );
});

test("a collector that stopped early, or left no readable status, carries every unseen entry", (t) => {
  const all = [E_CAPTURE, E_MERGE, E_TRACKED, E_C];
  const stopped = carrySweep(t, {
    status: { complete: false, truncated: "stopped at unit d2: call budget", partial: [MERGE] },
    units: [ciUnit],
    findings: readA1,
  });
  assert.deepEqual(stopped.kept, all);
  assert.deepEqual(new Set(Object.values(stopped.reasons)), new Set(["collector-stopped"]));
  const missing = carrySweep(t, { status: undefined, units: [ciUnit], findings: readA1 });
  assert.deepEqual(missing.kept, all);
  assert.deepEqual(new Set(Object.values(missing.reasons)), new Set(["collector-status-unreadable"]));
});

test("a unit whose findings were not read carries the unseen entries of its slice and workflow", (t) => {
  const unparsable = { unit: "a2", findings: [], dropped: [{ index: null, reason: "unparsable" }] };
  const sweep = carrySweep(t, {
    status: { complete: true, truncated: null, partial: [] },
    units: [ciUnit, { id: "a2", slice: "A", workflow: CAPTURE }],
    findings: { ...readA1, "findings-a2": unparsable },
  });
  assert.deepEqual(sweep.kept, [E_CAPTURE, E_TRACKED]);
  assert.deepEqual(sweep.reasons, { [E_CAPTURE]: "unit-unread", [E_TRACKED]: "no-workflow" });

  const unreadC = carrySweep(t, {
    status: { complete: true, truncated: null, partial: [] },
    units: [ciUnit, { id: "c1", slice: "C" }],
    findings: readA1,
  });
  assert.deepEqual(unreadC.kept, [E_TRACKED, E_C], "an unread C unit binds no workflow, so every C entry carries");

  const unreadable = carrySweep(t, {
    status: { complete: true, truncated: null, partial: [] },
    units: [ciUnit],
    findings: { ...readA1, "findings-a2": "not json" },
  });
  assert.deepEqual(unreadable.kept, [E_CAPTURE, E_MERGE, E_TRACKED, E_C], "an unreadable findings file names no unit, so all carry");
});

test("a complete sweep drops every unseen entry, one naming no workflow included", (t) => {
  const sweep = carrySweep(t, { status: { complete: true, truncated: null, partial: [] }, units: [ciUnit], findings: readA1 });
  assert.equal(sweep.complete, true);
  assert.deepEqual(sweep.kept, []);
  assert.deepEqual(sweep.dropped, [E_CAPTURE, E_MERGE, E_TRACKED, E_C]);
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
    return {};
  };
  return { issues, calls, call };
};
const ROOT = new URL("../../..", import.meta.url).pathname;
// The org Work status field and the option ids it maps, written by hand.
const FIELD = 48484079;
const OPTION = { "needs-triage": 84879216, "needs-owner-decision": 84879218, "agent-ready": 84879220 };
const HUMAN = 153232337;
// One issue's Work status field reading `state`, last set by account `setter`,
// behind a real statusWriter. A POST sets it as the lanes App, or throws
// `postError`; `written` lists the states POSTed.
function workStatus(state, setter, postError) {
  const written = [];
  const value = () => (state === null ? [] : [{ issue_field_id: FIELD, single_select_option: { id: OPTION[state] } }]);
  const github = async (method, path, body) => {
    if (method === "GET" && path.endsWith("/issue-field-values")) return value();
    if (method === "POST" && path === "/graphql") {
      const nodes = state === null ? [] : [{ __typename: "IssueFieldAddedEvent", value: state, actor: { databaseId: setter }, issueField: { fullDatabaseId: String(FIELD) } }];
      return { data: { repository: { issue: { timelineItems: { nodes } } } } };
    }
    if (method === "POST" && path.endsWith("/issue-field-values")) {
      if (postError) throw postError;
      state = body.issue_field_values[0].value;
      written.push(state);
      setter = 337595936;
      return value();
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { written, writer: () => statusWriter({ env: { BASE_PATH: ROOT }, github, repository: "o/r" }) };
}
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
    s.calls.slice(-2).map(([m, p]) => `${m} ${p}`),
    ["POST /repos/o/r/issues/100/comments", "PATCH /repos/o/r/issues/100"],
  );
  assert.ok(!s.calls.some(([m]) => m === "DELETE"), "no label DELETE: the Work status field takes agent-ready off");
  assert.match(s.calls.at(-2)[2].body, /New:\n\n- fix\(ci\): another/);
  assert.match(s.calls.at(-2)[2].body, /No longer seen:\n\n- fix\(ci\): skip the dispatch/);
  assert.ok(!s.issues[0].body.includes(FP), "the fixed finding dropped off");

  assert.deepEqual(await run(s, []), { ...nothing, updated: [100] });
  assert.equal(s.issues[0].state, "closed");
  assert.deepEqual(await run(s, []), nothing);

  assert.deepEqual(await run(s, [a]), { ...nothing, reopened: [100] });
  assert.equal(s.issues[0].state, "open");
  assert.equal(s.issues.length, 1);
});

test("a rewrite takes agent-ready off through the Work status field before the PATCH", async () => {
  const log = [];
  const call = async (method) => (log.push(method), {});
  const leaveAgentReady = async (number, state, options) => log.push(["FIELD", number, state, options]);
  const plan = { action: "update", number: 100, entries: [{ fingerprint: FP, tracked: null, title: "t", text: "x" }], added: [], dropped: [] };
  const done = await writeDigest({ plan, call, repo: "o/r", labels: [], runUrl: "https://run/1", leaveAgentReady, wait: async () => {} });
  assert.deepEqual(done.updated, [100]);
  assert.deepEqual(log, ["POST", ["FIELD", 100, "needs-triage", { orUnset: true }], "PATCH"]);
});

test("a rewrite whose Work status write fails leaves the PATCH for the next run", async () => {
  const log = [];
  const call = async (method) => (log.push(method), {});
  const leaveAgentReady = async () => {
    throw new Error("#100's Work status field could not be read: HTTP 502");
  };
  const plan = { action: "update", number: 100, entries: [{ fingerprint: FP, tracked: null, title: "t", text: "x" }], added: [], dropped: [] };
  const done = await writeDigest({ plan, call, repo: "o/r", labels: [], runUrl: "https://run/1", leaveAgentReady, wait: async () => {} });
  assert.deepEqual(done.updated, []);
  assert.deepEqual(done.failed, [{ target: "#100", error: "#100's Work status field could not be read: HTTP 502" }]);
  assert.deepEqual(log, ["POST"]);
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

const rewriteWith = async (s, leaveAgentReady) => {
  const items = [{ fingerprint: "fedcba9876543210", finding: finding() }];
  const plan = planDigest({ items, existing: s.issues, openNumbers: new Set() });
  const done = await writeDigest({ plan, call: s.call, repo: "o/r", labels: [], runUrl: "u", leaveAgentReady, wait: async () => {} });
  return { done, next: planDigest({ items, existing: s.issues, openNumbers: new Set() }).action };
};

for (const [why, state, setter, written] of [
  ["an unset field", null, undefined, ["needs-triage"]],
  ["a field at agent-ready", "agent-ready", HUMAN, ["needs-triage"]],
  ["a person's needs-owner-decision", "needs-owner-decision", HUMAN, []],
]) {
  test(`a rewrite with ${why} writes Work status ${written.join() || "nothing"} and deletes no label`, async () => {
    const s = store();
    await run(s, [{ fingerprint: FP, finding: finding() }]);
    s.issues[0].labels.push("agent-ready");
    const f = workStatus(state, setter);
    const { done } = await rewriteWith(s, (await f.writer()).leaveAgentReady);
    assert.deepEqual(done, { ...nothing, updated: [100] });
    assert.deepEqual(f.written, written);
    assert.ok(!s.calls.some(([m]) => m === "DELETE"), "agent-ready comes off through the field, never a label DELETE");
  });
}

test("a rewrite whose Work status write fails reports it and leaves the old state to retry", async () => {
  const s = store();
  await run(s, [{ fingerprint: FP, finding: finding() }]);
  const old = s.issues[0].body;
  const f = workStatus(null, undefined, new Error("HTTP 500"));
  const { done, next } = await rewriteWith(s, (await f.writer()).leaveAgentReady);
  assert.deepEqual(done.updated, []);
  assert.equal(done.failed.length, 1);
  assert.equal(done.failed[0].target, "#100");
  assert.match(done.failed[0].error, /^#100's Work status field was not set to `needs-triage`: HTTP 500/);
  assert.equal(s.issues[0].body, old);
  assert.equal(next, "update");
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
  assert.deepEqual(s.calls.map(([m]) => m), ["POST"], "no PATCH");
});
