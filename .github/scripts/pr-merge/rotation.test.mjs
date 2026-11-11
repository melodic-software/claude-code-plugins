// Expected values come from the rotation rule in pr-merge.yml: the gate loop
// starts after the last candidate the previous loop reached and wraps round to
// the lowest PR number, and only a scheduled or hand-started pr-merge.yml run
// on main sets that position (a pull_request_target run runs the PR base
// branch's copy). The cursor is found from the workflow's own run list.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { crc32 } from "node:zlib";

import { fakeGhArchive, fakeGhDownload } from "./gh-download.fixture.mjs";
import { forgetMainTip, main as headRefs } from "./head-ref-map.mjs";
import { main as laneRecords } from "./lane-records.mjs";
import { mainCall } from "./on-main.fixture.mjs";
import { ghDownload, ghDownloadArtifact, main, newestTrustedArtifact, newestTrustedRun, rotate, sharedReads } from "./rotation.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const REPO = "melodic-software/claude-code-plugins";
const dir = tempDir("rotation-");
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
    const id = /\/actions\/runs\/(\d+)\/artifacts\?per_page=100$/.exec(path)?.[1];
    assert.ok(id, `unexpected call ${path}`);
    const artifacts = id in cursors ? [{ name: "pr-merge-summary", expired: false }, { name: "pr-merge-gate-cursor", expired: false }] : [];
    return { total_count: artifacts.length, artifacts };
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
  return { order: numbers(written), deferred: numbers(written.filter((c) => c.deferred === true)), calls, downloads, lines };
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

test("the newest run is the highest id, whatever order created_at lists them in", async () => {
  // Run 7 was created an hour before run 8 but stamped an hour ahead, so the
  // API lists it first (2026-11-01 08:00-09:00Z).
  const result = await run({
    pages: [[wf(999, "schedule"), wf(7, "schedule"), wf(8, "schedule")]],
    cursors: { 7: '{"last": 20}', 8: '{"last": 10}' },
  });
  assert.deepEqual(result.downloads, [8]);
  assert.deepEqual(result.order, [20, 30, 10]);
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

// pr-merge.yml's run-name marks a PR-scoped dispatch, which reads one pull
// request: no sweep reads its files, and it costs no artifact listing.
test("a PR-scoped dispatch's files are never read, and a hand-started sweep's are", async () => {
  const scoped = (id, title) => ({ ...wf(id, "workflow_dispatch"), display_title: title });
  const result = await run({
    pages: [[scoped(9, "pr-merge: arm #42"), scoped(8, "pr-merge: arm #not a number"), scoped(7, "pr-merge"), wf(6, "schedule")]],
    cursors: { 9: '{"last": 30}', 8: '{"last": 30}', 7: '{"last": 20}', 6: '{"last": 10}' },
  });
  assert.deepEqual(result.downloads, [7]);
  assert.ok(!result.calls.some((path) => /\/runs\/[89]\/artifacts/.test(path)));
  assert.deepEqual(result.order, [30, 10, 20]);
});

test("the lookup pages through main's runs, then stops at its bounds", async () => {
  // A full first page of push runs, then the trusted run on page two.
  const found = await run({ pages: [filler(1000, 100), [wf(9, "schedule")]], cursors: { 9: '{"last": 10}' } });
  assert.deepEqual(found.downloads, [9]);
  assert.deepEqual(found.order, [20, 30, 10]);
  // Ten trusted runs without a cursor end the search before an eleventh is asked.
  const runs = Array.from({ length: 11 }, (_, i) => wf(110 - i, "schedule"));
  const bounded = await run({ pages: [runs], cursors: { 100: '{"last": 10}' } });
  assert.equal(bounded.calls.filter((path) => path.includes("/artifacts")).length, 10);
  assert.deepEqual(bounded.downloads, []);
  // Never more than two pages.
  const paged = await run({ pages: [filler(1000, 100), filler(2000, 100), [wf(9, "schedule")]], cursors: { 9: '{"last": 10}' } });
  assert.equal(paged.calls.filter((path) => path.includes("/workflows/")).length, 2);
  assert.deepEqual(paged.order, [10, 20, 30]);
});

test("a candidate the last run deferred at its read limit is gated first, and alone marked deferred", async () => {
  const deferred = await run({ pages: [[wf(7, "schedule")]], cursors: { 7: '{"last": 30, "deferred": 20}' } });
  assert.deepEqual(deferred.order, [20, 30, 10]);
  assert.deepEqual(deferred.deferred, [20]);
  // With none deferred, no candidate is marked.
  const plain = await run({ pages: [[wf(7, "schedule")]], cursors: { 7: '{"last": 10}' } });
  assert.deepEqual(plain.order, [20, 30, 10]);
  assert.deepEqual(plain.deferred, []);
  // A deferred PR no longer listed leaves none marked, starting above it.
  const gone = await run({ pages: [[wf(7, "schedule")]], cursors: { 7: '{"last": 30, "deferred": 15}' } });
  assert.deepEqual(gone.order, [20, 30, 10]);
  assert.deepEqual(gone.deferred, []);
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

// One job's three readers, as the merge job runs them, against main's runs
// newest first: this run (999), a run that skipped its gate and kept nothing
// but its summary (8), and the run that kept all three files (7). Counted by
// hand, each reader alone lists the runs, asks runs 8 and 7 for artifacts and,
// for the map and the records, compares run 7's head with main: 3 + 4 + 4 = 11
// calls. Shared, those are read once: 4.
const RECORDS = JSON.stringify({ version: 1, repo: REPO, records: {} });
const MAP = JSON.stringify({ version: 1, repo: REPO, head_refs: { 5: "feat/x" } });
async function job({ shared, total } = {}) {
  n += 1;
  const paths = {
    candidates: join(dir, `candidates-${n}.json`),
    map: join(dir, `map-${n}.json`),
    records: join(dir, `records-${n}.json`),
    reads: shared ? join(dir, `reads-${n}.json`) : undefined,
  };
  writeFileSync(paths.candidates, JSON.stringify(prs(30, 10, 20)));
  forgetMainTip();
  const calls = [];
  const sha = (id) => String(id).padStart(40, "a");
  const kept = {
    "pr-merge-gate-cursor": '{"last": 10}',
    "pr-merge-head-refs": MAP,
    "pr-merge-lane-records": RECORDS,
  };
  const actions = async (method, path) => {
    calls.push(path);
    if (/\/actions\/workflows\/pr-merge\.yml\/runs\?/.test(path)) {
      return { workflow_runs: [999, 8, 7].map((id) => ({ ...wf(id, "schedule"), head_sha: sha(id) })) };
    }
    const onMain = mainCall(path);
    if (onMain !== undefined) return onMain;
    const [, id, query] = /\/actions\/runs\/(\d+)\/artifacts\?(.*)$/.exec(path);
    const artifacts = [{ name: "pr-merge-summary", expired: false }, ...(id === "7" ? Object.keys(kept).map((name) => ({ name, expired: false })) : [])];
    if (query.startsWith("name=")) return { artifacts: artifacts.filter((a) => a.name === query.slice(5)) };
    return { total_count: total ?? artifacts.length, artifacts };
  };
  const download = (name) => (id) => {
    assert.equal(id, 7);
    return kept[name];
  };
  const env = { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "999", PR_MERGE_READS_PATH: paths.reads };
  const log = console.log;
  console.log = () => {};
  try {
    await main({ env: { ...env, CANDIDATES_PATH: paths.candidates }, actions, download: download("pr-merge-gate-cursor") });
    await headRefs({ mode: "read", env: { ...env, HEAD_REFS_PATH: paths.map }, actions, download: download("pr-merge-head-refs") });
    await laneRecords({ mode: "read", env: { ...env, LANE_RECORDS_PATH: paths.records }, actions, download: download("pr-merge-lane-records") });
  } finally {
    console.log = log;
  }
  return {
    calls,
    order: numbers(JSON.parse(readFileSync(paths.candidates, "utf8"))),
    map: readFileSync(paths.map, "utf8"),
    records: readFileSync(paths.records, "utf8"),
  };
}

test("a job's readers share one run listing, each run's artifact list and each compare", async () => {
  const alone = await job();
  const shared = await job({ shared: true });
  // The tag named main and main's tip are read once per process
  // (head-ref-map.mjs onMain), here once for both readers.
  assert.equal(alone.calls.length, 13);
  assert.equal(shared.calls.length, 6);
  // Every reader still finds its own file, so the answers are the same.
  for (const result of [alone, shared]) {
    assert.deepEqual(result.order, [20, 30, 10]);
    assert.equal(result.map, MAP);
    assert.equal(result.records, RECORDS);
  }
});

test("a run whose artifacts fill more than one page is asked by name", async () => {
  const result = await job({ shared: true, total: 101 });
  assert.ok(result.calls.some((path) => path.endsWith("/runs/7/artifacts?name=pr-merge-head-refs")));
  assert.deepEqual(result.order, [20, 30, 10]);
  assert.equal(result.map, MAP);
});

test("a write through the shared reads is sent every time, never answered from the file", async () => {
  const sent = [];
  const actions = sharedReads(async (method, url) => {
    sent.push(`${method} ${url}`);
    return { ok: sent.length };
  }, join(dir, "writes.json"));
  const url = `/repos/${REPO}/issues/1/labels`;
  assert.deepEqual(await actions("POST", url), { ok: 1 });
  assert.deepEqual(await actions("POST", url), { ok: 2 });
  assert.deepEqual(sent, [`POST ${url}`, `POST ${url}`]);
});

// The routes are api-budget.bash's templating of the two API URLs gh logs
// (log-api-budget.test.mjs's verdict download records the same two); the
// download host is off GitHub's API, so it is no request.
test("ghDownload counts each API request gh run download sends in the job's api-calls notice", () => {
  const run = tempDir("rotation-download-");
  try {
    const bin = fakeGhDownload(run, "cursor.json", '{"last":7}');
    const env = { PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: run, TMPDIR: run, API_BUDGET_TOKEN: "github-token" };
    const download = ghDownload({ repo: "o/r", token: "t", dir: run, env });
    assert.equal(download(41), '{"last":7}');
    assert.equal(download(41), '{"last":7}', "a second read of the same run downloads nothing");
    assert.equal(readFileSync(join(run, "gh-calls"), "utf8").split("\n").filter(Boolean).length, 1);
    assert.equal(
      readFileSync(join(run, "api-budget", "github-token"), "utf8"),
      "request repos/{repo}/actions/runs/{n}/artifacts\nrequest repos/{repo}/actions/artifacts/{n}/{x}\n",
    );
    const lib = fileURLToPath(new URL("../../actions/log-api-budget/api-budget.bash", import.meta.url));
    const calls = execFileSync("bash", ["-c", '. "$0"; api_budget_emit_calls github-token', lib], { encoding: "utf8", env });
    assert.equal(calls, "::notice title=api-calls::github-token=2 not-modified=0 graphql=0 core-unread=2\n");
  } finally {
    rmSync(run, { recursive: true, force: true });
  }
});

test("ghDownload runs gh run download until the rate guard holds a stop, then sends nothing and fails", () => {
  const run = tempDir("rotation-download-");
  try {
    const bin = fakeGhDownload(run, "cursor.json", "{}");
    const env = { PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: run, TMPDIR: run, API_BUDGET_TOKEN: "github-token" };
    assert.equal(ghDownload({ repo: "o/r", token: "t", dir: run, env })(40), "{}");
    writeFileSync(join(run, "api-budget", "stop"), `* ${Math.floor(Date.now() / 1000) + 600}\n`);
    assert.throws(() => ghDownload({ repo: "o/r", token: "t", dir: run, env })(41), /Command failed/);
    assert.deepEqual(readFileSync(join(run, "gh-calls"), "utf8").split("\n").filter(Boolean).map((args) => args.split(" ")[2]), ["40"], "the refused download never ran gh");
    assert.equal(readFileSync(join(run, "api-budget", "github-token"), "utf8").split("\n").filter(Boolean).length, 2, "only run 40's requests");
  } finally {
    rmSync(run, { recursive: true, force: true });
  }
});

test("a graphql or search stop does not refuse gh run download, which spends core", () => {
  const run = tempDir("rotation-download-");
  try {
    const bin = fakeGhDownload(run, "cursor.json", "{}");
    const env = { PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: run, TMPDIR: run, API_BUDGET_TOKEN: "github-token" };
    assert.equal(ghDownload({ repo: "o/r", token: "t", dir: run, env })(40), "{}");
    const until = Math.floor(Date.now() / 1000) + 600;
    writeFileSync(join(run, "api-budget", "stop"), `graphql ${until}\nsearch ${until}\n`);
    assert.equal(ghDownload({ repo: "o/r", token: "t", dir: run, env })(41), "{}");
    writeFileSync(join(run, "api-budget", "stop"), `core ${until}\n`);
    assert.throws(() => ghDownload({ repo: "o/r", token: "t", dir: run, env })(42), /Command failed/);
  } finally {
    rmSync(run, { recursive: true, force: true });
  }
});

// A one-entry zip with the entry stored uncompressed, laid out as PKWARE's
// APPNOTE.TXT section 4.3 gives a local header, its data, the central
// directory header and the end of central directory record.
function storedZip(name, text) {
  const data = Buffer.from(text);
  const file = Buffer.from(name);
  const crc = crc32(data);
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(20, 4);
  local.writeUInt32LE(crc, 14);
  local.writeUInt32LE(data.length, 18);
  local.writeUInt32LE(data.length, 22);
  local.writeUInt16LE(file.length, 26);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0);
  central.writeUInt16LE(20, 4);
  central.writeUInt16LE(20, 6);
  central.writeUInt32LE(crc, 16);
  central.writeUInt32LE(data.length, 20);
  central.writeUInt32LE(data.length, 24);
  central.writeUInt16LE(file.length, 28);
  const offset = local.length + file.length + data.length;
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(1, 8);
  end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length + file.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([local, file, data, central, file, end]);
}

test("ghDownloadArtifact fetches an artifact by id with one counted API request and lists no artifacts", () => {
  const run = tempDir("rotation-archive-");
  try {
    const archive = join(run, "fixture.zip");
    writeFileSync(archive, storedZip("settled.json", '{"version":3}'));
    const bin = fakeGhArchive(run, archive);
    const env = { PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: run, TMPDIR: run, API_BUDGET_TOKEN: "github-token" };
    const download = ghDownloadArtifact({ repo: "o/r", token: "t", dir: run, name: "reconcile-settled-runs", file: "settled.json", env });
    assert.equal(download(9), '{"version":3}');
    assert.equal(download(9), '{"version":3}', "a second read of the same artifact downloads nothing");
    assert.deepEqual(readFileSync(join(run, "gh-calls"), "utf8").split("\n").filter(Boolean), ["api -i repos/o/r/actions/artifacts/9/zip"]);
    const lib = fileURLToPath(new URL("../../actions/log-api-budget/api-budget.bash", import.meta.url));
    const calls = execFileSync("bash", ["-c", '. "$0"; api_budget_emit_calls github-token', lib], { encoding: "utf8", env });
    assert.match(calls, /github-token=1 /, "the download host is off GitHub's API, so only the archive request counts");
    assert.throws(
      () => ghDownloadArtifact({ repo: "o/r", token: "t", dir: run, name: "x", file: "other.json", env })(10),
      (error) => error.code === "ENOENT" && error.syscall === "open",
      "a file the archive lacks fails as a missing file would",
    );
  } finally {
    rmSync(run, { recursive: true, force: true });
  }
});

test("ghDownloadArtifact reads an archive member larger than execFileSync's 1 MiB default maxBuffer", () => {
  const run = tempDir("rotation-large-archive-");
  try {
    const text = `{"blob":"${"abcdefgh".repeat(256 * 1024)}"}`;
    assert.ok(text.length > 2 * 1024 * 1024, "the member is over 2 MiB, twice Node's 1 MiB default");
    const archive = join(run, "fixture.zip");
    writeFileSync(archive, storedZip("cache.json", text));
    const bin = fakeGhArchive(run, archive);
    const env = { PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: run, TMPDIR: run, API_BUDGET_TOKEN: "github-token" };
    const download = ghDownloadArtifact({ repo: "o/r", token: "t", dir: run, name: "pr-merge-run-cache", file: "cache.json", env });
    assert.equal(download(11) === text, true, "the large member round-trips byte for byte");
    assert.equal(download(11) === text, true, "a second read of the same artifact extracts again without error");
  } finally {
    rmSync(run, { recursive: true, force: true });
  }
});

// A reader's artifact listing saved in the shared reads (artifactsNamed) names
// the artifact, so ghDownload fetches it by id, one request where gh run
// download sends two (the listing and the archive), with the same text.
test("ghDownload fetches by the id the shared artifact listing names, and lists again only without one", () => {
  const run = tempDir("rotation-shared-download-");
  try {
    const archive = join(run, "fixture.zip");
    writeFileSync(archive, storedZip("cursor.json", '{"last":7}'));
    const bin = fakeGhArchive(run, archive);
    const env = { PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: run, TMPDIR: run, API_BUDGET_TOKEN: "github-token" };
    const shared = join(run, "reads.json");
    const listing = (artifacts) => ({ total_count: artifacts.length, artifacts });
    writeFileSync(
      shared,
      JSON.stringify({
        "/repos/o/r/actions/runs/41/artifacts?per_page=100": listing([
          { id: 8, name: "pr-merge-gate-cursor", expired: false },
          { id: 9, name: "pr-merge-gate-cursor", expired: false },
          { id: 12, name: "pr-merge-gate-cursor", expired: true },
          { id: 13, name: "other", expired: false },
        ]),
      }),
    );
    const download = ghDownload({ repo: "o/r", token: "t", dir: run, env, shared });
    assert.equal(download(41), '{"last":7}');
    assert.deepEqual(readFileSync(join(run, "gh-calls"), "utf8").split("\n").filter(Boolean), ["api -i repos/o/r/actions/artifacts/9/zip"]);
    // An artifact missing the file (a pr-merge-verify-answers artifact without
    // eam-skip.json) reads as gh run download's missing file does: ENOENT on
    // open, which verify-answers.mjs takes as "no skip records".
    assert.throws(() => download(41, "eam-skip.json"), (error) => error.code === "ENOENT" && error.syscall === "open");
  } finally {
    rmSync(run, { recursive: true, force: true });
  }
  for (const [why, saved] of [
    ["no listing for the run", {}],
    ["only an expired one", { "/repos/o/r/actions/runs/41/artifacts?per_page=100": { total_count: 1, artifacts: [{ id: 9, name: "pr-merge-gate-cursor", expired: true }] } }],
    ["a listing short of its count", { "/repos/o/r/actions/runs/41/artifacts?per_page=100": { total_count: 101, artifacts: [{ id: 9, name: "pr-merge-gate-cursor", expired: false }] } }],
  ]) {
    const dir = tempDir("rotation-shared-download-");
    try {
      const bin = fakeGhDownload(dir, "cursor.json", '{"last":7}');
      const env = { PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, TMPDIR: dir, API_BUDGET_TOKEN: "github-token" };
      const shared = join(dir, "reads.json");
      writeFileSync(shared, JSON.stringify(saved));
      assert.equal(ghDownload({ repo: "o/r", token: "t", dir, env, shared })(41), '{"last":7}', why);
      assert.match(readFileSync(join(dir, "gh-calls"), "utf8"), /^run download 41 /, why);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

test("newestTrustedArtifact names the newest unexpired artifact of the run newestTrustedRun picks", async () => {
  const listing = { workflow_runs: [wf(8, "schedule"), wf(7, "schedule")] };
  const artifacts = {
    8: [{ id: 80, name: "pr-merge-gate-cursor", expired: true }],
    7: [{ id: 71, name: "pr-merge-gate-cursor", expired: false }, { id: 73, name: "pr-merge-gate-cursor", expired: false }, { id: 79, name: "other", expired: false }],
  };
  const actions = async (method, path) => {
    if (path.includes("/workflows/")) return listing;
    const list = artifacts[/\/runs\/(\d+)\/artifacts/.exec(path)[1]];
    return { total_count: list.length, artifacts: list };
  };
  const options = { repo: REPO, runId: "999", actions, name: "pr-merge-gate-cursor" };
  assert.deepEqual(await newestTrustedArtifact(options), { runId: 7, artifactId: 73 });
  assert.equal(await newestTrustedRun(options), 7);
  artifacts[7] = [{ name: "pr-merge-gate-cursor", expired: false }];
  assert.deepEqual(await newestTrustedArtifact(options), { runId: 7, artifactId: undefined });
  assert.equal(await newestTrustedRun(options), 7, "a listing without ids still finds the run");
});
