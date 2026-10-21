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

test("a reopen comments with the checked claims, then sets the state open as reopened", async () => {
  const calls = [];
  const call = async (method, path, body) => {
    calls.push([method, path, body]);
    return {};
  };
  const plan = { file: [], comment: [], reopen: [{ number: 12, fingerprint: "cccc", finding: finding() }] };
  const result = await writeAll({ plan, call, repo: "o/r", labels: [], runUrl: "https://run/1", wait: async () => {} });
  assert.deepEqual(result, { filed: [], commented: [], reopened: [12], failed: [] });
  assert.deepEqual(
    calls.map(([method, path]) => `${method} ${path}`),
    ["POST /repos/o/r/issues/12/comments", "PATCH /repos/o/r/issues/12"],
  );
  assert.match(calls[0][2].body, /https:\/\/run\/1/);
  assert.match(calls[0][2].body, /```text\na\.yml:1: if: true\n```/);
  assert.deepEqual(calls[1][2], { state: "open", state_reason: "reopened" });
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
