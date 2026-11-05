// find-capture.mjs, which each pr-verify judge job runs: it takes only the
// capture run the same upstream run started, waits for it within a bound,
// records every miss as a blocked reason, and never fails the job, whatever
// it finds or fails to read.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { APPEAR_MS, artifactName, CAPTURE_PATH, findCapture, main, missReason, runTitle, WAIT_MS } from "./find-capture.mjs";

const REPO = "melodic-software/claude-code-plugins";
const UPSTREAM = "777";
const PR = "41";
const HEAD = "a".repeat(40);
const MINUTE = 60_000;
const ids = { repository: REPO, upstreamRunId: UPSTREAM, pr: PR, headSha: HEAD };
const run = (overrides = {}) => ({
  id: 900,
  path: CAPTURE_PATH,
  event: "workflow_run",
  head_branch: "main",
  repository: { full_name: REPO },
  display_title: `pr-verify-capture ${UPSTREAM} ${HEAD}`,
  status: "completed",
  conclusion: "success",
  ...overrides,
});
const artifact = (overrides = {}) => ({ id: 5001, name: `pr-capture-${PR}-${HEAD}`, expired: false, ...overrides });
const LIST = `GET /repos/${REPO}/actions/workflows/pr-verify-capture.yml/runs?event=workflow_run&branch=main&per_page=50&page=1`;
const RECORD = `GET /repos/${REPO}/actions/runs/900`;
const ARTIFACTS = `GET /repos/${REPO}/actions/runs/900/artifacts?name=pr-capture-41-${HEAD}&per_page=10`;

// A GitHub stand-in: each runs listing answers the next of `listings`, each
// run record read the next of `records` (the last of each repeats), each
// artifacts read answers `artifacts`; a fake clock that each sleep moves on.
const fake = ({ listings, records = [run()], artifacts = [artifact()] }) => {
  const calls = [];
  let clock = 0;
  let listed = 0;
  let read = 0;
  const github = async (method, apiPath) => {
    calls.push(`${method} ${apiPath}`);
    if (apiPath.includes("/actions/workflows/")) {
      const runs = listings[Math.min(listed, listings.length - 1)];
      listed += 1;
      return { workflow_runs: runs };
    }
    if (/\/actions\/runs\/\d+$/.test(apiPath)) {
      const record = records[Math.min(read, records.length - 1)];
      read += 1;
      return record;
    }
    return { artifacts };
  };
  const sleeps = [];
  const options = { now: () => clock, sleep: async (ms) => { sleeps.push(ms); clock += ms; } };
  return { github, calls, sleeps, options };
};

test("the run-name and artifact name it looks for are the capture workflow's, and never a verdict's", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-verify-capture.yml", import.meta.url), "utf8");
  assert.match(workflow, new RegExp(`^run-name: ${runTitle("\\$\\{\\{ github\\.event\\.workflow_run\\.id \\}\\}", "\\$\\{\\{ github\\.event\\.workflow_run\\.head_sha \\}\\}")}$`, "m"));
  assert.match(workflow, /^ {10}name: pr-capture-\$\{\{ steps\.pr\.outputs\.pr-number \}\}-\$\{\{ steps\.pr\.outputs\.head-sha \}\}$/m);
  assert.equal(artifactName(PR, HEAD), `pr-capture-41-${HEAD}`);
  assert.doesNotMatch(artifactName(PR, HEAD), /^pr-verify-/);
});

test("a completed capture run of this upstream run gives its artifact id", async () => {
  const { github, calls, options } = fake({ listings: [[run()]] });
  assert.deepEqual(await findCapture(github, ids, options), { artifactId: "5001", runId: "900" });
  assert.deepEqual(calls, [LIST, ARTIFACTS]);
  // The listing starts at the upstream run's creation.
  const since = fake({ listings: [[run()]] });
  await findCapture(since.github, { ...ids, createdAt: "2026-11-03T10:00:00Z" }, since.options);
  assert.equal(since.calls[0], `GET /repos/${REPO}/actions/workflows/pr-verify-capture.yml/runs?event=workflow_run&branch=main&created=%3E%3D2026-11-03T10%3A00%3A00Z&per_page=50&page=1`);
});

// The review repro (#13053): a later judge job asks hours after the capture,
// when 50 capture runs of other pull requests fill the first page.
test("a capture run past the first page is still found", async () => {
  const others = Array.from({ length: 50 }, (_, i) => run({ id: 2000 + i, display_title: `pr-verify-capture ${1000 + i} ${HEAD}` }));
  const { github, calls, options } = fake({ listings: [others, [run()]] });
  assert.deepEqual(await findCapture(github, ids, options), { artifactId: "5001", runId: "900" });
  assert.match(calls[1], /&page=2$/);
  // A short page ends the listing: no second page is read.
  const short = fake({ listings: [others.slice(0, 49)] });
  assert.equal((await findCapture(short.github, ids, short.options)).reason, "no capture run was started for this head");
  assert.ok(short.calls.every((call) => call.endsWith("&page=1")));
});

const STRANGERS = [
  { path: ".github/workflows/pr-verify.yml" },
  { event: "workflow_dispatch" },
  { head_branch: "feature" },
  { repository: { full_name: "someone/fork" } },
  { display_title: `pr-verify-capture 778 ${HEAD}` },
  { display_title: `pr-verify-capture ${UPSTREAM} ${"b".repeat(40)}` },
];

test("a run that is not this file's on main by workflow_run for this upstream run and head is never taken", async () => {
  for (const other of STRANGERS) {
    const { github, options } = fake({ listings: [[run(other)]] });
    const found = await findCapture(github, ids, options);
    assert.equal(found.artifactId, undefined, JSON.stringify(other));
    assert.equal(found.reason, "no capture run was started for this head", JSON.stringify(other));
  }
});

test("once found, only the run's own record is read, first after 3 minutes and then every 3, until it completes", async () => {
  const done = fake({ listings: [[run({ status: "in_progress", conclusion: null })]], records: [run({ status: "queued", conclusion: null }), run()] });
  assert.deepEqual(await findCapture(done.github, ids, done.options), { artifactId: "5001", runId: "900" });
  assert.deepEqual(done.sleeps, [3 * MINUTE, 3 * MINUTE]);
  assert.deepEqual(done.calls, [LIST, RECORD, RECORD, ARTIFACTS]);
});

// The call counts the polling costs: a listing each minute made 36 calls over
// the 35-minute bound, and 5 for a run completing 3 minutes in.
test("a run still going at the bound costs 13 calls, its last read at the bound and never past it", async () => {
  const late = fake({ listings: [[run({ status: "in_progress", conclusion: null })]], records: [run({ status: "in_progress", conclusion: null })] });
  const found = await findCapture(late.github, ids, late.options);
  assert.equal(found.reason, "capture run 900 was still running after 35 minutes");
  assert.equal(found.miss, "running:900");
  assert.equal(late.calls.length, 13);
  assert.equal(late.calls.filter((call) => call === LIST).length, 1);
  // Eleven 3-minute waits and a 2-minute one that lands on the bound.
  assert.deepEqual(late.sleeps, [...Array(11).fill(3 * MINUTE), 2 * MINUTE]);
  assert.equal(late.sleeps.reduce((a, b) => a + b, 0), WAIT_MS);
  // A run completing 3 minutes in: the listing, one record read, the artifacts.
  const quick = fake({ listings: [[run({ status: "in_progress", conclusion: null })]], records: [run()] });
  assert.deepEqual(await findCapture(quick.github, ids, quick.options), { artifactId: "5001", runId: "900" });
  assert.equal(quick.calls.length, 3);
});

test("a run record that stops matching this upstream run and head is not taken", async () => {
  for (const other of [...STRANGERS, { id: 901 }]) {
    const { github, calls, options } = fake({ listings: [[run({ status: "in_progress", conclusion: null })]], records: [run(other)] });
    const found = await findCapture(github, ids, options);
    assert.equal(found.reason, "capture run 900's record no longer names this upstream run and head", JSON.stringify(other));
    assert.equal(found.artifactId, undefined);
    assert.ok(!calls.includes(ARTIFACTS));
  }
});

test("a capture run that ended other than success is named by its conclusion, and its artifact is not read", async () => {
  for (const conclusion of ["failure", "cancelled", "timed_out"]) {
    const listed = fake({ listings: [[run({ conclusion })]] });
    assert.deepEqual(await findCapture(listed.github, ids, listed.options), { miss: `ended:900:${conclusion}`, reason: `capture run 900 ended ${conclusion}` });
    assert.deepEqual(listed.calls, [LIST]);
  }
  // Read off its own record after a wait.
  const polled = fake({ listings: [[run({ status: "in_progress", conclusion: null })]], records: [run({ conclusion: "failure" })] });
  assert.equal((await findCapture(polled.github, ids, polled.options)).reason, "capture run 900 ended failure");
  // A conclusion outside GitHub's lowercase enum is no conclusion to quote.
  for (const conclusion of [null, "Failure", "x y", "failure\nartifact-id=1"]) {
    const odd = fake({ listings: [[run({ conclusion })]] });
    assert.deepEqual(await findCapture(odd.github, ids, odd.options), { miss: "unreadable", reason: "the capture run or its artifact could not be read" }, JSON.stringify(conclusion));
  }
});

test("a capture run that never shows up is given up on after two minutes", async () => {
  const { github, calls, sleeps, options } = fake({ listings: [[]] });
  assert.equal((await findCapture(github, ids, options)).reason, "no capture run was started for this head");
  assert.equal(sleeps.reduce((a, b) => a + b, 0), APPEAR_MS);
  // Listed each minute while it has yet to show up: at 0, 1 and 2 minutes.
  assert.equal(calls.length, 3);
});

test("a completed run with no live artifact of the exact name gives none", async () => {
  for (const artifacts of [[], [artifact({ expired: true })], [artifact({ name: `pr-capture-41-${HEAD}-x` })], [artifact({ name: `pr-verify-41-${HEAD}-pass` })]]) {
    const { github, options } = fake({ listings: [[run()]], artifacts });
    assert.deepEqual(await findCapture(github, ids, options), { miss: "no-artifact:900", reason: "capture run 900 left no capture artifact for this head" }, JSON.stringify(artifacts));
  }
  // The newest of two runs and of two artifacts.
  const { github, options } = fake({ listings: [[run({ id: 900 }), run({ id: 950 })]], artifacts: [artifact({ id: 6 }), artifact({ id: 7 })] });
  assert.deepEqual(await findCapture(github, ids, options), { artifactId: "7", runId: "950" });
});

test("a miss code gives its reason only in its exact shape", () => {
  assert.equal(missReason("not-started"), "no capture run was started for this head");
  assert.equal(missReason("ended:900:startup_failure"), "capture run 900 ended startup_failure");
  for (const bad of ["", "900:5001", "running", "running:0", "running:900:1", "ended:900", "ended:900:Failure", "ended:x:failure", "not-started\nx", " not-started", "no-app", undefined, null]) {
    assert.equal(missReason(bad), undefined, JSON.stringify(bad));
  }
});

// A miss that can change writes its reason but no carry, so a later job searches again.
const UNREADABLE = "blocked-reason=the capture run or its artifact could not be read\n";
const NOT_STARTED = "blocked-reason=no capture run was started for this head\n";
const FOUND = "artifact-id=5001\nrun-id=900\ncarry=900:5001\nblocked-reason=capture run 900's artifact 5001 did not download a summary\n";

test("main writes the ids for a found capture, a blocked reason for every miss, nothing with no app, and never throws", async () => {
  const dir = tempDir("find-capture-");
  const env = (extra) => {
    const output = path.join(dir, `out-${Math.random()}`);
    writeFileSync(output, "");
    return { GITHUB_OUTPUT: output, GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPO, UPSTREAM_RUN_ID: UPSTREAM, PR_NUMBER: PR, HEAD_SHA: HEAD, CAPTURE_APP: "claude-code", ...extra };
  };
  const out = (e) => readFileSync(e.GITHUB_OUTPUT, "utf8");
  const found = env();
  const { github, options } = fake({ listings: [[run()]] });
  await main(found, { github, ...options });
  assert.equal(out(found), FOUND);
  const noApp = env({ CAPTURE_APP: "" });
  let called = false;
  await main(noApp, { github: async () => { called = true; } });
  assert.equal(called, false);
  assert.equal(out(noApp), "");
  // An API failure: the error's text stays in the log, out of the outputs.
  const failing = env();
  await main(failing, { github: async () => { throw new Error("HTTP 502\nartifact-id=1"); }, ...options });
  assert.equal(out(failing), UNREADABLE);
  const unset = env({ GITHUB_TOKEN: "" });
  await main(unset, { github, ...options });
  assert.equal(out(unset), UNREADABLE);
  const malformed = env({ HEAD_SHA: "not-a-sha" });
  await main(malformed, { github, ...options });
  assert.equal(out(malformed), "carry=malformed\nblocked-reason=the upstream run, pull request or head is malformed\n");
  for (const [listings, expected, records] of [
    [[[run({ conclusion: "failure" })]], "carry=ended:900:failure\nblocked-reason=capture run 900 ended failure\n"],
    [[[]], NOT_STARTED],
    [[[run({ status: "in_progress", conclusion: null })]], "blocked-reason=capture run 900 was still running after 35 minutes\n"],
    [[[run({ status: "in_progress", conclusion: null })]], "carry=mismatch:900\nblocked-reason=capture run 900's record no longer names this upstream run and head\n", [run({ head_branch: "feature" })]],
  ]) {
    const missed = env();
    const stand = fake({ listings, records: records ?? [run({ status: "in_progress", conclusion: null })] });
    await main(missed, { github: stand.github, ...stand.options });
    assert.equal(out(missed), expected);
  }
  const bare = env();
  const empty = fake({ listings: [[run()]], artifacts: [] });
  await main(bare, { github: empty.github, ...empty.options });
  assert.equal(out(bare), "carry=no-artifact:900\nblocked-reason=capture run 900 left no capture artifact for this head\n");
});

test("a later judge job takes a capture or a miss that cannot change and reads nothing, and searches again after any other", async () => {
  const dir = tempDir("find-capture-carry-");
  const run = async (carried) => {
    const output = path.join(dir, `out-${Math.random()}`);
    writeFileSync(output, "");
    let calls = 0;
    const github = async () => {
      calls += 1;
      return { workflow_runs: [] };
    };
    let clock = 0;
    await main(
      { GITHUB_OUTPUT: output, GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPO, UPSTREAM_RUN_ID: UPSTREAM, PR_NUMBER: PR, HEAD_SHA: HEAD, CAPTURE_APP: "claude-code", FOUND_CAPTURE: carried },
      { github, now: () => clock, sleep: async (ms) => { clock += ms; } },
    );
    return { output: readFileSync(output, "utf8"), calls };
  };
  assert.deepEqual(await run("900:5001"), { output: FOUND, calls: 0 });
  assert.deepEqual(await run("ended:900:failure"), { output: "carry=ended:900:failure\nblocked-reason=capture run 900 ended failure\n", calls: 0 });
  assert.deepEqual(await run("malformed"), { output: "carry=malformed\nblocked-reason=the upstream run, pull request or head is malformed\n", calls: 0 });
  assert.deepEqual(await run("no-artifact:900"), { output: "carry=no-artifact:900\nblocked-reason=capture run 900 left no capture artifact for this head\n", calls: 0 });
  assert.deepEqual(await run("mismatch:900"), { output: "carry=mismatch:900\nblocked-reason=capture run 900's record no longer names this upstream run and head\n", calls: 0 });
  // A miss that can change, and anything else, is no carry: the job looks for
  // itself and records its own reason (here, the fake lists no run).
  for (const carried of ["unreadable", "not-started", "running:900", "", "900", "900:5001:7", "0:5001", "900:x", "900:5001\nartifact-id=1", "ended:900:Failure", "running:0", "mismatch:0", "not-started\nartifact-id=1", "no-app"]) {
    const result = await run(carried);
    assert.ok(result.calls > 0, JSON.stringify(carried));
    assert.equal(result.output, NOT_STARTED, JSON.stringify(carried));
  }
});
