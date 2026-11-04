// find-capture.mjs, which each pr-verify judge job runs: it takes only the
// capture run the same upstream run started, waits for it within a bound,
// and never fails the job, whatever it finds or fails to read.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { APPEAR_MS, artifactName, CAPTURE_PATH, findCapture, main, runTitle, WAIT_MS } from "./find-capture.mjs";

const REPO = "melodic-software/claude-code-plugins";
const UPSTREAM = "777";
const PR = "41";
const HEAD = "a".repeat(40);
const MINUTE = 60_000;
const ids = { repository: REPO, upstreamRunId: UPSTREAM, pr: PR, headSha: HEAD };
const run = (overrides = {}) => ({
  id: 900,
  path: CAPTURE_PATH,
  event: "workflow_run",
  head_branch: "main",
  repository: { full_name: REPO },
  display_title: `pr-verify-capture ${UPSTREAM} ${HEAD}`,
  status: "completed",
  ...overrides,
});
const artifact = (overrides = {}) => ({ id: 5001, name: `pr-capture-${PR}-${HEAD}`, expired: false, ...overrides });

// A GitHub stand-in: each runs listing answers the next of `listings` (the
// last repeats), each artifacts read answers `artifacts`; a fake clock that
// each sleep moves on.
const fake = ({ listings, artifacts = [artifact()] }) => {
  const calls = [];
  let clock = 0;
  let listed = 0;
  const github = async (method, apiPath) => {
    calls.push(`${method} ${apiPath}`);
    if (apiPath.includes("/actions/workflows/")) {
      const runs = listings[Math.min(listed, listings.length - 1)];
      listed += 1;
      return { workflow_runs: runs };
    }
    return { artifacts };
  };
  const sleeps = [];
  const options = { now: () => clock, sleep: async (ms) => { sleeps.push(ms); clock += ms; } };
  return { github, calls, sleeps, options };
};

test("the run-name and artifact name it looks for are the capture workflow's, and never a verdict's", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-verify-capture.yml", import.meta.url), "utf8");
  assert.match(workflow, new RegExp(`^run-name: ${runTitle("\\$\\{\\{ github\\.event\\.workflow_run\\.id \\}\\}", "\\$\\{\\{ github\\.event\\.workflow_run\\.head_sha \\}\\}")}$`, "m"));
  assert.match(workflow, /^ {10}name: pr-capture-\$\{\{ steps\.pr\.outputs\.pr-number \}\}-\$\{\{ steps\.pr\.outputs\.head-sha \}\}$/m);
  assert.equal(artifactName(PR, HEAD), `pr-capture-41-${HEAD}`);
  assert.doesNotMatch(artifactName(PR, HEAD), /^pr-verify-/);
});

test("a completed capture run of this upstream run gives its artifact id", async () => {
  const { github, calls, options } = fake({ listings: [[run()]] });
  assert.deepEqual(await findCapture(github, ids, options), { artifactId: "5001", runId: "900" });
  assert.deepEqual(calls, [
    `GET /repos/${REPO}/actions/workflows/pr-verify-capture.yml/runs?event=workflow_run&branch=main&per_page=50`,
    `GET /repos/${REPO}/actions/runs/900/artifacts?name=pr-capture-41-${HEAD}&per_page=10`,
  ]);
});

test("a run that is not this file's on main by workflow_run for this upstream run and head is never taken", async () => {
  for (const other of [
    { path: ".github/workflows/pr-verify.yml" },
    { event: "workflow_dispatch" },
    { head_branch: "feature" },
    { repository: { full_name: "someone/fork" } },
    { display_title: `pr-verify-capture 778 ${HEAD}` },
    { display_title: `pr-verify-capture ${UPSTREAM} ${"b".repeat(40)}` },
  ]) {
    const { github, options } = fake({ listings: [[run(other)]] });
    const found = await findCapture(github, ids, options);
    assert.equal(found.artifactId, undefined, JSON.stringify(other));
    assert.equal(found.reason, "no capture run was started for this head", JSON.stringify(other));
  }
});

test("a running capture is waited for until it completes, and no longer than the bound", async () => {
  const done = fake({ listings: [[run({ status: "in_progress" })], [run({ status: "queued" })], [run()]] });
  assert.deepEqual(await findCapture(done.github, ids, done.options), { artifactId: "5001", runId: "900" });
  assert.deepEqual(done.sleeps, [MINUTE, MINUTE]);
  const late = fake({ listings: [[run({ status: "in_progress" })]] });
  const found = await findCapture(late.github, ids, late.options);
  assert.equal(found.reason, "capture run 900 was still running after 35 minutes");
  // Polled once a minute up to the bound, never past it.
  assert.equal(late.sleeps.length, 35);
  assert.ok(late.sleeps.reduce((a, b) => a + b, 0) <= WAIT_MS);
});

test("a capture run that never shows up is given up on after two minutes", async () => {
  const { github, sleeps, options } = fake({ listings: [[]] });
  assert.equal((await findCapture(github, ids, options)).reason, "no capture run was started for this head");
  assert.equal(sleeps.reduce((a, b) => a + b, 0), APPEAR_MS);
});

test("a completed run with no live artifact of the exact name gives none", async () => {
  for (const artifacts of [[], [artifact({ expired: true })], [artifact({ name: `pr-capture-41-${HEAD}-x` })], [artifact({ name: `pr-verify-41-${HEAD}-pass` })]]) {
    const { github, options } = fake({ listings: [[run()]], artifacts });
    assert.equal((await findCapture(github, ids, options)).reason, `capture run 900 left no pr-capture-41-${HEAD} artifact`, JSON.stringify(artifacts));
  }
  // The newest of two runs and of two artifacts.
  const { github, options } = fake({ listings: [[run({ id: 900 }), run({ id: 950 })]], artifacts: [artifact({ id: 6 }), artifact({ id: 7 })] });
  assert.deepEqual(await findCapture(github, ids, options), { artifactId: "7", runId: "950" });
});

test("main writes the ids only for a found capture, reads nothing with no app, and never throws", async () => {
  const dir = tempDir("find-capture-");
  const env = (extra) => {
    const output = path.join(dir, `out-${Math.random()}`);
    writeFileSync(output, "");
    return { GITHUB_OUTPUT: output, GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPO, UPSTREAM_RUN_ID: UPSTREAM, PR_NUMBER: PR, HEAD_SHA: HEAD, CAPTURE_APP: "claude-code", ...extra };
  };
  const found = env();
  const { github, options } = fake({ listings: [[run()]] });
  await main(found, { github, ...options });
  assert.equal(readFileSync(found.GITHUB_OUTPUT, "utf8"), "artifact-id=5001\nrun-id=900\n");
  const noApp = env({ CAPTURE_APP: "" });
  let called = false;
  await main(noApp, { github: async () => { called = true; } });
  assert.equal(called, false);
  assert.equal(readFileSync(noApp.GITHUB_OUTPUT, "utf8"), "");
  const failing = env();
  await main(failing, { github: async () => { throw new Error("HTTP 502"); }, ...options });
  assert.equal(readFileSync(failing.GITHUB_OUTPUT, "utf8"), "");
  const malformed = env({ HEAD_SHA: "not-a-sha" });
  await main(malformed, { github, ...options });
  assert.equal(readFileSync(malformed.GITHUB_OUTPUT, "utf8"), "");
});
