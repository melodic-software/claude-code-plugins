import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { laneClient, levelVariableWriter, run } from "./publish-lane-level.mjs";

const REPO = "melodic-software/claude-code-plugins";
// 2026-11-10T23:47:00Z.
const NOW_S = 1794354420;
const NOW = NOW_S * 1000;
const dir = mkdtempSync(join(tmpdir(), "publish-lane-level-"));
after(() => rmSync(dir, { recursive: true, force: true }));

function resolved(laneLevel) {
  const path = join(dir, `resolved-${Math.random().toString(16).slice(2)}.json`);
  writeFileSync(path, JSON.stringify({ limits: { "lane-level": { floor: 2, ceiling: 4, default: 3, "clean-windows": 2, pools: ["lanes-app"], ...laneLevel }, api: {} } }));
  return path;
}

// A quiet window: 400 of the lanes App's 5000 used.
const QUIET = JSON.stringify({ at: NOW_S, pools: { "lanes-app": { used: 400, limit: 5000 } }, signals: [] });

// The job token's reads: the issue lane's runs in progress, and the
// lane-level-state artifact of the last scheduled sweep (run 70), which holds
// `state` when it is not null.
function fakeActions({ active = 5, state = null } = {}) {
  const calls = [];
  const actions = async (method, path) => {
    calls.push(`${method} ${path}`);
    const lane = /^\/repos\/[^/]+\/[^/]+\/actions\/workflows\/work-resolve-issue\.yml\/runs\?status=([a-z_]+)&per_page=1$/.exec(path);
    if (lane) {
      // Unfinished runs: `active` in progress and one waiting on a runner.
      return { total_count: { in_progress: active, queued: 1 }[lane[1]] ?? 0, workflow_runs: [] };
    }
    if (path.startsWith(`/repos/${REPO}/actions/workflows/work-unblock.yml/runs?branch=main&event=schedule&`)) {
      const run = (id, event) => ({ id, path: ".github/workflows/work-unblock.yml", event, head_branch: "main", head_repository: { full_name: REPO } });
      return { workflow_runs: [run(71, "workflow_run"), run(70, "schedule")] };
    }
    if (path === `/repos/${REPO}/actions/runs/70/artifacts?per_page=100`) {
      const artifacts = state === null ? [] : [{ id: 900, name: "lane-level-state", expired: false }];
      return { total_count: artifacts.length, artifacts };
    }
    throw Object.assign(new Error(`unexpected ${method} ${path}`), { status: 404 });
  };
  return { actions, calls, download: () => JSON.stringify(state) };
}

function fakeLaneToken({ missing = false } = {}) {
  const writes = [];
  const github = async (method, path, body) => {
    writes.push({ method, path, body });
    if (missing && method === "PATCH") {
      throw Object.assign(new Error("Not Found"), { status: 404 });
    }
    return null;
  };
  return { github, writes };
}

async function decideWith({ laneLevel = {}, readings = QUIET, vars = {}, state = null, active = 5, lane } = {}) {
  const { actions, calls, download } = fakeActions({ active, state });
  const stateOut = join(dir, `state-${Math.random().toString(16).slice(2)}.json`);
  const lines = [];
  const original = console.log;
  console.log = (line) => lines.push(line);
  let decision;
  try {
    decision = await run({
      env: { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "72", RESOLVED_CONFIG: resolved(laneLevel), LANE_READINGS: readings, LANE_VARS: JSON.stringify(vars), STATE_OUT: stateOut },
      now: NOW,
      actions,
      download,
      github: lane?.github,
    });
  } finally {
    console.log = original;
  }
  return { decision, lines, calls, state: JSON.parse(readFileSync(stateOut, "utf8")) };
}

test("shadow: a quiet busy window after one clean window steps 3 to 4, writes no variable, and logs it", async () => {
  const lane = fakeLaneToken();
  const { decision, lines, state, calls } = await decideWith({ state: { level: 3, streak: 1, holdUntil: 0 }, lane });
  assert.deepEqual(decision, { level: 4, streak: 0, holdUntil: 0, reason: "step-up" });
  assert.deepEqual(lane.writes, [], "shadow mode wrote to GitHub");
  assert.deepEqual(state, { level: 4, streak: 0, holdUntil: 0, reason: "step-up", at: NOW_S });
  assert.deepEqual(
    calls,
    [
      `GET /repos/${REPO}/actions/workflows/work-unblock.yml/runs?branch=main&event=schedule&exclude_pull_requests=true&per_page=100&page=1`,
      `GET /repos/${REPO}/actions/runs/70/artifacts?per_page=100`,
      ...["queued", "in_progress", "waiting", "pending", "requested"].map((status) => `GET /repos/${REPO}/actions/workflows/work-resolve-issue.yml/runs?status=${status}&per_page=1`),
    ],
    "an hour's reads: one scheduled-run listing, one artifact listing, five run counts (the download is one more job-token call)",
  );
  assert.deepEqual(lines, [
    "::notice title=lane-level::level 4 (step-up, from 3); applied now: lane level 3 (shadow; would use 3, empty); shadow: would set CLAUDE_LANE_LEVEL to 4@1794363420; wrote nothing",
  ]);
});

test("live: the decided level is written to the level variable, valid for valid-minutes", async () => {
  const lane = fakeLaneToken();
  await decideWith({ laneLevel: { shadow: false, "valid-minutes": 90 }, state: { level: 3, streak: 1, holdUntil: 0 }, lane });
  assert.deepEqual(lane.writes, [{ method: "PATCH", path: `/repos/${REPO}/actions/variables/CLAUDE_LANE_LEVEL`, body: { name: "CLAUDE_LANE_LEVEL", value: `4@${NOW_S + 5400}` } }]);
});

test("live: a variable that does not exist yet is created", async () => {
  const lane = fakeLaneToken({ missing: true });
  await decideWith({ laneLevel: { shadow: false }, lane });
  assert.deepEqual(
    lane.writes.map(({ method, path }) => `${method} ${path}`),
    [`PATCH /repos/${REPO}/actions/variables/CLAUDE_LANE_LEVEL`, `POST /repos/${REPO}/actions/variables`],
  );
});

test("live with no lane token writes nothing and says so", async () => {
  const { lines } = await decideWith({ laneLevel: { shadow: false } });
  assert.match(lines.at(-1), /no lane token, so CLAUDE_LANE_LEVEL was not set to 3@\d+; it holds until it expires$/);
});

test("with no kept state the published level is the previous one; with neither, the default", async () => {
  const published = await decideWith({ vars: { CLAUDE_LANE_LEVEL: `4@${NOW_S + 600}` }, readings: "" });
  assert.deepEqual(published.decision, { level: 4, streak: 0, holdUntil: 0, reason: "missing-data" });
  const none = await decideWith({ readings: "" });
  assert.deepEqual(none.decision, { level: 3, streak: 0, holdUntil: 0, reason: "missing-data" });
});

test("demand: every unfinished status counts; past the applied level they wait for a slot, and none waiting with fewer running than L is no demand", async () => {
  // 1 in progress + 1 queued = 2 unfinished, under the applied 3.
  const idle = await decideWith({ state: { level: 3, streak: 1, holdUntil: 0 }, active: 1 });
  assert.equal(idle.decision.reason, "no-demand");
  // 2 in progress + 1 queued = 3: every slot running, which is demand.
  const full = await decideWith({ state: { level: 3, streak: 1, holdUntil: 0 }, active: 2 });
  assert.equal(full.decision.reason, "step-up");
  const counted = idle.calls.filter((call) => call.includes("work-resolve-issue.yml/runs?status=")).map((call) => /status=([a-z_]+)/.exec(call)[1]);
  assert.deepEqual(counted, ["queued", "in_progress", "waiting", "pending", "requested"]);
});

test("the lane token's readings go under lanes-app while the step's API_BUDGET_TOKEN is github-token", async () => {
  const temp = mkdtempSync(join(dir, "runner-"));
  const saved = { RUNNER_TEMP: process.env.RUNNER_TEMP, API_BUDGET_TOKEN: process.env.API_BUDGET_TOKEN };
  process.env.RUNNER_TEMP = temp;
  process.env.API_BUDGET_TOKEN = "github-token";
  try {
    const headers = { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4990", "x-ratelimit-used": "10", "x-ratelimit-reset": String(NOW_S + 600), "x-ratelimit-resource": "core" };
    const fetchImpl = async () => new Response(null, { status: 204, headers });
    await laneClient({ GH_TOKEN: "ghs_lane" }, fetchImpl)("PATCH", `/repos/${REPO}/actions/variables/CLAUDE_LANE_LEVEL`, { name: "CLAUDE_LANE_LEVEL", value: "3@1" });
    assert.match(readFileSync(join(temp, "api-budget", "lanes-app"), "utf8"), /^204 5000 4990 10 \d+ core repos\/\{repo\}\/actions\/variables\/\{x\}$/m);
    assert.throws(() => readFileSync(join(temp, "api-budget", "github-token"), "utf8"), /ENOENT/);
  } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("a limit signal halves the level and holds a step up until its reset", async () => {
  const refused = JSON.stringify({ at: NOW_S, pools: { "lanes-app": { used: 5000, limit: 5000 } }, signals: ["429"], reset: NOW_S + 600 });
  const { decision } = await decideWith({ readings: refused, state: { level: 4, streak: 1, holdUntil: 0 } });
  assert.deepEqual(decision, { level: 2, streak: 0, holdUntil: NOW_S + 600, reason: "step-down" });
});

test("the writer refuses every name but a *_LANE_LEVEL variable, and any malformed value, before a request", async () => {
  const lane = fakeLaneToken();
  for (const name of ["CLAUDE_LANES_DISABLED", "CLAUDE_LANES_REPO_DISABLED", "LANES_BROKER_URL", "", undefined]) {
    assert.throws(() => levelVariableWriter({ github: lane.github, repo: REPO, name }), /only a \*_LANE_LEVEL variable/, String(name));
  }
  const writer = levelVariableWriter({ github: lane.github, repo: REPO, name: "CLAUDE_LANE_LEVEL" });
  for (const value of ["false", "4", "4@1794363420; CLAUDE_LANES_REPO_DISABLED=false"]) {
    await assert.rejects(writer.write(value), /not <level>@<valid-until>/, value);
  }
  assert.deepEqual(lane.writes, []);
});

test("a configured kill switch name writes nothing and the run still ends with a notice", async () => {
  const lane = fakeLaneToken();
  const { lines } = await decideWith({ laneLevel: { shadow: false, variable: "CLAUDE_LANES_REPO_DISABLED" }, lane });
  assert.deepEqual(lane.writes, []);
  assert.match(lines.at(-1), /CLAUDE_LANES_REPO_DISABLED was not set: refusing to write variable "CLAUDE_LANES_REPO_DISABLED"/);
});
