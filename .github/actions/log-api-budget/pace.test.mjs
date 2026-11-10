// The burn-rate pacer's rules (pace.mjs): a timer-driven run is paced when
// the GITHUB_TOKEN pool's remaining at its reset, projected at the burn rate
// the window has shown so far, falls under `pace` of the header's limit, the
// share the breaker is also stated in (pr-pipeline.schema.json api-pool).
// Expected values are worked by hand from limit, remaining and reset.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { main, paceDecision, previousRun } from "./pace.mjs";
import { apiLimits } from "./rate-guard.mjs";
import { PACED_LOOKBACK_HOURS, PACED_STEP, SWEEP_MARGIN_MIN } from "../../scripts/work-unblock/label-unblocked.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const NOW = 1_800_000_000;

test("the pace share is a config value: rate-limits.json's github-token default, under limits.api", () => {
  assert.equal(apiLimits({ resolvedPath: "" })["github-token"].pace, 0.2);
  const dir = tempDir("pace-config-");
  const resolved = join(dir, "resolved.json");
  writeFileSync(resolved, JSON.stringify({ limits: { api: { "github-token": { pace: 0.35 } } } }));
  assert.equal(apiLimits({ resolvedPath: resolved })["github-token"].pace, 0.35);
  // The schema lets limits.api set it, in the same range as the breaker.
  const schema = JSON.parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json", import.meta.url), "utf8"));
  assert.deepEqual(
    { ...schema.$defs["api-pool"].properties.pace, description: undefined },
    { ...schema.$defs["api-pool"].properties.breaker, description: undefined },
  );
});

test("a run is paced when the projected remaining at reset falls under the share", () => {
  // 30 minutes in: 2,000 of 5,000 used, so 2,000 more by the reset leaves 1,000, 20%.
  const half = { limit: 5000, remaining: 3000, reset: NOW + 1800 };
  assert.deepEqual(paceDecision(half, 0.2, NOW), { paced: false, projected: 0.2 });
  // 2,100 used: 2,100 more leaves 800, 16%.
  assert.deepEqual(paceDecision({ ...half, remaining: 2900 }, 0.2, NOW), { paced: true, projected: 0.16 });
  // The evidence window's reading: used 4,289, remaining 711, about 4 minutes to reset.
  assert.equal(paceDecision({ limit: 5000, remaining: 711, reset: NOW + 252 }, 0.2, NOW).paced, true);
  // A slow burn early in the window: 100 used in 10 minutes projects 500 more, 4,400 left.
  assert.deepEqual(paceDecision({ limit: 5000, remaining: 4900, reset: NOW + 3000 }, 0.2, NOW), { paced: false, projected: 0.88 });
  // A projection under zero is clamped to it.
  assert.deepEqual(paceDecision({ limit: 1000, remaining: 100, reset: NOW + 1800 }, 0.2, NOW), { paced: true, projected: 0 });
});

test("the first minute projects nothing, so only the remaining itself can pace it", () => {
  assert.deepEqual(paceDecision({ limit: 5000, remaining: 4000, reset: NOW + 3590 }, 0.2, NOW), { paced: false, projected: 0.8 });
  assert.deepEqual(paceDecision({ limit: 5000, remaining: 900, reset: NOW + 3590 }, 0.2, NOW), { paced: true, projected: 0.18 });
});

test("a reading that cannot project, or a share of 0, never paces", () => {
  for (const reading of [{}, { limit: 0, remaining: 0, reset: NOW + 60 }, { limit: 5000, remaining: "na", reset: NOW + 60 }, { limit: 5000, remaining: 100, reset: NOW - 10 }, { limit: 5000, remaining: 6000, reset: NOW + 60 }]) {
    assert.equal(paceDecision(reading, 0.2, NOW).paced, false, JSON.stringify(reading));
  }
  assert.equal(paceDecision({ limit: 5000, remaining: 10, reset: NOW + 1800 }, 0, NOW).paced, false);
});

// A fake GitHub for main: the workflow's scheduled-run listing, whose headers
// are the pool reading, and each listed run's jobs. `runs` is newest first;
// `steps[id]` is the conclusion of the lane's work step in run `id`
// (undefined: the run has no such step).
const HOT = { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "2900", "x-ratelimit-reset": String(NOW + 1800) };
const COLD = { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4900", "x-ratelimit-reset": String(NOW + 3000) };
const WORK_STEP = "Do the sweep";
const minutesAgo = (minutes) => new Date((NOW - minutes * 60) * 1000).toISOString();
function github({ headers = HOT, runs = [], steps = {}, listStatus = 200, jobsStatus = 200 } = {}) {
  const urls = [];
  const fetchImpl = async (url) => {
    urls.push(url);
    const jobs = /\/actions\/runs\/([0-9]+)\/jobs\?filter=latest&per_page=100$/.exec(url);
    if (jobs) {
      const conclusion = steps[jobs[1]];
      const body = { jobs: [{ name: "sweep", steps: [{ name: "Set up job", conclusion: "success" }, ...(conclusion === undefined ? [] : [{ name: WORK_STEP, conclusion }])] }] };
      return new Response(JSON.stringify(body), { status: jobsStatus });
    }
    assert.equal(url, "https://api.github.com/repos/o/r/actions/workflows/lane.yml/runs?event=schedule&per_page=5");
    return new Response(JSON.stringify({ workflow_runs: runs }), { status: listStatus, headers });
  };
  return { fetchImpl, urls };
}
// This run (id 9) and the scheduled run before it (id 8), created an hour apart.
const LANE = { GITHUB_RUN_ID: "9", GITHUB_WORKFLOW_REF: "o/r/.github/workflows/lane.yml@refs/heads/main", PACE_WORK_STEP: WORK_STEP };
const PAIR = [
  { id: 9, created_at: minutesAgo(1) },
  { id: 8, created_at: minutesAgo(61) },
];
const run = async (env, fetchImpl) => {
  const dir = tempDir("pace-");
  const output = join(dir, "output");
  writeFileSync(output, "");
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    await main({ GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: output, RUNNER_TEMP: dir, EVENT_NAME: "schedule", ...LANE, ...env }, { fetchImpl, now: () => NOW });
  } finally {
    console.log = log;
  }
  return { output: readFileSync(output, "utf8"), lines };
};

test("a hot tick after a scheduled run that did its work is paced, with a notice", async () => {
  const gh = github({ runs: PAIR, steps: { 8: "success" } });
  const got = await run({}, gh.fetchImpl);
  assert.equal(got.output, "paced=true\n");
  assert.deepEqual(got.lines, ["::notice title=api-pace::github-token projected=0.16 pace=0.2 paced=true; this tick skips its work, run 8 did the last"]);
  assert.equal(gh.urls.length, 2, "the listing, then run 8's jobs");
  assert.match(gh.urls[1], /\/actions\/runs\/8\/jobs\?/);
});

test("a cold tick reads only the listing and runs", async () => {
  const gh = github({ headers: COLD, runs: PAIR, steps: { 8: "success" } });
  const got = await run({}, gh.fetchImpl);
  assert.equal(got.output, "paced=false\n");
  assert.deepEqual(got.lines, ["::notice title=api-pace::github-token projected=0.88 pace=0.2 paced=false"]);
  assert.equal(gh.urls.length, 1, "no jobs read while the projection does not pace");
});

// The guarantee: whatever other events do to the run counter, two scheduled
// ticks in a row are never both paced, and a pool that stays hot paces every
// other one. Each tick's listing holds the runs before it; a paced run's
// work step is skipped, an unpaced one's succeeds. The run numbers are
// pr-merge's real consecutive scheduled pair 12822 and 12826 (both even, so
// run-number parity paced both) and more of the same kind.
test("hot ticks alternate, paced and not, however the run numbers fall", async () => {
  const numbers = [12822, 12826, 12830, 12834, 12836, 12840, 12841, 12850];
  const runs = [];
  const steps = {};
  const pacedTicks = [];
  for (const [index, number] of numbers.entries()) {
    const id = 1000 + index;
    runs.unshift({ id, run_number: number, created_at: minutesAgo(numbers.length - index) });
    const gh = github({ runs: runs.slice(0, 3), steps });
    const paced = (await run({ GITHUB_RUN_ID: String(id), RUN_NUMBER: String(number) }, gh.fetchImpl)).output === "paced=true\n";
    steps[id] = paced ? "skipped" : "success";
    pacedTicks.push(paced);
  }
  assert.deepEqual(pacedTicks, [false, true, false, true, false, true, false, true]);
});

test("a previous scheduled run that did not finish its work, or none, keeps the tick running", async () => {
  const cases = [
    ["skipped", "run 8, the last scheduled one, shows no successful `Do the sweep`"],
    ["failure", "run 8, the last scheduled one, shows no successful `Do the sweep`"],
    [null, "run 8, the last scheduled one, shows no successful `Do the sweep`"],
    [undefined, "run 8, the last scheduled one, shows no successful `Do the sweep`"],
  ];
  for (const [conclusion, why] of cases) {
    const got = await run({}, github({ runs: PAIR, steps: { 8: conclusion } }).fetchImpl);
    assert.equal(got.output, "paced=false\n", String(conclusion));
    assert.deepEqual(got.lines, [`::notice title=api-pace::github-token projected=0.16 pace=0.2 paced=false; this tick runs: ${why}`]);
  }
  const alone = await run({}, github({ runs: [PAIR[0]] }).fetchImpl);
  assert.match(alone.lines[0], /paced=false; this tick runs: no earlier scheduled run$/);
  // A newer scheduled run listed ahead of this one is not its previous run.
  const newer = [{ id: 10, created_at: minutesAgo(0) }, ...PAIR];
  assert.equal((await run({}, github({ runs: newer, steps: { 10: "success", 8: "skipped" } }).fetchImpl)).output, "paced=false\n");
  const unnamed = await run({ PACE_WORK_STEP: "" }, github({ runs: PAIR, steps: { 8: "success" } }).fetchImpl);
  assert.match(unnamed.lines[0], /this tick runs: no PACE_WORK_STEP names this lane's work$/);
});

// The previous run is the highest id below this one, whatever created_at
// says: on 2026-11-01 runs were stamped an hour ahead (rotation.mjs runOrder).
test("the previous scheduled run is found by run id, not by its creation time", async () => {
  // Run 8 is stamped later than this run; run 7, stamped between, came before 8.
  const skewed = [
    { id: 8, created_at: minutesAgo(-60) },
    { id: 9, created_at: minutesAgo(1) },
    { id: 7, created_at: minutesAgo(30) },
  ];
  const gh = github({ runs: skewed, steps: { 8: "success", 7: "skipped" } });
  assert.equal((await run({}, gh.fetchImpl)).output, "paced=true\n");
  assert.match(gh.urls[1], /\/actions\/runs\/8\/jobs\?/);
  assert.equal((await run({}, github({ runs: skewed, steps: { 8: "skipped", 7: "success" } }).fetchImpl)).output, "paced=false\n");
  assert.equal(previousRun(skewed, "9")?.id, 8);
  assert.equal(previousRun(skewed, "7"), undefined, "no run below the lowest");
  assert.equal(previousRun([{ id: "8" }, { id: 7 }], "9")?.id, 7, "an id that is no number is left out");
  assert.equal(previousRun(skewed, ""), undefined, "no run id of its own");
});

test("any other event, an unreadable answer or a failed read is never paced", async () => {
  let calls = 0;
  const counting = async () => {
    calls += 1;
    return new Response("{}", { status: 200 });
  };
  for (const event of ["workflow_dispatch", "push", "pull_request", "pull_request_target", "merge_group", "issues", "workflow_run", ""]) {
    assert.equal((await run({ EVENT_NAME: event }, counting)).output, "paced=false\n", `event ${JSON.stringify(event)}`);
  }
  assert.equal(calls, 0, "no read off a schedule tick");
  assert.equal((await run({}, counting)).output, "paced=false\n", "no headers");
  assert.equal((await run({}, github({ runs: PAIR, steps: { 8: "success" }, listStatus: 502 }).fetchImpl)).output, "paced=false\n", "a failed listing");
  const jobsDown = await run({}, github({ runs: PAIR, steps: { 8: "success" }, jobsStatus: 502 }).fetchImpl);
  assert.equal(jobsDown.output, "paced=false\n", "a failed jobs read");
  assert.match(jobsDown.lines.join("\n"), /::warning::/);
  const noRef = await run({ GITHUB_WORKFLOW_REF: "" }, github({ runs: PAIR, steps: { 8: "success" } }).fetchImpl);
  assert.equal(noRef.output, "paced=false\n", "no workflow file to list");
  const throws = async () => {
    throw new Error("down");
  };
  const failed = await run({}, throws);
  assert.equal(failed.output, "paced=false\n");
  assert.match(failed.lines.join("\n"), /::warning::/);
});

// The step that hands the base config's limits.api to the pacer, in
// resolve-config's output shape, which apiLimits reads.
const READ_STEP = "Read the pace override from the base config";
const READ_RUN = `yq -o=json '{"limits": {"api": (.limits.api // {})}}' .base/docs/conventions/pr-pipeline.yaml >"$RUNNER_TEMP/pace-config.json"`;

// The documented off switch, limits.api github-token pace: 0 in
// pr-pipeline.yaml, through that step to main: a pool burning toward the
// breaker after a tick that did its work runs, with no pace notice.
test("pace: 0 in the base config turns the pacer off", async () => {
  const dir = tempDir("pace-off-");
  mkdirSync(join(dir, ".base/docs/conventions"), { recursive: true });
  const read = (yaml) => {
    writeFileSync(join(dir, ".base/docs/conventions/pr-pipeline.yaml"), yaml);
    const result = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", READ_RUN], { cwd: dir, env: { PATH: process.env.PATH, RUNNER_TEMP: dir }, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    return join(dir, "pace-config.json");
  };
  const low = github({ runs: PAIR, steps: { 8: "success" } }).fetchImpl;
  const off = await run({ RESOLVED_CONFIG: read("limits:\n  api:\n    github-token:\n      pace: 0\n") }, low);
  assert.equal(off.output, "paced=false\n");
  assert.deepEqual(off.lines, []);
  // With no api entry the rate-limits.json default paces the same reading.
  assert.equal((await run({ RESOLVED_CONFIG: read("limits:\n  wip-cap: 12\n") }, low)).output, "paced=true\n");
  assert.equal(apiLimits({ resolvedPath: read("lanes: {}\n") })["github-token"].pace, 0.2, "no limits section");
});

const PACE_STEP = "Pace the tick on the GITHUB_TOKEN burn rate";
const WORK_DONE = "Mark this tick's work done";
const workflow = (file) => readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
// A job's text, from `  <job>:` to the next job, and its steps, each less the
// blank and comment lines that lead into the next step.
const jobOf = (file, job) => new RegExp(`\\n  ${job}:\\n([\\s\\S]*?)(?=\\n  [a-z0-9-]+:\\n|$)`).exec(workflow(file))?.[1] ?? "";
const stepsOf = (file, job) =>
  jobOf(file, job)
    .split(/\n(?= {6}- name: )/)
    .slice(1)
    .map((s) => ({ name: /^ {6}- name: (.*)$/m.exec(s)[1], s: s.replace(/(\n *(#[^\n]*)?)+$/, "") }));

// The pacer step and the override read before it, in the one shape every
// paced lane uses.
function assertPaceSteps(file, steps) {
  const at = (name) => steps.findIndex((step) => step.name === name);
  const pace = steps[at(PACE_STEP)]?.s ?? "";
  // The base config's limits.api reaches the pacer, so its pace (0 for off)
  // overrides rate-limits.json.
  assert.ok(at(READ_STEP) >= 0 && at(READ_STEP) < at(PACE_STEP), `${file}: the override is read before the pacer`);
  assert.equal(steps[at(READ_STEP)].s.replace(/^[\s\S]*?\n {8}run: \|\n {10}/, ""), READ_RUN, file);
  assert.match(steps[at(READ_STEP)].s, /\n {8}continue-on-error: true\n/, file);
  assert.equal(/\n {8}if: (.*)\n/.exec(steps[at(READ_STEP)].s)?.[1], /\n {8}if: (.*)\n/.exec(pace)?.[1], `${file}: the read runs when the pacer does`);
  assert.match(pace, /\n {10}RESOLVED_CONFIG: \$\{\{ runner\.temp \}\}\/pace-config\.json\n/, file);
  assert.match(pace, /\n {8}id: pace\n/, file);
  assert.match(pace, /\n {8}continue-on-error: true\n/, file);
  assert.match(pace, /\n {10}EVENT_NAME: \$\{\{ github\.event_name \}\}\n/, file);
  assert.doesNotMatch(pace, /RUN_NUMBER/, `${file}: the run counter plays no part`);
  assert.match(pace, /\n {8}run: node \.base\/\.github\/actions\/log-api-budget\/pace\.mjs\n?$/, file);
  return { at, work: /\n {10}PACE_WORK_STEP: (.*)\n/.exec(pace)?.[1] };
}

// Each lane's marker, the step whose success in the previous scheduled run
// lets a tick pace: named once in the workflow, so no other step stands in
// for it; run only on the lane's clean outcome (`clean`), with no status
// function, so any earlier failed step skips it; and the step that writes
// that outcome waits on the pacer, through `chain` (each link's `if:` reads
// the one before it, the first reads the pacer), so a paced tick skips it.
function assertMarker(file, steps, work, clean, chain) {
  const at = (name) => steps.findIndex((step) => step.name === name);
  assert.equal(work, WORK_DONE, file);
  assert.equal(workflow(file).split(`\n      - name: ${work}\n`).length, 2, `${file}: \`${work}\` is named once`);
  const marker = /\n {8}if: (.*)\n/.exec(steps[at(work)]?.s ?? "")?.[1];
  assert.equal(marker, clean, `${file}: the marker waits on the clean outcome`);
  assert.doesNotMatch(marker, /always\(\)|cancelled\(\)|failure\(\)/, file);
  if (chain.length === 0) return;
  assert.match(steps[at(chain[0][0])]?.s ?? "", /\n {8}if: .*steps\.pace\.outputs\.paced != 'true'/s, `${file}: ${chain[0][0]} waits on the pacer`);
  for (const [name, reads] of chain.slice(1)) {
    assert.match(/\n {8}if: (.*)\n/.exec(steps[at(name)]?.s ?? "")?.[1] ?? "", reads, `${file}: ${name}`);
  }
  assert.ok(at(work) > at(chain.at(-1)[0]), `${file}: the marker follows ${chain.at(-1)[0]}`);
}

// The timer-driven lanes that read the pacer: each reads it once on the
// event, never fails on it, and gates every step that spends the pool.
test("each paced timer lane reads the pacer before its work and gates every spending step on it", () => {
  const dispatch = "Dispatch pr-unblock for conflicting, review-tier Dependabot and failing lanes App PRs";
  const lanes = {
    "maintenance-reconcile-lost-runs.yml": {
      job: "reconcile",
      gated: ["Find lost runs", "Re-run lost runs"],
      clean: "steps.plan.outputs.clean == 'true'",
      chain: [["Find lost runs"]],
    },
    "pr-unblock-dispatch.yml": {
      job: "dispatch",
      gated: ["Install resolve-config's dependencies", "Restore the dispatch record", dispatch],
      clean: "steps.dispatch.outputs.listed == 'true'",
      chain: [[dispatch]],
    },
    // Every later spending step waits on the config step's lane token.
    "work-unblock.yml": {
      job: "label-unblocked",
      gated: ["Resolve the config"],
      clean: "steps.label.outputs.clean-sweep == 'true'",
      chain: [
        ["Resolve the config"],
        ["Request the lane token", /steps\.config\.outcome == 'success'/],
        ["Label the unblocked issues", /^steps\.lane-token\.outputs\.token != ''$/],
      ],
    },
  };
  for (const [file, { job, gated, clean, chain }] of Object.entries(lanes)) {
    const steps = stepsOf(file, job);
    const { at, work } = assertPaceSteps(file, steps);
    for (const name of gated) {
      assert.ok(at(name) > at(PACE_STEP), `${file}: ${name} follows the pacer`);
      assert.match(steps[at(name)].s, /steps\.pace\.outputs\.paced != 'true'/, `${file}: ${name}`);
    }
    assertMarker(file, steps, work, clean, chain);
  }
});

// The monitoring lane reads a fixed window (WINDOW_MINUTES, 65) and its
// signals count what falls inside it (signals.mjs throttleFindings counts
// rate-limited holds by windowStart), so a skipped hour would never be read,
// and in the hot hours pacing acts in. It stays unpaced.
test("the monitoring lane reads no pacer", () => {
  assert.doesNotMatch(workflow("maintenance-monitor-signals.yml"), /pace\.mjs|steps\.pace\./);
});

// A paced work-unblock run marks itself (PACED_STEP), and the sweep after it
// reads back from the clean sweep before it, up to PACED_LOOKBACK_HOURS
// (label-unblocked.test.mjs drives that window). With the clean sweep S, the
// paced tick one cron period later and the tick after it dropped, the next
// sweep starts three periods after S, plus its wait in the job's concurrency
// group, and reads from SWEEP_MARGIN_MIN before S: that must fit.
test("work-unblock marks a paced run, and the sweep after it reaches back past a dropped tick", () => {
  const text = workflow("work-unblock.yml");
  const steps = stepsOf("work-unblock.yml", "label-unblocked");
  const at = (name) => steps.findIndex((step) => step.name === name);
  assert.ok(at(PACED_STEP) > at(PACE_STEP), "after the pacer");
  assert.equal(/\n {8}if: (.*)\n/.exec(steps[at(PACED_STEP)].s)?.[1], "steps.pace.outputs.paced == 'true'");
  const crons = [...text.matchAll(/\n {4}- cron: "([0-9]+) ([0-9,-]+) \* \* \*"(?=\n)/g)];
  assert.ok(crons.length > 0, "the schedule is read");
  const hours = (field) => field.split(",").flatMap((part) => {
    const [from, to = from] = part.split("-").map(Number);
    return Array.from({ length: to - from + 1 }, (_, i) => from + i);
  });
  const fires = crons.flatMap(([, minute, hour]) => hours(hour).map((h) => h * 60 + Number(minute))).sort((a, b) => a - b);
  const period = Math.max(...fires.map((at, i) => (i === 0 ? at + 1440 : at) - fires.at(i - 1)));
  assert.equal(period, 60, "hourly");
  const wait = Number(/\n {4}timeout-minutes: ([0-9]+)\n/.exec(jobOf("work-unblock.yml", "label-unblocked"))?.[1]);
  assert.equal(wait, 10);
  const reach = 3 * period + wait + SWEEP_MARGIN_MIN;
  assert.ok(reach <= PACED_LOOKBACK_HOURS * 60, `${reach} minutes inside ${PACED_LOOKBACK_HOURS} h`);
});

// pr-merge's sweep jobs skip at job level: a step-level skip would leave a
// paced run's job waiting in its group, and superseded.mjs would let an
// earlier run hand its work to it. post-merge-dispatch reads the pacer and
// never waits on it, so the post-merge check and cover dispatch run on every
// tick.
test("pr-merge reads the pacer in post-merge-dispatch and skips only the sweep jobs on it", () => {
  const file = "pr-merge.yml";
  const steps = stepsOf(file, "post-merge-dispatch");
  const { work } = assertPaceSteps(file, steps);
  // The merge job, which a paced tick skips whole, marks a sweep that listed
  // (a held listing writes held, never listed) and gated.
  assertMarker(file, stepsOf(file, "merge"), work, "steps.candidates.outputs.listed == 'true' && steps.gate.outcome == 'success'", []);
  const merge = stepsOf(file, "merge");
  const index = (name) => merge.findIndex((step) => step.name === name);
  assert.ok(index(work) > index("Run the merge gate on each candidate"), "the marker follows the gate");
  assert.match(jobOf(file, "post-merge-dispatch"), /\n {4}outputs:\n(?: {6}.*\n)*? {6}paced: \$\{\{ steps\.pace\.outputs\.paced \}\}\n/);
  const waiting = steps.filter((step) => /steps\.pace\.outputs/.test(step.s)).map((step) => step.name);
  assert.deepEqual(waiting, [], "no post-merge-dispatch step waits on the pacer");
  for (const job of ["merge", "enable-auto-merge"]) {
    const gate = /\n {4}if: >-\n((?: {6}.*\n)+)/.exec(jobOf(file, job))?.[1] ?? "";
    assert.match(gate, /\n {6}&& needs\.post-merge-dispatch\.outputs\.paced != 'true'\n/, job);
    assert.doesNotMatch(jobOf(file, job), /steps\.pace\./, `${job} reads no pacer of its own`);
  }
});
