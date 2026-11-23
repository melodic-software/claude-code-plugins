import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { commitMessage, loadRules, rowFor } from "../apply-patch/apply-patch.mjs";
import { main, planDeclarations, readTrace, traceGaps, traceOnlyFailure } from "./declare-test-scope.mjs";
import { declarationRefusal } from "./test-scope.mjs";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const git = (cwd, args) => execFileSync("git", args, { cwd, encoding: "utf8" }).trim();

function scratch(t, prefix = "declare-test-scope-") {
  const dir = tempDir(prefix);
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function repo(t, files) {
  const dir = scratch(t);
  git(dir, ["init", "-q", "-b", "main"]);
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(join(dir, dirname(path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  git(dir, ["add", "-A"]);
  git(dir, ["-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "-m", "c"]);
  return { dir, head: git(dir, ["rev-parse", "HEAD"]) };
}

function traceDir(t, { gaps, suites, verdicts = "" }) {
  const dir = scratch(t);
  writeFileSync(join(dir, "gaps.tsv"), gaps);
  writeFileSync(join(dir, "suites.tsv"), suites);
  writeFileSync(join(dir, "verdicts.tsv"), verdicts);
  return dir;
}

const job = (name, conclusion, steps = []) => ({ name, conclusion, steps: steps.map(([stepName, stepConclusion]) => ({ name: stepName, conclusion: stepConclusion })) });
const SETUP = [["Check out", "success"], ["Install", "success"]];

test("traceOnlyFailure takes a run whose one failed job is Test Selection, failed first at the trace step", () => {
  const run = { conclusion: "failure" };
  const trace = job("Test Selection", "failure", [...SETUP, ["Trace the changed suites", "failure"], ["Upload the trace report", "success"]]);
  assert.equal(traceOnlyFailure({ run, jobs: [job("Lint", "success"), trace, job("CI Status", "failure")] }), true);
  assert.equal(traceOnlyFailure({ run, jobs: [job("Lint", "failure"), trace] }), false, "another lane failed too");
  assert.equal(traceOnlyFailure({ run, jobs: [job("Test Selection", "failure", [["Check out", "success"], ["Install", "failure"], ["Trace the changed suites", "failure"]])] }), false, "an earlier step failed");
  assert.equal(traceOnlyFailure({ run, jobs: [job("Test Selection", "cancelled", [...SETUP, ["Trace the changed suites", "failure"]])] }), false, "cancelled, not failed");
  assert.equal(traceOnlyFailure({ run: { conclusion: "success" }, jobs: [trace] }), false);
});

test("readTrace refuses a carriage return, a short row and a symbolic link as test-scope-invalid", (t) => {
  assert.equal(readTrace(traceDir(t, { gaps: "a.test.sh\tx.sh\tselects no suite\r\n", suites: "a.test.sh\t0\n" })).reason, "test-scope-invalid");
  assert.equal(readTrace(traceDir(t, { gaps: "a.test.sh\tx.sh\n", suites: "a.test.sh\t0\n" })).reason, "test-scope-invalid");
  const linked = traceDir(t, { gaps: "", suites: "" });
  rmSync(join(linked, "gaps.tsv"));
  symlinkSync("/etc/hostname", join(linked, "gaps.tsv"));
  assert.equal(readTrace(linked).reason, "test-scope-invalid");
  assert.deepEqual(readTrace(traceDir(t, { gaps: "a.test.sh\tx.sh\tselects no suite\n", suites: "a.test.sh\t1\n" })).gaps, [["a.test.sh", "x.sh", "selects no suite"]]);
});

test("traceGaps accepts only selects and unmapped verdicts, and refuses a trace with an untraced suite or unchecked file", () => {
  const suites = [["a.test.sh", "1"]];
  const gap = (verdict) => traceGaps({ gaps: [["a.test.sh", "x.sh", verdict]], suites, verdicts: [] });
  assert.deepEqual(gap("selects 2 other suite(s)").gaps, [{ suite: "a.test.sh", file: "x.sh" }]);
  assert.deepEqual(gap("selects no suite").gaps, [{ suite: "a.test.sh", file: "x.sh" }]);
  assert.deepEqual(gap("unmapped: the fallback corpus does not run this suite").gaps, [{ suite: "a.test.sh", file: "x.sh" }]);
  assert.equal(gap("deleted: x.sh").reason, "test-scope-not-all-gaps");
  assert.equal(gap("not selected").reason, "test-scope-not-all-gaps");
  const gaps = [["a.test.sh", "x.sh", "selects no suite"]];
  assert.equal(traceGaps({ gaps, suites: [...suites, ["b.test.sh", "not-traced"]], verdicts: [] }).reason, "test-scope-not-all-gaps");
  assert.equal(traceGaps({ gaps, suites, verdicts: [["y.sh", "not checked: budget spent"]] }).reason, "test-scope-not-all-gaps");
  assert.equal(traceGaps({ gaps: [["c.test.sh", "x.sh", "selects no suite"]], suites, verdicts: [] }).reason, "test-scope-invalid");
  assert.equal(traceGaps({ gaps: [], suites, verdicts: [] }).reason, "test-scope-not-all-gaps");
});

const plan = (gaps, { changed = { "t/a.test.sh": "modified" }, base = ["x.sh"], head = { "t/a.test.sh": "# A.\nset -e\n", "x.sh": "" } } = {}) =>
  planDeclarations({
    gaps,
    changed: new Map(Object.entries(changed)),
    headEntry: (path) => (Object.hasOwn(head, path) ? { mode: "100644", type: "blob" } : null),
    baseHas: (path) => base.includes(path),
    headText: (path) => head[path],
  });

test("planDeclarations declares each read once in the suite, and refuses every gap the lane may not answer", () => {
  const [file] = plan([{ suite: "t/a.test.sh", file: "x.sh" }, { suite: "t/a.test.sh", file: "x.sh" }]).files;
  assert.equal(file.after, "# A.\n# test-scope: x.sh\nset -e\n");
  assert.equal(plan([{ suite: "t/a.test.sh", file: "x.sh" }], { changed: {} }).reason, "test-scope-not-all-gaps", "the PR does not change the suite");
  assert.equal(plan([{ suite: "t/a.test.sh", file: "x.sh" }], { changed: { "t/a.test.sh": "removed" } }).reason, "test-scope-not-all-gaps");
  assert.equal(plan([{ suite: "t/a.test.sh", file: "x.sh" }], { base: [] }).reason, "test-scope-not-all-gaps", "a read the PR adds is not at the base");
  assert.equal(plan([{ suite: "t/a.test.sh", file: "x.sh" }], { head: { "t/a.test.sh": "# test-scope: x.sh\n", "x.sh": "" } }).reason, "test-scope-not-all-gaps", "already declared");
  assert.equal(plan([{ suite: ".github/s/a.test.sh", file: "x.sh" }], { changed: { ".github/s/a.test.sh": "modified" } }).reason, "test-scope-not-all-gaps");
  assert.equal(plan([{ suite: "t/a.test.sh", file: "../x.sh" }]).reason, "test-scope-invalid");
  assert.equal(plan([{ suite: "t/a.test.sh", file: "x/*.sh" }]).reason, "test-scope-invalid");
});

test("build writes a patch that applies to the head and that apply-patch's content rule admits, CRLF kept", async (t) => {
  const suites = { "t/a.test.sh": "#!/bin/bash\n# A.\nset -e\n", "t/B.Tests.ps1": "# B.\r\nDescribe 'b' {}\r\n", "lib/x.sh": "x\n", "lib/y.ps1": "y\n" };
  const head = repo(t, suites);
  const base = repo(t, { "lib/x.sh": "x\n", "lib/y.ps1": "y\n" });
  const trace = traceDir(t, {
    gaps: "t/B.Tests.ps1\tlib/y.ps1\tselects no suite\nt/a.test.sh\tlib/x.sh\tunmapped: the fallback corpus does not run this suite\n",
    suites: "t/B.Tests.ps1\t1\nt/a.test.sh\t1\n",
    verdicts: "lib/x.sh\tunmapped: CI runs its fallback corpus\nlib/y.ps1\tselects no suite\n",
  });
  const out = scratch(t);
  const env = { GITHUB_OUTPUT: join(out, "output"), GITHUB_REPOSITORY: "o/r", PR_NUMBER: "7", HEAD_SHA: head.head, TRACE_DIR: trace, HEAD_DIR: head.dir, BASE_DIR: base.dir, PATCH_OUT: join(out, "patch.diff") };
  writeFileSync(env.GITHUB_OUTPUT, "");
  const call = async () => [{ filename: "t/a.test.sh", status: "added" }, { filename: "t/B.Tests.ps1", status: "modified" }];
  assert.equal(await main(["build"], env, { call, log: () => {}, loadTestScope: async () => ({ apply: false }) }), 0);
  const output = readFileSync(env.GITHUB_OUTPUT, "utf8");
  assert.match(output, /^state=written$/m);
  assert.match(output, /^declarations=2$/m);
  assert.match(output, /^apply=false$/m);
  git(head.dir, ["apply", "--check", env.PATCH_OUT]);
  git(head.dir, ["apply", env.PATCH_OUT]);
  assert.equal(readFileSync(join(head.dir, "t/B.Tests.ps1"), "utf8"), "# B.\r\n# test-scope: lib/y.ps1\r\nDescribe 'b' {}\r\n");
  for (const path of ["t/a.test.sh", "t/B.Tests.ps1"]) {
    assert.equal(declarationRefusal(path, suites[path], readFileSync(join(head.dir, path), "utf8")), null, path);
  }
});

test("build refuses a deleted verdict and writes no patch", async (t) => {
  const head = repo(t, { "t/a.test.sh": "# A.\n", "lib/x.sh": "x\n" });
  const trace = traceDir(t, { gaps: "t/a.test.sh\tlib/x.sh\tdeleted\n", suites: "t/a.test.sh\t1\n" });
  const out = scratch(t);
  const env = { GITHUB_OUTPUT: join(out, "output"), GITHUB_REPOSITORY: "o/r", PR_NUMBER: "7", HEAD_SHA: head.head, TRACE_DIR: trace, HEAD_DIR: head.dir, BASE_DIR: head.dir, PATCH_OUT: join(out, "patch.diff") };
  writeFileSync(env.GITHUB_OUTPUT, "");
  await main(["build"], env, { call: async () => [], log: () => {} });
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "escalation-reason=test-scope-not-all-gaps\n");
  assert.throws(() => readFileSync(env.PATCH_OUT));
});

const HEAD = "a".repeat(40);
const TRACED_RUN = { id: 9, run_attempt: 2, path: ".github/workflows/pr-require-checks.yml", status: "completed", conclusion: "failure", created_at: "2026-11-23T00:00:00Z", head_repository: { full_name: "o/r" } };
const TRACED_JOBS = [job("Test Selection", "failure", [...SETUP, ["Trace the changed suites", "failure"]])];

function locateApi({ pull = {}, commits = [{ commit: { message: "feat: x" } }], runs = [TRACED_RUN], jobs = TRACED_JOBS } = {}) {
  return async (method, path) => {
    if (path === "/repos/o/r/pulls/7") {
      return { draft: false, head: { sha: HEAD, repo: { full_name: "o/r" } }, user: { login: "someone" }, ...pull };
    }
    if (path.startsWith("/repos/o/r/pulls/7/commits")) {
      return commits;
    }
    if (path.startsWith("/repos/o/r/actions/runs?")) {
      return { workflow_runs: runs };
    }
    if (path.startsWith("/repos/o/r/actions/runs/9/jobs")) {
      return { jobs };
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
}

async function locateWith(t, api) {
  const out = join(scratch(t), "output");
  writeFileSync(out, "");
  await main(["locate"], { GITHUB_OUTPUT: out, GITHUB_REPOSITORY: "o/r", PR_NUMBER: "7", HEAD_SHA: HEAD }, { call: api, log: () => {} });
  return readFileSync(out, "utf8");
}

test("locate names the run whose trace failed alone, and skips or stops every head the lane leaves alone", async (t) => {
  assert.equal(await locateWith(t, locateApi()), "run-id=9\nrun-attempt=2\n");
  assert.equal(await locateWith(t, locateApi({ pull: { user: { login: "dependabot[bot]" } } })), "skip-reason=not-applicable\n");
  assert.equal(await locateWith(t, locateApi({ pull: { head: { sha: HEAD, repo: { full_name: "fork/r" } } } })), "skip-reason=not-applicable\n");
  assert.equal(await locateWith(t, locateApi({ pull: { head: { sha: "b".repeat(40), repo: { full_name: "o/r" } } } })), "skip-reason=superseded-sha\n");
  assert.equal(await locateWith(t, locateApi({ jobs: [...TRACED_JOBS, job("Lint", "failure")] })), "skip-reason=not-applicable\n");
  const row = rowFor(loadRules(join(import.meta.dirname, "../../..")), { prepare: "test-scope" });
  const own = { commit: { message: commitMessage(row, { ref: "b", lane: "pr-unblock", activity: "fix-test-scope" }) } };
  assert.equal(await locateWith(t, locateApi({ commits: [{ commit: { message: "feat: x" } }, own] })), "escalation-reason=test-scope-gaps-remain\n", "the head is the lane's own commit");
  assert.equal(await locateWith(t, locateApi({ commits: [own, own, { commit: { message: "fix: y" } }] })), "escalation-reason=test-scope-gaps-remain\n", "two lane commits already");
  assert.equal(await locateWith(t, locateApi({ commits: [own, { commit: { message: "fix: y" } }] })), "run-id=9\nrun-attempt=2\n", "one lane commit leaves room for a second");
});
