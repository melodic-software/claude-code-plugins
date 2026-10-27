// The collector's unit rules from docs/conventions/pr-pipeline/README.md,
// "The lane sweep": slice A takes the four workflows with the most failed
// runs, slice D the two lane workflows with the most runs, slice C open PRs by
// listed authors in tens, fork runs never count, at most 8 units, and the
// collector stops at its call budget. The listing reads every run of the
// window: GitHub's run listing returns at most 1,000 runs per filtered search
// (REST "List workflow runs for a workflow"), so a range over that is split.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { createBudget, DETAIL_RESERVE, listRuns, main, selectUnits, tailLog } from "./collect.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const run = (id, path, conclusion, over = {}) => ({
  id,
  path,
  conclusion,
  head_repository: { full_name: "o/r" },
  ...over,
});

test("slice A takes the four workflows with the most failed same-repository runs", () => {
  const runs = [
    ...[1, 2, 3].map((id) => run(id, ".github/workflows/a.yml", "failure")),
    ...[4, 5].map((id) => run(id, ".github/workflows/b.yml", "failure")),
    run(6, ".github/workflows/c.yml", "failure"),
    run(7, ".github/workflows/d.yml", "failure"),
    run(8, ".github/workflows/e.yml", "success"),
    ...[9, 10, 11, 12].map((id) =>
      run(id, ".github/workflows/fork.yml", "failure", {
        head_repository: { full_name: "x/r" },
      }),
    ),
  ];
  const units = selectUnits({
    repo: "o/r",
    runs,
    pulls: [],
    trusted: new Set(),
  });
  assert.deepEqual(
    units.filter((u) => u.slice === "A").map((u) => [u.workflow, u.runIds]),
    [
      [".github/workflows/a.yml", [1, 2, 3]],
      [".github/workflows/b.yml", [4, 5]],
      [".github/workflows/c.yml", [6]],
      [".github/workflows/d.yml", [7]],
    ],
  );
});

test("slice D takes the two lane workflows with the most runs, successes included", () => {
  const runs = [
    ...[1, 2, 3].map((id) => run(id, ".github/workflows/pr-merge.yml", "success")),
    ...[4, 5].map((id) => run(id, ".github/workflows/work-unblock.yml", "skipped")),
    run(6, ".github/workflows/pr-refine.yml", "failure"),
    ...[7, 8, 9, 10].map((id) => run(id, ".github/workflows/release-publish-plugins.yml", "success")),
  ];
  const units = selectUnits({
    repo: "o/r",
    runs,
    pulls: [],
    trusted: new Set(),
  });
  assert.deepEqual(
    units.filter((u) => u.slice === "D").map((u) => [u.workflow, u.runIds.length]),
    [
      [".github/workflows/pr-merge.yml", 3],
      [".github/workflows/work-unblock.yml", 2],
    ],
  );
});

test("slice C takes listed authors' open PRs in tens, and units stop at 8", () => {
  const pulls = Array.from({ length: 25 }, (_, i) => ({
    number: i + 1,
    user: { id: i % 5 === 0 ? 99 : 1 },
  }));
  const runs = Array.from({ length: 6 }, (_, i) => run(i + 1, `.github/workflows/w${i}.yml`, "failure"));
  const units = selectUnits({
    repo: "o/r",
    runs,
    pulls,
    trusted: new Set(["1"]),
  });
  assert.deepEqual(
    units.filter((u) => u.slice === "C").map((u) => u.pulls.length),
    [10, 10],
  );
  assert.equal(units.length, 6);
  assert.ok(units.every((u, i) => u.id === `${u.slice.toLowerCase()}${i + 1}`));
  const many = selectUnits({
    repo: "o/r",
    runs: [...runs, ...[1, 2, 3].map((id) => run(100 + id, `.github/workflows/pr-x${id}.yml`, "success"))],
    pulls: Array.from({ length: 40 }, (_, i) => ({
      number: i + 1,
      user: { id: 1 },
    })),
    trusted: new Set(["1"]),
  });
  assert.equal(many.length, 8);
});

test("the budget refuses the call past its limit", () => {
  const budget = createBudget(2);
  budget.spend();
  budget.spend();
  assert.throws(() => budget.spend(), /call budget of 2/);
  assert.equal(budget.used, 2);
});

test("a log tail keeps the last lines without ANSI codes or timestamps", () => {
  const log = ["2026-10-17T21:13:05.1234567Z one", "2026-10-17T21:13:06.0000000Z \u001b[31mtwo\u001b[0m", "three"].join(
    "\n",
  );
  assert.equal(tailLog(log, 2), "two\nthree");
});

// A fake of the two listing endpoints over a fixed run set. A run listing
// answers at most 1,000 runs of a created range, as GitHub does, and its
// total_count is every run in the range.
const FROM = Date.parse("2026-10-22T00:00:00Z");
const TO = Date.parse("2026-10-23T00:00:00Z");
const WORKFLOWS = [
  { id: 1, path: ".github/workflows/pr-merge.yml" },
  { id: 2, path: ".github/workflows/ci.yml" },
  { id: 3, path: ".github/workflows/empty.yml" },
  { id: 4, path: ".github/workflows/maintenance-audit-lane-runs.yml" },
];
const at = (ms) => new Date(ms).toISOString();
function fakeRuns() {
  const runs = [];
  // 2,500 pr-merge runs, one every 30 s from the window start.
  for (let i = 0; i < 2500; i += 1) runs.push(run(10_000 + i, WORKFLOWS[0].path, "success", { created_at: at(FROM + i * 30_000) }));
  for (let i = 0; i < 50; i += 1) runs.push(run(20_000 + i, WORKFLOWS[1].path, "failure", { created_at: at(FROM + i * 600_000) }));
  for (let i = 0; i < 5; i += 1) runs.push(run(30_000 + i, WORKFLOWS[3].path, "success", { created_at: at(FROM + i * 1000) }));
  // Outside the window on both sides.
  runs.push(run(40_000, WORKFLOWS[1].path, "failure", { created_at: at(FROM - 1000) }));
  runs.push(run(40_001, WORKFLOWS[1].path, "failure", { created_at: at(TO + 1000) }));
  return runs;
}
function fakeGh(budget, runs = fakeRuns(), workflows = WORKFLOWS) {
  const calls = [];
  const call = async (path) => {
    budget.spend();
    calls.push(path);
    const url = new URL(path, "https://api.test");
    const page = Number(url.searchParams.get("page") ?? "1");
    const perPage = Number(url.searchParams.get("per_page"));
    if (url.pathname === "/repos/o/r/actions/workflows") {
      return { total_count: workflows.length, workflows: page === 1 ? workflows : [] };
    }
    const id = Number(/^\/repos\/o\/r\/actions\/workflows\/(\d+)\/runs$/.exec(url.pathname)?.[1]);
    const [a, b] = url.searchParams.get("created").split("..").map(Date.parse);
    const path_ = workflows.find((w) => w.id === id).path;
    const matching = runs
      .filter((r) => r.path === path_ && Date.parse(r.created_at) >= a && Date.parse(r.created_at) <= b)
      .sort((x, y) => Date.parse(y.created_at) - Date.parse(x.created_at));
    const capped = matching.slice(0, 1000);
    return { total_count: matching.length, workflow_runs: capped.slice((page - 1) * perPage, page * perPage) };
  };
  return { gh: { call }, calls };
}
const fullWindow = `created=2026-10-22T00:00:00Z..2026-10-23T00:00:00Z`;

test("the listing reads every run of the window, splitting a range the 1,000 cap would cut", async () => {
  const budget = createBudget(350);
  const { gh, calls } = fakeGh(budget);
  const { runs, partial } = await listRuns({ gh, repo: "o/r", from: FROM, to: TO, budget });
  assert.deepEqual(partial, []);
  assert.equal(runs.length, 2550);
  assert.equal(new Set(runs.map((r) => r.id)).size, 2550);
  assert.equal(runs.filter((r) => r.path === WORKFLOWS[0].path).length, 2500);
  assert.equal(runs.filter((r) => r.path === WORKFLOWS[1].path).length, 50);
  assert.ok(!runs.some((r) => r.path === WORKFLOWS[3].path), "the sweep's own runs never count");
  // One call over the whole window per workflow the sweep reads: its first
  // page of 100, which carries the count.
  for (const w of [1, 2, 3]) {
    const whole = calls.filter((c) => c.startsWith(`/repos/o/r/actions/workflows/${w}/runs?${fullWindow}&`));
    assert.deepEqual(whole, [`/repos/o/r/actions/workflows/${w}/runs?${fullWindow}&per_page=100`], `workflow ${w}`);
  }
  assert.ok(!calls.some((c) => c.includes("/workflows/4/")));
  // No count-only call, and no range's page 1 read again: every page call
  // goes on from a first page this range already read.
  const runCalls = calls.filter((c) => c.includes("/runs?"));
  assert.ok(!runCalls.some((c) => /[?&]per_page=1(&|$)/.test(c)));
  assert.ok(!runCalls.some((c) => /[?&]page=1(&|$)/.test(c)));
  for (const c of runCalls.filter((x) => /[?&]page=\d/.test(x))) {
    assert.ok(runCalls.includes(c.replace(/&page=\d+$/, "")), c);
  }
  // A workflow with no run, or 50, costs its first page alone.
  assert.equal(calls.filter((c) => c.includes("/workflows/3/")).length, 1);
  assert.equal(calls.filter((c) => c.includes("/workflows/2/")).length, 1);
  assert.ok(budget.used <= 350 - DETAIL_RESERVE, `${budget.used} calls`);
});

test("the reserve covers the dearest unit mix: four A units, no D unit and four C units", async (t) => {
  const dir = tempDir("lane-sweep-");
  const trusted = join(dir, "trusted.json");
  writeFileSync(trusted, JSON.stringify({ actors: [{ id: 1 }] }));
  const output = join(dir, "output");
  writeFileSync(output, "");
  // Four workflows outside the lane pattern, five failed runs each.
  const workflows = [1, 2, 3, 4].map((id) => ({ id, path: `.github/workflows/check-${id}.yml` }));
  const runs = workflows.flatMap((w) =>
    [0, 1, 2, 3, 4].map((i) => run(w.id * 100 + i, w.path, "failure", { created_at: at(FROM + i * 60_000) })),
  );
  const { gh } = fakeGh(createBudget(100), runs, workflows);
  const pulls = Array.from({ length: 40 }, (_, i) => ({
    number: i + 1,
    user: { id: 1 },
    head: { sha: `s${i}` },
    labels: [],
  }));
  // Three full pages of open issues, the most the collector reads.
  const issues = Array.from({ length: 100 }, (_, i) => ({ number: 1000 + i, title: "t", user: { id: 2 } }));
  t.mock.method(globalThis, "fetch", async (url) => {
    const path = String(url).replace("https://api.test", "");
    let body;
    if (path.startsWith("/repos/o/r/actions/workflows")) body = await gh.call(path);
    else if (path.includes("/pulls")) body = pulls;
    else if (path.includes("/issues")) body = issues;
    else if (path.includes("/annotations")) body = [];
    else if (/\/actions\/runs\/\d+\/jobs/.test(path)) {
      body = {
        jobs: [1, 2, 3].map((j) => ({
          id: j,
          name: `job ${j}`,
          conclusion: "failure",
          check_run_url: `https://api.test/repos/o/r/check-runs/${j}`,
          steps: [],
        })),
      };
    } else body = { check_runs: [] };
    return { ok: true, status: 200, json: async () => body, text: async () => "log" };
  });
  t.mock.method(console, "log", () => {});
  // The listing: 1 workflow list and 4 first pages, each holding all its runs.
  const budget = 5 + DETAIL_RESERVE;
  await main({
    env: {
      REPOSITORY: "o/r",
      OUT_DIR: dir,
      GITHUB_OUTPUT: output,
      GITHUB_API_URL: "https://api.test",
      GITHUB_TOKEN: "x",
      TRUSTED_ACTORS_PATH: trusted,
      CALL_BUDGET: String(budget),
    },
    now: TO,
  });
  const out = readFileSync(output, "utf8");
  const units = JSON.parse(/units<<(\S+)\n(.*)\n\1/.exec(out)[2]);
  assert.deepEqual(units, ["a1", "a2", "a3", "a4", "c5", "c6", "c7", "c8"]);
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "collect-status.json"), "utf8")), {
    complete: true,
    truncated: null,
    partial: [],
  });
  assert.equal(/calls<<(\S+)\n(.*)\n\1/.exec(out)[2], String(budget));
});

test("the busiest workflow is listed first, so a short budget leaves the smaller ones part-read", async () => {
  const runs = [
    ...Array.from({ length: 450 }, (_, i) => run(10_000 + i, WORKFLOWS[0].path, "success", { created_at: at(FROM + i * 60_000) })),
    ...Array.from({ length: 250 }, (_, i) => run(20_000 + i, WORKFLOWS[1].path, "failure", { created_at: at(FROM + i * 60_000) })),
  ];
  // 1 workflow list + 3 first pages, then pr-merge's pages 2 to 5 and one of ci's two.
  const budget = createBudget(9);
  const { gh } = fakeGh(budget, runs);
  const { runs: read, partial } = await listRuns({ gh, repo: "o/r", from: FROM, to: TO, budget, reserve: 0 });
  assert.equal(read.filter((r) => r.path === WORKFLOWS[0].path).length, 450);
  assert.deepEqual(partial, [{ path: WORKFLOWS[1].path, listed: 200, total: 250 }]);
});

test("a listing the budget cuts short names the workflow, what it read and its count, and never spends the reserve", async () => {
  // 1 workflow list + 3 first pages, ci's 50 runs all on its first, leaves 8
  // for the 2,500 runs.
  const budget = createBudget(12);
  const { gh } = fakeGh(budget);
  const { runs, partial } = await listRuns({ gh, repo: "o/r", from: FROM, to: TO, budget, reserve: 0 });
  const listed = runs.filter((r) => r.path === WORKFLOWS[0].path).length;
  assert.deepEqual(partial, [{ path: WORKFLOWS[0].path, listed, total: 2500 }]);
  assert.ok(listed < 2500);
  assert.equal(runs.filter((r) => r.path === WORKFLOWS[1].path).length, 50);
  assert.ok(budget.used <= 12);
  // Room for the workflow list and two first pages: the third workflow has no
  // count read, and the two counted keep their first pages, all of ci's runs.
  const tight = createBudget(3);
  const left = await listRuns({ gh: fakeGh(tight).gh, repo: "o/r", from: FROM, to: TO, budget: tight, reserve: 0 });
  assert.equal(left.runs.filter((r) => r.path === WORKFLOWS[1].path).length, 50);
  assert.deepEqual(left.partial, [
    { path: WORKFLOWS[2].path, listed: 0, total: null },
    { path: WORKFLOWS[0].path, listed: 100, total: 2500 },
  ]);
});

test("a unit from a part-read workflow is marked incomplete, and the run warns", async (t) => {
  const dir = tempDir("lane-sweep-");
  const trusted = join(dir, "trusted.json");
  writeFileSync(trusted, JSON.stringify({ actors: [] }));
  const output = join(dir, "output");
  writeFileSync(output, "");
  const budget = createBudget(400);
  const { gh } = fakeGh(budget);
  t.mock.method(globalThis, "fetch", async (url) => {
    const path = String(url).replace("https://api.test", "");
    const body = path.startsWith("/repos/o/r/actions/workflows")
      ? await gh.call(path)
      : path.includes("/pulls") || path.includes("/issues")
        ? []
        : { jobs: [], check_runs: [] };
    return { ok: true, status: 200, json: async () => body, text: async () => "" };
  });
  const log = t.mock.method(console, "log", () => {});
  await main({
    env: {
      REPOSITORY: "o/r",
      OUT_DIR: dir,
      GITHUB_OUTPUT: output,
      GITHUB_API_URL: "https://api.test",
      GITHUB_TOKEN: "x",
      TRUSTED_ACTORS_PATH: trusted,
      // Before the reserve: 1 workflow list and 3 first pages of 100, then
      // pr-merge's first pages of its first half and quarter.
      CALL_BUDGET: String(DETAIL_RESERVE + 6),
    },
    now: TO,
  });
  const unit = (id) => JSON.parse(readFileSync(join(dir, "units", `${id}.json`), "utf8"));
  const units = JSON.parse(/units<<(\S+)\n(.*)\n\1/.exec(readFileSync(output, "utf8"))[2]);
  const byWorkflow = Object.fromEntries(units.map((id) => [unit(id).workflow, unit(id)]));
  assert.equal(byWorkflow[WORKFLOWS[1].path].window_complete, true);
  assert.equal(byWorkflow[WORKFLOWS[0].path].window_complete, false);
  assert.equal(byWorkflow[WORKFLOWS[0].path].window_start, "2026-10-22T00:00:00.000Z");
  assert.equal(byWorkflow[WORKFLOWS[0].path].window_end, "2026-10-23T00:00:00.000Z");
  const lines = log.mock.calls.map((c) => String(c.arguments[0]));
  assert.ok(
    lines.some((l) => l === "::warning::collect read part of the window for 1 workflow(s): .github/workflows/pr-merge.yml 300 of 2500 runs"),
    lines.join("\n"),
  );
});
