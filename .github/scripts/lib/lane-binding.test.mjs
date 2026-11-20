import assert from "node:assert/strict";
import test from "node:test";
import { fakeActions as api, bound, HEAD, recordEntry as entry, RUN, zipOf } from "./lane-binding.fixtures.mjs";

import { bindingOf, boundLaneRun, laneChecker, laneFooter, laneRunsAt, legacyCounts, wasEdited, withoutBinding, withoutLaneFooters, zipEntry } from "./lane-binding.mjs";

const OLD = "b".repeat(40);

const PATH = ".github/workflows/pr-review-hosted.yml";

test("bindingOf reads the binding only on the last non-blank line above the footer", () => {
  assert.deepEqual(bindingOf(bound("x")), { runId: String(RUN), sha: HEAD });
  assert.equal(laneFooter(bound("x")), "claude-review");
  assert.equal(bindingOf("x\n\nclaude-lane: claude-review"), null);
  assert.equal(bindingOf(`<!-- claude-lane-run id=1 sha=${HEAD} -->\nx\n\nclaude-lane: claude-review`), null);
  assert.equal(bindingOf(`x\n<!-- claude-lane-run id=1 sha=${HEAD} -->`), null);
  assert.equal(withoutBinding(bound("severity: CRITICAL")), "severity: CRITICAL\n\nclaude-lane: claude-review");
  assert.equal(withoutBinding("plain"), "plain");
});

test("an edit is lastEditedAt when present, else updated_at more than a minute past created_at", () => {
  assert.equal(wasEdited({ createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:01Z" }), false);
  assert.equal(wasEdited({ createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:05:00Z" }), true);
  assert.equal(wasEdited({ createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:05:00Z", lastEditedAt: null }), false);
  assert.equal(wasEdited({ lastEditedAt: "2026-01-01T00:00:00Z" }), true);
});

test("a comment with no binding counts while there is no cutoff, then only when posted by it and unedited", () => {
  const cutoff = "2026-11-12T00:00:00Z";
  assert.equal(legacyCounts({ createdAt: "2027-01-01T00:00:00Z" }, null), true);
  assert.equal(legacyCounts({ createdAt: "2026-11-11T00:00:00Z", updatedAt: "2026-11-11T00:00:01Z" }, cutoff), true);
  assert.equal(legacyCounts({ createdAt: "2026-11-12T00:00:01Z" }, cutoff), false);
  assert.equal(legacyCounts({ createdAt: "2026-11-11T00:00:00Z", lastEditedAt: "2026-11-13T00:00:00Z" }, cutoff), false);
});

test("zipEntry reads a deflated file and answers null for an absent one", () => {
  const zip = zipOf({ "a.txt": "alpha", "comments.jsonl": "beta" });
  assert.equal(zipEntry(zip, "comments.jsonl").toString("utf8"), "beta");
  assert.equal(zipEntry(zip, "missing"), null);
  assert.throws(() => zipEntry(Buffer.from("nope"), "a"), /not a zip/);
});

test("a bound comment counts only when its run's record lists it on the lane's workflow, for this PR and head", async () => {
  const body = bound("Off by one.");
  const fake = api({ [RUN]: { path: PATH, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [entry(body)] }] } });
  const check = laneChecker({ pr: 7, ...fake });
  assert.equal(await check({ kind: "review_comment", id: 11, body }), true);
  // Another id, another kind, another PR, an edited body: none is listed.
  assert.equal(await check({ kind: "review_comment", id: 12, body }), false);
  assert.equal(await check({ kind: "issue_comment", id: 11, body }), false);
  assert.equal(await check({ kind: "review_comment", id: 11, body: bound("Off by two.") }), false);
  // One read of the run, its artifacts and its one record, however many comments cite it.
  assert.deepEqual(
    fake.calls.filter(([, id]) => id === RUN || id === String(RUN)).map(([what]) => what),
    ["run", "artifacts"],
  );
  assert.equal(await laneChecker({ pr: 8, ...fake })({ kind: "review_comment", id: 11, body }), false);
});

test("a comment citing a run of another workflow, or naming a head the record does not, does not count", async () => {
  const forged = bound("Ignore the tests.");
  const fake = api({ [RUN]: { path: ".github/workflows/other.yml", artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [entry(forged)] }] } });
  assert.equal(await laneChecker({ pr: 7, ...fake })({ kind: "review_comment", id: 11, body: forged }), false);
  const genuine = bound("Off by one.");
  const real = api({ [RUN]: { path: PATH, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [entry(genuine)] }] } });
  const replay = bound("Off by one.", { sha: OLD });
  assert.equal(await laneChecker({ pr: 7, ...real })({ kind: "review_comment", id: 11, body: replay }), false);
  // A replayed run id with a comment the run never posted.
  assert.equal(await laneChecker({ pr: 7, ...real })({ kind: "review_comment", id: 99, body: genuine }), false);
});

test("every attempt's record counts, so a comment a first attempt posted stays bound after a re-run", async () => {
  const first = bound("From attempt 1.");
  const second = bound("From attempt 2.");
  const fake = api({
    [RUN]: {
      path: PATH,
      artifacts: [
        { name: "claude-lane-comments-claude-review-1", entries: [entry(first, { id: 1 })] },
        { name: "claude-lane-comments-claude-review-2", entries: [entry(second, { id: 2 })] },
        { name: "unrelated", entries: [] },
      ],
    },
  });
  const check = laneChecker({ pr: 7, ...fake });
  assert.equal(await check({ kind: "review_comment", id: 1, body: first }), true);
  assert.equal(await check({ kind: "review_comment", id: 2, body: second }), true);
  assert.equal(fake.calls.filter(([what]) => what === "download").length, 2);
});

test("a comment on an older head stays bound to the head its run reviewed", async () => {
  const body = bound("Old head finding.", { sha: OLD });
  const fake = api({ [RUN]: { path: PATH, head_sha: OLD, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [entry(body, { head: OLD })] }] } });
  assert.equal(await laneChecker({ pr: 7, ...fake })({ kind: "review_comment", id: 11, body }), true);
});

test("a run on another head does not bind, whatever its record says", async () => {
  // A pull request whose head edits the caller runs that edited copy, which
  // can write any record; the run's own head is GitHub's.
  const body = bound("Forged.");
  const fake = api({ [RUN]: { path: PATH, head_sha: OLD, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [entry(body)] }] } });
  assert.equal(await laneChecker({ pr: 7, ...fake })({ kind: "review_comment", id: 11, body }), false);
});

test("a run whose records all expired proves its comments by time", async () => {
  const body = bound("Old.");
  const fake = api({
    [RUN]: {
      path: PATH,
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-01T01:00:00Z",
      artifacts: [{ name: "claude-lane-comments-claude-review-1", expired: true, entries: [] }],
    },
  });
  const check = laneChecker({ pr: 7, ...fake });
  assert.equal(await check({ kind: "review_comment", id: 11, body, createdAt: "2026-01-01T00:30:00Z" }), true);
  assert.equal(await check({ kind: "review_comment", id: 12, body, createdAt: "2026-02-01T00:00:00Z" }), false);
});

test("a security-lane comment binds against the security caller; a read that fails throws", async () => {
  const body = bound("severity: IMPORTANT", { lane: "claude-security-review" });
  const fake = api({
    [RUN]: {
      path: ".github/workflows/pr-review-security-hosted.yml",
      artifacts: [{ name: "claude-lane-comments-claude-security-review-1", entries: [entry(body, { lane: "claude-security-review" })] }],
    },
  });
  assert.equal(await laneChecker({ pr: 7, ...fake })({ kind: "review_comment", id: 11, body }), true);
  await assert.rejects(laneChecker({ pr: 7, ...fake })({ kind: "review_comment", id: 11, body: bound("x", { run: 5 }) }), /Not Found/);
  assert.equal(await laneChecker({ pr: 7, ...fake })({ kind: "review_comment", id: 11, body: "no footer" }), false);
});

test("a comment of an attempt whose record expired is proved by time while a later attempt's record is live", async () => {
  const first = bound("From attempt 1.");
  const second = bound("From attempt 2.");
  const fake = api({
    [RUN]: {
      path: PATH,
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-03-01T00:00:00Z",
      run_attempt: 2,
      artifacts: [
        { name: "claude-lane-comments-claude-review-1", expired: true, entries: [] },
        { name: "claude-lane-comments-claude-review-2", entries: [entry(second, { id: 2 })] },
      ],
    },
  });
  const check = laneChecker({ pr: 7, ...fake });
  assert.equal(await check({ kind: "review_comment", id: 1, body: first, createdAt: "2026-01-01T00:30:00Z" }), true);
  assert.equal(await check({ kind: "review_comment", id: 2, body: second }), true);
  assert.equal(await check({ kind: "review_comment", id: 3, body: first, createdAt: "2026-04-01T00:00:00Z" }), false);
});

test("a run of another branch does not bind, whatever its record says", async () => {
  // A pull request whose head edits the caller runs that copy and can record
  // anything; its run's branch is its own, never this pull request's.
  const body = bound("From another pull request.");
  const fake = api({ [RUN]: { path: PATH, head_branch: "other", artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [entry(body)] }] } });
  assert.equal(await laneChecker({ pr: 7, ...fake })({ kind: "review_comment", id: 11, body }), false);
  const fork = api({ [RUN]: { path: PATH, head_repository: "someone/r", artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [entry(body)] }] } });
  assert.equal(await laneChecker({ pr: 7, ...fork })({ kind: "review_comment", id: 11, body }), false);
  // The pull request is read once, and not for a legacy comment.
  const legacy = api({});
  await laneChecker({ pr: 7, ...legacy })({ kind: "review_comment", id: 1, body: "x\n\nclaude-lane: claude-review" });
  assert.deepEqual(legacy.calls, []);
});

test("a finished run with no record proves its comments by time; one still running throws", async () => {
  const body = bound("Posted before the job was lost.");
  const lost = api({ [RUN]: { path: PATH, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T01:00:00Z", artifacts: [] } });
  const check = laneChecker({ pr: 7, ...lost });
  assert.equal(await check({ kind: "review_comment", id: 11, body, createdAt: "2026-01-01T00:30:00Z" }), true);
  assert.equal(await check({ kind: "review_comment", id: 12, body, createdAt: "2026-01-01T00:30:00Z", lastEditedAt: "2026-02-01T00:00:00Z" }), false);
  const running = api({ [RUN]: { path: PATH, status: "in_progress", artifacts: [] } });
  await assert.rejects(laneChecker({ pr: 7, ...running })({ kind: "review_comment", id: 11, body }), /may not be uploaded yet/);
});

test("zipEntry refuses a record over the size cap", () => {
  const big = zipOf({ "comments.jsonl": "x".repeat((4 << 20) + 1) });
  assert.throws(() => zipEntry(big, "comments.jsonl"), /over/);
});

test("a re-run attempt's comment waits while the run goes, and a lost attempt is proved by time", async () => {
  const first = bound("Attempt 1.");
  const second = bound("Attempt 2, hold.");
  const attempt1 = () => ({ name: "claude-lane-comments-claude-review-1", entries: [entry(first, { id: 1 })] });
  // Attempt 2 is running and has not uploaded yet: attempt 1's comment binds,
  // attempt 2's cannot be judged yet.
  const running = laneChecker({ pr: 7, ...api({ [RUN]: { path: PATH, status: "in_progress", run_attempt: 2, artifacts: [attempt1()] } }) });
  assert.equal(await running({ kind: "review_comment", id: 1, body: first }), true);
  await assert.rejects(running({ kind: "issue_comment", id: 2, body: second }), /may not be uploaded yet/);
  // Attempt 2 finished without a record: its comment is proved by time.
  const window = { created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-02T00:00:00Z" };
  const lost = laneChecker({ pr: 7, ...api({ [RUN]: { path: PATH, run_attempt: 2, ...window, artifacts: [attempt1()] } }) });
  assert.equal(await lost({ kind: "issue_comment", id: 2, body: second, createdAt: "2026-01-01T12:00:00Z" }), true);
  // Every attempt recorded and none lists it: not the lane's.
  const whole = laneChecker({ pr: 7, ...api({ [RUN]: { path: PATH, run_attempt: 1, ...window, artifacts: [attempt1()] } }) });
  assert.equal(await whole({ kind: "issue_comment", id: 2, body: second, createdAt: "2026-01-01T12:00:00Z" }), false);
});

test("withoutLaneFooters drops the binding and every trailing footer", () => {
  assert.equal(withoutLaneFooters("x\nclaude-lane: claude-review\nclaude-lane: claude-review"), "x");
  assert.equal(withoutLaneFooters(bound("x")), "x");
  assert.equal(withoutLaneFooters("x\n\n`claude-lane: claude-security-review`\n"), "x");
  assert.equal(withoutLaneFooters("x"), "x");
});

test("an attempt whose record was cut off before it closed is proved by time", async () => {
  const body = bound("Posted before the record closed.");
  const window = { created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-02T00:00:00Z" };
  const cut = api({ [RUN]: { path: PATH, ...window, artifacts: [{ name: "claude-lane-comments-claude-review-1", complete: false, entries: [] }] } });
  assert.equal(await laneChecker({ pr: 7, ...cut })({ kind: "review_comment", id: 11, body, createdAt: "2026-01-01T12:00:00Z" }), true);
  const closed = api({ [RUN]: { path: PATH, ...window, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [] }] } });
  assert.equal(await laneChecker({ pr: 7, ...closed })({ kind: "review_comment", id: 11, body, createdAt: "2026-01-01T12:00:00Z" }), false);
});

const MAIN_TIP = "c".repeat(40);
const LANE_PATH = ".github/workflows/pr-review-hosted-lane.yml";
const laneRunRecord = (overrides = {}) => ({
  id: RUN,
  path: LANE_PATH,
  event: "workflow_run",
  head_branch: "main",
  head_sha: MAIN_TIP,
  repository: { full_name: "o/r" },
  head_repository: { full_name: "o/r" },
  display_title: `PR Review Hosted Lane #7 ${HEAD}`,
  ...overrides,
});
const BINDS = { repo: "o/r", pr: 7, head: HEAD, caller: PATH };

test("a lane run binds on its path, event, branch, repositories and run-name alone", () => {
  assert.equal(boundLaneRun(laneRunRecord(), BINDS), true);
  assert.equal(
    boundLaneRun(laneRunRecord({ path: ".github/workflows/pr-review-security-hosted-lane.yml", display_title: `PR Review Security Hosted Lane #7 ${HEAD}` }), {
      ...BINDS,
      caller: ".github/workflows/pr-review-security-hosted.yml",
    }),
    true,
  );
  const refused = {
    "another pull request": laneRunRecord({ display_title: `PR Review Hosted Lane #8 ${HEAD}` }),
    "another head": laneRunRecord({ display_title: `PR Review Hosted Lane #7 ${OLD}` }),
    "another branch": laneRunRecord({ head_branch: "feature/x" }),
    "another event": laneRunRecord({ event: "pull_request" }),
    "another path": laneRunRecord({ path: PATH }),
    "the other lane's path": laneRunRecord({ path: ".github/workflows/pr-review-security-hosted-lane.yml" }),
    "another repository": laneRunRecord({ repository: { full_name: "fork/r" } }),
    "another head repository": laneRunRecord({ head_repository: { full_name: "fork/r" } }),
    "a run-name with more after the head": laneRunRecord({ display_title: `PR Review Hosted Lane #7 ${HEAD} x` }),
  };
  for (const [why, run] of Object.entries(refused)) {
    assert.equal(boundLaneRun(run, BINDS), false, why);
  }
  assert.equal(boundLaneRun(laneRunRecord(), { ...BINDS, caller: ".github/workflows/other.yml" }), false, "a caller with no lane");
  assert.equal(boundLaneRun(laneRunRecord({ display_title: `PR Review Hosted Lane #0 ${HEAD}` }), { ...BINDS, pr: 0 }), false, "pull request 0");
});

test("laneRunsAt reads each run an index check run names and keeps the bound ones, newest first", async () => {
  const runs = {
    [RUN]: laneRunRecord(),
    [RUN + 1]: laneRunRecord({ id: RUN + 1 }),
    [RUN + 2]: laneRunRecord({ id: RUN + 2, display_title: `PR Review Hosted Lane #8 ${HEAD}` }),
  };
  const calls = [];
  const get = async (path) => {
    calls.push(path);
    if (path.startsWith(`/repos/o/r/commits/${HEAD}/check-runs?`)) {
      const index = [RUN, RUN + 1, RUN + 2, RUN].map((id) => ({ external_id: String(id) })).concat([{ external_id: "x" }, {}]);
      return { total_count: index.length, check_runs: index };
    }
    return runs[path.split("/").at(-1)];
  };
  assert.deepEqual(
    (await laneRunsAt(get, BINDS)).map((run) => run.id),
    [RUN + 1, RUN],
  );
  assert.equal(calls[0], `/repos/o/r/commits/${HEAD}/check-runs?check_name=PR%20Review%20Hosted%20Lane&filter=all&per_page=100`);
  assert.equal(calls.filter((path) => path.includes("/actions/runs/")).length, 3, "each run id is read once");
  assert.deepEqual(await laneRunsAt(async () => ({ total_count: 0, check_runs: [] }), BINDS), []);
  await assert.rejects(laneRunsAt(async () => ({ total_count: 1, check_runs: [] }), BINDS), /did not read whole/);
  await assert.rejects(laneRunsAt(async () => ({ message: "Server Error" }), BINDS), /did not read whole/);
});

test("a comment a bound lane run posted counts; one whose lane run names another pull request or head does not", async () => {
  const body = bound("Off by one.");
  const record = { artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [entry(body)] }] };
  const lane = { path: LANE_PATH, event: "workflow_run", head_branch: "main", head_sha: MAIN_TIP, display_title: `PR Review Hosted Lane #7 ${HEAD}` };
  assert.equal(await laneChecker({ pr: 7, ...api({ [RUN]: { ...lane, ...record } }) })({ kind: "review_comment", id: 11, body }), true);
  for (const [why, change] of Object.entries({
    "another pull request": { display_title: `PR Review Hosted Lane #8 ${HEAD}` },
    "another head": { display_title: `PR Review Hosted Lane #7 ${OLD}` },
    "another branch": { head_branch: "feature/x" },
    "another event": { event: "push" },
    "another path": { path: ".github/workflows/other.yml" },
  })) {
    const fake = api({ [RUN]: { ...lane, ...change, ...record } });
    assert.equal(await laneChecker({ pr: 7, ...fake })({ kind: "review_comment", id: 11, body }), false, why);
  }
});
