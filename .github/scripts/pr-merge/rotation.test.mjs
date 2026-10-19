// Expected values come from the rotation rule in pr-merge.yml: the gate loop
// starts after the last candidate the previous loop reached and wraps round to
// the lowest PR number, and only a run of main's copy of pr-merge.yml (a
// scheduled or hand-started run on main, or a pull_request_target run) sets
// that position.
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
async function run({ artifacts = [], runs = {}, cursor = '{"last": 20}', fail } = {}) {
  n += 1;
  const candidates = join(dir, `candidates-${n}.json`);
  writeFileSync(candidates, JSON.stringify(prs(30, 10, 20)));
  const output = join(dir, `output-${n}`);
  const calls = [];
  const downloads = [];
  const actions = async (method, path) => {
    calls.push(path);
    if (fail) throw fail;
    if (path.startsWith(`/repos/${REPO}/actions/artifacts?`)) return { artifacts };
    const id = /\/actions\/runs\/(\d+)$/.exec(path)?.[1];
    return runs[id];
  };
  const download = (id) => {
    downloads.push(id);
    return cursor;
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    await main({ env: { GITHUB_REPOSITORY: REPO, CANDIDATES_PATH: candidates, GITHUB_OUTPUT: output }, actions, download });
  } finally {
    console.log = log;
  }
  return {
    order: numbers(JSON.parse(readFileSync(candidates, "utf8"))),
    output: readFileSync(output, "utf8"),
    calls,
    downloads,
    lines,
  };
}

const artifact = (runId, createdAt, expired = false) => ({ expired, created_at: createdAt, workflow_run: { id: runId } });
const mainRun = (event, branch = "main") => ({ path: ".github/workflows/pr-merge.yml", event, head_branch: branch });

test("main reads the newest trusted cursor and rewrites the candidates in rotated order", async () => {
  const result = await run({
    artifacts: [artifact(1, "2026-10-19T01:00:00Z"), artifact(2, "2026-10-19T02:00:00Z")],
    runs: { 1: mainRun("schedule"), 2: mainRun("pull_request_target", "some-pr-branch") },
  });
  assert.deepEqual(result.downloads, [2]);
  assert.deepEqual(result.order, [30, 10, 20]);
  assert.match(result.output, /^last=20$/m);
});

test("a cursor from a run of another copy of the workflow is skipped", async () => {
  const result = await run({
    artifacts: [
      artifact(3, "2026-10-19T03:00:00Z"),
      artifact(4, "2026-10-19T02:30:00Z"),
      artifact(5, "2026-10-19T02:00:00Z"),
      artifact(6, "2026-10-19T01:00:00Z", true),
    ],
    runs: {
      3: mainRun("pull_request"),
      4: mainRun("workflow_dispatch", "feature"),
      5: { ...mainRun("schedule"), path: ".github/workflows/other.yml" },
      6: mainRun("schedule"),
    },
  });
  assert.deepEqual(result.downloads, []);
  assert.deepEqual(result.order, [10, 20, 30]);
  assert.match(result.output, /^last=$/m);
});

test("an unreadable cursor leaves the listing order with a warning", async () => {
  for (const options of [
    { fail: new Error("HTTP 502") },
    { artifacts: [artifact(1, "t")], runs: { 1: mainRun("schedule") }, cursor: '{"last": "x"}' },
    { artifacts: [artifact(1, "t")], runs: { 1: mainRun("schedule") }, cursor: "not json" },
  ]) {
    const result = await run(options);
    assert.deepEqual(result.order, [30, 10, 20]);
    assert.match(result.output, /^last=$/m);
    assert.ok(result.lines.some((line) => line.startsWith("::warning title=rotation::")));
  }
});
