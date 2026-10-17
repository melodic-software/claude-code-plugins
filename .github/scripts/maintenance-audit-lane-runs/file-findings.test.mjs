// The judge's output is untrusted: write-findings keeps at most three
// well-formed findings and names what it dropped; the filer drops any finding
// with a failed claim before planning, and stamps each kept one with its
// fingerprint.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { prepareItems } from "./file-findings.mjs";
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
