// The judge's output is untrusted: write-findings keeps at most three
// well-formed findings and names what it dropped; the filer drops any finding
// with a failed claim before planning, stamps each kept one with its
// fingerprint, and writes them into one rolling digest issue.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { droppedLine, prepareItems, writeDigest } from "./file-findings.mjs";
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

test("a finding with any failed claim is dropped before planning", (t) => {
  const base = mkdtempSync(join(tmpdir(), "lane-sweep-file-"));
  writeFileSync(join(base, "a.yml"), "if: true\n");
  const dir = mkdtempSync(join(tmpdir(), "lane-sweep-findings-"));
  t.after(() => {
    rmSync(base, { recursive: true, force: true });
    rmSync(dir, { recursive: true, force: true });
  });
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
  const { items, dropped } = prepareItems({ findingsDir: dir, baseDir: base });
  assert.equal(items.length, 1);
  assert.match(items[0].fingerprint, /^[0-9a-f]{16}$/);
  assert.deepEqual(dropped, [{ unit: "d1", title: finding().title, reason: "a.yml:1 quote-not-on-line" }]);
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
