// Expected values come from the head-ref map rules in head-ref-map.mjs and
// pr-merge.yml: the map is read only from the newest scheduled or hand-started
// pr-merge.yml run on main other than this one (found the way rotation.mjs
// finds the cursor) whose head commit is on main, holds artifact id to head ref and nothing else, keeps an
// entry only while its id is listed (with no listing file, every entry as it
// is), adds only this run's own downloads, and on any other failure writes
// nothing.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

import { forgetMainTip, main, nextMap, onMain } from "./head-ref-map.mjs";

import { mainCall } from "./on-main.fixture.mjs";

const REPO = "melodic-software/claude-code-plugins";
const dir = mkdtempSync(join(tmpdir(), "head-ref-map-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const mapOf = (refs, extra = {}) => JSON.stringify({ version: 1, repo: REPO, head_refs: refs, ...extra });
const sha = (id) => String(id).padStart(40, "a");
const wf = (id, event, branch = "main", path = ".github/workflows/pr-merge.yml", head_sha = sha(id)) => ({
  id,
  event,
  head_branch: branch,
  path,
  head_sha,
});

let n = 0;
// `pages` is the workflow's run listing, newest first; `maps` maps a run id to
// the text its pr-merge-head-refs artifact holds; `offMain` lists the head
// commits the compare API reports as not on main. Requests count REST
// requests: each API call, and two per `gh run download` (it lists the run's
// artifacts, then fetches the archive).
async function readRun({ pages = [[]], maps = {}, offMain = [], fail } = {}) {
  forgetMainTip();
  n += 1;
  const path = join(dir, `in-${n}.json`);
  const calls = [];
  const downloads = [];
  const actions = async (method, url) => {
    calls.push(url);
    if (fail) throw fail;
    const page = /\/actions\/workflows\/pr-merge\.yml\/runs\?branch=main&.*&page=(\d+)$/.exec(url)?.[1];
    if (page) return { workflow_runs: pages[Number(page) - 1] ?? [] };
    const onMain = mainCall(url, { offMain });
    if (onMain !== undefined) return onMain;
    const id = /\/actions\/runs\/(\d+)\/artifacts\?per_page=100$/.exec(url)?.[1];
    assert.ok(id, `unexpected call ${url}`);
    const artifacts = id in maps ? [{ name: "pr-merge-head-refs", expired: false }] : [{ name: "pr-merge-summary", expired: false }];
    return { total_count: artifacts.length, artifacts };
  };
  const download = (id) => {
    downloads.push(id);
    return maps[id];
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    await main({ mode: "read", env: { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "999", HEAD_REFS_PATH: path }, actions, download });
  } finally {
    console.log = log;
  }
  return {
    written: existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : undefined,
    requests: calls.length + 2 * downloads.length,
    downloads,
    lines,
  };
}

test("the newest trusted run's map is read in seven requests", async () => {
  const result = await readRun({
    pages: [[wf(999, "schedule"), wf(8, "pull_request_target"), wf(7, "schedule"), wf(6, "workflow_dispatch")]],
    maps: { 8: mapOf({ 1: "forged" }), 7: mapOf({ 30: "feat/other", 40: "" }), 6: mapOf({ 1: "old" }) },
  });
  // This run (999) is skipped, and a pull_request_target run is never asked.
  assert.deepEqual(result.downloads, [7]);
  assert.deepEqual(result.written, { version: 1, repo: REPO, head_refs: { 30: "feat/other", 40: "" } });
  // The run listing, run 7's artifact filter, the tag named main (absent),
  // main's tip, the compare of run 7's head commit with it, and its download.
  assert.equal(result.requests, 7);
});

test("a run whose head commit is not on main is passed over", async () => {
  // Run 9 ran on a tag named main whose commit main does not hold; run 8's
  // head_sha is not a commit id.
  const result = await readRun({
    pages: [[wf(9, "workflow_dispatch"), wf(8, "schedule", "main", undefined, "main"), wf(7, "schedule")]],
    maps: { 9: mapOf({ 1: "forged" }), 8: mapOf({ 1: "forged" }), 7: mapOf({ 30: "feat/other" }) },
    offMain: [sha(9)],
  });
  assert.deepEqual(result.downloads, [7]);
  assert.deepEqual(result.written.head_refs, { 30: "feat/other" });
});

test("no run on main with a map writes nothing", async () => {
  const result = await readRun({ pages: [[wf(9, "schedule")]], maps: { 9: mapOf({ 1: "forged" }) }, offMain: [sha(9)] });
  assert.equal(result.written, undefined);
  assert.deepEqual(result.downloads, []);
});

test("an unreadable, foreign or misshapen map writes nothing and warns", async () => {
  for (const options of [
    { fail: new Error("HTTP 502") },
    { pages: [[wf(1, "schedule")]], maps: { 1: "not json" } },
    { pages: [[wf(1, "schedule")]], maps: { 1: mapOf({ 30: "x" }, { version: 2 }) } },
    { pages: [[wf(1, "schedule")]], maps: { 1: mapOf({ 30: "x" }, { repo: "someone/else" }) } },
    { pages: [[wf(1, "schedule")]], maps: { 1: mapOf({ 30: null }) } },
    { pages: [[wf(1, "schedule")]], maps: { 1: mapOf({ "03": "x" }) } },
    { pages: [[wf(1, "schedule")]], maps: { 1: mapOf({ abc: "x" }) } },
  ]) {
    const result = await readRun(options);
    assert.equal(result.written, undefined);
    assert.ok(result.lines.some((line) => line.startsWith("::warning title=head-ref map::")));
  }
});

test("no trusted run with a map writes nothing, quietly", async () => {
  const result = await readRun({ pages: [[wf(5, "schedule"), wf(4, "workflow_dispatch", "feature")]], maps: { 4: mapOf({ 1: "x" }) } });
  assert.equal(result.written, undefined);
  assert.deepEqual(result.downloads, []);
  assert.ok(!result.lines.some((line) => line.startsWith("::warning")));
});

const listed = (...ids) => ({ fetchedAt: "t", artifacts: ids.map((id) => ({ id, expired: false })) });
const cached = (entries) => ({
  "fail-head-ref": Object.fromEntries(Object.entries(entries).map(([k, v]) => [k, { at: "t", value: v }])),
});

test("the next map keeps listed entries and adds this run's downloads", () => {
  const refs = nextMap({
    previous: { 30: "feat/other", 50: "gone" },
    runCache: {
      ...cached({ [`${REPO}|40`]: { head_ref: "feat/x" }, [`${REPO}|60`]: { head_ref: null }, [`other/repo|70`]: { head_ref: "y" }, [`${REPO}|90`]: { head_ref: "z" } }),
      "carried-fail-head-ref": { [`${REPO}|80`]: { at: "t", value: { head_ref: "carried" } } },
    },
    listing: { artifacts: [...listed(30, 40, 60, 70, 80).artifacts, { id: 50, expired: true }] },
    repo: REPO,
  });
  // 50 has expired; 60 recorded no head ref; 70 is another repository's key;
  // 80 came from the last run's carried run cache, never a download; 90 was
  // downloaded but is no longer listed.
  assert.deepEqual(refs, { 30: "feat/other", 40: "feat/x", 60: "" });
});

async function writeRun({ previous, runCache, listing }) {
  n += 1;
  const paths = Object.fromEntries(["in", "cache", "listing", "out"].map((k) => [k, join(dir, `${k}-${n}.json`)]));
  if (previous !== undefined) writeFileSync(paths.in, previous);
  if (runCache !== undefined) writeFileSync(paths.cache, JSON.stringify(runCache));
  if (listing !== undefined) writeFileSync(paths.listing, typeof listing === "string" ? listing : JSON.stringify(listing));
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    await main({
      mode: "write",
      env: {
        GITHUB_REPOSITORY: REPO,
        HEAD_REFS_PATH: paths.in,
        BABYSIT_RUN_CACHE: paths.cache,
        BABYSIT_VERIFY_LISTING: paths.listing,
        HEAD_REFS_OUT: paths.out,
      },
    });
  } finally {
    console.log = log;
  }
  return { written: existsSync(paths.out) ? JSON.parse(readFileSync(paths.out, "utf8")) : undefined, out: paths.out, lines };
}

test("write merges the map read before the gate with the run's downloads", async () => {
  const { written } = await writeRun({
    previous: mapOf({ 30: "feat/other", 990: "feat/x" }),
    runCache: cached({ [`${REPO}|40`]: { head_ref: "feat/x" } }),
    listing: listed(30, 40),
  });
  assert.deepEqual(written, { version: 1, repo: REPO, head_refs: { 30: "feat/other", 40: "feat/x" } });
});

test("write with no listing carries the map read before the gate, quietly", async () => {
  // A run with no candidates saves no listing; the next run that saves one prunes the map.
  const { written, lines } = await writeRun({ previous: mapOf({ 30: "a", 31: "" }), runCache: cached({ [`${REPO}|40`]: { head_ref: "b" } }) });
  // 40 is a download no listing vouches for, so only the map read before the gate is carried.
  assert.deepEqual(written, { version: 1, repo: REPO, head_refs: { 30: "a", 31: "" } });
  assert.equal(lines.length, 1);
  assert.ok(!lines[0].startsWith("::warning"));
  // No map read before the gate, or one that is dropped: nothing to carry.
  const none = await writeRun({ runCache: cached({}) });
  assert.equal(none.written, undefined);
  assert.equal(none.lines.length, 1);
  assert.ok(!none.lines[0].startsWith("::warning"));
  assert.equal((await writeRun({ previous: "{" })).written, undefined);
});

test("a listing that exists but cannot be read writes nothing and warns", async () => {
  for (const listing of ["{", JSON.stringify({ artifacts: "none" })]) {
    const result = await writeRun({ previous: mapOf({ 30: "a" }), runCache: cached({}), listing });
    assert.equal(result.written, undefined);
    assert.ok(result.lines.some((line) => line.startsWith("::warning title=head-ref map::")));
  }
});

test("a bad previous map is dropped; no run cache prunes the previous map", async () => {
  const bad = await writeRun({ previous: "{", runCache: cached({ [`${REPO}|40`]: { head_ref: "b" } }), listing: listed(30, 40) });
  assert.deepEqual(bad.written.head_refs, { 40: "b" });
  const bare = await writeRun({ previous: mapOf({ 30: "a", 31: "c" }), listing: listed(30) });
  assert.deepEqual(bare.written.head_refs, { 30: "a" });
});

// The gate's reader (babysit_verify_evidence.py `load_head_refs`) loads the
// map a run with no listing carries.
test("the gate reads the carried map", async () => {
  const { out } = await writeRun({ previous: mapOf({ 30: "a", 31: "" }) });
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const load = "import json, sys; from babysit_verify_evidence import load_head_refs; print(json.dumps(load_head_refs(sys.argv[1], sys.argv[2])))";
  const run = spawnSync("python3", ["-c", load, out, REPO], { cwd: scripts, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(JSON.parse(run.stdout), { 30: "a", 31: "" });
});

// The tag named main and main's tip are read once per process, however many
// runs are checked; a failed read is remembered too, and refuses every run.
test("onMain reads the tag named main and main's tip once per process", async () => {
  const calls = [];
  const actions = async (method, url) => {
    calls.push(url);
    return mainCall(url);
  };
  forgetMainTip();
  assert.equal(await onMain({ repo: REPO, actions, sha: sha(7) }), true);
  assert.equal(await onMain({ repo: REPO, actions, sha: sha(8) }), true);
  assert.equal(calls.filter((u) => u.endsWith("/git/ref/tags/main")).length, 1);
  assert.equal(calls.filter((u) => u.endsWith("/git/ref/heads/main")).length, 1);
  assert.equal(calls.filter((u) => u.includes("/compare/")).length, 2);
  forgetMainTip();
  const tagged = async (method, url) => {
    calls.push(url);
    return mainCall(url, { mainTag: true });
  };
  assert.equal(await onMain({ repo: REPO, actions: tagged, sha: sha(7) }), false);
  // Still refused with a client that would answer 404: the refusal holds.
  assert.equal(await onMain({ repo: REPO, actions, sha: sha(7) }), false);
});
