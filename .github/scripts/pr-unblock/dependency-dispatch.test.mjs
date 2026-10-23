import assert from "node:assert/strict";
import { test } from "node:test";

import { LIMIT_DEFAULTS } from "../work-resolve-issue/limits.mjs";
import { dispatchDependencyReviews } from "./dependency-dispatch.mjs";
import { emptyRecord, markHandled, parseRecord } from "./dispatch-record.mjs";

const CHECK = "pr-unblock / review-dependency";

function pr(number, overrides = {}) {
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: String(number).padStart(40, "c"),
    headRefName: `dependabot/npm_and_yarn/x-${number}`,
    // The GraphQL listing's shape: the Bot login has no [bot] suffix.
    author: { login: "dependabot", databaseId: 49699333 },
    title: "build(deps): bump x from 1.0.0 to 2.0.0",
    body: "",
    labels: { nodes: [{ name: "dependencies" }] },
    changedFiles: 0,
    commits: { totalCount: 1 },
    ...overrides,
  };
}

const DEPENDABOT_COMMIT_AUTHOR = { name: "dependabot[bot]", email: "49699333+dependabot[bot]@users.noreply.github.com" };
// GitHub verified and committed it, as it does Dependabot's commits.
const SIGNED = { committer: { email: "noreply@github.com" }, verification: { verified: true, reason: "valid" } };

function fakeApi({ nodes = [], checks = new Map(), ci = new Map(), files = new Map(), commits = new Map() } = {}) {
  const calls = { dispatch: [], checks: [], commits: [], files: [] };
  return {
    calls,
    async listPullCommits(number) {
      calls.commits.push(number);
      return commits.get(number) ?? [{ sha: "d".repeat(40), commit: { message: "bump", author: DEPENDABOT_COMMIT_AUTHOR, ...SIGNED } }];
    },
    async getCommit(sha) {
      return { sha, files: [] };
    },
    async listPullFiles(number) {
      calls.files.push(number);
      return files.get(number) ?? [];
    },
    async listOpenPulls() {
      return { nodes, pageInfo: { hasNextPage: false, endCursor: null } };
    },
    async listCheckRuns({ sha, checkName, appId }) {
      calls.checks.push({ sha, checkName, appId });
      if (checkName === "ci-status") {
        return ci.get(sha) ?? [];
      }
      // A run that names no check is the review-dependency one.
      return (checks.get(sha) ?? []).filter((run) => (run.name ?? CHECK) === checkName);
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      calls.dispatch.push({ workflow, ref, inputs });
      return { workflowRunId: 7000 + Number(inputs["pr-number"]) };
    },
  };
}

const run = (api, extra = {}) =>
  dispatchDependencyReviews({ api, runId: "55", log: () => {}, config: [], policy: { autoMerge: { reviewOnly: [] } }, provenance: async () => [], ...extra });

test("dispatches review-dependency for a review-tier Dependabot PR", async () => {
  const api = fakeApi({ nodes: [pr(4)] });
  const { dispatched, failed } = await run(api);
  assert.equal(failed, 0);
  assert.deepEqual(dispatched, [{ number: 4, workflowRunId: "7004" }]);
  assert.deepEqual(api.calls.dispatch[0], {
    workflow: "pr-unblock.yml",
    ref: "refs/heads/main",
    inputs: { "pr-number": "4", activity: "review-dependency", "dispatcher-run-id": "55" },
  });
});

test("leaves auto-tier bumps, other authors, drafts and forks alone", async () => {
  const api = fakeApi({
    nodes: [
      pr(1, { title: "bump x from 1.0.0 to 1.1.0" }),
      pr(2, { author: { login: "octocat" } }),
      pr(3, { isDraft: true }),
      pr(5, { isCrossRepository: true }),
      pr(6, { baseRefName: "release/plugins" }),
    ],
  });
  const { dispatched } = await run(api);
  assert.deepEqual(dispatched, []);
});

test("Dependabot is matched by its account id, never by a login", async () => {
  const api = fakeApi({
    nodes: [
      pr(7),
      pr(8, { author: { login: "dependabot" } }),
      pr(9, { author: { login: "dependabot[bot]" } }),
      pr(10, { author: { login: "dependabot", databaseId: 1 } }),
    ],
  });
  const { dispatched } = await run(api);
  assert.deepEqual(dispatched.map((d) => d.number), [7]);
});

test("a minor bump whose registry provenance changed is dispatched for review", async () => {
  const api = fakeApi({ nodes: [pr(1, { title: "bump x from 1.0.0 to 1.1.0" })] });
  await run(api, { provenance: async () => ["provenance-changed:x"] });
  assert.deepEqual(api.calls.dispatch.map((call) => call.inputs["pr-number"]), ["1"]);
});

test("a red ci-status makes a patch bump review", async () => {
  const node = pr(8, { title: "bump x from 1.0.0 to 1.0.1" });
  const api = fakeApi({
    nodes: [node],
    ci: new Map([[node.headRefOid, [{ id: 1, app: { slug: "github-actions" }, status: "completed", conclusion: "failure" }]]]),
  });
  assert.equal((await run(api)).dispatched.length, 1);
});

test("a review-only dependency makes a patch bump review, and an unreadable policy makes every bump review", async () => {
  const node = pr(9, { title: "bump x from 1.0.0 to 1.0.1", changedFiles: 1 });
  const files = new Map([[9, [{ filename: "package.json", patch: "" }]]]);
  const entry = { repository: "o/r", ecosystem: "npm", directory: "/", dependency: "x", reviewed: "2026-10-17", basis: "b", control: "c" };
  const policy = (dependency) => ({ autoMerge: { reviewOnly: [{ ...entry, dependency }] } });
  const extra = { config: [["npm", "/"]], repository: "o/r" };
  assert.equal((await run(fakeApi({ nodes: [node], files }), { ...extra, policy: policy("x") })).dispatched.length, 1);
  assert.equal((await run(fakeApi({ nodes: [node], files }), { ...extra, policy: policy("y") })).dispatched.length, 0);
  assert.equal((await run(fakeApi({ nodes: [node], files }), { ...extra, policy: null })).dispatched.length, 1);
  assert.equal((await run(fakeApi({ nodes: [node], files }), { ...extra, policy: undefined })).dispatched.length, 1);
});

test("skips a head that already has a review-dependency check run, except an untrusted-trigger skip", async () => {
  const a = pr(10);
  const b = pr(11);
  const api = fakeApi({
    nodes: [a, b],
    checks: new Map([
      [a.headRefOid, [{ status: "completed", conclusion: "success", output: { title: "Reviewed" } }]],
      [b.headRefOid, [{ status: "completed", conclusion: "neutral", output: { title: "Skipped: untrusted-trigger" } }]],
    ]),
  });
  const { dispatched } = await run(api);
  assert.deepEqual(dispatched.map((d) => d.number), [11]);
  assert.ok(api.calls.checks.some((call) => call.checkName === CHECK && call.appId === 15368));
});

test("Dependabot commit metadata that disagrees with the title is review, and so is another author's commit", async () => {
  const message = "bump\n---\nupdated-dependencies:\n- dependency-name: other\n  update-type: version-update:semver-patch\n...\n";
  const nodes = [pr(30, { title: "bump x from 1.0.0 to 1.0.1" }), pr(31, { title: "bump x from 1.0.0 to 1.0.1" }), pr(32, { title: "bump x from 1.0.0 to 1.0.1" })];
  const commits = new Map([
    [30, [{ sha: "a".repeat(40), commit: { message, author: DEPENDABOT_COMMIT_AUTHOR, ...SIGNED } }]],
    [31, [{ sha: "b".repeat(40), commit: { message, author: { name: "someone", email: "someone@example.test" }, ...SIGNED } }]],
    [32, [{ sha: "e".repeat(40), commit: { message: "bump", author: DEPENDABOT_COMMIT_AUTHOR } }]],
  ]);
  const { dispatched } = await run(fakeApi({ nodes, commits }), { maxDispatch: 3 });
  assert.deepEqual(dispatched.map((d) => d.number), [30, 31, 32], "an unverified Dependabot author is review too");
});

test("a patch bump whose files the content rule does not cover is review", async () => {
  const config = [["npm", "/"]];
  const nodes = [pr(40, { title: "bump x from 1.0.0 to 1.0.1", changedFiles: 1 }), pr(41, { title: "bump x from 1.0.0 to 1.0.1", changedFiles: 2 })];
  const files = new Map([
    [40, [{ filename: "package-lock.json" }]],
    [41, [{ filename: "package-lock.json" }, { filename: "dist/bundle.js" }]],
  ]);
  const { dispatched } = await run(fakeApi({ nodes, files }), { config });
  assert.deepEqual(dispatched.map((d) => d.number), [41]);
});

test("a patch bump whose commits listing is short of its total is review", async () => {
  const config = [["npm", "/"]];
  const bump = { title: "bump x from 1.0.0 to 1.0.1", changedFiles: 1 };
  const nodes = [pr(50, bump), pr(51, { ...bump, commits: { totalCount: 251 } })];
  const files = new Map([
    [50, [{ filename: "package-lock.json" }]],
    [51, [{ filename: "package-lock.json" }]],
  ]);
  const { dispatched } = await run(fakeApi({ nodes, files }), { config });
  assert.deepEqual(dispatched.map((d) => d.number), [51]);
});

test("dispatches at most the cap, lowest number first", async () => {
  const api = fakeApi({ nodes: [pr(23), pr(21), pr(22)] });
  const { dispatched } = await run(api, { maxDispatch: 2 });
  assert.deepEqual(dispatched.map((d) => d.number), [21, 22]);
});

// A round whose verdict job found no model turn (#9362): its
// apply-dependency-verdict check skipped no-model-turn, so the
// review-dependency check runs before it handled nothing, and the next run
// dispatches the head again. Every such round posts its round marker, so the
// select job's round cap still ends it.
const roundRun = (name, conclusion, title, started) => ({
  name: `pr-unblock / ${name}`,
  status: "completed",
  conclusion,
  started_at: started,
  completed_at: started,
  output: { title, summary: "" },
});
const noModelTurn = (started = "2026-10-17T10:05:00Z") => roundRun("apply-dependency-verdict", "neutral", "Skipped: no-model-turn", started);
const headOf = (node, runs) => new Map([[node.headRefOid, runs]]);

test("a head whose last round had no model turn dispatches again, and is not recorded as handled", async () => {
  for (const [label, check] of [
    ["the model call failed", roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z")],
    ["the broker refused the run", roundRun("review-dependency", "neutral", "Skipped: not-assessed", "2026-10-17T10:00:00Z")],
  ]) {
    const node = pr(60);
    const record = emptyRecord();
    const { dispatched } = await run(fakeApi({ nodes: [node], checks: headOf(node, [check, noModelTurn()]) }), { record });
    assert.deepEqual(dispatched, [{ number: 60, workflowRunId: "7060" }], label);
    assert.equal(record.handled.get(CHECK), undefined, label);
  }
});

// A review-dependency run the usage limit stopped at `started`, its lane record
// naming a reset an hour later.
const limitStop = (started) => {
  const resets = new Date(Date.parse(started) + 3_600_000).toISOString().replace(".000", "");
  return {
    ...roundRun("review-dependency", "failure", "Failed", started),
    output: { title: "Failed", summary: `lane=pr-unblock activity=review-dependency class=rate-limit resets=${resets}` },
  };
};

// A rate-limited model call leaves no verdict, so its verdict job also skips
// no-model-turn; that never releases the limit stop before its reset.
test("a no-model-turn verdict after a limit stop still holds the head until the reset", async () => {
  const node = pr(61);
  const checks = headOf(node, [limitStop("2026-10-17T10:00:00Z"), noModelTurn()]);
  const { dispatched } = await run(fakeApi({ nodes: [node], checks }), { now: Date.parse("2026-10-17T10:30:00Z") });
  assert.deepEqual(dispatched, []);
});

// limit-stop.mjs: a limit stop holds its head until the limit resets, then the
// next run dispatches the head again, until limits.limit-stops-per-head stops
// (3 by default, work-resolve-issue/limits.mjs) hold it for good. A limit stop
// is never recorded as handled, or its reset could not release it.
test("a limit-stopped head is held until its reset, dispatched after it, and held once limit-stops-per-head stops are reached", async () => {
  const node = pr(70);
  const once = [limitStop("2026-10-17T10:00:00Z"), noModelTurn()];
  const record = emptyRecord();
  const before = await run(fakeApi({ nodes: [node], checks: headOf(node, once) }), { record, now: Date.parse("2026-10-17T10:59:00Z") });
  assert.deepEqual(before.dispatched, [], "held before the reset");
  assert.equal(record.handled.get(CHECK), undefined, "a limit stop is not recorded");
  const after = await run(fakeApi({ nodes: [node], checks: headOf(node, once) }), { record, now: Date.parse("2026-10-17T11:01:00Z") });
  assert.deepEqual(after.dispatched, [{ number: 70, workflowRunId: "7070" }], "dispatched after the reset");

  const stops = (n) => Array.from({ length: n }, (_, i) => limitStop(`2026-10-17T1${i * 2}:00:00Z`));
  const late = Date.parse("2026-10-18T00:00:00Z");
  const two = await run(fakeApi({ nodes: [node], checks: headOf(node, stops(2)) }), { now: late });
  assert.deepEqual(two.dispatched.map((d) => d.number), [70], "2 reset stops of the default 3");
  const three = await run(fakeApi({ nodes: [node], checks: headOf(node, stops(3)) }), { now: late });
  assert.deepEqual(three.dispatched, [], "3 reset stops reach the default cap");
  const capped = await run(fakeApi({ nodes: [node], checks: headOf(node, stops(1)) }), { now: late, limits: { ...LIMIT_DEFAULTS, "limit-stops-per-head": 1 } });
  assert.deepEqual(capped.dispatched, [], "the resolved limits set the cap");
});

test("a round that answered, or a newer review-dependency check, still holds the head", async () => {
  for (const [label, runs] of [
    ["the last round escalated", [roundRun("review-dependency", "success", "Passed", "2026-10-17T10:00:00Z"), roundRun("apply-dependency-verdict", "neutral", "Skipped: awaiting-human", "2026-10-17T10:05:00Z")]],
    ["a no-model-turn round before a round that answered", [
      roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z"),
      noModelTurn(),
      roundRun("review-dependency", "success", "Passed", "2026-10-17T11:00:00Z"),
      roundRun("apply-dependency-verdict", "success", "Passed", "2026-10-17T11:05:00Z"),
    ]],
    // review-dependency-not-run posts the round cap's skip after the round.
    ["the round cap was reached after it", [
      roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z"),
      noModelTurn(),
      roundRun("review-dependency", "neutral", "Skipped: awaiting-human", "2026-10-17T11:00:00Z"),
    ]],
    ["no verdict job ran", [roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z")]],
  ]) {
    const node = pr(62);
    const lines = [];
    const api = fakeApi({ nodes: [node], checks: headOf(node, runs) });
    assert.deepEqual((await run(api, { log: (line) => lines.push(line) })).dispatched, [], label);
    assert.deepEqual(api.calls.dispatch, [], label);
    assert.match(lines.at(-1), /already has a pr-unblock \/ review-dependency check run/, label);
  }
});

// Between the round's review-dependency check and its verdict job's check, a
// dispatcher run must not record the head, or the verdict's no-model-turn skip
// could never release it.
test("a head whose newest review-dependency check has no later verdict check is not recorded, and is released once the verdict skips no-model-turn", async () => {
  const node = pr(63);
  const record = emptyRecord();
  const check = roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z");
  assert.deepEqual((await run(fakeApi({ nodes: [node], checks: headOf(node, [check]) }), { record })).dispatched, [], "the head is handled for now");
  assert.equal(record.handled.get(CHECK), undefined, "but not recorded");
  // An older verdict check, from an earlier round, does not count.
  await run(fakeApi({ nodes: [node], checks: headOf(node, [noModelTurn("2026-10-17T09:05:00Z"), check]) }), { record });
  assert.equal(record.handled.get(CHECK), undefined);
  const later = await run(fakeApi({ nodes: [node], checks: headOf(node, [check, noModelTurn()]) }), { record });
  assert.deepEqual(later.dispatched, [{ number: 63, workflowRunId: "7063" }]);
});

// The round cap's skip, posted by review-dependency-not-run, has no verdict
// job after it, so it records the head at once; a read runner skip waits for
// its verdict.
test("a head whose newest review-dependency check is a select skip is recorded, and a read runner skip is not", async () => {
  for (const [label, runs] of [
    ["the round cap after a no-model-turn round", [roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z"), noModelTurn(), roundRun("review-dependency", "neutral", "Skipped: awaiting-human", "2026-10-17T11:00:00Z")]],
    ["the round cap alone", [roundRun("review-dependency", "neutral", "Skipped: awaiting-human", "2026-10-17T11:00:00Z")]],
    ["a sort that no longer applies", [roundRun("review-dependency", "neutral", "Skipped: not-applicable", "2026-10-17T11:00:00Z")]],
  ]) {
    const node = pr(64);
    const record = emptyRecord();
    assert.deepEqual((await run(fakeApi({ nodes: [node], checks: headOf(node, runs) }), { record })).dispatched, [], label);
    assert.ok(record.handled.get(CHECK)?.has(node.headRefOid), label);
  }
  const node = pr(65);
  const record = emptyRecord();
  await run(fakeApi({ nodes: [node], checks: headOf(node, [roundRun("review-dependency", "neutral", "Skipped: not-assessed", "2026-10-17T10:00:00Z")]) }), { record });
  assert.equal(record.handled.get(CHECK), undefined);
});

// A record the dispatcher wrote before a no-model-turn verdict released the
// head holds it as handled; that record's version is read as empty.
test("a version 1 record that holds a no-model-turn head is ignored, and the head dispatches again", async () => {
  const node = pr(66);
  const record = parseRecord(JSON.stringify({ version: 1, handled: { [CHECK]: [node.headRefOid] }, dispatched: {} }));
  const checks = headOf(node, [roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z"), noModelTurn()]);
  assert.deepEqual((await run(fakeApi({ nodes: [node], checks }), { record })).dispatched, [{ number: 66, workflowRunId: "7066" }]);
});

// Reads spent only where they change the decision. Each count beside the
// assertion is what the dispatcher read before it skipped them.
const RED_CI = [{ id: 1, app: { slug: "github-actions" }, status: "completed", conclusion: "failure" }];

test("a red ci-status is review without reading the commits or files", async () => {
  const node = pr(8, { title: "bump x from 1.0.0 to 1.0.1" });
  const api = fakeApi({ nodes: [node], ci: new Map([[node.headRefOid, RED_CI]]) });
  assert.deepEqual((await run(api)).dispatched, [{ number: 8, workflowRunId: "7008" }]);
  // Before: one commits and one files listing.
  assert.deepEqual(api.calls.commits, []);
  assert.deepEqual(api.calls.files, []);
});

test("once the cap is reached the rest are left unread", async () => {
  const api = fakeApi({ nodes: [pr(24), pr(23), pr(21), pr(22)] });
  const lines = [];
  const { dispatched } = await run(api, { maxDispatch: 2, log: (line) => lines.push(line) });
  assert.deepEqual(dispatched.map((d) => d.number), [21, 22]);
  // Before: 8 check-run reads and 4 commits listings, for the same two dispatches.
  assert.equal(api.calls.checks.length, 4);
  assert.deepEqual(api.calls.commits, [21, 22]);
  assert.ok(lines.includes("defer #23: 2 review dispatches this run; left for a later run unread"));
});

test("a reviewed head is recorded, and the next run reads nothing for it", async () => {
  const node = pr(10);
  // The round's verdict job posted after it, so no no-model-turn skip can still release the head.
  const reviewed = { status: "completed", conclusion: "success", started_at: "2026-10-17T10:00:00Z", output: { title: "Reviewed" } };
  const checks = new Map([[node.headRefOid, [reviewed, roundRun("apply-dependency-verdict", "success", "Passed", "2026-10-17T10:05:00Z")]]]);
  const record = emptyRecord();
  const first = fakeApi({ nodes: [node], checks });
  assert.deepEqual((await run(first, { record })).dispatched, []);
  // ci-status, then both checks' runs.
  assert.equal(first.calls.checks.length, 3);
  assert.ok(record.handled.get(CHECK).has(node.headRefOid));
  const second = fakeApi({ nodes: [node], checks });
  assert.deepEqual((await run(second, { record })).dispatched, []);
  assert.deepEqual([second.calls.checks, second.calls.commits, second.calls.files], [[], [], []]);
});

test("a review run still going, or an untrusted-trigger skip, is not recorded", async () => {
  const a = pr(12);
  const b = pr(13);
  const checks = new Map([
    [a.headRefOid, [{ status: "in_progress", conclusion: null }]],
    [b.headRefOid, [{ status: "completed", conclusion: "neutral", output: { title: "Skipped: untrusted-trigger" } }]],
  ]);
  const record = emptyRecord();
  await run(fakeApi({ nodes: [a, b], checks }), { record });
  assert.equal(record.handled.get(CHECK), undefined);
  markHandled(record, CHECK, a.headRefOid);
  assert.deepEqual((await run(fakeApi({ nodes: [a, b], checks }), { record })).dispatched.map((d) => d.number), [13]);
});
