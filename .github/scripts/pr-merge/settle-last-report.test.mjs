import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../lib/test-tmp.mjs";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const SCRIPT = join(root, ".github/scripts/pr-merge/settle-last-report.sh");
const SETTLE_PY = join(root, "plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py");
const SHA = "c".repeat(40);

const settleLast = ({ code = "0", files = true, sha = SHA, settle = 0, args = [], sleep = 0, timeout } = {}) => {
  const dir = tempDir("settle-last-report-");
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const calls = join(dir, "calls");
  writeFileSync(
    join(bin, "python3"),
    `#!/usr/bin/env bash\necho "$@" >>'${calls}'\n${sleep ? `exec sleep ${sleep}` : ""}\necho '{"reuse": ${settle === 0}}'\nexit ${settle}\n`,
  );
  chmodSync(join(bin, "python3"), 0o755);
  const report = join(dir, "post-merge");
  mkdirSync(report);
  if (files) {
    writeFileSync(join(report, "post-merge.json"), "{}");
    writeFileSync(join(report, "post-merge-code"), `${code}\n`);
    if (sha !== null) writeFileSync(join(report, "post-merge-code-sha"), `${sha}\n`);
  }
  const env = { PATH: `${bin}:${process.env.PATH}`, REPO: "o/r" };
  if (timeout !== undefined) env.SETTLE_TIMEOUT = String(timeout);
  const run = spawnSync("bash", ["--noprofile", "--norc", SCRIPT, report, ...args], { env, encoding: "utf8" });
  return {
    report,
    status: run.status,
    stdout: run.stdout,
    calls: existsSync(calls) ? readFileSync(calls, "utf8").trim().split("\n") : [],
  };
};

test("a passing report that settle --idle-tick keeps stands", () => {
  for (const code of ["0", "5"]) {
    const run = settleLast({ code });
    assert.equal(run.status, 0, `exit ${code}`);
    assert.deepEqual(run.calls, [`${SETTLE_PY} settle --idle-tick --repo o/r --postmerge-result ${run.report}/post-merge.json --code-sha ${SHA}`], `exit ${code}`);
    assert.equal(run.stdout, '{"reuse": true}\n', "settle's answer is printed for the caller");
  }
});

test("a report settle refuses, or that settle cannot read, does not stand", () => {
  assert.equal(settleLast({ settle: 1 }).status, 1);
  assert.notEqual(settleLast({ settle: 2 }).status, 0);
});

test("a report from a check that did not pass, or with no report or code, is refused before settle", () => {
  for (const [why, options] of [
    ["a failed lane merge", { code: "1" }],
    ["a check that could not judge", { code: "3" }],
    ["a rate-limit stop", { code: "75" }],
    ["an empty code", { code: "" }],
    ["no report", { files: false }],
  ]) {
    const run = settleLast(options);
    assert.equal(run.status, 1, why);
    assert.deepEqual(run.calls, [], `${why}: settle is not called`);
  }
});

test("a report with no commit kept is offered with an empty one, which settle refuses as code-changed", () => {
  assert.match(settleLast({ sha: null }).calls[0], / --code-sha$/);
});

test("extra arguments go to settle", () => {
  assert.match(settleLast({ args: ["--probe-unmoved"] }).calls[0], new RegExp(` --code-sha ${SHA} --probe-unmoved$`));
});

test("with SETTLE_TIMEOUT a stalled settle is cut off and the report does not stand", () => {
  const started = Date.now();
  const run = settleLast({ sleep: 10, timeout: 1 });
  assert.notEqual(run.status, 0);
  assert.ok(Date.now() - started < 8000, "cut off at the limit, not after settle's 10 s");
  assert.equal(settleLast({ sleep: 0, timeout: 5 }).status, 0, "a settle inside the limit still stands");
});
