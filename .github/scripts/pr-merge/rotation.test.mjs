// Expected values come from the rotation rule in pr-merge.yml: the gate loop
// starts after the last candidate the previous loop reached and wraps round to
// the lowest PR number, and only a scheduled or hand-started pr-merge.yml run
// on main sets that position (a pull_request_target run runs the PR base
// branch's copy). The cursor is found from the workflow's own run list.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { main, rotate } from "./rotation.mjs";

const REPO = "melodic-software/claude-code-plugins";
const dir = mkdtempSync(join(tmpdir(), "rotation-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const prs = (...numbers) => numbers.map((number) => ({ number, head: `h${number}`, updatedAt: "u" }));
const numbers = (list) => list.map((c) => c.number);

test("the loop starts after the last candidate reached", () => {
  assert.deepEqual(numbers(rotate(prs(10, 20, 30, 40), 20)), [30, 40, 10, 20]);
  assert.deepEqual(numbers(rotate(prs(10, 20, 30, 40), 25)), [30, 40, 10, 20]);
});

test("the loop wraps round to the lowest number after the highest", () => {
  assert.deepEqual(numbers(rotate(prs(10, 20, 30), 30)), [10, 20, 30]);
  assert.deepEqual(numbers(rotate(prs(10, 20, 30), 99)), [10, 20, 30]);
});

test("with no cursor the loop starts at the lowest number", () => {
  assert.deepEqual(numbers(rotate(prs(30, 10, 20), undefined)), [10, 20, 30]);
  assert.deepEqual(rotate([], 5), []);
});

test("budgeted runs reach every candidate across runs", () => {
  // Each run reaches two candidates; the cursor is the last one reached.
  const all = prs(1, 2, 3, 4, 5);
  const seen = new Set();
  let last;
  for (let run = 0; run < 3; run += 1) {
    const reached = rotate(all, last).slice(0, 2);
    for (const c of reached) seen.add(c.number);
    last = reached.at(-1).number;
  }
  assert.deepEqual([...seen].sort(), [1, 2, 3, 4, 5]);
});

let n = 0;
// `pages` is the workflow's run listing, newest first, page by page; `cursors`
// maps a run id to the cursor its artifact holds.
async function run({ pages = [[]], cursors = {}, fail } = {}) {
  n += 1;
  const candidates = join(dir, `candidates-${n}.json`);
  writeFileSync(candidates, JSON.stringify(prs(30, 10, 20)));
  const calls = [];
  const downloads = [];
  const actions = async (method, path) => {
    calls.push(path);
    if (fail) throw fail;
    const page = /\/actions\/workflows\/pr-merge\.yml\/runs\?branch=main&.*&page=(\d+)$/.exec(path)?.[1];
    if (page) return { workflow_runs: pages[Number(page) - 1] ?? [] };
    const id = /\/actions\/runs\/(\d+)\/artifacts\?name=pr-merge-gate-cursor$/.exec(path)?.[1];
    assert.ok(id, `unexpected call ${path}`);
    return { artifacts: id in cursors ? [{ expired: false }] : [] };
  };
  const download = (id) => {
    downloads.push(id);
    return cursors[id];
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    await main({ env: { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "999", CANDIDATES_PATH: candidates }, actions, download });
  } finally {
    console.log = log;
  }
  const written = JSON.parse(readFileSync(candidates, "utf8"));
  return { order: numbers(written), uncapped: numbers(written.filter((c) => c.uncapped === true)), calls, downloads, lines };
}

const wf = (id, event, branch = "main", path = ".github/workflows/pr-merge.yml") => ({ id, event, head_branch: branch, path });
const filler = (from, count) => Array.from({ length: count }, (_, i) => wf(from + i, "push"));

test("main reads the newest trusted run's cursor and rewrites the candidates in rotated order", async () => {
  const result = await run({
    pages: [[wf(999, "schedule"), wf(8, "schedule"), wf(7, "workflow_dispatch"), wf(6, "schedule")]],
    cursors: { 7: '{"last": 20}', 6: '{"last": 10}' },
  });
  // This run (999) is skipped; run 8 has no cursor (a superseded run).
  assert.deepEqual(result.downloads, [7]);
  assert.deepEqual(result.order, [30, 10, 20]);
});

test("a pull_request_target run's cursor is never read", async () => {
  const result = await run({
    pages: [[wf(5, "pull_request_target"), wf(4, "pull_request"), wf(3, "workflow_dispatch", "feature"), wf(2, "schedule", "main", ".github/workflows/other.yml")]],
    cursors: { 5: '{"last": 20}', 4: '{"last": 20}', 3: '{"last": 20}', 2: '{"last": 20}' },
  });
  assert.deepEqual(result.downloads, []);
  assert.ok(!result.calls.some((path) => /\/runs\/[2-5]\/artifacts/.test(path)));
  assert.deepEqual(result.order, [10, 20, 30]);
});

test("the lookup pages through main's runs, then stops at its bounds", async () => {
  // A full first page of push runs, then the trusted run on page two.
  const found = await run({ pages: [filler(1000, 100), [wf(9, "schedule")]], cursors: { 9: '{"last": 10}' } });
  assert.deepEqual(found.downloads, [9]);
  assert.deepEqual(found.order, [20, 30, 10]);
  // Ten trusted runs without a cursor end the search before an eleventh is asked.
  const runs = Array.from({ length: 11 }, (_, i) => wf(100 + i, "schedule"));
  const bounded = await run({ pages: [runs], cursors: { 110: '{"last": 10}' } });
  assert.equal(bounded.calls.filter((path) => path.includes("/artifacts")).length, 10);
  assert.deepEqual(bounded.downloads, []);
  // Never more than two pages.
  const paged = await run({ pages: [filler(1000, 100), filler(2000, 100), [wf(9, "schedule")]], cursors: { 9: '{"last": 10}' } });
  assert.equal(paged.calls.filter((path) => path.includes("/workflows/")).length, 2);
  assert.deepEqual(paged.order, [10, 20, 30]);
});

test("a candidate the last run deferred at its read limit is gated first, and alone uncapped", async () => {
  const deferred = await run({ pages: [[wf(7, "schedule")]], cursors: { 7: '{"last": 30, "deferred": 20}' } });
  assert.deepEqual(deferred.order, [20, 30, 10]);
  assert.deepEqual(deferred.uncapped, [20]);
  // With none deferred, no candidate is uncapped.
  const plain = await run({ pages: [[wf(7, "schedule")]], cursors: { 7: '{"last": 10}' } });
  assert.deepEqual(plain.order, [20, 30, 10]);
  assert.deepEqual(plain.uncapped, []);
  // A deferred PR no longer listed leaves the others capped, starting above it.
  const gone = await run({ pages: [[wf(7, "schedule")]], cursors: { 7: '{"last": 30, "deferred": 15}' } });
  assert.deepEqual(gone.order, [20, 30, 10]);
  assert.deepEqual(gone.uncapped, []);
});

test("an unreadable cursor leaves the listing order with a warning", async () => {
  for (const options of [
    { pages: [[wf(1, "schedule")]], cursors: { 1: '{"last": 20, "deferred": "x"}' } },
    { fail: new Error("HTTP 502") },
    { pages: [[wf(1, "schedule")]], cursors: { 1: '{"last": "x"}' } },
    { pages: [[wf(1, "schedule")]], cursors: { 1: "not json" } },
  ]) {
    const result = await run(options);
    assert.deepEqual(result.order, [30, 10, 20]);
    assert.ok(result.lines.some((line) => line.startsWith("::warning title=rotation::")));
  }
});
