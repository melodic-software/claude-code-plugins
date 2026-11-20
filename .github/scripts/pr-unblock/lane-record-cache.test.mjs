import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";

import { zipOf } from "../lib/lane-binding.fixtures.mjs";
import { CACHE_FILE, LANE_RECORD_CACHE, laneRecordStore } from "./lane-record-cache.mjs";

const WORKFLOW = ".github/workflows/pr-dispatch-feedback.yml";
const REPO = "o/r";
const NOW = Date.parse("2026-11-20T00:00:00Z");
const LATER = "2026-12-20T00:00:00.000Z";
const CACHE_RUN = 900;
const LANE_PATH = ".github/workflows/pr-review-hosted.yml";

const laneRun = (id, attempt = 1, extra = {}) => ({
  id,
  path: LANE_PATH,
  head_sha: "a".repeat(40),
  head_branch: "feature/x",
  head_repository: { full_name: REPO },
  status: "completed",
  run_attempt: attempt,
  created_at: "2026-11-19T00:00:00Z",
  updated_at: "2026-11-19T01:00:00Z",
  ...extra,
});
const records = (attempt) => Array.from({ length: attempt }, (_, i) => `claude-lane-comments-claude-review-${i + 1}`);
const ENTRY = { lane: "claude-review", pr: 7, head: "a".repeat(40), kind: "review_comment", id: 11, sha256: "f".repeat(64) };
const saved = (id, attempt = 1, extra = {}) => ({
  [`${id}/${attempt}`]: { seen: "2026-11-19T23:00:00.000Z", expires: LATER, run: laneRun(id, attempt), entries: [ENTRY], recorded: records(attempt), ...extra },
});
const fileOf = (runs, top = {}) => JSON.stringify({ version: 1, repo: REPO, runs, ...top });
const trustedRun = (extra = {}) => ({ id: CACHE_RUN, path: WORKFLOW, head_branch: "main", event: "workflow_run", head_repository: { full_name: REPO }, ...extra });

function reads({ rows, run = trustedRun(), zip, listError } = {}) {
  const calls = [];
  return {
    calls,
    listArtifactsNamed: async (name) => {
      calls.push(["list", name]);
      if (listError) throw listError;
      return rows ?? [{ id: 9, name: LANE_RECORD_CACHE, expired: false, workflow_run: { id: CACHE_RUN } }];
    },
    getRun: async (id) => {
      calls.push(["run", id]);
      return run;
    },
    download: async (id) => {
      calls.push(["download", id]);
      if (zip instanceof Error) throw zip;
      return zip;
    },
  };
}
const storeOver = (fake, logs = []) =>
  laneRecordStore({ workflow: WORKFLOW, repository: REPO, ...fake, log: (line) => logs.push(line), now: NOW });

test("the newest unexpired cache of a trusted run answers a stored run in three reads", async () => {
  const rows = [
    { id: 5, name: LANE_RECORD_CACHE, expired: false, workflow_run: { id: 1 } },
    { id: 12, name: LANE_RECORD_CACHE, expired: true, workflow_run: { id: 2 } },
    { id: 9, name: LANE_RECORD_CACHE, expired: false, workflow_run: { id: CACHE_RUN } },
  ];
  const fake = reads({ rows, zip: zipOf({ [CACHE_FILE]: fileOf(saved(4242)) }) });
  const store = storeOver(fake);
  const hit = await store.get("4242");
  assert.equal(hit.run.run_attempt, 1, "the stored run's attempt");
  assert.deepEqual(hit.entries, [ENTRY], "the stored run's entries");
  assert.deepEqual([...hit.recorded], ["claude-lane-comments-claude-review-1"], "the stored run's complete records");
  assert.equal(await store.get("77"), undefined, "a run the cache does not hold");
  assert.deepEqual(fake.calls, [["list", LANE_RECORD_CACHE], ["run", CACHE_RUN], ["download", 9]], "one listing, one run read, one download");
});

test("a cache another run uploaded is no cache", async () => {
  const zip = zipOf({ [CACHE_FILE]: fileOf(saved(4242)) });
  const cases = {
    "another workflow": trustedRun({ path: ".github/workflows/other.yml" }),
    "another branch": trustedRun({ head_branch: "feature/x" }),
    "another event": trustedRun({ event: "pull_request" }),
    "a fork's run": trustedRun({ head_repository: { full_name: "someone/r" } }),
    "another run id": trustedRun({ id: CACHE_RUN + 1 }),
  };
  for (const [what, run] of Object.entries(cases)) {
    const logs = [];
    const fake = reads({ run, zip });
    assert.equal(await storeOver(fake, logs).get("4242"), undefined, what);
    assert.equal(fake.calls.some(([call]) => call === "download"), false, `${what}: nothing downloaded`);
    assert.match(logs.join("\n"), /read live/, `${what}: logged`);
  }
});

test("a missing, unreadable or invalid cache is no cache, and the read never throws", async () => {
  const cases = {
    "none listed": reads({ rows: [] }),
    "only an expired one": reads({ rows: [{ id: 9, name: LANE_RECORD_CACHE, expired: true, workflow_run: { id: CACHE_RUN } }] }),
    "the listing fails": reads({ listError: new Error("HTTP 502") }),
    "the download fails": reads({ zip: new Error("HTTP 410") }),
    "not a zip": reads({ zip: Buffer.from("nope") }),
    "no cache file": reads({ zip: zipOf({ "other.json": "{}" }) }),
    "not JSON": reads({ zip: zipOf({ [CACHE_FILE]: "{" }) }),
    "another version": reads({ zip: zipOf({ [CACHE_FILE]: fileOf(saved(4242), { version: 2 }) }) }),
    "another repository": reads({ zip: zipOf({ [CACHE_FILE]: fileOf(saved(4242), { repo: "x/y" }) }) }),
  };
  for (const [what, fake] of Object.entries(cases)) {
    const logs = [];
    assert.equal(await storeOver(fake, logs).get("4242"), undefined, what);
    assert.match(logs.join("\n"), /read live/, `${what}: logged`);
  }
});

test("an entry that expired, sat unused for a day, or is not a settled run is dropped", async () => {
  const runs = {
    ...saved(1, 1, { expires: "2026-11-19T00:00:00.000Z" }),
    ...saved(2, 1, { seen: "2026-11-18T23:00:00.000Z" }),
    ...saved(3, 1, { run: laneRun(3, 1, { status: "in_progress" }) }),
    ...saved(4, 2, { recorded: records(1) }),
    ...saved(5, 1, { run: laneRun(6) }),
    ...saved(7, 1, { run: laneRun(7, 1, { path: ".github/workflows/other.yml" }) }),
    ...saved(8),
  };
  const store = storeOver(reads({ zip: zipOf({ [CACHE_FILE]: fileOf(runs) }) }));
  for (const [id, what] of [[1, "records expired"], [2, "unused for a day"], [3, "still running"], [4, "attempt 2 unrecorded"], [5, "key and run disagree"], [7, "not a lane workflow"]]) {
    assert.equal(await store.get(String(id)), undefined, what);
  }
  assert.equal((await store.get("8")).run.id, 8, "a settled, unexpired, recently used run");
});

test("nothing is read or written until a run is asked", async () => {
  const fake = reads({ zip: zipOf({ [CACHE_FILE]: fileOf(saved(4242)) }) });
  const store = storeOver(fake);
  const path = join(tempDir("lane-records-"), CACHE_FILE);
  assert.equal(store.save(path), false, "an idle tick saves nothing");
  assert.equal(existsSync(path), false, "no file written");
  assert.deepEqual(fake.calls, [], "no reads");
  await store.get("4242");
  assert.equal(store.save(path), true, "a tick that read the cache saves it");
  assert.equal(existsSync(path), true, "the file is written");
});

test("save keeps the read entries with the new ones, a re-run's attempt replacing the earlier one", async () => {
  const store = storeOver(reads({ zip: zipOf({ [CACHE_FILE]: fileOf({ ...saved(1), ...saved(2) }) }) }));
  await store.get("3");
  const expiresAt = Date.parse(LATER);
  const loaded = (run, attempt) => ({ run: { ...laneRun(run, attempt), html_url: "dropped" }, entries: [ENTRY, { complete: true }], recorded: new Set(records(attempt)), expiresAt });
  await store.put("1", loaded(1, 2));
  await store.put("3", loaded(3, 1));
  await store.put("4", { ...loaded(4, 1), expiresAt: Number.NaN });
  const path = join(tempDir("lane-records-"), CACHE_FILE);
  assert.equal(store.save(path), true);
  const file = JSON.parse(readFileSync(path, "utf8"));
  assert.deepEqual(Object.keys(file.runs).sort(), ["1/2", "2/1", "3/1"], "attempt 2 replaces attempt 1; a run with no record expiry is not kept");
  assert.equal(file.runs["3/1"].run.html_url, undefined, "only the run fields the checks read");
  assert.deepEqual(file.runs["3/1"].entries, [ENTRY], "only comment entries");
  assert.equal(file.runs["3/1"].seen, new Date(NOW).toISOString());
  const next = storeOver(reads({ zip: zipOf({ [CACHE_FILE]: readFileSync(path, "utf8") }) }));
  assert.equal((await next.get("1")).run.run_attempt, 2, "the next tick reads what this one saved");
});

test("a save that fails is logged, not thrown", async () => {
  const logs = [];
  const store = storeOver(reads({ rows: [] }), logs);
  await store.get("1");
  assert.equal(store.save(join(tempDir("lane-records-"), "missing", CACHE_FILE)), false);
  assert.match(logs.join("\n"), /not saved/);
});

test("the workflow writes and uploads the file name the reader opens", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-dispatch-feedback.yml", import.meta.url), "utf8");
  const named = [...workflow.matchAll(/(?:FEEDBACK_LANE_RECORDS_PATH|path): \$\{\{ runner\.temp \}\}\/(\S*lane-records\S*)/g)].map((m) => m[1]);
  assert.ok(named.length >= 3, named.join(", "));
  assert.deepEqual([...new Set(named)], [CACHE_FILE]);
});
