// The judge's output is untrusted: write-findings keeps at most three
// well-formed findings and names what it dropped; the filer drops any finding
// with a failed claim before planning, and stamps each kept one with its
// fingerprint.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { checkBornTriaged } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { droppedLine, FILING_LABELS, prepareItems, writeAll } from "./file-findings.mjs";
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

test("a filed fix issue is born triaged: marker, Bug type, confirmed status and high priority, no needs-triage", async () => {
  const calls = [];
  const call = async (method, path, body) => {
    calls.push(body);
    return { number: 1 };
  };
  const plan = { file: [{ fingerprint: "aaaa", finding: finding() }], comment: [], reopen: [] };
  await writeAll({ plan, call, repo: "o/r", labels: FILING_LABELS, runUrl: "u", wait: async () => {} });
  const [filed] = calls;
  assert.equal(filed.type, "Bug");
  assert.ok(filed.labels.includes("status: confirmed"));
  assert.ok(filed.labels.includes("priority: high"));
  assert.ok(!filed.labels.includes("needs-triage"));
  const issue = { body: filed.body, user: { id: 7 }, type: { name: filed.type }, labels: filed.labels.map((name) => ({ name })) };
  const list = { version: 1, actors: [{ id: 7, kind: "human" }] };
  assert.deepEqual(checkBornTriaged({ issue, list }), { skip: "true", reason: "born-triaged" });
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
