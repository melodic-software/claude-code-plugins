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

import { infraCause, infraOnly } from "./infra-failure.mjs";

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

test("a job whose first failed step installs is infra, even when a later step fails too", () => {
  assert.equal(infraCause(job("failure", "Install the pinned YAML reader", "Aggregate hygiene results")), "install");
  assert.equal(infraCause(job("failure", "Set up Node")), "install");
  assert.equal(infraCause(job("failure", "Set up job")), "install");
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
