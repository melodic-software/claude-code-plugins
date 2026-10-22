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

import { contractOnly, infraCause, infraOnly, testedRun } from "./infra-failure.mjs";

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
