import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { check, laneClient, levelVariableWriter, listVariables, run, snapshot } from "./publish-lane-level.mjs";

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

test("an expired, malformed or too-far published value is no previous level: decide() starts from the default", async () => {
  for (const value of [`4@${NOW_S}`, `4@${NOW_S - 3600}`, "4", `4@${NOW_S + 9001}`]) {
    const { decision } = await decideWith({ vars: { CLAUDE_LANE_LEVEL: value }, readings: "" });
    assert.deepEqual(decision, { level: 3, streak: 0, holdUntil: 0, reason: "missing-data" }, value);
  }
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

// GET /repos/{repo}/actions/variables as the REST docs describe it: per_page
// defaults to 10 and caps at 30, page counts from 1, and every page carries
// the whole total_count. `state.variables` is the repository's list, which a
// test edits between the two listings.
function variablesApi(initial) {
  const state = { variables: initial.map((variable) => ({ ...variable })), fail: false, calls: [] };
  const github = async (method, path) => {
    state.calls.push(`${method} ${path}`);
    const url = new URL(path, "https://api.github.invalid");
    if (method !== "GET" || url.pathname !== `/repos/${REPO}/actions/variables`) {
      throw Object.assign(new Error(`unexpected ${method} ${path}`), { status: 404 });
    }
    if (state.fail) {
      throw Object.assign(new Error("GET /repos/{repo}/actions/variables: 502"), { status: 502 });
    }
    const perPage = Math.min(Number(url.searchParams.get("per_page") ?? 10), 30);
    const page = Number(url.searchParams.get("page") ?? 1);
    return { total_count: state.variables.length, variables: state.variables.slice((page - 1) * perPage, page * perPage) };
  };
  return { github, state };
}

const variable = (name, value, updated_at = "2026-11-10T22:00:00Z") => ({ name, value, created_at: "2026-11-01T00:00:00Z", updated_at });
const LATER = "2026-11-10T23:47:30Z";
const BASE = [
  variable("CLAUDE_LANE_LEVEL", `3@${NOW_S}`),
  variable("CLAUDE_LANES_REPO_DISABLED", "false"),
  variable("LANES_BROKER_URL", "https://broker.example.invalid/mint"),
];

async function checkAround(initial, edit, { laneLevel = {}, failAfter = false } = {}) {
  const api = variablesApi(initial);
  const env = {
    GITHUB_REPOSITORY: REPO,
    RESOLVED_CONFIG: resolved({ shadow: false, ...laneLevel }),
    VARIABLES_STATE: join(dir, `variables-${Math.random().toString(16).slice(2)}.json`),
  };
  const lines = [];
  const original = console.log;
  console.log = (line) => lines.push(line);
  try {
    const listed = await snapshot({ env, github: api.github });
    edit(api.state.variables);
    api.state.fail = failAfter;
    const passed = await check({ env, github: api.github });
    return { listed, passed, lines, calls: api.state.calls, state: readFileSync(env.VARIABLES_STATE, "utf8") };
  } finally {
    console.log = original;
  }
}

const set = (list, name, value, updated_at = LATER) => {
  const found = list.find((v) => v.name === name);
  Object.assign(found, { value, updated_at });
};

test("variable check: a new level value passes, and so does creating the level variable", async () => {
  const changed = await checkAround(BASE, (list) => set(list, "CLAUDE_LANE_LEVEL", `4@${NOW_S + 9000}`));
  assert.equal(changed.passed, true);
  assert.equal(changed.lines.at(-1), "no repository variable changed but the level variable (3 listed)");
  const created = await checkAround(BASE.slice(1), (list) => list.push(variable("CLAUDE_LANE_LEVEL", `3@${NOW_S + 9000}`, LATER)));
  assert.equal(created.passed, true);
  assert.equal(created.lines.at(-1), "no repository variable changed but the level variable (3 listed)");
});

test("variable check: a created, changed or deleted variable fails, named with its change", async () => {
  const cases = [
    ["a new kill switch shadowing the organization's", (list) => list.push(variable("CLAUDE_LANES_DISABLED", "false", LATER)), "created CLAUDE_LANES_DISABLED"],
    ["the repository kill switch updated", (list) => set(list, "CLAUDE_LANES_REPO_DISABLED", "true"), "changed CLAUDE_LANES_REPO_DISABLED"],
    ["the broker endpoint deleted", (list) => list.splice(2, 1), "deleted LANES_BROKER_URL"],
    ["the broker endpoint rewritten with its own value", (list) => set(list, "LANES_BROKER_URL", "https://broker.example.invalid/mint"), "changed LANES_BROKER_URL"],
    ["the level variable deleted", (list) => list.splice(0, 1), "deleted CLAUDE_LANE_LEVEL"],
  ];
  for (const [label, edit, change] of cases) {
    const { listed, passed, lines } = await checkAround(BASE, edit);
    assert.equal(listed, true, label);
    assert.equal(passed, false, label);
    assert.equal(lines.at(-1), `::error title=lane-variables::lane-variables-changed: ${change}`, label);
  }
});

test("variable check: only the configured level variable may change, never a sibling *_LANE_LEVEL", async () => {
  const initial = [...BASE, variable("PR_LANE_LEVEL", `2@${NOW_S}`)];
  const { passed, lines } = await checkAround(initial, (list) => {
    set(list, "CLAUDE_LANE_LEVEL", `4@${NOW_S + 9000}`);
    set(list, "PR_LANE_LEVEL", `4@${NOW_S + 9000}`);
  });
  assert.equal(passed, false);
  assert.equal(lines.at(-1), "::error title=lane-variables::lane-variables-changed: changed PR_LANE_LEVEL");
});

test("variable check: a level variable configured to a kill switch name allows no change to it", async () => {
  const { passed, lines } = await checkAround(BASE, (list) => set(list, "CLAUDE_LANES_REPO_DISABLED", "true"), { laneLevel: { variable: "CLAUDE_LANES_REPO_DISABLED" } });
  assert.equal(passed, false);
  assert.equal(lines.at(-1), "::error title=lane-variables::lane-variables-changed: changed CLAUDE_LANES_REPO_DISABLED");
});

test("variable check: over 30 variables are paged 30 at a time, so a change on the second page fails", async () => {
  const many = Array.from({ length: 35 }, (_, i) => variable(`VAR_${String(i + 1).padStart(2, "0")}`, `value ${i + 1}`));
  const quiet = await checkAround(many, () => {});
  assert.equal(quiet.passed, true);
  assert.equal(quiet.lines.at(-1), "no repository variable changed but the level variable (35 listed)");
  assert.deepEqual(quiet.calls, [
    `GET /repos/${REPO}/actions/variables?per_page=30&page=1`,
    `GET /repos/${REPO}/actions/variables?per_page=30&page=2`,
    `GET /repos/${REPO}/actions/variables?per_page=30&page=1`,
    `GET /repos/${REPO}/actions/variables?per_page=30&page=2`,
  ], "two pages per listing for 35 variables");
  const changed = await checkAround(many, (list) => set(list, "VAR_33", "value 33"));
  assert.equal(changed.passed, false);
  assert.equal(changed.lines.at(-1), "::error title=lane-variables::lane-variables-changed: changed VAR_33");
});

test("variable check: a failed listing before or after the publish fails red", async () => {
  const api = variablesApi(BASE);
  api.state.fail = true;
  const env = { GITHUB_REPOSITORY: REPO, RESOLVED_CONFIG: resolved({ shadow: false }), VARIABLES_STATE: join(dir, "variables-unwritten.json") };
  const lines = [];
  const original = console.log;
  console.log = (line) => lines.push(line);
  let listed;
  let passed;
  try {
    listed = await snapshot({ env, github: api.github });
    passed = await check({ env, github: api.github });
  } finally {
    console.log = original;
  }
  assert.equal(listed, false);
  assert.match(lines[0], /^::error title=lane-variables::lane-variables-unread: the repository variables were not listed before the publish, so nothing is published \(.*502\)$/);
  assert.equal(passed, false, "with no listing before, the check cannot pass");
  assert.match(lines[1], /^::error title=lane-variables::lane-variables-unread: the listing before the publish was not read/);

  const after = await checkAround(BASE, () => {}, { failAfter: true });
  assert.equal(after.listed, true);
  assert.equal(after.passed, false);
  assert.match(after.lines.at(-1), /^::error title=lane-variables::lane-variables-unread: the repository variables were not listed after the publish/);
});

test("the variable listing throws when it falls short of total_count or the total shifts between pages", async () => {
  const short = async () => ({ total_count: 12, variables: [variable("A", "1"), variable("B", "2")] });
  await assert.rejects(listVariables({ github: short, repo: REPO }), /held 2 of its 12 variables/);
  let page = 0;
  const shifting = async () => {
    page += 1;
    return { total_count: page === 1 ? 31 : 32, variables: page === 1 ? Array.from({ length: 30 }, (_, i) => variable(`V${i}`, "x")) : [variable("V30", "x")] };
  };
  await assert.rejects(listVariables({ github: shifting, repo: REPO }), /page 2 .* total_count changed/);
  const repeated = async () => ({ total_count: 2, variables: [variable("A", "1"), variable("A", "1")] });
  await assert.rejects(listVariables({ github: repeated, repo: REPO }), /repeated variable/);
  const empty = async () => ({ total_count: 0, variables: [] });
  assert.deepEqual(await listVariables({ github: empty, repo: REPO }), {});
});

test("variable check: no variable value reaches the logs or the state file", async () => {
  const { lines, state } = await checkAround(BASE, (list) => set(list, "LANES_BROKER_URL", "https://attacker.example.invalid/mint"));
  for (const text of [...lines, state]) {
    assert.ok(!text.includes("broker.example.invalid") && !text.includes("attacker.example.invalid"), `a value leaked: ${text}`);
  }
  assert.equal(lines.at(-1), "::error title=lane-variables::lane-variables-changed: changed LANES_BROKER_URL");
});
