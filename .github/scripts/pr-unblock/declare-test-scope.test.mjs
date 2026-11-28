// test-scope: scripts/selection-audit.sh
// test-scope: scripts/lib/pytest-python.sh
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { commitMessage, loadRules, rowFor } from "../apply-patch/apply-patch.mjs";
import { SUITE_COLUMNS, main, planDeclarations, readTrace, traceGaps, traceOnlyFailure } from "./declare-test-scope.mjs";
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

test("traceOnlyFailure takes trace matrix shards that each failed first at the trace step, and no other failed job", () => {
  const run = { conclusion: "failure" };
  const shard = (index, steps = [...SETUP, ["Trace the changed suites", "failure"]]) => job(`Test Selection (${index})`, "failure", steps);
  assert.equal(traceOnlyFailure({ run, jobs: [shard(0), job("Test Selection (1)", "success"), shard(2), job("CI Status", "failure")] }), true);
  assert.equal(traceOnlyFailure({ run, jobs: [shard(0), shard(1, [["Check out", "success"], ["Install", "failure"]])] }), false, "one shard failed before the trace");
  assert.equal(traceOnlyFailure({ run, jobs: [shard(0), job("Lint", "failure")] }), false, "another lane failed too");
  assert.equal(traceOnlyFailure({ run, jobs: [job("Test Selection (x)", "failure", [...SETUP, ["Trace the changed suites", "failure"]])] }), false, "not a shard index");
});

test("readTrace joins the shard directories a multi-artifact download writes, and refuses a download with none", (t) => {
  const dir = scratch(t);
  for (const [name, suite] of [["selection-trace-1-1-0", "a.test.sh"], ["selection-trace-1-1-1", "b.test.sh"]]) {
    mkdirSync(join(dir, name));
    writeFileSync(join(dir, name, "gaps.tsv"), `${suite}\tx.sh\tselects no suite\n`);
    writeFileSync(join(dir, name, "suites.tsv"), `${suite}\t1\t3\t1\n`);
    writeFileSync(join(dir, name, "verdicts.tsv"), "x.sh\tselects no suite\n");
  }
  const joined = readTrace(dir);
  assert.deepEqual(joined.suites.map(([suite]) => suite), ["a.test.sh", "b.test.sh"]);
  assert.deepEqual(traceGaps(joined).gaps, [{ suite: "a.test.sh", file: "x.sh" }, { suite: "b.test.sh", file: "x.sh" }]);
  assert.equal(readTrace(scratch(t)).reason, "test-scope-invalid");
});

test("readTrace refuses a carriage return, a short row and a symbolic link as test-scope-invalid", (t) => {
  assert.equal(readTrace(traceDir(t, { gaps: "a.test.sh\tx.sh\tselects no suite\r\n", suites: "a.test.sh\t0\t3\t1\n" })).reason, "test-scope-invalid");
  assert.equal(readTrace(traceDir(t, { gaps: "a.test.sh\tx.sh\n", suites: "a.test.sh\t0\t3\t1\n" })).reason, "test-scope-invalid");
  const linked = traceDir(t, { gaps: "", suites: "" });
  rmSync(join(linked, "gaps.tsv"));
  symlinkSync("/etc/hostname", join(linked, "gaps.tsv"));
  assert.equal(readTrace(linked).reason, "test-scope-invalid");
  assert.deepEqual(readTrace(traceDir(t, { gaps: "a.test.sh\tx.sh\tselects no suite\n", suites: "a.test.sh\t1\t3\t1\n" })).gaps, [["a.test.sh", "x.sh", "selects no suite"]]);
});

test("readTrace takes a suites.tsv row as suite, exit code or not-traced, seconds and read count, and refuses any other row", (t) => {
  const gaps = "a.test.sh\tx.sh\tselects no suite\n";
  const suites = (row) => readTrace(traceDir(t, { gaps, suites: `${row}\n` }));
  assert.deepEqual(suites("a.test.sh\t0\t29\t12").suites, [["a.test.sh", "0", "29", "12"]]);
  assert.deepEqual(suites("a.test.sh\tnot-traced\t0\t0").suites, [["a.test.sh", "not-traced", "0", "0"]]);
  for (const row of ["a.test.sh\t0", "a.test.sh\t0\t29\t12\t1", "a.test.sh\tpassed\t29\t12", "a.test.sh\t-1\t29\t12", "a.test.sh\t0\t2.5\t12", "a.test.sh\t0\t29\tmany"]) {
    assert.equal(suites(row).reason, "test-scope-invalid", JSON.stringify(row));
  }
});

const AUDIT = join(import.meta.dirname, "../../../scripts/selection-audit.sh");

function auditRepo(t) {
  const dir = scratch(t, "declare-test-scope-audit-");
  const stubs = scratch(t, "declare-test-scope-stubs-");
  const files = {
    ".github/workflows/pr-require-checks.yml": "run: scripts/plan-test-lanes.sh\n",
    "data/x.txt": "x\n",
    "suites/a.test.sh": "cat data/x.txt\nexit 1\n",
  };
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(join(dir, dirname(path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  git(dir, ["init", "-q", "-b", "main"]);
  git(dir, ["add", "-A"]);
  git(dir, ["-c", "user.email=t@example.com", "-c", "user.name=t", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "c"]);
  writeFileSync(join(stubs, "selector.sh"), "#!/usr/bin/env bash\nexit 0\n", { mode: 0o755 });
  writeFileSync(
    join(stubs, "strace"),
    [
      "#!/usr/bin/env bash",
      'while [[ "$1" == -* ]]; do case "$1" in -o | -e) [[ "$1" == -e ]] || log="$2"; shift 2 ;; *) shift ;; esac; done',
      'printf \'100 openat(AT_FDCWD, "data/x.txt", O_RDONLY) = 3<%s/data/x.txt>\\n\' "$(pwd -P)" >"$log"',
      'exec "$@"',
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  return { dir, stubs };
}

function runAudit(t, { dir, stubs }, args) {
  const out = scratch(t, "declare-test-scope-trace-");
  const env = { ...process.env, PATH: `${stubs}:${process.env.PATH}`, SELECTION_AUDIT_SELECTOR: join(stubs, "selector.sh") };
  delete env.RUNNER_TEMP;
  delete env.GITHUB_STEP_SUMMARY;
  const run = spawnSync("bash", [AUDIT, "trace", "--strict", ...args, "--out", out, "suites/a.test.sh"], { cwd: dir, env, encoding: "utf8" });
  assert.equal(run.status, 1, `selection-audit.sh trace exits 1 on a gap or an untraced suite: ${run.stderr}`);
  return out;
}

test("readTrace and traceGaps take the trace scripts/selection-audit.sh writes, with only strace and the selector stubbed", (t) => {
  const repoDir = auditRepo(t);
  const traced = readTrace(runAudit(t, repoDir, []));
  assert.equal(traced.reason, undefined, traced.why);
  assert.deepEqual(traced.suites.map(([suite, status, , reads]) => [suite, status, reads]), [["suites/a.test.sh", "1", "1"]]);
  assert.deepEqual(traced.verdicts, [["data/x.txt", "selects no suite"]]);
  assert.deepEqual(traceGaps(traced), { gaps: [{ suite: "suites/a.test.sh", file: "data/x.txt" }] });
  const untraced = readTrace(runAudit(t, repoDir, ["--budget", "1"]));
  assert.deepEqual(untraced.suites, [["suites/a.test.sh", "not-traced", "0", "0"]]);
  assert.equal(traceGaps(untraced).reason, "test-scope-not-all-gaps");
});

test("every suites.tsv row scripts/selection-audit.sh prints has the width readTrace reads", () => {
  const writers = readFileSync(AUDIT, "utf8")
    .split("\n")
    .filter((line) => line.includes('"$out/suites/$key"'));
  assert.equal(writers.length, 2, "the traced and the not-traced row");
  for (const line of writers) {
    const format = /printf '([^']*)'/.exec(line)?.[1];
    assert.equal(format?.replace(/\\n$/, "").split("\\t").length, SUITE_COLUMNS, line);
  }
});

test("traceGaps accepts only selects and unmapped verdicts, and refuses a trace with an untraced suite or unchecked file", () => {
  const suites = [["a.test.sh", "1", "3", "1"]];
  const gap = (verdict) => traceGaps({ gaps: [["a.test.sh", "x.sh", verdict]], suites, verdicts: [] });
  assert.deepEqual(gap("selects 2 other suite(s)").gaps, [{ suite: "a.test.sh", file: "x.sh" }]);
  assert.deepEqual(gap("selects no suite").gaps, [{ suite: "a.test.sh", file: "x.sh" }]);
  assert.deepEqual(gap("unmapped: the fallback corpus does not run this suite").gaps, [{ suite: "a.test.sh", file: "x.sh" }]);
  assert.equal(gap("deleted: x.sh").reason, "test-scope-not-all-gaps");
  assert.equal(gap("not selected").reason, "test-scope-not-all-gaps");
  const gaps = [["a.test.sh", "x.sh", "selects no suite"]];
  assert.equal(traceGaps({ gaps, suites: [...suites, ["b.test.sh", "not-traced", "0", "0"]], verdicts: [] }).reason, "test-scope-not-all-gaps");
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
  assert.equal(plan([{ suite: "t/a.test.sh", file: "../x.sh" }]).reason, "test-scope-invalid");
  assert.equal(plan([{ suite: "t/a.test.sh", file: "x/*.sh" }]).reason, "test-scope-invalid");
});

const planIn = (suite, read = "x.sh") => plan([{ suite, file: read }], { changed: { [suite]: "modified" }, base: [read], head: { [suite]: "// A.\nimport x;\n", [read]: "" } });

test("planDeclarations declares in a .github suite outside workflows, and refuses workflows, lane-grants and CODEOWNERS paths", () => {
  const suite = ".github/scripts/pr-review-main/write-verdict.test.mjs";
  const [file] = planIn(suite, "plugins/source-control/skills/babysit-prs/scripts/babysit_merge_settings.py").files;
  assert.equal(file.path, suite);
  assert.equal(file.after, "// A.\n// test-scope: plugins/source-control/skills/babysit-prs/scripts/babysit_merge_settings.py\nimport x;\n");
  assert.ok(planIn(".github/actions/collect-base-activity/collect-base-activity.test.mjs").files);
  for (const refused of [".github/workflows/x.test.mjs", ".github/workflows/x.yml", ".GitHub/Workflows/x.test.mjs", ".github/lane-grants.json", ".github/lane-grants.test.mjs", "t/Lane-Grants.test.mjs", ".github/CODEOWNERS", "CODEOWNERS"]) {
    const { reason, why } = planIn(refused);
    assert.equal(reason, "test-scope-not-all-gaps", refused);
    assert.match(why, /is not a suite the lane may declare in$/, refused);
  }
});

test("build writes a patch that applies to the head and that apply-patch's content rule admits, CRLF kept", async (t) => {
  const suites = { "t/a.test.sh": "#!/bin/bash\n# A.\nset -e\n", "t/B.Tests.ps1": "# B.\r\nDescribe 'b' {}\r\n", "lib/x.sh": "x\n", "lib/y.ps1": "y\n" };
  const head = repo(t, suites);
  const base = repo(t, { "lib/x.sh": "x\n", "lib/y.ps1": "y\n" });
  const trace = traceDir(t, {
    gaps: "t/B.Tests.ps1\tlib/y.ps1\tselects no suite\nt/a.test.sh\tlib/x.sh\tunmapped: the fallback corpus does not run this suite\n",
    suites: "t/B.Tests.ps1\t1\t4\t1\nt/a.test.sh\t1\t2\t1\n",
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

test("build refuses a deleted verdict and writes no patch: a stop with test-scope.apply on, a lane-stopped skip while dark", async (t) => {
  const head = repo(t, { "t/a.test.sh": "# A.\n", "lib/x.sh": "x\n" });
  const trace = traceDir(t, { gaps: "t/a.test.sh\tlib/x.sh\tdeleted\n", suites: "t/a.test.sh\t1\t2\t1\n" });
  for (const [apply, expected] of [[true, "escalation-reason=test-scope-not-all-gaps\n"], [false, "skip-reason=lane-stopped\n"], [undefined, "skip-reason=lane-stopped\n"]]) {
    const out = scratch(t);
    const env = { GITHUB_OUTPUT: join(out, "output"), GITHUB_REPOSITORY: "o/r", PR_NUMBER: "7", HEAD_SHA: head.head, TRACE_DIR: trace, HEAD_DIR: head.dir, BASE_DIR: head.dir, PATCH_OUT: join(out, "patch.diff") };
    writeFileSync(env.GITHUB_OUTPUT, "");
    await main(["build"], env, { call: async () => [], log: () => {}, loadTestScope: async () => ({ apply }) });
    assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), expected, `apply ${apply}`);
    assert.throws(() => readFileSync(env.PATCH_OUT));
  }
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
      const page = Number(new URL(path, "https://api.example").searchParams.get("page"));
      return { jobs: jobs.slice((page - 1) * 100, page * 100) };
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
}

test("locate reads a run's jobs past three pages, as a wide test-selection matrix lists them", async (t) => {
  const shards = Array.from({ length: 349 }, (_, index) => job(`Test Selection (${index})`, "success"));
  const jobs = [...shards, job("Test Selection (349)", "failure", [...SETUP, ["Trace the changed suites", "failure"]])];
  assert.equal(await locateWith(t, locateApi({ jobs })), "run-id=9\nrun-attempt=2\n");
});

async function locateWith(t, api, scope = { apply: true }) {
  const out = join(scratch(t), "output");
  writeFileSync(out, "");
  await main(["locate"], { GITHUB_OUTPUT: out, GITHUB_REPOSITORY: "o/r", PR_NUMBER: "7", HEAD_SHA: HEAD, BASE_DIR: "/base" }, { call: api, log: () => {}, loadTestScope: async () => scope });
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
  for (const apply of [false, undefined]) {
    assert.equal(await locateWith(t, locateApi({ commits: [{ commit: { message: "feat: x" } }, own] }), { apply }), "skip-reason=lane-stopped\n", `dark (apply ${apply}): the stop posts no failing status`);
    assert.equal(await locateWith(t, locateApi({ pull: { user: { login: "dependabot[bot]" } } }), { apply }), "skip-reason=not-applicable\n", `dark (apply ${apply}): a skip stays a skip`);
  }
});
