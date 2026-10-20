// Expected values come from pr-merge.yml: a run that ran the gate uploads the
// pr-merge-summary artifact when its sweep ends; scheduled and hand-started
// runs always sweep; a pull_request_target run skips its sweep when such an
// artifact from a pr-merge.yml run is younger than
// merge.event-sweep-min-minutes (absent: 10, 0: never skip), and any failure
// sweeps, as every run did before this check.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { main } from "./recent-sweep.mjs";

const REPO = "melodic-software/claude-code-plugins";
const THIS_RUN = "500";
const NOW = Date.parse("2026-10-20T07:00:00Z");
const ARTIFACTS = `/repos/${REPO}/actions/artifacts?name=pr-merge-summary&per_page=10`;
const RUN = (id) => `/repos/${REPO}/actions/runs/${id}`;
const dir = mkdtempSync(join(tmpdir(), "recent-sweep-"));
after(() => rmSync(dir, { recursive: true, force: true }));

const minutesAgo = (m) => new Date(NOW - m * 60_000).toISOString();
const artifact = (runId, minutes, extra = {}) => ({
  name: "pr-merge-summary",
  expired: false,
  created_at: minutesAgo(minutes),
  workflow_run: { id: runId },
  ...extra,
});
const sweepRun = (id, event = "schedule", extra = {}) => ({
  id,
  event,
  path: ".github/workflows/pr-merge.yml",
  head_branch: "main",
  ...extra,
});

let n = 0;
async function check({ event = "pull_request_target", min = "", artifacts = [], runs = {}, fail, body } = {}) {
  n += 1;
  const output = join(dir, `output-${n}`);
  const summary = join(dir, `summary-${n}`);
  const calls = [];
  const actions = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (fail) {
      throw fail;
    }
    if (path === ARTIFACTS) {
      return body ?? { total_count: artifacts.length, artifacts };
    }
    const id = /\/runs\/(\d+)$/.exec(path)?.[1];
    if (id && runs[id]) {
      return runs[id];
    }
    throw new GitHubError(404, `${method} ${path}`);
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  let status;
  try {
    status = await main({
      env: {
        GITHUB_REPOSITORY: REPO,
        GITHUB_RUN_ID: THIS_RUN,
        GITHUB_EVENT_NAME: event,
        GITHUB_OUTPUT: output,
        GITHUB_STEP_SUMMARY: summary,
        MIN_MINUTES: min,
      },
      actions,
      now: NOW,
    });
  } finally {
    console.log = log;
  }
  let written = "";
  try {
    written = readFileSync(output, "utf8");
  } catch {}
  return { status, calls, stdout: lines.join("\n"), skip: /^skip=true$/m.test(written), written };
}

test("an event run within the default 10 minutes of a finished sweep skips, with one greppable line", async () => {
  const run = await check({ artifacts: [artifact(400, 4)], runs: { 400: sweepRun(400) } });
  assert.equal(run.status, 0);
  assert.equal(run.skip, true);
  assert.deepEqual(run.calls, [`GET ${ARTIFACTS}`, `GET ${RUN(400)}`]);
  assert.match(run.stdout, /^event-sweep-skip: last-sweep-finished=2026-10-20T06:56:00\.000Z age-min=4 min-minutes=10$/m);
});

test("an event run outside the window sweeps", async () => {
  const run = await check({ artifacts: [artifact(400, 11)], runs: { 400: sweepRun(400) } });
  assert.equal(run.skip, false);
  assert.match(run.written, /^skip=false$/m);
  assert.doesNotMatch(run.stdout, /event-sweep-skip:/);
});

test("the setting sets the window", async () => {
  const inside = await check({ min: "30", artifacts: [artifact(400, 20)], runs: { 400: sweepRun(400) } });
  assert.equal(inside.skip, true);
  assert.match(inside.stdout, /age-min=20 min-minutes=30$/m);
  const outside = await check({ min: "3", artifacts: [artifact(400, 4)], runs: { 400: sweepRun(400) } });
  assert.equal(outside.skip, false);
});

test("a setting of 0 never skips and makes no call", async () => {
  const run = await check({ min: "0", artifacts: [artifact(400, 1)], runs: { 400: sweepRun(400) } });
  assert.equal(run.skip, false);
  assert.deepEqual(run.calls, []);
});

test("scheduled and hand-started runs always sweep, with no call", async () => {
  for (const event of ["schedule", "workflow_dispatch"]) {
    const run = await check({ event, artifacts: [artifact(400, 1)], runs: { 400: sweepRun(400) } });
    assert.equal(run.skip, false, event);
    assert.deepEqual(run.calls, [], event);
  }
});

test("a sweep an earlier event run finished counts", async () => {
  const run = await check({
    artifacts: [artifact(400, 2)],
    runs: { 400: sweepRun(400, "pull_request_target", { head_branch: "feat/x" }) },
  });
  assert.equal(run.skip, true);
});

test("the newest unexpired artifact is the one checked", async () => {
  const run = await check({
    artifacts: [artifact(401, 30), artifact(402, 2, { expired: true }), artifact(403, 5)],
    runs: { 401: sweepRun(401), 403: sweepRun(403) },
  });
  assert.equal(run.skip, true);
  assert.deepEqual(run.calls, [`GET ${ARTIFACTS}`, `GET ${RUN(403)}`]);
});

test("an artifact from another workflow, a pull_request run, or a hand-started run off main does not count", async () => {
  for (const other of [
    sweepRun(400, "schedule", { path: ".github/workflows/other.yml" }),
    sweepRun(400, "pull_request"),
    sweepRun(400, "workflow_dispatch", { head_branch: "fix/other" }),
  ]) {
    const run = await check({ artifacts: [artifact(400, 1)], runs: { 400: other } });
    assert.equal(run.skip, false, JSON.stringify(other));
  }
});

test("no finished sweep at all: the event run sweeps", async () => {
  const run = await check({ artifacts: [] });
  assert.equal(run.skip, false);
  assert.deepEqual(run.calls, [`GET ${ARTIFACTS}`]);
});

test("this run's own artifact never counts", async () => {
  const run = await check({ artifacts: [artifact(Number(THIS_RUN), 0)], runs: { [THIS_RUN]: sweepRun(Number(THIS_RUN)) } });
  assert.equal(run.skip, false);
});

test("a failed listing sweeps, with a warning", async () => {
  const run = await check({ fail: new GitHubError(503, `GET ${ARTIFACTS}`) });
  assert.equal(run.status, 0);
  assert.equal(run.skip, false);
  assert.match(run.stdout, /^::warning title=recent-sweep::.*status 503.*the sweep runs$/m);
});

test("an unreadable listing, run or date sweeps, with a warning", async () => {
  const shape = await check({ body: { artifacts: "nope" } });
  assert.equal(shape.skip, false);
  assert.match(shape.stdout, /^::warning title=recent-sweep::.*unexpected shape/m);
  const missing = await check({ artifacts: [artifact(400, 1)], runs: {} });
  assert.equal(missing.skip, false);
  assert.match(missing.stdout, /^::warning title=recent-sweep::/m);
  const date = await check({ artifacts: [artifact(400, 1, { created_at: "soon" })], runs: { 400: sweepRun(400) } });
  assert.equal(date.skip, false);
});

test("a setting that is not a whole number sweeps, with a warning and no call", async () => {
  const run = await check({ min: "ten", artifacts: [artifact(400, 1)], runs: { 400: sweepRun(400) } });
  assert.equal(run.skip, false);
  assert.deepEqual(run.calls, []);
  assert.match(run.stdout, /^::warning title=recent-sweep::.*event-sweep-min-minutes/m);
});
