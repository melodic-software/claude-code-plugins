// Expected values come from the verdict rules in
// docs/conventions/pr-pipeline/README.md ("Verifier verdict"): the artifact is named pr-verify-<pr>-<head-sha>-<verdict>, the
// verdict JSON holds {pr, head_sha, base_sha, head_ref, linked_issues,
// verdict, summary, notes, run_id}, each linked issue records its author, and
// malformed output writes nothing.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { artifactName, buildVerdict, main } from "./write-verdict.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const ISSUE = {
  number: 7,
  author_login: "maintainer",
  author_id: 100,
  author_type: "User",
  last_edited_at: null,
  editor_login: null,
  editor_id: null,
  editor_type: null,
  spec_comments: [{ id: 1, updated_at: "2026-10-12T00:00:00Z" }],
};
const ids = { pr: "41", headSha: HEAD, baseSha: BASE, runId: "9001", headRef: "feat/x", linkedIssues: [ISSUE] };
const ok = JSON.stringify({ verdict: "pass", summary: "s", notes: [] });

test("each verdict names its artifact with the PR, the head and the verdict", () => {
  for (const verdict of ["pass", "pass-notes", "fail"]) {
    const built = buildVerdict({ ...ids, output: JSON.stringify({ verdict, summary: "s", notes: ["n"] }) });
    assert.deepEqual(built, {
      pr: 41,
      head_sha: HEAD,
      base_sha: BASE,
      head_ref: "feat/x",
      linked_issues: [ISSUE],
      verdict,
      summary: "s",
      notes: ["n"],
      run_id: 9001,
    });
    assert.equal(artifactName(built), `pr-verify-41-${HEAD}-${verdict}`);
  }
});

test("output outside the schema throws", () => {
  for (const output of [
    "",
    "not json",
    "[]",
    JSON.stringify({ verdict: "PASS", summary: "s", notes: [] }),
    JSON.stringify({ verdict: "pass", summary: 1, notes: [] }),
    JSON.stringify({ verdict: "pass", summary: "s", notes: "n" }),
    JSON.stringify({ verdict: "pass", summary: "s", notes: [1] }),
    JSON.stringify({ verdict: "pass", summary: "s" }),
    JSON.stringify({ verdict: "pass", summary: "s", notes: [], extra: true }),
  ]) {
    assert.throws(() => buildVerdict({ ...ids, output }), undefined, output);
  }
});

test("a malformed PR number, SHA, run id or head branch throws", () => {
  for (const bad of [{ pr: "0" }, { pr: "4x" }, { headSha: "A".repeat(40) }, { baseSha: "" }, { runId: "-1" }, { headRef: "a b" }, { headRef: "" }]) {
    assert.throws(() => buildVerdict({ ...ids, ...bad, output: ok }), undefined, JSON.stringify(bad));
  }
});

test("linked issues outside their schema throw", () => {
  for (const linkedIssues of [
    null,
    {},
    [{ ...ISSUE, number: 0 }],
    [{ ...ISSUE, author_login: 5 }],
    [{ ...ISSUE, author_id: "100" }],
    [{ ...ISSUE, author_type: 1 }],
    [{ ...ISSUE, editor_login: 5 }],
    [{ ...ISSUE, editor_id: "200" }],
    [{ ...ISSUE, editor_type: false }],
    [{ ...ISSUE, last_edited_at: 0 }],
    [{ ...ISSUE, spec_comments: null }],
    [{ ...ISSUE, spec_comments: [{ id: "1", updated_at: "t" }] }],
    [{ ...ISSUE, spec_comments: [{ id: 1, updated_at: null }] }],
    [{ ...ISSUE, spec_comments: [{ id: 1, updated_at: "t", body: "x" }] }],
    [{ ...ISSUE, extra: 1 }],
    [{ number: 7, author_login: "m", author_id: 1 }],
  ]) {
    assert.throws(() => buildVerdict({ ...ids, linkedIssues, output: ok }), undefined, JSON.stringify(linkedIssues));
  }
  assert.deepEqual(buildVerdict({ ...ids, linkedIssues: [], output: ok }).linked_issues, []);
  const edited = { ...ISSUE, last_edited_at: "2026-10-14T00:00:00Z", editor_login: "lanes", editor_id: 200, editor_type: "Bot" };
  assert.deepEqual(buildVerdict({ ...ids, linkedIssues: [edited], output: ok }).linked_issues, [edited]);
});

test("long model text is cut, not refused", () => {
  const built = buildVerdict({
    ...ids,
    output: JSON.stringify({ verdict: "pass-notes", summary: "x".repeat(5000), notes: Array(40).fill("y".repeat(1200)) }),
  });
  assert.equal(built.summary.length, 4000);
  assert.equal(built.notes.length, 30);
  assert.equal(built.notes[0].length, 1000);
});

test("main writes the verdict file and the artifact name, and nothing on bad output", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-"));
  const spec = path.join(dir, "spec.json");
  writeFileSync(spec, JSON.stringify([ISSUE]));
  const env = {
    PR_NUMBER: "41",
    HEAD_SHA: HEAD,
    BASE_SHA: BASE,
    HEAD_REF: "feat/x",
    SPEC_FILE: spec,
    GITHUB_RUN_ID: "9001",
    VERDICT_DIR: path.join(dir, "verdict"),
    GITHUB_OUTPUT: path.join(dir, "out"),
  };
  main({ ...env, STRUCTURED_OUTPUT: JSON.stringify({ verdict: "fail", summary: "wrong", notes: [] }) });
  const written = JSON.parse(readFileSync(path.join(env.VERDICT_DIR, "verdict.json"), "utf8"));
  assert.equal(written.verdict, "fail");
  assert.deepEqual(written.linked_issues, [ISSUE]);
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `name=pr-verify-41-${HEAD}-fail\nverdict=fail\n`);

  for (const [label, extra] of [
    ["bad output", { STRUCTURED_OUTPUT: "{}" }],
    ["unreadable spec", { STRUCTURED_OUTPUT: ok, SPEC_FILE: path.join(dir, "missing.json") }],
  ]) {
    const other = { ...env, VERDICT_DIR: path.join(dir, `none-${label}`), GITHUB_OUTPUT: path.join(dir, `out-${label}`), ...extra };
    assert.throws(() => main(other), undefined, label);
    assert.equal(existsSync(path.join(other.VERDICT_DIR, "verdict.json")), false, label);
    assert.equal(existsSync(other.GITHUB_OUTPUT), false, label);
  }
});
