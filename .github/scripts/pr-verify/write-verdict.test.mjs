// Expected values come from issue #7702 (Scope) and pr-verify.yml's design:
// the artifact is named pr-verify-<pr>-<head-sha>-<pass|pass-notes|fail>, the
// verdict JSON holds {pr, head_sha, base_sha, verdict, summary, notes, run_id},
// and schema-invalid output writes nothing.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { artifactName, buildVerdict, main } from "./write-verdict.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const ids = { pr: "41", headSha: HEAD, baseSha: BASE, runId: "9001" };

test("each verdict names its artifact with the PR, the head and the verdict", () => {
  for (const verdict of ["pass", "pass-notes", "fail"]) {
    const built = buildVerdict({ ...ids, output: JSON.stringify({ verdict, summary: "s", notes: ["n"] }) });
    assert.deepEqual(built, { pr: 41, head_sha: HEAD, base_sha: BASE, verdict, summary: "s", notes: ["n"], run_id: 9001 });
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

test("a malformed PR number, SHA or run id throws", () => {
  const output = JSON.stringify({ verdict: "pass", summary: "s", notes: [] });
  for (const bad of [{ pr: "0" }, { pr: "4x" }, { headSha: "A".repeat(40) }, { baseSha: "" }, { runId: "-1" }]) {
    assert.throws(() => buildVerdict({ ...ids, ...bad, output }), undefined, JSON.stringify(bad));
  }
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
  const env = {
    PR_NUMBER: "41",
    HEAD_SHA: HEAD,
    BASE_SHA: BASE,
    GITHUB_RUN_ID: "9001",
    VERDICT_DIR: path.join(dir, "verdict"),
    GITHUB_OUTPUT: path.join(dir, "out"),
  };
  main({ ...env, STRUCTURED_OUTPUT: JSON.stringify({ verdict: "fail", summary: "wrong", notes: [] }) });
  assert.equal(JSON.parse(readFileSync(path.join(env.VERDICT_DIR, "verdict.json"), "utf8")).verdict, "fail");
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `name=pr-verify-41-${HEAD}-fail\nverdict=fail\n`);

  const other = { ...env, VERDICT_DIR: path.join(dir, "none"), GITHUB_OUTPUT: path.join(dir, "out2") };
  assert.throws(() => main({ ...other, STRUCTURED_OUTPUT: "{}" }));
  assert.equal(existsSync(path.join(other.VERDICT_DIR, "verdict.json")), false);
  assert.equal(existsSync(other.GITHUB_OUTPUT), false);
});
