// Expected values come from the skip-unchanged design: the skip records are
// read only from the newest scheduled or hand-started pr-merge.yml run on
// main other than this one (found as head-ref-map.mjs finds its map) whose
// head commit is on main, under the name pr-merge-verify-answers, never
// through actions/cache; a file already at the path is never read; any
// failure writes nothing and warns.
import assert from "node:assert/strict";
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { after, test } from "node:test";

import { forgetMainTip } from "./head-ref-map.mjs";
import { mainCall } from "./on-main.fixture.mjs";
import { ANSWERS_ARTIFACT, SKIP_FILE, main } from "./verify-answers.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const REPO = "melodic-software/claude-code-plugins";
const dir = tempDir("verify-answers-");
after(() => rmSync(dir, { recursive: true, force: true }));
const skipsOf = (entries) => JSON.stringify({ v: 1, repo: REPO, entries });
const sha = (id) => String(id).padStart(40, "a");
const wf = (id, event, branch = "main") => ({ id, event, head_branch: branch, path: ".github/workflows/pr-merge.yml", head_sha: sha(id) });

let n = 0;
async function readRun({ pages = [[]], skips = {}, offMain = [], fail, beforeSkips } = {}) {
  forgetMainTip();
  n += 1;
  const skipPath = join(dir, `skip-${n}.json`);
  if (beforeSkips !== undefined) writeFileSync(skipPath, beforeSkips);
  const downloads = [];
  const actions = async (method, url) => {
    if (fail) throw fail;
    const page = /\/actions\/workflows\/pr-merge\.yml\/runs\?branch=main&.*&page=(\d+)$/.exec(url)?.[1];
    if (page) return { workflow_runs: pages[Number(page) - 1] ?? [] };
    const onMain = mainCall(url, { offMain });
    if (onMain !== undefined) return onMain;
    const id = /\/actions\/runs\/(\d+)\/artifacts\?per_page=100$/.exec(url)?.[1];
    assert.ok(id, `unexpected call ${url}`);
    const artifacts = id in skips ? [{ name: ANSWERS_ARTIFACT, expired: false }] : [{ name: "pr-merge-head-refs", expired: false }];
    return { total_count: artifacts.length, artifacts };
  };
  // A file the artifact lacks (null) fails as readFileSync does;
  // "download-fails" fails as `gh run download` does.
  const download = (id, file) => {
    downloads.push(`${id}:${file}`);
    if (skips[id] === "download-fails") throw new Error("Command failed: gh run download");
    if (skips[id] === null) throw Object.assign(new Error(`ENOENT: no such file, open '${file}'`), { code: "ENOENT", syscall: "open" });
    return skips[id];
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    assert.equal(await main({ env: { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "999", EAM_SKIP_PATH: skipPath }, actions, download }), 0);
  } finally {
    console.log = log;
  }
  return { skipsWritten: existsSync(skipPath) ? readFileSync(skipPath, "utf8") : undefined, downloads, lines };
}

test("the newest trusted run on main's skip records are written as they were kept", async () => {
  const kept = skipsOf({ 41: { key: "k" } });
  const result = await readRun({
    pages: [[wf(999, "schedule"), wf(9, "pull_request_target"), wf(8, "schedule"), wf(7, "workflow_dispatch"), wf(6, "schedule")]],
    skips: { 9: skipsOf({ 41: { key: "forged" } }), 8: skipsOf({ 1: {} }), 7: kept, 6: skipsOf({}) },
    offMain: [sha(8)],
  });
  // This run is skipped, a pull_request_target run is never asked, and run 8
  // is not on main.
  assert.deepEqual(result.downloads, [`7:${SKIP_FILE}`]);
  assert.equal(result.skipsWritten, kept);
  assert.ok(result.lines.includes("skip records of run 7"), result.lines.join("\n"));
});

test("no earlier records write nothing, and remove a file left at the path", async () => {
  const result = await readRun({ pages: [[wf(5, "schedule")]], beforeSkips: "planted" });
  assert.equal(result.skipsWritten, undefined);
  assert.deepEqual(result.lines, ["no earlier skip records; each pull request is read"]);
});

test("a run whose artifact lacks the records hands on none, with no warning", async () => {
  const result = await readRun({ pages: [[wf(7, "schedule")]], skips: { 7: null }, beforeSkips: "planted" });
  assert.equal(result.skipsWritten, undefined);
  assert.deepEqual(result.lines, ["run 7 kept no skip records; each pull request is read"]);
});

test("a failed read writes nothing and warns", async () => {
  for (const options of [{ fail: new Error("HTTP 502") }, { pages: [[wf(1, "schedule")]], skips: { 1: "download-fails" } }]) {
    const result = await readRun({ ...options, beforeSkips: "planted" });
    assert.equal(result.skipsWritten, undefined);
    assert.ok(result.lines.some((line) => line.startsWith("::warning title=skip records::")), result.lines.join("\n"));
  }
});
