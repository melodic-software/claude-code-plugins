import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import {
  isMergeRiskTitle,
  isPrRefineTitle,
  isPrUnblockTitle,
  isPrVerifyCaptureTitle,
  mergeRiskTitle,
  PR_MERGE_TITLE,
  PR_UNBLOCK_TITLE,
  PR_VERIFY_CAPTURE_TITLE,
  PREFIXES,
  prMergeTitle,
  prRefineTitle,
  prUnblockTitle,
  prVerifyCaptureTitle,
} from "./run-title.mjs";

const HEAD = "a".repeat(40);
const runName = (workflow) => /^run-name: (.*)$/m.exec(readFileSync(new URL(`../../workflows/${workflow}`, import.meta.url), "utf8"))?.[1];

test("each prefix is letters, spaces and dashes, so it reads as itself inside a pattern, and no two workflows share one", () => {
  const all = Object.values(PREFIXES).flat();
  for (const prefix of all) assert.match(prefix, /^[A-Za-z][A-Za-z -]*[A-Za-z]$/);
  assert.equal(new Set(all).size, all.length);
});

test("each workflow's run-name writes what its builder builds", () => {
  assert.equal(runName("pr-merge.yml"), `"\${{ inputs.pr && format('${prMergeTitle("{0}")}', inputs.pr) || '' }}"`);
  assert.equal(
    runName("pr-rate-merge-risk.yml"),
    `"${mergeRiskTitle("${{ github.event.workflow_run.pull_requests[0].number || 'none' }}", "${{ github.event.workflow_run.head_sha }}")}"`,
  );
  assert.equal(runName("pr-refine.yml"), `"${prRefineTitle("${{ inputs.activity }}", "${{ inputs.pr-number }}")}"`);
  assert.equal(runName("pr-unblock.yml"), `"${prUnblockTitle("${{ inputs.activity }}", "${{ inputs.pr-number }}")}"`);
  assert.equal(runName("pr-verify-capture.yml"), prVerifyCaptureTitle("${{ github.event.workflow_run.id }}", "${{ github.event.workflow_run.head_sha }}"));
});

test("pr-merge.yml: both prefixes read, the capture is the input as given, and a near miss reads as no dispatch", () => {
  assert.equal(PR_MERGE_TITLE.exec("pr-merge: arm #42")?.[1], "42");
  assert.equal(PR_MERGE_TITLE.exec("PR Merge: arm #42")?.[1], "42");
  assert.equal(PR_MERGE_TITLE.exec("PR Merge: arm #4\n2")?.[1], "4\n2");
  for (const near of ["PR Merge", "pr-merge", "Pr Merge: arm #42", "pr merge: arm #42", "PR MERGE: arm #42", "PR Unblock: arm #42", "PR Merge: arm 42", "x PR Merge: arm #42"]) {
    assert.equal(PR_MERGE_TITLE.exec(near), null, near);
  }
  assert.equal(prMergeTitle(PR_MERGE_TITLE.exec(prMergeTitle(42))[1]), prMergeTitle(42));
});

test("pr-rate-merge-risk.yml: both prefixes match their PR and head, and nothing else", () => {
  assert.ok(isMergeRiskTitle(`merge-risk #7 ${HEAD}`, 7, HEAD));
  assert.ok(isMergeRiskTitle(`PR Rate Merge Risk #7 ${HEAD}`, 7, HEAD));
  assert.ok(isMergeRiskTitle(mergeRiskTitle(7, HEAD), 7, HEAD));
  for (const near of [`pr rate merge risk #7 ${HEAD}`, `Merge-Risk #7 ${HEAD}`, `PR Refine #7 ${HEAD}`, `PR Rate Merge Risk 7 ${HEAD}`, `PR Rate Merge Risk #8 ${HEAD}`, undefined]) {
    assert.equal(isMergeRiskTitle(near, 7, HEAD), false, near);
  }
});

test("pr-refine.yml: both prefixes match their activity and PR, and nothing else", () => {
  assert.ok(isPrRefineTitle("pr-refine fix-docs #7", "fix-docs", 7));
  assert.ok(isPrRefineTitle("PR Refine fix-docs #7", "fix-docs", 7));
  assert.ok(isPrRefineTitle(prRefineTitle("fix-docs", 7), "fix-docs", 7));
  for (const near of ["pr refine fix-docs #7", "PR REFINE fix-docs #7", "PR Unblock fix-docs #7", "pr-unblock fix-docs #7", "PR Refine fix-docs 7", "PR Refine fix-marker #7"]) {
    assert.equal(isPrRefineTitle(near, "fix-docs", 7), false, near);
  }
});

test("pr-unblock.yml: both prefixes match and parse to the same activity and PR, and a near miss does neither", () => {
  for (const title of ["pr-unblock resolve-conflicts #9", "PR Unblock resolve-conflicts #9"]) {
    assert.ok(isPrUnblockTitle(title, "resolve-conflicts", 9), title);
    assert.deepEqual(PR_UNBLOCK_TITLE.exec(title)?.slice(1), ["resolve-conflicts", "9"], title);
  }
  const [, activity, number] = PR_UNBLOCK_TITLE.exec(prUnblockTitle("address-feedback", 42));
  assert.equal(prUnblockTitle(activity, number), prUnblockTitle("address-feedback", 42));
  for (const near of ["pr unblock fix-ci #9", "Pr Unblock fix-ci #9", "PR Refine fix-ci #9", "pr-refine fix-ci #9", "PR Unblock fix-ci 9", "PR Unblock fix-ci #09", "PR Unblock Fix-CI #9", "PR Unblock fix-ci #9 "]) {
    assert.equal(PR_UNBLOCK_TITLE.exec(near), null, near);
    assert.equal(isPrUnblockTitle(near, "fix-ci", 9), false, near);
  }
});

test("pr-verify-capture.yml: both prefixes match and parse to the same run and head, and a near miss does neither", () => {
  for (const title of [`pr-verify-capture 812 ${HEAD}`, `PR Verify Capture 812 ${HEAD}`]) {
    assert.ok(isPrVerifyCaptureTitle(title, 812, HEAD), title);
    assert.deepEqual(PR_VERIFY_CAPTURE_TITLE.exec(title)?.slice(1), ["812", HEAD], title);
  }
  const [, runId, head] = PR_VERIFY_CAPTURE_TITLE.exec(prVerifyCaptureTitle(812, HEAD));
  assert.equal(prVerifyCaptureTitle(runId, head), prVerifyCaptureTitle(812, HEAD));
  for (const near of [`pr verify capture 812 ${HEAD}`, `PR VERIFY CAPTURE 812 ${HEAD}`, `PR Unblock 812 ${HEAD}`, `PR Verify Capture ${HEAD}`, `PR Verify Capture 812 ${HEAD.toUpperCase()}`, `PR Verify Capture 812 ${HEAD}x`]) {
    assert.equal(PR_VERIFY_CAPTURE_TITLE.exec(near), null, near);
    assert.equal(isPrVerifyCaptureTitle(near, 812, HEAD), false, near);
  }
});
