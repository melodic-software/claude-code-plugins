// Expected values come from the lane-record carry rules in lane-records.mjs
// and pr-merge.yml: the records are read only from the newest scheduled or
// hand-started pr-merge.yml run on main other than this one (found the way
// rotation.mjs finds the cursor) whose head commit is on main; a file of any
// other shape is no file; the next run's file keeps a record only while it is
// unexpired and, when the run's artifact listing can be read, listed
// unexpired by its artifact id; and on any failure nothing is written.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { main, nextRecords } from "./lane-records.mjs";

const REPO = "melodic-software/claude-code-plugins";
const NOW = Date.parse("2026-10-23T12:00:00Z");
const dir = mkdtempSync(join(tmpdir(), "lane-records-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const sha = (id) => String(id).padStart(40, "a");
const sender = (changes = {}) => ({
  id: 500,
  path: ".github/workflows/pr-merge.yml",
  event: "schedule",
  status: "completed",
  head_branch: "main",
  head_sha: sha(5),
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  ...changes,
});
const entry = (artifact, changes = {}) => ({
  created_at: "2026-10-23T10:00:00+00:00",
  artifact,
  expires_at: "2027-01-21T10:00:00Z",
  sender: sender(),
  ...changes,
});
const fileOf = (records, extra = {}) => JSON.stringify({ version: 1, repo: REPO, records, ...extra });
const wf = (id, event, branch = "main", path = ".github/workflows/pr-merge.yml", head_sha = sha(id)) => ({
  id,
  event,
  head_branch: branch,
  path,
  head_sha,
});

let n = 0;
// `pages` is the workflow's run listing, newest first; `files` maps a run id
// to the text its pr-merge-lane-records artifact holds; `offMain` lists the
// head commits the compare API reports as not on main. Requests count REST
// requests: each API call, and two per `gh run download` (it lists the run's
// artifacts, then fetches the archive).
async function readRun({ pages = [[]], files = {}, offMain = [], fail } = {}) {
  n += 1;
  const path = join(dir, `in-${n}.json`);
  const calls = [];
  const downloads = [];
  const actions = async (method, url) => {
    calls.push(url);
    if (fail) throw fail;
    const page = /\/actions\/workflows\/pr-merge\.yml\/runs\?branch=main&.*&page=(\d+)$/.exec(url)?.[1];
    if (page) return { workflow_runs: pages[Number(page) - 1] ?? [] };
    const base = /\/compare\/([0-9a-f]{40})\.\.\.refs\/heads\/main\?per_page=1$/.exec(url)?.[1];
    if (base) return { status: offMain.includes(base) ? "diverged" : "ahead" };
    const id = /\/actions\/runs\/(\d+)\/artifacts\?name=pr-merge-lane-records$/.exec(url)?.[1];
    assert.ok(id, `unexpected call ${url}`);
    return { artifacts: id in files ? [{ expired: false }] : [] };
  };
  const download = (id) => {
    downloads.push(id);
    return files[id];
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    await main({ mode: "read", env: { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "999", LANE_RECORDS_PATH: path }, actions, download });
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

test("the newest trusted run's records are read in five requests", async () => {
  const records = { "pr-merge-dispatched-11": entry(9011), "pr-merge-rerun-11-attempt-2": entry(9012) };
  const result = await readRun({
    pages: [[wf(999, "schedule"), wf(8, "pull_request_target"), wf(7, "schedule"), wf(6, "workflow_dispatch")]],
    files: { 8: fileOf({ "pr-merge-dispatched-1": entry(1) }), 7: fileOf(records), 6: fileOf({}) },
  });
  // This run (999) is skipped, and a pull_request_target run is never asked.
  assert.deepEqual(result.downloads, [7]);
  assert.deepEqual(result.written, { version: 1, repo: REPO, records });
  // The run listing, run 7's artifact filter, the compare of its head commit
  // with main, and its download.
  assert.equal(result.requests, 5);
});

test("a run whose head commit is not on main is passed over", async () => {
  const result = await readRun({
    pages: [[wf(9, "workflow_dispatch"), wf(8, "schedule", "main", undefined, "main"), wf(7, "schedule")]],
    files: {
      9: fileOf({ "pr-merge-dispatched-1": entry(1) }),
      8: fileOf({ "pr-merge-dispatched-1": entry(1) }),
      7: fileOf({ "pr-merge-dispatched-30": entry(30) }),
    },
    offMain: [sha(9)],
  });
  assert.deepEqual(result.downloads, [7]);
  assert.deepEqual(Object.keys(result.written.records), ["pr-merge-dispatched-30"]);
});

test("an unreadable, foreign or misshapen file writes nothing and warns", async () => {
  const good = entry(9011);
  for (const records of [
    "not json",
    fileOf({ "pr-merge-dispatched-11": good }, { version: 2 }),
    fileOf({ "pr-merge-dispatched-11": good }, { repo: "someone/else" }),
    fileOf({ "pr-merge-summary": good }),
    fileOf({ "pr-merge-dispatched-011": good }),
    fileOf({ "pr-merge-rerun-11-attempt-3": good }),
    fileOf({ "pr-merge-dispatched-11": entry("9011") }),
    fileOf({ "pr-merge-dispatched-11": entry(9011, { expires_at: "soon" }) }),
    fileOf({ "pr-merge-dispatched-11": entry(9011, { created_at: "2026-10-23T10:00:00" }) }),
    fileOf({ "pr-merge-dispatched-11": entry(9011, { sender: sender({ status: "in_progress" }) }) }),
    fileOf({ "pr-merge-dispatched-11": entry(9011, { sender: null }) }),
    fileOf([]),
  ]) {
    const result = await readRun({ pages: [[wf(1, "schedule")]], files: { 1: records } });
    assert.equal(result.written, undefined, records);
    assert.ok(result.lines.some((line) => line.startsWith("::warning title=lane records::")), records);
  }
  const failed = await readRun({ fail: new Error("HTTP 502") });
  assert.equal(failed.written, undefined);
  assert.ok(failed.lines.some((line) => line.startsWith("::warning title=lane records::")));
});

test("no trusted run with records writes nothing, quietly", async () => {
  const result = await readRun({ pages: [[wf(5, "schedule"), wf(4, "workflow_dispatch", "feature")]], files: { 4: fileOf({}) } });
  assert.equal(result.written, undefined);
  assert.deepEqual(result.downloads, []);
  assert.ok(!result.lines.some((line) => line.startsWith("::warning")));
});

const listed = (...ids) => ({ fetchedAt: "t", artifacts: ids.map((id) => ({ id, expired: false })) });

test("the next file keeps unexpired records the listing lists unexpired", () => {
  const records = {
    "pr-merge-dispatched-11": entry(11),
    "pr-merge-dispatched-12": entry(12),
    "pr-merge-dispatched-13": entry(13),
    "pr-merge-dispatched-14": entry(14, { expires_at: "2026-10-23T12:00:00Z" }),
  };
  const listing = { artifacts: [...listed(11, 14).artifacts, { id: 12, expired: true }] };
  // 12 has expired in the listing; 13 is no longer listed; 14 expires now.
  assert.deepEqual(Object.keys(nextRecords({ records, listing, now: NOW })), ["pr-merge-dispatched-11"]);
  // With no listing, only the expiry each record was listed with prunes.
  assert.deepEqual(Object.keys(nextRecords({ records, listing: undefined, now: NOW })), [
    "pr-merge-dispatched-11",
    "pr-merge-dispatched-12",
    "pr-merge-dispatched-13",
  ]);
});

async function writeRun({ records, listing }) {
  n += 1;
  const paths = Object.fromEntries(["in", "listing", "out"].map((k) => [k, join(dir, `${k}-${n}.json`)]));
  if (records !== undefined) writeFileSync(paths.in, records);
  if (listing !== undefined) writeFileSync(paths.listing, typeof listing === "string" ? listing : JSON.stringify(listing));
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    await main({
      mode: "write",
      env: { GITHUB_REPOSITORY: REPO, LANE_RECORDS_PATH: paths.in, BABYSIT_VERIFY_LISTING: paths.listing, LANE_RECORDS_OUT: paths.out },
      now: NOW,
    });
  } finally {
    console.log = log;
  }
  return { written: existsSync(paths.out) ? JSON.parse(readFileSync(paths.out, "utf8")) : undefined, lines };
}

test("write keeps the checks' records the listing still lists", async () => {
  const records = { "pr-merge-dispatched-11": entry(11), "pr-merge-dispatched-12": entry(12) };
  const { written } = await writeRun({ records: fileOf(records), listing: listed(11) });
  assert.deepEqual(written, { version: 1, repo: REPO, records: { "pr-merge-dispatched-11": records["pr-merge-dispatched-11"] } });
});

test("write with no listing prunes by expiry; a bad or missing file writes nothing", async () => {
  const records = { "pr-merge-dispatched-11": entry(11), "pr-merge-dispatched-12": entry(12, { expires_at: "2026-10-01T00:00:00Z" }) };
  for (const listing of [undefined, "{", { artifacts: "x" }]) {
    const { written, lines } = await writeRun({ records: fileOf(records), listing });
    assert.deepEqual(Object.keys(written.records), ["pr-merge-dispatched-11"]);
    assert.ok(lines.some((line) => line.includes("no artifact listing")), String(listing));
  }
  const bad = await writeRun({ records: fileOf(records, { version: 2 }), listing: listed(11) });
  assert.equal(bad.written, undefined);
  assert.ok(bad.lines.some((line) => line.startsWith("::warning title=lane records::")));
  const none = await writeRun({ listing: listed(11) });
  assert.equal(none.written, undefined);
  assert.ok(!none.lines.some((line) => line.startsWith("::warning")));
});
