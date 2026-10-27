// carry-run-cache.mjs: only reads that cannot change reach the next pr-merge
// run, each under a carried-* name the reader uses only to count a FAIL. The kept and dropped sections follow
// babysit_run_cache.py's readers (babysit_verify_evidence.py: run-record,
// fail-head-ref, on-branch; babysit_merge*.py: the MAX_AGE-bounded and
// credential-keyed ones); record shapes follow GET .../actions/runs/{id}.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { carry, main, read } from "./carry-run-cache.mjs";
import { forgetMainTip } from "./head-ref-map.mjs";
import { mainCall } from "./on-main.fixture.mjs";

const REPO = "example-org/example-repo";
const NOW = Date.parse("2026-10-19T12:00:00+00:00");
const AT = "2026-10-19T11:00:00+00:00";
const MAIN_SHA = "c".repeat(40);
const opts = { repo: REPO, branch: "main", now: NOW };
const entry = (value, at = AT) => ({ at, value });
const origin = (id, overrides = {}) => ({
  id,
  path: ".github/workflows/pr-verify.yml",
  event: "workflow_run",
  head_branch: "main",
  head_sha: MAIN_SHA,
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  status: "completed",
  conclusion: "failure",
  run_attempt: 1,
  run_started_at: "2026-10-19T10:00:00Z",
  ...overrides,
});

test("keeps origin run records, FAIL head refs and run heads on main, each under a carried name", () => {
  const kept = carry(
    {
      "run-record": { [`${REPO}|7`]: entry(origin(7)) },
      "carried-run-record": { [`${REPO}|6`]: entry(origin(6)) },
      "fail-head-ref": { [`${REPO}|70`]: entry({ head_ref: "feat/x" }) },
      "carried-fail-head-ref": { [`${REPO}|60`]: entry({ head_ref: "feat/y" }) },
      "on-branch": { [`${REPO}|${MAIN_SHA}...main`]: entry(true) },
      "carried-on-branch": { [`${REPO}|${"e".repeat(40)}...main`]: entry(true) },
    },
    opts,
  );
  assert.deepEqual(kept, {
    "carried-run-record": { [`${REPO}|6`]: entry(origin(6)), [`${REPO}|7`]: entry(origin(7)) },
    "carried-fail-head-ref": {
      [`${REPO}|60`]: entry({ head_ref: "feat/y" }),
      [`${REPO}|70`]: entry({ head_ref: "feat/x" }),
    },
    "carried-on-branch": {
      [`${REPO}|${"e".repeat(40)}...main`]: entry(true),
      [`${REPO}|${MAIN_SHA}...main`]: entry(true),
    },
  });
});

test("trims a run record's repositories to their names, keeping every other field", () => {
  const full = { full_name: REPO, id: 1, owner: { login: "o" }, description: "x".repeat(99) };
  const kept = carry(
    {
      "run-record": { [`${REPO}|7`]: entry(origin(7, { repository: full, head_repository: { ...full } })) },
      "carried-run-record": { [`${REPO}|6`]: entry(origin(6)) },
    },
    opts,
  );
  assert.deepEqual(kept["carried-run-record"], {
    [`${REPO}|6`]: entry(origin(6)),
    [`${REPO}|7`]: entry(origin(7)),
  });
});

test("drops every section that can change between runs", () => {
  const sections = [
    "permission",
    "default-branch",
    "max-in-flight",
    "acting-login",
    "identity-only",
    "human-gated-label",
    "branch-rules",
    "queue-sweep",
    "trusted-humans",
  ];
  const restored = Object.fromEntries(sections.map((s) => [s, { [REPO]: entry("x") }]));
  // A section the reader trusts is never restored under its name: the
  // restored entry may come from any job in the default branch's scope.
  for (const s of ["on-branch", "run-record", "fail-head-ref"]) restored[s] = {};
  restored["on-branch"][`${REPO}|${MAIN_SHA}...main`] = entry(true);
  restored["run-record"][`${REPO}|7`] = entry(origin(7));
  restored["fail-head-ref"][`${REPO}|70`] = entry({ head_ref: "feat/x" });
  const kept = carry(restored, opts);
  assert.deepEqual(Object.keys(kept).sort(), ["carried-fail-head-ref", "carried-on-branch", "carried-run-record"]);
});

test("drops a run record that would turn a FAIL away", () => {
  const forgeries = {
    "another workflow": { path: ".github/workflows/pr-require-checks.yml" },
    "a pull_request run": { event: "pull_request" },
    "a branch other than main": { head_branch: "feat/x" },
    "another repository": { repository: { full_name: "someone/fork" } },
    "a fork head": { head_repository: { full_name: "someone/fork" } },
    "a malformed run head": { head_sha: "c".repeat(39) },
    "another run's record": { id: 8 },
  };
  for (const [label, overrides] of Object.entries(forgeries)) {
    const kept = carry({ "run-record": { [`${REPO}|7`]: entry(origin(7, overrides)) } }, opts);
    assert.deepEqual(kept["carried-run-record"], {}, label);
  }
  const otherRepo = carry({ "run-record": { "someone/fork|7": entry(origin(7)) } }, opts);
  assert.deepEqual(otherRepo["carried-run-record"], {});
});

test("drops a head ref or run head of no known shape", () => {
  const kept = carry(
    {
      "fail-head-ref": {
        [`${REPO}|None`]: entry({ head_ref: "feat/x" }),
        [`${REPO}|71`]: entry({ head_ref: null }),
        [`${REPO}|72`]: entry("feat/x"),
      },
      "on-branch": {
        [`${REPO}|${MAIN_SHA}...feat/x`]: entry(true),
        [`someone/fork|${MAIN_SHA}...main`]: entry(true),
        [`${REPO}|${"d".repeat(40)}...main`]: entry(false),
      },
    },
    opts,
  );
  assert.deepEqual(kept["carried-fail-head-ref"], {});
  assert.deepEqual(kept["carried-on-branch"], {});
});

test("drops an entry dated in the future, with no zone, or past the 90-day retention", () => {
  const key = `${REPO}|${MAIN_SHA}...main`;
  for (const at of ["2026-10-19T13:00:00+00:00", "2026-10-19T11:00:00", "2026-07-20T11:59:00+00:00"]) {
    assert.deepEqual(carry({ "on-branch": { [key]: entry(true, at) } }, opts)["carried-on-branch"], {}, at);
  }
  // 89 days old is still inside the retention.
  assert.deepEqual(
    Object.keys(carry({ "on-branch": { [key]: entry(true, "2026-07-22T12:00:00+00:00") } }, opts)["carried-on-branch"]),
    [key],
  );
});

test("carries file to file, and writes nothing when the file is missing or unreadable", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "carry-run-cache-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const from = join(dir, "from.json");
  const to = join(dir, "to.json");
  const output = join(dir, "output");
  const env = { CARRY_FROM: from, CARRY_TO: to, GITHUB_REPOSITORY: REPO, GITHUB_OUTPUT: output };
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(line));

  main(env, NOW);
  assert.equal(existsSync(to), false);
  writeFileSync(from, "{not json");
  main(env, NOW);
  assert.equal(existsSync(to), false);
  assert.match(logs.at(-1), /^::warning::the run cache was not carried: /);
  assert.equal(existsSync(output), false);

  writeFileSync(from, JSON.stringify({ "trusted-humans": { [REPO]: entry([1]) }, "run-record": { [`${REPO}|7`]: entry(origin(7)) } }));
  main(env, NOW);
  assert.deepEqual(JSON.parse(readFileSync(to, "utf8")), {
    "carried-run-record": { [`${REPO}|7`]: entry(origin(7)) },
    "carried-fail-head-ref": {},
    "carried-on-branch": {},
  });
  assert.equal(logs.at(-1), "carried-run-record=1 carried-fail-head-ref=0 carried-on-branch=0");
  assert.equal(readFileSync(output, "utf8"), "carried=true\nkept=true\n");
});

// `read`, before the gate: the carried file comes only from the
// pr-merge-run-cache and pr-merge-verify-run-cache artifacts, each of the
// newest scheduled or hand-started pr-merge.yml run on main other than this
// one whose head commit is on main (rotation.mjs newestTrustedRun,
// head-ref-map.mjs onMain), as #9416's head-ref map does; never from
// actions/cache, which any job in main's cache scope can write (#9455).
const wf = (id, event, headSha = String(id).padStart(40, "a")) => ({
  id,
  event,
  head_branch: "main",
  path: ".github/workflows/pr-merge.yml",
  head_sha: headSha,
});

// `files` holds each run's pr-merge-run-cache file and `verify` each run's
// pr-merge-verify-run-cache file.
async function readRun(t, { pages = [[]], files = {}, verify = {}, offMain = [], fail, planted, mainTag = false } = {}) {
  forgetMainTip();
  const dir = mkdtempSync(join(tmpdir(), "carry-run-cache-read-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const to = join(dir, "pr-merge-carried.json");
  if (planted !== undefined) writeFileSync(to, planted);
  const downloads = [];
  const actions = async (method, url) => {
    if (fail) throw fail;
    const page = /\/actions\/workflows\/pr-merge\.yml\/runs\?branch=main&.*&page=(\d+)$/.exec(url)?.[1];
    if (page) return { workflow_runs: pages[Number(page) - 1] ?? [] };
    const onMain = mainCall(url, { offMain, mainTag });
    if (onMain !== undefined) return onMain;
    const id = /\/actions\/runs\/(\d+)\/artifacts\?per_page=100$/.exec(url)?.[1];
    assert.ok(id, `unexpected call ${url}`);
    const artifacts = [
      ...(id in files ? [{ name: "pr-merge-run-cache", expired: false }] : []),
      ...(id in verify ? [{ name: "pr-merge-verify-run-cache", expired: false }] : []),
    ];
    return { total_count: artifacts.length, artifacts };
  };
  const download = (id, name = "pr-merge-run-cache") => {
    if (name === "pr-merge-verify-run-cache") {
      downloads.push(`verify:${id}`);
      return verify[id];
    }
    assert.equal(name, "pr-merge-run-cache");
    downloads.push(id);
    return files[id];
  };
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(String(line)));
  await read({ env: { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "999", CARRY_TO: to }, actions, download });
  t.mock.restoreAll();
  return { written: existsSync(to) ? readFileSync(to, "utf8") : undefined, downloads, logs };
}

test("read takes the carried file from the newest trusted run on main only", async (t) => {
  const kept = JSON.stringify({
    "carried-run-record": { [`${REPO}|7`]: entry(origin(7)) },
    "skip-unchanged": { 12: { at: AT, value: { reason: "risk:MED" } } },
  });
  const result = await readRun(t, {
    // This run (999) and a pull_request_target run are never asked; run 9's
    // head commit is not on main.
    pages: [[wf(999, "schedule"), wf(10, "pull_request_target"), wf(9, "workflow_dispatch"), wf(8, "schedule")]],
    files: { 10: "{}", 9: "{}", 8: kept },
    offMain: [wf(9).head_sha],
  });
  assert.deepEqual(result.downloads, [8]);
  // Written as kept, skip-unchanged included: babysit_merge_skip.py filter
  // reads that section from this file, and the run cache takes the carried-*
  // sections through carry() in the next step.
  assert.equal(result.written, kept);
});

test("read removes a file already at its path and never reads it", async (t) => {
  const planted = JSON.stringify({ "carried-on-branch": { [`${REPO}|${MAIN_SHA}...main`]: entry(true) } });
  for (const options of [
    { planted },
    { planted, pages: [[wf(8, "schedule")]], files: { 8: "not json" } },
    { planted, pages: [[wf(8, "schedule")]], files: { 8: "[]" } },
    { planted, fail: new Error("HTTP 502") },
  ]) {
    const result = await readRun(t, options);
    assert.equal(result.written, undefined);
  }
});

test("read warns on a file it cannot use, and is quiet when no run has one", async (t) => {
  const quiet = await readRun(t, { pages: [[wf(8, "schedule")]] });
  assert.ok(!quiet.logs.some((line) => line.startsWith("::warning")));
  const bad = await readRun(t, { pages: [[wf(8, "schedule")]], files: { 8: "not json" } });
  assert.ok(bad.logs.some((line) => line.startsWith("::warning::the pr-merge-run-cache file was not carried: ")));
});

test("read takes no file while a tag shares main's name", async (t) => {
  // A run on a tag named main reports head_branch main, so only the tag's
  // absence (a 404) lets a run count (check-trusted-trigger.mjs
  // requireOnDefaultBranch).
  const options = { pages: [[wf(8, "schedule")]], files: { 8: "{}" } };
  assert.deepEqual((await readRun(t, options)).downloads, [8]);
  const result = await readRun(t, { ...options, mainTag: true });
  assert.deepEqual(result.downloads, []);
  assert.equal(result.written, undefined);
});

// The merge gate reads no lane verdict, so only enable-auto-merge's reader
// fills run-record; it uploads what it kept as pr-merge-verify-run-cache, and
// `read` adds that file's carried-* sections, and nothing else, to the merge
// job's file, whose other sections babysit_merge_skip.py reads.
const skip = { 12: { at: AT, value: { reason: "risk:MED" } } };
const mergeFile = JSON.stringify({
  "carried-run-record": { [`${REPO}|7`]: entry(origin(7)) },
  "carried-fail-head-ref": {},
  "carried-on-branch": {},
  "skip-unchanged": skip,
});
const verifyFile = JSON.stringify({
  "carried-run-record": { [`${REPO}|9`]: entry(origin(9)) },
  "carried-fail-head-ref": { [`${REPO}|90`]: entry({ head_ref: "feat/z" }) },
  "carried-on-branch": {},
  // Never taken from this file: only the merge job's refusals are skipped.
  "skip-unchanged": { 13: { at: AT, value: { reason: "risk:HIGH" } } },
  "run-record": { [`${REPO}|11`]: entry(origin(11)) },
});

test("read adds the verify file's carried sections to the merge file, every other section as it was", async (t) => {
  const result = await readRun(t, {
    pages: [[wf(9, "schedule"), wf(8, "schedule")]],
    files: { 8: mergeFile },
    verify: { 9: verifyFile },
  });
  // Each file from the newest trusted run holding it.
  assert.deepEqual(result.downloads, [8, "verify:9"]);
  const written = JSON.parse(result.written);
  assert.deepEqual(written, {
    "carried-run-record": { [`${REPO}|7`]: entry(origin(7)), [`${REPO}|9`]: entry(origin(9)) },
    "carried-fail-head-ref": { [`${REPO}|90`]: entry({ head_ref: "feat/z" }) },
    "carried-on-branch": {},
    "skip-unchanged": skip,
  });
  assert.equal(JSON.stringify(written["skip-unchanged"]), JSON.stringify(JSON.parse(mergeFile)["skip-unchanged"]));
});

test("read writes the merge file as it is when the verify file does not read", async (t) => {
  const result = await readRun(t, { pages: [[wf(8, "schedule")]], files: { 8: mergeFile }, verify: { 8: "not json" } });
  assert.equal(result.written, mergeFile);
  assert.ok(result.logs.some((line) => line.startsWith("::warning::the verifier reads were not carried: ")));
});

test("read carries the verify file's sections when the merge file does not read", async (t) => {
  const carried = {
    "carried-run-record": { [`${REPO}|9`]: entry(origin(9)) },
    "carried-fail-head-ref": { [`${REPO}|90`]: entry({ head_ref: "feat/z" }) },
    "carried-on-branch": {},
  };
  for (const bad of ["not json", "[]"]) {
    const result = await readRun(t, {
      pages: [[wf(9, "schedule"), wf(8, "schedule")]],
      files: { 8: bad },
      verify: { 9: verifyFile },
    });
    assert.deepEqual(JSON.parse(result.written), carried);
    assert.ok(result.logs.some((line) => line.startsWith("::warning::the pr-merge-run-cache file was not carried: ")));
  }
});

test("read writes nothing when neither file reads", async (t) => {
  const result = await readRun(t, {
    pages: [[wf(9, "schedule"), wf(8, "schedule")]],
    files: { 8: "not json" },
    verify: { 9: "not json" },
  });
  assert.equal(result.written, undefined);
  assert.ok(result.logs.some((line) => line.startsWith("::warning::the pr-merge-run-cache file was not carried: ")));
  assert.ok(result.logs.some((line) => line.startsWith("::warning::the verifier reads were not carried: ")));
});

test("read yields the carried sections of a run holding only one of the two files", async (t) => {
  const verifyOnly = await readRun(t, { pages: [[wf(8, "schedule")]], verify: { 8: verifyFile } });
  assert.deepEqual(JSON.parse(verifyOnly.written), {
    "carried-run-record": { [`${REPO}|9`]: entry(origin(9)) },
    "carried-fail-head-ref": { [`${REPO}|90`]: entry({ head_ref: "feat/z" }) },
    "carried-on-branch": {},
  });
  const mergeOnly = await readRun(t, { pages: [[wf(8, "schedule")]], files: { 8: mergeFile } });
  assert.equal(mergeOnly.written, mergeFile);
});

test("read takes no verify file from an untrusted run or one off main", async (t) => {
  const result = await readRun(t, {
    pages: [[wf(11, "pull_request_target"), wf(10, "push"), wf(9, "workflow_dispatch"), wf(8, "schedule")]],
    files: { 8: mergeFile },
    verify: { 11: verifyFile, 10: verifyFile, 9: verifyFile },
    offMain: [wf(9).head_sha],
  });
  assert.deepEqual(result.downloads, [8]);
  assert.equal(result.written, mergeFile);
  const tagged = await readRun(t, { pages: [[wf(8, "schedule")]], verify: { 8: verifyFile }, mainTag: true });
  assert.deepEqual(tagged.downloads, []);
  assert.equal(tagged.written, undefined);
});

test("keep reports kept=true only when it kept a read", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "carry-run-cache-kept-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const from = join(dir, "from.json");
  const output = join(dir, "output");
  const env = { CARRY_FROM: from, CARRY_TO: join(dir, "to.json"), GITHUB_REPOSITORY: REPO, GITHUB_OUTPUT: output };
  t.mock.method(console, "log", () => {});
  writeFileSync(from, JSON.stringify({ "trusted-humans": { [REPO]: entry([1]) } }));
  main(env, NOW);
  // carried=true still says the file was written, for the skip refusals.
  assert.equal(readFileSync(output, "utf8"), "carried=true\n");
});

// Two ticks: the first tick's merge gate reads no verdict and keeps an
// empty carried file beside its refusals; its enable-auto-merge reader fills
// run-record and keeps it. The second tick starts its run cache warm.
test("a second tick starts its run cache from the first tick's verifier reads", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "carry-run-cache-ticks-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(String(line)));
  const keep = (cache, name) => {
    const from = join(dir, `${name}-cache.json`);
    const to = join(dir, `${name}-carried.json`);
    const output = join(dir, `${name}-output`);
    writeFileSync(from, JSON.stringify(cache));
    main({ CARRY_FROM: from, CARRY_TO: to, GITHUB_REPOSITORY: REPO, GITHUB_OUTPUT: output }, NOW);
    return { text: readFileSync(to, "utf8"), output: readFileSync(output, "utf8") };
  };
  const merge = keep({ "trusted-humans": { [REPO]: entry([1]) } }, "merge");
  const mergeWithSkip = JSON.stringify({ ...JSON.parse(merge.text), "skip-unchanged": skip });
  const arm = keep({ "run-record": { [`${REPO}|7`]: entry(origin(7)) }, "on-branch": { [`${REPO}|${MAIN_SHA}...main`]: entry(true) } }, "arm");
  assert.equal(merge.output, "carried=true\n");
  assert.equal(arm.output, "carried=true\nkept=true\n");
  t.mock.restoreAll();

  const next = await readRun(t, { pages: [[wf(8, "schedule")]], files: { 8: mergeWithSkip }, verify: { 8: arm.text } });
  const from = join(dir, "next-carried.json");
  writeFileSync(from, next.written);
  const runCache = join(dir, "next-run-cache.json");
  t.mock.method(console, "log", (line) => logs.push(String(line)));
  main({ CARRY_FROM: from, CARRY_TO: runCache, GITHUB_REPOSITORY: REPO }, NOW);
  assert.equal(logs.at(-1), "carried-run-record=1 carried-fail-head-ref=0 carried-on-branch=1");
  assert.deepEqual(JSON.parse(next.written)["skip-unchanged"], skip);
});
