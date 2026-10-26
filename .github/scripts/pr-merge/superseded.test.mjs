// Expected values come from pr-merge.yml: a job waiting in its concurrency
// group starts after the running one, and it sweeps every candidate when its
// run is scheduled or a listed human started it (the "Check who started the
// run" step). superseded.mjs counts the starter and any re-runner as listed
// humans only by account id, since a login can pass to another account. Only
// schedule runs re-fire refused lane runs, and
// pull_request_target runs start no full CI run, so a merge job is superseded
// only by one that does at least what it does. Every enable-auto-merge run
// disarms on a hold, and only a scheduled or hand-started one arms. GitHub
// lists a run as pending while any one of its jobs waits on a group: run
// 40113925144 (schedule) read pending at 17:19Z on 2026-10-24 with its merge
// job completed at 17:14:54Z and its enable-auto-merge job pending.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { main } from "./superseded.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const LANES_BOT = { id: 337595936, login: "melodic-automation-lanes[bot]" };
const QUEUE_BOT = { id: 79413782, login: "github-merge-queue[bot]" };
const THIS_RUN = "500";
const LISTING = `/repos/${REPO}/actions/workflows/pr-merge.yml/runs?status=pending&exclude_pull_requests=true&per_page=100`;
const dir = mkdtempSync(join(tmpdir(), "superseded-"));
after(() => rmSync(dir, { recursive: true, force: true }));

// `actor` started the run and `rerunner` (its triggering_actor) last re-ran it.
const pending = (id, event, actor = OWNER, { rerunner = actor, branch = "main" } = {}) => ({
  id,
  event,
  status: "pending",
  head_branch: branch,
  actor,
  triggering_actor: rerunner,
});

const jobsOf = (id) => `/repos/${REPO}/actions/runs/${id}/jobs?filter=latest&per_page=100`;
const waiting = (name = "merge", status = "pending") => [{ name, status }];

let n = 0;
// `jobs` maps a run id to its jobs read; a run missing from it has `job`
// waiting. `jobsFail` is thrown by every jobs read.
async function check({ event = "schedule", runs = [], fail, body, job, jobs = {}, jobsFail } = {}) {
  n += 1;
  const output = join(dir, `output-${n}`);
  const calls = [];
  const actions = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (fail) {
      throw fail;
    }
    const id = /\/actions\/runs\/(\d+)\/jobs\?/.exec(path)?.[1];
    if (id !== undefined) {
      if (jobsFail) throw jobsFail;
      return { jobs: jobs[id] ?? waiting(job ?? "merge") };
    }
    return body ?? { total_count: runs.length, workflow_runs: runs };
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
        ...(job === undefined ? {} : { SUPERSEDED_JOB: job }),
        GITHUB_OUTPUT: output,
        TRUSTED_ACTORS_PATH: join(HERE, "fixtures/trusted-actors.json"),
      },
      actions,
    });
  } finally {
    console.log = log;
  }
  let written = "";
  try {
    written = readFileSync(output, "utf8");
  } catch {}
  return { status, calls, stdout: lines.join("\n"), superseded: /^superseded=true$/m.test(written), written };
}

test("a pending scheduled run whose merge job waits supersedes a scheduled run, with a listing, one jobs read and a notice", async () => {
  const run = await check({ runs: [pending(600, "schedule", QUEUE_BOT)] });
  assert.equal(run.status, 0);
  assert.equal(run.superseded, true);
  assert.deepEqual(run.calls, [`GET ${LISTING}`, `GET ${jobsOf(600)}`]);
  assert.match(run.stdout, /^::notice::.*run 600 \(schedule\)/m);
});

test("no other pending run: the gate runs", async () => {
  const run = await check({ runs: [] });
  assert.equal(run.superseded, false);
  assert.match(run.written, /^superseded=false$/m);
});

test("the run itself in the listing never supersedes it", async () => {
  const run = await check({ runs: [pending(Number(THIS_RUN), "schedule")] });
  assert.equal(run.superseded, false);
});

test("a pending run a listed human started by hand supersedes a pull_request_target run", async () => {
  const run = await check({ event: "pull_request_target", runs: [pending(600, "workflow_dispatch")] });
  assert.equal(run.superseded, true);
});

test("a pending pull_request_target run by a listed human supersedes another pull_request_target run", async () => {
  const run = await check({ event: "pull_request_target", runs: [pending(600, "pull_request_target")] });
  assert.equal(run.superseded, true);
});

test("a pending run a bot started stops before its sweep, so it supersedes nothing", async () => {
  const run = await check({ event: "pull_request_target", runs: [pending(600, "pull_request_target", LANES_BOT)] });
  assert.equal(run.superseded, false);
});

test("a listed human's login held by a different id does not count as that human, as starter or re-runner", async () => {
  const impostor = { id: 999001, login: OWNER.login };
  for (const [actor, rerunner] of [[impostor, impostor], [OWNER, impostor], [impostor, OWNER]]) {
    const run = await check({ event: "pull_request_target", runs: [pending(600, "workflow_dispatch", actor, { rerunner })] });
    assert.equal(run.superseded, false, `${actor.id} re-run by ${rerunner.id}`);
  }
});

test("a run with no triggering actor id is not counted as a listed human's", async () => {
  for (const rerunner of [{ login: OWNER.login }, { id: String(OWNER.id), login: OWNER.login }, null]) {
    const run = await check({ event: "pull_request_target", runs: [pending(600, "workflow_dispatch", OWNER, { rerunner })] });
    assert.equal(run.superseded, false, JSON.stringify(rerunner));
  }
});

test("a bot's run a listed human re-ran stops at the who step, so it supersedes nothing", async () => {
  const run = await check({ event: "pull_request_target", runs: [pending(600, "pull_request_target", LANES_BOT, { rerunner: OWNER })] });
  assert.equal(run.superseded, false);
});

test("a hand-started run on another branch runs that branch's copy, so it supersedes nothing", async () => {
  const run = await check({ event: "pull_request_target", runs: [pending(600, "workflow_dispatch", OWNER, { branch: "fix/other" })] });
  assert.equal(run.superseded, false);
});

test("a pull_request_target run never supersedes a scheduled or hand-started run, which do more", async () => {
  for (const event of ["schedule", "workflow_dispatch"]) {
    const run = await check({ event, runs: [pending(600, "pull_request_target")] });
    assert.equal(run.superseded, false, event);
  }
});

test("a hand-started run never supersedes a scheduled run, which alone re-fires refused lane runs", async () => {
  const run = await check({ event: "schedule", runs: [pending(600, "workflow_dispatch")] });
  assert.equal(run.superseded, false);
});

test("a run of any other event, or with no actor, supersedes nothing", async () => {
  const run = await check({ runs: [pending(600, "push"), { id: 601, event: "workflow_dispatch", status: "pending" }] });
  assert.equal(run.superseded, false);
});

test("a run whose listed status is not pending supersedes nothing", async () => {
  const run = await check({ runs: [{ ...pending(600, "schedule"), status: "in_progress" }] });
  assert.equal(run.superseded, false);
});

test("a failed listing runs the gate, with a warning", async () => {
  const run = await check({ fail: new GitHubError(503, `GET ${LISTING}`) });
  assert.equal(run.status, 0);
  assert.equal(run.superseded, false);
  assert.match(run.stdout, /^::warning title=superseded::.*status 503.*the job does its work$/m);
});

test("an unreadable listing runs the gate, with a warning", async () => {
  const run = await check({ body: { workflow_runs: "nope" } });
  assert.equal(run.superseded, false);
  assert.match(run.stdout, /^::warning title=superseded::.*unexpected shape/m);
});

test("an unknown current event, or an unknown job, does its work without a listing call", async () => {
  const unknown = await check({ job: "gate-check", runs: [pending(600, "schedule")] });
  assert.equal(unknown.superseded, false);
  assert.deepEqual(unknown.calls, []);
  const run = await check({ event: "push", runs: [pending(600, "schedule")] });
  assert.equal(run.superseded, false);
  assert.deepEqual(run.calls, []);
});

// Run 40113925144 above: pending only because another of its jobs waits.
test("a pending run whose merge job already ran supersedes nothing", async () => {
  const run = await check({
    runs: [pending(600, "schedule", QUEUE_BOT)],
    jobs: { 600: [{ name: "merge", status: "completed" }, { name: "enable-auto-merge", status: "pending" }] },
  });
  assert.equal(run.superseded, false);
});

test("the first pending run whose job still waits supersedes, and later runs are not read", async () => {
  const run = await check({
    runs: [pending(700, "schedule"), pending(600, "schedule"), pending(550, "schedule")],
    jobs: { 700: [{ name: "merge", status: "completed" }] },
  });
  assert.equal(run.superseded, true);
  assert.match(run.stdout, /run 600 \(schedule\)/);
  assert.deepEqual(run.calls, [`GET ${LISTING}`, `GET ${jobsOf(700)}`, `GET ${jobsOf(600)}`]);
});

test("a queued or waiting job counts as waiting; one missing from the run does not", async () => {
  for (const status of ["queued", "waiting"]) {
    assert.equal((await check({ runs: [pending(600, "schedule")], jobs: { 600: waiting("merge", status) } })).superseded, true, status);
  }
  assert.equal((await check({ runs: [pending(600, "schedule")], jobs: { 600: [] } })).superseded, false);
});

test("at most five pending runs have their jobs read", async () => {
  const runs = Array.from({ length: 7 }, (_, i) => pending(600 + i, "schedule"));
  const jobs = Object.fromEntries(runs.map((r) => [r.id, [{ name: "merge", status: "completed" }]]));
  const run = await check({ runs, jobs });
  assert.equal(run.superseded, false);
  assert.equal(run.calls.length, 1 + 5);
});

test("a failed jobs read does the work, with a warning", async () => {
  const run = await check({ runs: [pending(600, "schedule")], jobsFail: new GitHubError(502, `GET ${jobsOf(600)}`) });
  assert.equal(run.superseded, false);
  assert.match(run.stdout, /^::warning title=superseded::.*status 502/m);
});

test("enable-auto-merge: a pending edit run a listed human started supersedes another", async () => {
  const run = await check({ job: "enable-auto-merge", event: "pull_request_target", runs: [pending(600, "pull_request_target")] });
  assert.equal(run.superseded, true);
});

test("enable-auto-merge: a scheduled and a hand-started run, which both arm, supersede each other and every event run", async () => {
  for (const event of ["schedule", "workflow_dispatch", "pull_request_target"]) {
    for (const next of ["schedule", "workflow_dispatch"]) {
      const run = await check({ job: "enable-auto-merge", event, runs: [pending(600, next)] });
      assert.equal(run.superseded, true, `${event} by ${next}`);
    }
  }
});

test("enable-auto-merge: an event run, which never arms, supersedes no scheduled or hand-started run", async () => {
  for (const event of ["schedule", "workflow_dispatch"]) {
    const run = await check({ job: "enable-auto-merge", event, runs: [pending(600, "pull_request_target")] });
    assert.equal(run.superseded, false, event);
  }
});

test("enable-auto-merge: a waiting merge job, or an enable-auto-merge job a condition skipped, supersedes nothing", async () => {
  for (const jobs of [waiting("merge"), [{ name: "enable-auto-merge", status: "completed", conclusion: "skipped" }]]) {
    const run = await check({ job: "enable-auto-merge", runs: [pending(600, "schedule")], jobs: { 600: jobs } });
    assert.equal(run.superseded, false);
  }
});
