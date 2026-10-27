// Expected values come from the verifier-read cache design (step 2): the
// answers file is read only from the newest scheduled or hand-started
// pr-merge.yml run on main other than this one (found as head-ref-map.mjs
// finds its map) whose head commit is on main, under the name
// pr-merge-verify-answers, never through actions/cache; a file already at the
// path is never read; any failure writes nothing and warns.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { forgetMainTip } from "./head-ref-map.mjs";
import { mainCall } from "./on-main.fixture.mjs";
import { ANSWERS_ARTIFACT, main } from "./verify-answers.mjs";

const REPO = "melodic-software/claude-code-plugins";
const dir = mkdtempSync(join(tmpdir(), "verify-answers-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const answersOf = (entries, extra = {}) => JSON.stringify({ version: 1, repo: REPO, code: "c".repeat(64), entries, ...extra });
const sha = (id) => String(id).padStart(40, "a");
const wf = (id, event, branch = "main") => ({ id, event, head_branch: branch, path: ".github/workflows/pr-merge.yml", head_sha: sha(id) });

let n = 0;
async function readRun({ pages = [[]], files = {}, offMain = [], fail, before } = {}) {
  forgetMainTip();
  n += 1;
  const path = join(dir, `in-${n}.json`);
  if (before !== undefined) writeFileSync(path, before);
  const downloads = [];
  const actions = async (method, url) => {
    if (fail) throw fail;
    const page = /\/actions\/workflows\/pr-merge\.yml\/runs\?branch=main&.*&page=(\d+)$/.exec(url)?.[1];
    if (page) return { workflow_runs: pages[Number(page) - 1] ?? [] };
    const onMain = mainCall(url, { offMain });
    if (onMain !== undefined) return onMain;
    const id = /\/actions\/runs\/(\d+)\/artifacts\?per_page=100$/.exec(url)?.[1];
    assert.ok(id, `unexpected call ${url}`);
    const artifacts = id in files ? [{ name: ANSWERS_ARTIFACT, expired: false }] : [{ name: "pr-merge-head-refs", expired: false }];
    return { total_count: artifacts.length, artifacts };
  };
  const download = (id) => {
    downloads.push(id);
    return files[id];
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    assert.equal(await main({ env: { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "999", VERIFY_ANSWERS_PATH: path }, actions, download }), 0);
  } finally {
    console.log = log;
  }
  return { written: existsSync(path) ? readFileSync(path, "utf8") : undefined, downloads, lines };
}

test("the newest trusted run on main's answers are written as they were kept", async () => {
  const kept = answersOf({ 41: { key: "k" } });
  const result = await readRun({
    pages: [[wf(999, "schedule"), wf(9, "pull_request_target"), wf(8, "schedule"), wf(7, "workflow_dispatch"), wf(6, "schedule")]],
    files: { 9: answersOf({ 41: { key: "forged" } }), 8: answersOf({ 1: {} }), 7: kept, 6: answersOf({}) },
    offMain: [sha(8)],
  });
  // This run is skipped, a pull_request_target run is never asked, and run 8
  // is not on main.
  assert.deepEqual(result.downloads, [7]);
  assert.equal(result.written, kept);
  assert.ok(result.lines.includes("verifier answers of run 7: 1 pull requests"), result.lines.join("\n"));
});

test("no earlier answers write nothing, and remove a file left at the path", async () => {
  const result = await readRun({ pages: [[wf(5, "schedule")]], before: answersOf({ 41: { key: "planted" } }) });
  assert.equal(result.written, undefined);
  assert.deepEqual(result.lines, ["no earlier verifier answers; each pull request is read in full"]);
});

test("an unreadable or foreign answers file writes nothing and warns", async () => {
  for (const options of [
    { fail: new Error("HTTP 502") },
    { pages: [[wf(1, "schedule")]], files: { 1: "not json" } },
    { pages: [[wf(1, "schedule")]], files: { 1: answersOf({}, { repo: "someone/else" }) } },
    { pages: [[wf(1, "schedule")]], files: { 1: answersOf([]) } },
  ]) {
    const result = await readRun({ ...options, before: answersOf({ 41: { key: "planted" } }) });
    assert.equal(result.written, undefined);
    assert.ok(result.lines.some((line) => line.startsWith("::warning title=verifier answers::")), result.lines.join("\n"));
  }
});
