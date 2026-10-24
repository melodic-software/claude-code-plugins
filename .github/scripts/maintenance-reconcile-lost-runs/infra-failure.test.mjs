// Expected values come from the classifier's spec (a time-limit cancel, an
// install-step failure and a lost runner are infra; anything else is real; the
// ci-status aggregate alone is real) and from two recorded, trimmed job
// listings of pr-require-checks runs: 39710654665, whose check-plugins and
// test-node jobs exceeded their time limit (annotation "The job has exceeded
// the maximum execution time") while lint-shell failed its
// fixture-git-isolation check, and 39716948399, whose only failure is
// ci-status (a superseded contract-only run).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { contractOnly, infraCause, infraOnly, reconcilerOwns, stepsKnown, testedRun } from "./infra-failure.mjs";

const recorded = (id) => JSON.parse(readFileSync(new URL(`./fixtures/jobs-${id}.json`, import.meta.url), "utf8")).jobs;
const MIXED = recorded(39710654665);
const job = (conclusion, ...failedSteps) => ({
  name: "lint-repo",
  conclusion,
  steps: [{ name: "Set up job", conclusion: "success" }, ...failedSteps.map((name) => ({ name, conclusion: "failure" }))],
});

test("a run with a real failure beside time-limit cancels is not infra-only", () => {
  assert.equal(infraOnly(MIXED), false);
});

test("time-limit cancels alone, with the ci-status aggregate, are infra-only", () => {
  const jobs = MIXED.filter((j) => j.name !== "lint-shell");
  assert.deepEqual(
    jobs.filter((j) => j.conclusion === "cancelled").map((j) => [j.name, infraCause(j)]),
    [
      ["test-node", "time limit"],
      ["check-plugins", "time limit"],
    ],
  );
  assert.equal(infraOnly(jobs), true);
});

test("ci-status failing alone is real", () => {
  assert.equal(infraOnly(recorded(39716948399)), false);
});

// A step stopped mid-run concludes cancelled, as check-plugins' "Install the
// locked root toolchain" step does in run 39710654665.
const stopped = (conclusion, name, ...laterFailedSteps) => {
  const base = job("failure", ...laterFailedSteps);
  return { ...base, steps: [base.steps[0], { name, conclusion }, ...base.steps.slice(1)] };
};

test("a job whose install step was stopped is infra, even when a later step fails too", () => {
  assert.equal(infraCause(stopped("cancelled", "Install the pinned YAML reader", "Aggregate hygiene results")), "install");
  assert.equal(infraCause(stopped("timed_out", "Set up Node")), "install");
});

test("an install step that exits with a failure is real: a stale lockfile fails npm ci the same way", () => {
  assert.equal(infraCause(job("failure", "Install dependencies")), "");
  assert.equal(infraCause(job("failure", "Set up Node")), "");
  assert.equal(infraCause(job("failure", "Set up job")), "");
});

test("a failed job with no failed step lost its runner", () => {
  assert.equal(infraCause(job("failure")), "lost runner");
});

test("a job whose first failed step is not an install is real", () => {
  assert.equal(infraCause(job("failure", "Run this leg's shell suites", "Install the pinned YAML reader")), "");
  assert.equal(infraCause(job("failure", "Set up the fixture")), "");
  assert.equal(infraOnly([job("failure", "Install dependencies"), job("failure", "Lint markdown")]), false);
});

test("a run with no failed job, or no job listing, is not infra-only", () => {
  assert.equal(infraOnly([{ name: "lint-repo", conclusion: "success", steps: [] }]), false);
  assert.equal(infraOnly([]), false);
  assert.equal(infraOnly(undefined), false);
});

// The jobs API can list a finished job's steps empty, or cut short with its
// first steps missing and later ones still pending.
const unlisted = { name: "lint-repo", conclusion: "failure", runner_id: 7, steps: [] };
const cut = {
  name: "lint-repo",
  conclusion: "failure",
  runner_id: 7,
  steps: [
    { name: "Check out", status: "completed", conclusion: "success" },
    { name: "Lint markdown", status: "in_progress", conclusion: null },
  ],
};

test("a failed job whose steps did not list is neither a lost runner nor infra", () => {
  for (const job of [unlisted, cut, { ...unlisted, steps: undefined }]) {
    assert.equal(stepsKnown(job), false);
    assert.equal(infraCause(job), "");
    assert.equal(infraOnly([job]), false);
  }
  assert.equal(infraCause({ ...cut, conclusion: "cancelled" }), "time limit");
});

test("a job no runner took lists no steps, and that list is whole", () => {
  assert.equal(stepsKnown({ name: "verify", conclusion: "cancelled", steps: [] }), true);
  assert.equal(stepsKnown(job("failure")), true);
});

// Numbered as a cancelled lane job lists them: 1..n, then post steps after a gap.
const numbered = (...entries) => ({
  name: "lint-repo",
  conclusion: "failure",
  runner_id: 7,
  steps: entries.map(([number, name, conclusion = "success"]) => ({ number, name, status: "completed", conclusion })),
});

test("a numbered list is whole only when its steps run 1..n before the post steps", () => {
  const whole = numbered([1, "Set up job"], [2, "Check out"], [3, "Test", "failure"], [38, "Post Check out"], [39, "Complete job"]);
  assert.equal(stepsKnown(whole), true);
  assert.equal(infraCause(whole), "");
  const midCut = numbered([1, "Set up job"], [3, "Lint"], [38, "Post Check out"], [39, "Complete job"]);
  assert.equal(stepsKnown(midCut), false);
  assert.equal(infraCause(midCut), "", "a cut list with no failed step is not a lost runner");
  assert.equal(stepsKnown(numbered([1, "Set up job"], [2, "Check out"], [5, "Upload the verdict"])), false);
});

test("a finished job's list is whole only when every step is done and it ends with Complete job", () => {
  const done = { ...numbered([1, "Set up job"], [2, "Check out"], [3, "Test", "failure"], [38, "Post Check out"], [39, "Complete job"]), status: "completed" };
  assert.equal(stepsKnown(done), true);
  const tailCut = { ...numbered([1, "Set up job"], [2, "Check out"]), status: "completed" };
  assert.equal(stepsKnown(tailCut), false);
  assert.equal(infraCause(tailCut), "", "a tail-cut list with no failed step is not a lost runner");
  const stale = { ...done, steps: done.steps.map((s) => (s.name === "Test" ? { ...s, status: "in_progress", conclusion: null } : s)) };
  assert.equal(stepsKnown(stale), false);
  assert.equal(infraCause(stale), "");
});

// A runner that dies leaves its job's list cut at the running step, with no
// "Complete job"; GitHub records why on the job's check run, as
// maintenance-monitor-signals reads it.
const died = (message, level = "failure") => ({
  ...cut,
  status: "completed",
  annotations: [{ annotation_level: level, message }],
});

test("a lost-runner job with a cut list and no Complete job is still a lost runner, from its annotations", () => {
  for (const message of [
    "The hosted runner: GitHub Actions 7 lost communication with the server. Anything in your workflow that terminates the runner process can cause this error.",
    "The runner has received a shutdown signal. This can happen when the runner service is stopped.",
  ]) {
    assert.equal(stepsKnown(died(message)), false);
    assert.equal(infraCause(died(message)), "lost runner");
    assert.equal(infraOnly([died(message)]), true);
  }
});

test("a tail-cut job with no runner-loss annotation stays unknown", () => {
  assert.equal(infraCause({ ...cut, status: "completed" }), "");
  assert.equal(infraCause(died("Process completed with exit code 1.")), "");
  assert.equal(infraCause(died("The runner has received a shutdown signal.", "warning")), "");
  assert.equal(infraOnly([{ ...cut, status: "completed", annotations: [] }]), false);
});

test("the reconciler keeps a run whose failed jobs' steps did not list, inside its re-run window", () => {
  const now = Date.parse("2026-10-19T20:00:00Z");
  const run = (attempt, created = "2026-10-19T19:00:00Z") => ({ status: "completed", conclusion: "failure", run_attempt: attempt, created_at: created });
  for (const job of [unlisted, cut]) {
    assert.match(reconcilerOwns({ run: run(2), jobs: [job] }, now), /steps did not list/);
    assert.match(reconcilerOwns({ run: run(1), jobs: [job] }, now), /./);
    assert.equal(reconcilerOwns({ run: run(3), jobs: [job] }, now), "");
    assert.equal(reconcilerOwns({ run: run(2, "2026-10-18T19:00:00Z"), jobs: [job] }, now), "");
  }
  assert.equal(reconcilerOwns({ run: run(2), jobs: [job("failure", "Lint markdown")] }, now), "");
});

test("a run where only ci-status ran is contract-only; a tested run is not", () => {
  assert.equal(contractOnly(recorded(39716948399)), true);
  assert.equal(contractOnly(MIXED), false);
  assert.equal(contractOnly([{ name: "ci-status", conclusion: "failure" }]), false);
});

test("the tested run steps past failed contract-only runs, and stops at any other run", async () => {
  const jobsOf = new Map([
    [3, recorded(39716948399)],
    [2, MIXED],
  ]);
  const read = [];
  const readJobs = async (r) => {
    read.push(r.id);
    return jobsOf.get(r.id);
  };
  const failedRun = (id) => ({ id, status: "completed", conclusion: "failure" });
  assert.deepEqual(await testedRun([failedRun(3), failedRun(2), failedRun(1)], readJobs), { run: failedRun(2), jobs: MIXED });
  assert.deepEqual(read, [3, 2]);
  const green = { id: 4, status: "completed", conclusion: "success" };
  assert.deepEqual(await testedRun([green, failedRun(2)], readJobs), { run: green, jobs: null });
  assert.equal(await testedRun(Array.from({ length: 6 }, () => failedRun(3)), readJobs), undefined);
});
