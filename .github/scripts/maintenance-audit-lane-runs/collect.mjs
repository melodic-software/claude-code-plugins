// The lane sweep's collect job: reads the last day's runs and the open PRs
// through the REST API with the job's read-only token, and writes one data
// file per unit of model work, plus the open items the judge checks for
// coverage. No model. Stops gathering at its call budget and says so.
import { randomUUID } from "node:crypto";
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

export const MAX_UNITS = 8;
const A_WORKFLOWS = 4;
const D_WORKFLOWS = 2;
const PRS_PER_UNIT = 10;
const RUNS_PER_UNIT = 5;
const FAILED_JOBS_PER_RUN = 3;
const LOG_LINES = 60;
const ANSI = new RegExp(`${String.fromCharCode(27)}\\[[0-9;]*[A-Za-z]`, "g");
const LANE_WORKFLOW = /^\.github\/workflows\/(pr|work|intake)-[a-z0-9-]+\.ya?ml$/;
const SELF = ".github/workflows/maintenance-audit-lane-runs.yml";
// GitHub's run listing returns at most this many runs per filtered search.
const LIST_CAP = 1000;
// Calls the listing leaves for what follows: the open PR and issue reads (4)
// and the most the units can spend, four A units (5 runs, each a jobs read
// and 3 failed jobs' annotations and log), two D units (3 sampled runs) and
// the two C units left (10 PRs): 4 + 4 * 5 * 7 + 2 * 3 + 2 * 10.
export const DETAIL_RESERVE = 170;

export function createBudget(limit) {
  return {
    used: 0,
    limit,
    spend() {
      if (this.used >= limit) throw new Error(`call budget of ${limit} reached`);
      this.used += 1;
    },
  };
}

const ranked = (runs, keep) => {
  const groups = new Map();
  for (const r of runs) groups.set(r.path, [...(groups.get(r.path) ?? []), r.id]);
  return [...groups.entries()]
    .sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]))
    .slice(0, keep)
    .map(([workflow, runIds]) => ({ workflow, runIds }));
};

// Units in order A, D, C, at most MAX_UNITS; ids are slice letter plus position.
export function selectUnits({ repo, runs, pulls, trusted }) {
  const own = runs.filter((r) => r.head_repository?.full_name === repo);
  const units = [
    ...ranked(
      own.filter((r) => r.conclusion === "failure"),
      A_WORKFLOWS,
    ).map((u) => ({ slice: "A", ...u })),
    ...ranked(
      own.filter((r) => LANE_WORKFLOW.test(r.path)),
      D_WORKFLOWS,
    ).map((u) => ({ slice: "D", ...u })),
  ];
  const listed = pulls.filter((p) => trusted.has(String(p.user?.id)));
  for (let i = 0; i < listed.length; i += PRS_PER_UNIT) {
    units.push({
      slice: "C",
      pulls: listed.slice(i, i + PRS_PER_UNIT).map((p) => p.number),
    });
  }
  return units.slice(0, MAX_UNITS).map((u, i) => ({ id: `${u.slice.toLowerCase()}${i + 1}`, ...u }));
}

// The last `count` lines, with ANSI codes and the runner's timestamp prefix removed.
export function tailLog(text, count = LOG_LINES) {
  return String(text)
    .split("\n")
    .map((line) =>
      line
        .replace(ANSI, "")
        .replace(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z ?/, "")
        .trimEnd(),
    )
    .filter((line, i, all) => line !== "" || i < all.length - 1)
    .slice(-count)
    .join("\n");
}

const stamp = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");

// Every run of each workflow but this one created from `from` to `to` (whole
// seconds, both ends included). One per_page=1 call reads a workflow's count;
// a range at the listing cap is halved until each part fits. Listing stops
// before the budget's last `reserve` calls, and each workflow it could not
// read in full is in `partial` with the runs it read and its count (null
// when not read).
export async function listRuns({ gh, repo, from, to, budget, reserve = DETAIL_RESERVE }) {
  const room = () => budget.used < budget.limit - reserve;
  const workflows = [];
  for (let page = 1; ; page += 1) {
    const batch = await gh.call(`/repos/${repo}/actions/workflows?per_page=100&page=${page}`);
    workflows.push(...batch.workflows.filter((w) => w.path !== SELF));
    if (batch.workflows.length < 100) break;
  }
  const runsOf = (id, a, b) => `/repos/${repo}/actions/workflows/${id}/runs?created=${stamp(a)}..${stamp(b)}`;
  const count = async (id, a, b) => (await gh.call(`${runsOf(id, a, b)}&per_page=1`)).total_count;
  // Whether every run of the range was read into `got`.
  const list = async (id, a, b, total, got) => {
    if (total === 0) return true;
    if (total >= LIST_CAP && b - a >= 2000) {
      const mid = a + Math.floor((b - a) / 2000) * 1000;
      for (const [x, y] of [
        [a, mid],
        [mid + 1000, b],
      ]) {
        if (!room() || !(await list(id, x, y, await count(id, x, y), got))) return false;
      }
      return true;
    }
    let read = 0;
    for (let page = 1; page <= Math.ceil(Math.min(total, LIST_CAP) / 100); page += 1) {
      if (!room()) return false;
      const batch = await gh.call(`${runsOf(id, a, b)}&per_page=100&page=${page}`);
      for (const r of batch.workflow_runs) got.set(r.id, r);
      read += batch.workflow_runs.length;
      if (batch.workflow_runs.length < 100) break;
    }
    return read >= total;
  };
  const partial = [];
  const counted = [];
  for (const w of workflows) {
    if (room()) counted.push({ w, total: await count(w.id, from, to) });
    else partial.push({ path: w.path, listed: 0, total: null });
  }
  // Smallest first, so a budget that runs out leaves the fewest workflows part-read.
  counted.sort((x, y) => x.total - y.total || x.w.path.localeCompare(y.w.path));
  const runs = [];
  for (const { w, total } of counted) {
    const got = new Map();
    const whole = room() && (await list(w.id, from, to, total, got));
    runs.push(...got.values());
    if (!whole) partial.push({ path: w.path, listed: got.size, total });
  }
  return { runs, partial };
}

function client({ api, token, budget }) {
  const call = async (path, { text = false } = {}) => {
    budget.spend();
    const response = await fetch(`${api}${path}`, {
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${token}`,
        "x-github-api-version": "2022-11-28",
      },
    });
    if (!response.ok) throw new Error(`GET ${path}: HTTP ${response.status}`);
    return text ? response.text() : response.json();
  };
  return { call };
}

const seconds = (r) => Math.round((new Date(r.updated_at) - new Date(r.run_started_at ?? r.created_at)) / 1000);

async function detailA(gh, repo, unit) {
  const runs = [];
  for (const id of unit.runIds.slice(0, RUNS_PER_UNIT)) {
    const { jobs } = await gh.call(`/repos/${repo}/actions/runs/${id}/jobs?filter=latest&per_page=100`);
    const failed = [];
    for (const job of jobs.filter((j) => j.conclusion === "failure").slice(0, FAILED_JOBS_PER_RUN)) {
      const checkRunId = /\/check-runs\/(\d+)$/.exec(job.check_run_url ?? "")?.[1];
      const annotations = checkRunId
        ? (await gh.call(`/repos/${repo}/check-runs/${checkRunId}/annotations?per_page=50`)).map((a) => ({
            level: a.annotation_level,
            title: a.title,
            message: String(a.message).slice(0, 500),
            path: a.path,
            line: a.start_line,
          }))
        : [];
      let log;
      try {
        log = tailLog(
          await gh.call(`/repos/${repo}/actions/jobs/${job.id}/logs`, {
            text: true,
          }),
        );
      } catch (error) {
        if (/call budget/.test(error.message)) throw error;
        log = `log unavailable (${error.message})`;
      }
      failed.push({
        id: job.id,
        name: job.name,
        failed_steps: (job.steps ?? []).filter((s) => s.conclusion === "failure").map((s) => s.name),
        annotations,
        log_tail: log,
      });
    }
    runs.push({
      id,
      url: `https://github.com/${repo}/actions/runs/${id}`,
      failed_jobs: failed,
    });
  }
  return { runs };
}

async function detailD(gh, repo, unit, allRuns) {
  const mine = allRuns.filter((r) => unit.runIds.includes(r.id));
  const conclusions = {};
  for (const r of mine) conclusions[r.conclusion ?? r.status] = (conclusions[r.conclusion ?? r.status] ?? 0) + 1;
  const durations = mine.map(seconds).sort((a, b) => a - b);
  const sampled = [];
  for (const r of mine.filter((x) => x.conclusion === "success").slice(0, 3)) {
    const { jobs } = await gh.call(`/repos/${repo}/actions/runs/${r.id}/jobs?filter=latest&per_page=100`);
    sampled.push({
      id: r.id,
      url: `https://github.com/${repo}/actions/runs/${r.id}`,
      jobs: jobs.map((j) => ({
        name: j.name,
        conclusion: j.conclusion,
        seconds: Math.round((new Date(j.completed_at) - new Date(j.started_at)) / 1000),
        failed_steps_in_green_job: (j.steps ?? []).filter((s) => s.conclusion === "failure").map((s) => s.name),
      })),
    });
  }
  return {
    runs: mine.length,
    conclusions,
    reruns: mine.filter((r) => r.run_attempt > 1).length,
    seconds_median: durations[Math.floor(durations.length / 2)] ?? null,
    seconds_max: durations.at(-1) ?? null,
    events: [...new Set(mine.map((r) => r.event))],
    sampled_success_runs: sampled,
  };
}

async function detailC(gh, repo, unit, pullsByNumber) {
  const pulls = [];
  for (const number of unit.pulls) {
    const p = pullsByNumber.get(number);
    const { check_runs: checks } = await gh.call(`/repos/${repo}/commits/${p.head.sha}/check-runs?per_page=100`);
    const counts = {};
    for (const c of checks) counts[c.conclusion ?? c.status] = (counts[c.conclusion ?? c.status] ?? 0) + 1;
    pulls.push({
      number,
      title: p.title,
      draft: p.draft,
      labels: p.labels.map((l) => l.name),
      created_at: p.created_at,
      updated_at: p.updated_at,
      head_sha: p.head.sha,
      checks: counts,
      failing_checks: checks.filter((c) => c.conclusion === "failure").map((c) => c.name),
    });
  }
  return { pulls };
}

function writeOutput(file, name, value) {
  const delimiter = `ghadelimiter_${randomUUID()}`;
  appendFileSync(file, `${name}<<${delimiter}\n${value}\n${delimiter}\n`);
}

export async function main({ env = process.env, now = Date.now() } = {}) {
  const repo = env.REPOSITORY;
  const out = env.OUT_DIR;
  const budget = createBudget(Number(env.CALL_BUDGET ?? 350));
  const gh = client({
    api: env.GITHUB_API_URL,
    token: env.GITHUB_TOKEN,
    budget,
  });
  const list = JSON.parse(readFileSync(env.TRUSTED_ACTORS_PATH, "utf8"));
  const trusted = new Set(list.actors.map((a) => String(a.id)));
  if (/^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "")) trusted.add(env.LANES_APP_ID);
  // The window is fixed when the run starts, so runs created while it reads
  // do not move the pages under it.
  const to = Math.floor(now / 1000) * 1000;
  const from = to - Number(env.WINDOW_HOURS ?? 24) * 3_600_000;
  const since = new Date(from).toISOString();
  const until = new Date(to).toISOString();
  const { runs, partial } = await listRuns({ gh, repo, from, to, budget });
  const pulls = await gh.call(`/repos/${repo}/pulls?state=open&per_page=100`);
  const pullsByNumber = new Map(pulls.map((p) => [p.number, p]));
  const open = [];
  for (let page = 1; page <= 3; page += 1) {
    const batch = await gh.call(`/repos/${repo}/issues?state=open&per_page=100&page=${page}`);
    open.push(...batch.filter((i) => trusted.has(String(i.user?.id))));
    if (batch.length < 100) break;
  }

  const units = selectUnits({ repo, runs, pulls, trusted });
  mkdirSync(join(out, "units"), { recursive: true });
  const written = [];
  let truncated = null;
  for (const unit of units) {
    let detail;
    try {
      if (unit.slice === "A") detail = await detailA(gh, repo, unit);
      else if (unit.slice === "D") detail = await detailD(gh, repo, unit, runs);
      else detail = await detailC(gh, repo, unit, pullsByNumber);
    } catch (error) {
      if (!/call budget/.test(error.message)) throw error;
      truncated = `stopped at unit ${unit.id}: ${error.message}`;
      break;
    }
    // A unit of a workflow the listing read only part of says so.
    const window = { window_start: since, window_end: until };
    if (unit.workflow) window.window_complete = !partial.some((p) => p.path === unit.workflow);
    writeFileSync(join(out, "units", `${unit.id}.json`), `${JSON.stringify({ ...unit, ...window, ...detail }, null, 2)}\n`);
    written.push(unit.id);
  }
  writeFileSync(
    join(out, "open-items.json"),
    `${JSON.stringify(
      open.map((i) => ({
        number: i.number,
        kind: i.pull_request ? "pr" : "issue",
        title: i.title,
      })),
      null,
      2,
    )}\n`,
  );
  console.log(
    `collect: ${runs.length} runs, ${pulls.length} open PRs, units ${written.join(",") || "none"}, ${budget.used} calls`,
  );
  if (partial.length > 0) {
    const named = partial.map((p) => `${p.path} ${p.listed} of ${p.total ?? "an unread count of"} runs`).join(", ");
    console.log(`::warning::collect read part of the window for ${partial.length} workflow(s): ${named}`);
  }
  if (truncated) console.log(`::warning::collect ${truncated}`);
  writeOutput(env.GITHUB_OUTPUT, "units", JSON.stringify(written));
  writeOutput(env.GITHUB_OUTPUT, "calls", String(budget.used));
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
