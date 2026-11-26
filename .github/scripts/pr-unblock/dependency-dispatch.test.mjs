import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { LIMIT_DEFAULTS } from "../work-resolve-issue/limits.mjs";
import { dispatchDependencyReviews } from "./dependency-dispatch.mjs";
import { emptyRecord, markHandled, parseRecord, serializeRecord } from "./dispatch-record.mjs";

const CHECK = "pr-unblock / review-dependency";

function pr(number, overrides = {}) {
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: String(number).padStart(40, "c"),
    headRefName: `dependabot/npm_and_yarn/x-${number}`,
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
const SIGNED = { committer: { email: "noreply@github.com" }, verification: { verified: true, reason: "valid" } };

function fakeApi({ nodes = [], checks = new Map(), ci = new Map(), files = new Map(), commits = new Map(), runs = [], annotations = {}, comments = new Map(), jobs = {} } = {}) {
  const calls = { dispatch: [], checks: [], commits: [], files: [], runs: 0, reruns: [], comments: [] };
  return {
    calls,
    async listAnnotations(id) {
      return annotations[id] ?? [];
    },
    async listIssueComments(number) {
      calls.comments.push(number);
      return comments.get(number) ?? [];
    },
    async readLatestJobs(runId) {
      return jobs[runId] ? { jobs: jobs[runId] } : null;
    },
    async rerunJob(jobId) {
      calls.reruns.push(jobId);
    },
    async listWorkflowRuns() {
      calls.runs += 1;
      return runs;
    },
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

test("a check-run read that fails, on a 5xx after its retries, a rate limit or any other answer, skips that PR with a warning and fails nothing", async () => {
  const api = fakeApi({ nodes: [pr(4), pr(5)] });
  const listCheckRuns = api.listCheckRuns;
  let error = Object.assign(new Error("GET check-runs returned 502"), { status: 502 });
  api.listCheckRuns = async (query) => {
    if (query.sha === pr(4).headRefOid) {
      throw error;
    }
    return listCheckRuns(query);
  };
  const lines = [];
  const skipped = await run(api, { log: (line) => lines.push(line) });
  assert.deepEqual(skipped, { dispatched: [{ number: 5, workflowRunId: "7005" }], failed: 0 });
  assert.ok(lines.some((line) => line.startsWith("::warning::#4:") && line.includes("502")));
  for (const other of [
    Object.assign(new Error("GET check-runs returned 403"), { status: 403, rateLimited: true }),
    Object.assign(new Error("GET check-runs returned 404"), { status: 404 }),
  ]) {
    error = other;
    lines.length = 0;
    assert.equal((await run(api, { log: (line) => lines.push(line) })).failed, 0, other.message);
    assert.ok(lines.some((line) => line.startsWith("::warning::#4:") && line.includes(other.message)), other.message);
  }
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

test("a red CI Status makes a patch bump review, and a green ci-status alias beside it is not read", async () => {
  const node = pr(8, { title: "bump x from 1.0.0 to 1.0.1" });
  const api = fakeApi({
    nodes: [node],
    checks: new Map([[node.headRefOid, [{ id: 1, name: "CI Status", app: { slug: "github-actions" }, status: "completed", conclusion: "failure" }]]]),
    ci: new Map([[node.headRefOid, [{ id: 2, app: { slug: "github-actions" }, status: "completed", conclusion: "success" }]]]),
  });
  assert.equal((await run(api)).dispatched.length, 1);
  assert.deepEqual(api.calls.checks.slice(0, 1).map((call) => call.checkName), ["CI Status"]);
  assert.equal(api.calls.checks.some((call) => call.checkName === "ci-status"), false);
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

test("a PR whose review-dependency run is not done yet is not sent again, and the slot goes to the next PR", async () => {
  const runs = [
    { id: 901, status: "in_progress", display_title: "PR Unblock review-dependency #21" },
    { id: 902, status: "queued", display_title: "PR Unblock resolve-conflicts #22" },
    { id: 903, status: "completed", display_title: "PR Unblock review-dependency #22" },
  ];
  const api = fakeApi({ nodes: [pr(21), pr(22), pr(23)], runs });
  const lines = [];
  const { dispatched, failed } = await run(api, { maxDispatch: 1, log: (line) => lines.push(line) });
  assert.equal(failed, 0);
  assert.deepEqual(dispatched.map((d) => d.number), [22]);
  assert.ok(lines.includes("skip #21: pr-unblock.yml run 901 for review-dependency is not done yet"));
  assert.ok(lines.includes("defer #23: 1 review dispatches this run; left for a later run unread"));
  assert.equal(api.calls.runs, 1);
});

test("the run listing is read only for a PR about to be sent", async () => {
  const node = pr(10);
  const reviewed = { status: "completed", conclusion: "success", started_at: "2026-10-17T10:00:00Z", output: { title: "Reviewed" } };
  const api = fakeApi({ nodes: [node], checks: new Map([[node.headRefOid, [reviewed]]]) });
  assert.deepEqual((await run(api)).dispatched, []);
  assert.equal(api.calls.runs, 0);
});

test("a run listing that cannot be read holds the PR with a warning and fails nothing", async () => {
  const api = fakeApi({ nodes: [pr(4)] });
  api.listWorkflowRuns = async () => {
    throw Object.assign(new Error("GET runs returned 403"), { status: 403, rateLimited: true });
  };
  const lines = [];
  assert.deepEqual(await run(api, { log: (line) => lines.push(line) }), { dispatched: [], failed: 0 });
  assert.ok(lines.includes("::warning::#4: pr-unblock.yml run listing is rate limited (GET runs returned 403); skipped, a later run retries"));
});

test("dispatches at most the cap, lowest number first", async () => {
  const api = fakeApi({ nodes: [pr(23), pr(21), pr(22)] });
  const { dispatched } = await run(api, { maxDispatch: 2 });
  assert.deepEqual(dispatched.map((d) => d.number), [21, 22]);
});

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
const ciStatusRun = (conclusion, at, id = 1) => ({
  id,
  name: "CI Status",
  app: { slug: "github-actions" },
  status: conclusion ? "completed" : "in_progress",
  conclusion,
  started_at: at,
  completed_at: conclusion ? at : null,
});

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

test("a head the kill switch stopped dispatches again, and is not recorded as handled", async () => {
  for (const [label, checks] of [
    ["the verdict job's mint was refused", [roundRun("review-dependency", "success", "Passed", "2026-10-17T10:00:00Z"), roundRun("apply-dependency-verdict", "neutral", "Skipped: kill-switch", "2026-10-17T10:05:00Z")]],
    ["the review run's own kill step stopped it", [roundRun("review-dependency", "neutral", "Skipped: kill-switch", "2026-10-17T10:00:00Z")]],
  ]) {
    const node = pr(60);
    const record = emptyRecord();
    const { dispatched } = await run(fakeApi({ nodes: [node], checks: headOf(node, checks) }), { record });
    assert.deepEqual(dispatched, [{ number: 60, workflowRunId: "7060" }], label);
    assert.equal(record.handled.get(CHECK), undefined, label);
  }
});

const lagged = (started) => roundRun("review-dependency", "neutral", "Skipped: superseded-sha", started);

test("a review the gate stopped head-lag on the current head is sent again once, under the cap, and not recorded", async () => {
  const node = pr(62);
  const record = emptyRecord();
  const lines = [];
  const once = await run(fakeApi({ nodes: [node], checks: headOf(node, [lagged("2026-10-17T10:00:00Z")]) }), { record, log: (line) => lines.push(line) });
  assert.deepEqual(once.dispatched, [{ number: 62, workflowRunId: "7062" }]);
  assert.equal(record.handled.get(CHECK), undefined);
  assert.ok(lines.includes(`refire: #62: head ${node.headRefOid}'s ${CHECK} was stopped head-lag; sending it again`), lines.join("\n"));
  for (const [label, checks] of [
    ["a newer review passed", [lagged("2026-10-17T10:00:00Z"), roundRun("review-dependency", "success", "Passed", "2026-10-17T10:30:00Z")]],
    ["a newer review is still going", [lagged("2026-10-17T10:00:00Z"), { ...roundRun("review-dependency", null, "", "2026-10-17T10:30:00Z"), status: "in_progress" }]],
    ["the head is at the cap", [lagged("2026-10-17T10:00:00Z"), lagged("2026-10-17T10:30:00Z"), lagged("2026-10-17T11:00:00Z")]],
  ]) {
    const { dispatched } = await run(fakeApi({ nodes: [node], checks: headOf(node, checks) }));
    assert.deepEqual(dispatched, [], label);
  }
});

const limitStop = (started) => {
  const resets = new Date(Date.parse(started) + 3_600_000).toISOString().replace(".000", "");
  return {
    ...roundRun("review-dependency", "failure", "Failed", started),
    output: {
      title: "Failed",
      text: `lane-outcome ${JSON.stringify({ v: 1, lane: "pr-unblock", activity: "review-dependency", outcome: "failure", class: "rate-limit", credential: { secret: "CLAUDE_CODE_OAUTH_TOKEN", kind: "oauth-token" }, resets: { at: resets, window: "five_hour" } })}`,
    },
  };
};

test("a no-model-turn verdict after a limit stop still holds the head until the reset", async () => {
  const node = pr(61);
  const checks = headOf(node, [limitStop("2026-10-17T10:00:00Z"), noModelTurn()]);
  const { dispatched } = await run(fakeApi({ nodes: [node], checks }), { now: Date.parse("2026-10-17T10:30:00Z") });
  assert.deepEqual(dispatched, []);
});

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

test("three limit stops under a cap of 5 leave the head unrecorded and dispatched after the last reset", async () => {
  const node = pr(71);
  const runs = [limitStop("2026-10-17T07:00:00Z"), limitStop("2026-10-17T08:00:00Z"), limitStop("2026-10-17T09:30:00Z"), noModelTurn("2026-10-17T09:35:00Z")];
  const limits = { ...LIMIT_DEFAULTS, "limit-stops-per-head": 5 };
  const record = emptyRecord();
  const before = await run(fakeApi({ nodes: [node], checks: headOf(node, runs) }), { record, limits, now: Date.parse("2026-10-17T10:00:00Z") });
  assert.deepEqual(before.dispatched, [], "held before the newest stop's reset");
  assert.equal(record.handled.get(CHECK), undefined, "a limit stop is not recorded");
  const after = await run(fakeApi({ nodes: [node], checks: headOf(node, runs) }), { record, limits, now: Date.parse("2026-10-17T11:00:00Z") });
  assert.deepEqual(after.dispatched, [{ number: 71, workflowRunId: "7071" }], "3 stops of a cap of 5");
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

const laneStopped = (started) => roundRun("apply-dependency-verdict", "neutral", "Skipped: lane-stopped", started);
test("a head whose last verdict was a lane stop dispatches again under the per-head cap, and not at it", async () => {
  const limits = { ...LIMIT_DEFAULTS, "limit-stops-per-head": 2 };
  const node = pr(64);
  const first = [roundRun("review-dependency", "success", "Passed", "2026-10-17T10:00:00Z"), laneStopped("2026-10-17T10:05:00Z")];
  const record = emptyRecord();
  const under = await run(fakeApi({ nodes: [node], checks: headOf(node, first) }), { record, limits });
  assert.deepEqual(under.dispatched, [{ number: 64, workflowRunId: "7064" }], "1 stop of a cap of 2");
  assert.equal(record.handled.get(CHECK), undefined, "a released head is not recorded");

  const atCap = [...first, roundRun("review-dependency", "success", "Passed", "2026-10-17T11:00:00Z"), laneStopped("2026-10-17T11:05:00Z")];
  const lines = [];
  const capRecord = emptyRecord();
  const api = fakeApi({ nodes: [node], checks: headOf(node, atCap) });
  assert.deepEqual((await run(api, { record: capRecord, limits, log: (line) => lines.push(line) })).dispatched, [], "2 stops of a cap of 2");
  assert.deepEqual(api.calls.dispatch, []);
  assert.ok(lines.some((line) => line.startsWith("::warning::#64:") && line.includes("stopped 2 time(s)")), "the cap is named");
  assert.ok(capRecord.handled.get(CHECK)?.has(node.headRefOid), "a capped head is recorded");
});

test("a head whose newest review-dependency check has no later verdict check is not recorded, and is released once the verdict skips no-model-turn", async () => {
  const node = pr(63);
  const record = emptyRecord();
  const check = roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z");
  assert.deepEqual((await run(fakeApi({ nodes: [node], checks: headOf(node, [check]) }), { record })).dispatched, [], "the head is handled for now");
  assert.equal(record.handled.get(CHECK), undefined, "but not recorded");
  await run(fakeApi({ nodes: [node], checks: headOf(node, [noModelTurn("2026-10-17T09:05:00Z"), check]) }), { record });
  assert.equal(record.handled.get(CHECK), undefined);
  const later = await run(fakeApi({ nodes: [node], checks: headOf(node, [check, noModelTurn()]) }), { record });
  assert.deepEqual(later.dispatched, [{ number: 63, workflowRunId: "7063" }]);
});

test("a head whose newest review-dependency check is a select skip is recorded, and a read runner skip is not", async () => {
  for (const [label, runs] of [
    ["the round cap after a no-model-turn round", [roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z"), noModelTurn(), roundRun("review-dependency", "neutral", "Skipped: awaiting-human", "2026-10-17T11:00:00Z")]],
    ["the round cap alone", [roundRun("review-dependency", "neutral", "Skipped: awaiting-human", "2026-10-17T11:00:00Z")]],
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

const CAPTURED_RUN = "45325911125";
const CAPTURED_JOBS = JSON.parse(readFileSync(new URL("./fixtures/jobs-45325911125-attempt-1.json", import.meta.url), "utf8")).jobs;
const capturedRun = (jobs = CAPTURED_JOBS) => ({ [CAPTURED_RUN]: jobs });
const shifted = (jobs, minutes, attempt) =>
  jobs.map((job) => ({ ...job, run_attempt: attempt ?? job.run_attempt, started_at: new Date(Date.parse(job.started_at) + minutes * 60_000).toISOString().replace(".000", "") }));
const notApplicable = (posted) => ({
  ...roundRun("review-dependency", "neutral", "Skipped: not-applicable", posted),
  external_id: `pr-unblock:review-dependency:${CAPTURED_RUN}:1`,
});

test("a not-applicable skip holds its head unrecorded while CI Status runs, and the gate ending red sends the head", async () => {
  const node = pr(73);
  const skip = notApplicable("2026-11-24T04:24:53Z");
  const jobs = capturedRun();
  const record = emptyRecord();
  const running = await run(fakeApi({ nodes: [node], checks: headOf(node, [ciStatusRun(null, "2026-11-24T04:23:07Z", 2), skip]), jobs }), { record });
  assert.deepEqual(running.dispatched, [], "the skip holds the head while the gate runs");
  assert.equal(record.handled.get(CHECK), undefined, "not recorded, so the next run reads the head again");
  const ended = await run(fakeApi({ nodes: [node], checks: headOf(node, [ciStatusRun("failure", "2026-11-24T04:30:55Z", 2), skip]), jobs }), { record });
  assert.deepEqual(ended.dispatched, [{ number: 73, workflowRunId: "7073" }], "the red gate sends the round that moves the pin");
});

test("a skip posted after the gate ended red is released when its own attempt started before the gate ended", async () => {
  const node = pr(75);
  const checks = headOf(node, [ciStatusRun("failure", "2026-11-24T04:24:00Z", 2), notApplicable("2026-11-24T04:24:53Z")]);
  const raced = await run(fakeApi({ nodes: [node], checks, jobs: capturedRun() }));
  assert.deepEqual(raced.dispatched, [{ number: 75, workflowRunId: "7075" }], "select read the gate before it ended red");
  const otherAttempt = await run(fakeApi({ nodes: [node], checks, jobs: capturedRun([...shifted(CAPTURED_JOBS, 2), ...shifted(CAPTURED_JOBS, 0, 2)]) }));
  assert.deepEqual(otherAttempt.dispatched, [], "an earlier job of another attempt does not stand for the skip's run");
});

test("a skip whose run started after the gate ended red holds the head unrecorded, and a red re-run of the gate on the same head sends it", async () => {
  const node = pr(76);
  const skip = notApplicable("2026-11-24T04:32:00Z");
  const jobs = capturedRun(shifted(CAPTURED_JOBS, 9));
  const record = emptyRecord();
  const held = await run(fakeApi({ nodes: [node], checks: headOf(node, [ciStatusRun("failure", "2026-11-24T04:30:55Z", 2), skip]), jobs }), { record });
  assert.deepEqual(held.dispatched, [], "the skip sorted the finished gate");
  assert.equal(record.handled.get(CHECK), undefined, "and is left out of the record");
  const gates = [ciStatusRun("failure", "2026-11-24T04:30:55Z", 2), ciStatusRun("failure", "2026-11-24T04:40:00Z", 3)];
  const rerun = await run(fakeApi({ nodes: [node], checks: headOf(node, [...gates, skip]), jobs }), { record });
  assert.deepEqual(rerun.dispatched, [{ number: 76, workflowRunId: "7076" }]);
});

test("a gate that ends green does not release a not-applicable skip taken while it ran", async () => {
  const node = pr(77);
  const checks = headOf(node, [ciStatusRun("success", "2026-11-24T04:30:55Z", 2), notApplicable("2026-11-24T04:24:53Z")]);
  assert.deepEqual((await run(fakeApi({ nodes: [node], checks, jobs: capturedRun() }))).dispatched, []);
});

const VERSION_7_WRITER_OUTPUT = '{"version":7,"handled":{"pr-unblock / review-dependency":["cccccccccccccccccccccccccccccccccccccc74"]},"bases":{},"dispatched":{},"docsRuns":{}}\n';

test("a version 7 record that holds a head a not-applicable skip left is read as empty, and the version 8 writer's record reads back", async () => {
  const node = pr(74);
  const record = parseRecord(VERSION_7_WRITER_OUTPUT);
  assert.equal(record.handled.get(CHECK), undefined, "read as empty");
  const checks = headOf(node, [ciStatusRun("failure", "2026-11-24T04:30:55Z", 2), notApplicable("2026-11-24T04:24:53Z")]);
  assert.deepEqual((await run(fakeApi({ nodes: [node], checks, jobs: capturedRun() }), { record })).dispatched, [{ number: 74, workflowRunId: "7074" }]);
  markHandled(record, CHECK, node.headRefOid);
  const text = serializeRecord(record);
  assert.equal(JSON.parse(text).version, 8);
  assert.deepEqual([...parseRecord(text).handled.get(CHECK)], [node.headRefOid]);
});

test("a version 1 record that holds a no-model-turn head is ignored, and the head dispatches again", async () => {
  const node = pr(66);
  const record = parseRecord(JSON.stringify({ version: 1, handled: { [CHECK]: [node.headRefOid] }, dispatched: {} }));
  const checks = headOf(node, [roundRun("review-dependency", "failure", "Failed", "2026-10-17T10:00:00Z"), noModelTurn()]);
  assert.deepEqual((await run(fakeApi({ nodes: [node], checks }), { record })).dispatched, [{ number: 66, workflowRunId: "7066" }]);
});

test("a version 2 record that holds a limit-stopped head is ignored, and the head dispatches after the reset", async () => {
  const node = pr(67);
  const record = parseRecord(JSON.stringify({ version: 2, handled: { [CHECK]: [node.headRefOid] }, dispatched: {} }));
  assert.equal(record.handled.get(CHECK), undefined, "read as empty");
  const checks = headOf(node, [limitStop("2026-10-17T10:00:00Z"), noModelTurn()]);
  const { dispatched } = await run(fakeApi({ nodes: [node], checks }), { record, now: Date.parse("2026-10-17T12:00:00Z") });
  assert.deepEqual(dispatched, [{ number: 67, workflowRunId: "7067" }]);
});

test("a version 5 record that holds a head-lag-stopped head is ignored, and the head dispatches again", async () => {
  const node = pr(68);
  const record = parseRecord(JSON.stringify({ version: 5, handled: { [CHECK]: [node.headRefOid] }, dispatched: {} }));
  assert.equal(record.handled.get(CHECK), undefined, "read as empty");
  const checks = headOf(node, [roundRun("review-dependency", "neutral", "Skipped: superseded-sha", "2026-10-17T10:00:00Z")]);
  assert.deepEqual((await run(fakeApi({ nodes: [node], checks }), { record })).dispatched, [{ number: 68, workflowRunId: "7068" }]);
});

const RED_CI = [{ id: 1, app: { slug: "github-actions" }, status: "completed", conclusion: "failure" }];

test("a gate-hold skip holds the head while CI Status is red, unrecorded, and dispatches again once CI Status passes on it", async () => {
  const node = pr(70);
  const gateHeld = roundRun("review-dependency", "neutral", "Skipped: gate-hold", "2026-10-17T10:00:00Z");
  const record = emptyRecord();
  for (const tick of [1, 2]) {
    const held = await run(fakeApi({ nodes: [node], checks: headOf(node, [gateHeld]), ci: new Map([[node.headRefOid, RED_CI]]) }), { record });
    assert.deepEqual(held.dispatched, [], `tick ${tick}: no dispatch while the trust-gate hold stands`);
    assert.equal(record.handled.get(CHECK), undefined, `tick ${tick}: not recorded, so a later sweep reads it again`);
  }
  const green = [{ id: 2, app: { slug: "github-actions" }, status: "completed", conclusion: "success" }];
  const approved = await run(fakeApi({ nodes: [node], checks: headOf(node, [gateHeld]), ci: new Map([[node.headRefOid, green]]) }), { record });
  assert.deepEqual(approved.dispatched, [{ number: 70, workflowRunId: "7070" }]);
});

test("an awaiting-human skip with a green CI Status still holds the head", async () => {
  const node = pr(71);
  const green = [{ id: 2, app: { slug: "github-actions" }, status: "completed", conclusion: "success" }];
  const held = roundRun("review-dependency", "neutral", "Skipped: awaiting-human", "2026-10-17T10:00:00Z");
  assert.deepEqual((await run(fakeApi({ nodes: [node], checks: headOf(node, [held]), ci: new Map([[node.headRefOid, green]]) }))).dispatched, []);
});

test("a red ci-status is review without reading the commits or files", async () => {
  const node = pr(8, { title: "bump x from 1.0.0 to 1.0.1" });
  const api = fakeApi({ nodes: [node], ci: new Map([[node.headRefOid, RED_CI]]) });
  assert.deepEqual((await run(api)).dispatched, [{ number: 8, workflowRunId: "7008" }]);
  assert.deepEqual(api.calls.commits, []);
  assert.deepEqual(api.calls.files, []);
});

test("once the cap is reached the rest are left unread", async () => {
  const api = fakeApi({ nodes: [pr(24), pr(23), pr(21), pr(22)] });
  const lines = [];
  const { dispatched } = await run(api, { maxDispatch: 2, log: (line) => lines.push(line) });
  assert.deepEqual(dispatched.map((d) => d.number), [21, 22]);
  assert.equal(api.calls.checks.length, 6);
  assert.deepEqual(api.calls.commits, [21, 22]);
  assert.ok(lines.includes("defer #23: 2 review dispatches this run; left for a later run unread"));
});

test("a reviewed head is recorded, and the next run reads nothing for it", async () => {
  const node = pr(10);
  const reviewed = { status: "completed", conclusion: "success", started_at: "2026-10-17T10:00:00Z", output: { title: "Reviewed" } };
  const checks = new Map([[node.headRefOid, [reviewed, roundRun("apply-dependency-verdict", "success", "Passed", "2026-10-17T10:05:00Z")]]]);
  const record = emptyRecord();
  const first = fakeApi({ nodes: [node], checks });
  assert.deepEqual((await run(first, { record })).dispatched, []);
  assert.equal(first.calls.checks.length, 4);
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

const LANE_APP = 337595936;
const gateRed = (number) =>
  pr(number, {
    commits: {
      totalCount: 1,
      nodes: [{ commit: { statusCheckRollup: { contexts: { nodes: [{ __typename: "CheckRun", name: "CI Status", conclusion: "FAILURE", checkSuite: { app: { databaseId: 15368 } } }] } } } }],
    },
  });
const gateRun = { id: 901, name: "CI Status", app: { slug: "github-actions" }, status: "completed", conclusion: "failure", started_at: "2026-11-23T10:00:00Z", details_url: "https://github.com/o/r/actions/runs/600/job/901" };
const EXIT_NOTE = { annotation_level: "failure", message: "Process completed with exit code 1." };
const verdictHold = (number) => ({
  annotation_level: "failure",
  message: `#${number} by Dependabot swaps only action refs, each to a tagged commit, on trust-gate paths: .github/workflows/ci.yml, and merge.dependabot.trusted-action-owners does not list the owner of: evilcorp/setup-tool. The lanes App's review-dependency verdict=merge at this head clears it, as does a person on the trusted-actor list approving this head.`,
});
const personHold = (number) => ({
  annotation_level: "failure",
  message: `#${number} is by an author no review lane reviews and changes trust-gate paths: CODEOWNERS. A person merges it; a person on the trusted-actor list approving this head clears it.`,
});
const roundComment = (head, verdict, createdAt, author = LANE_APP) => ({
  id: 5,
  created_at: createdAt,
  user: { id: author },
  body: `<!-- pr-unblock:review-dependency-round head=${head} verdict=${verdict} run=12-1 -->\nThe pr-unblock lane reviewed this Dependabot pull request.`,
});
const GATE_JOBS = { 600: [{ id: 901, check_run_url: "https://api.github.com/repos/o/r/check-runs/901" }] };
const reviewedHead = (node) => headOf(node, [gateRun, { status: "completed", conclusion: "success", started_at: "2026-11-23T09:00:00Z", output: { title: "Reviewed" } }]);

test("a CI Status held only for a merge verdict the lanes App posted after it started is re-run once, even on a recorded head", async () => {
  const node = gateRed(80);
  const record = emptyRecord();
  markHandled(record, CHECK, node.headRefOid);
  const api = fakeApi({
    nodes: [node],
    checks: reviewedHead(node),
    annotations: { 901: [EXIT_NOTE, verdictHold(80)] },
    comments: new Map([[80, [roundComment(node.headRefOid, "merge", "2026-11-23T10:02:00Z")]]]),
    jobs: GATE_JOBS,
  });
  const lines = [];
  const result = await run(api, { record, laneAppId: LANE_APP, log: (line) => lines.push(line) });
  assert.deepEqual(api.calls.reruns, [901]);
  assert.deepEqual(result.dispatched, [], "a re-run sends no review");
  assert.ok(lines.some((line) => line.startsWith("rerun: #80:") && line.includes("job 901")), lines.join("\n"));
});

test("CI Status is not re-run without a merge verdict at the head that is newer than it, a hold the verdict clears, or a lanes App id", async () => {
  const head = gateRed(81).headRefOid;
  const cases = [
    ["the marker predates CI Status", [EXIT_NOTE, verdictHold(81)], [roundComment(head, "merge", "2026-11-23T09:59:00Z")], LANE_APP],
    ["the marker names an older head", [EXIT_NOTE, verdictHold(81)], [roundComment("e".repeat(40), "merge", "2026-11-23T10:02:00Z")], LANE_APP],
    ["the newest marker is not merge", [EXIT_NOTE, verdictHold(81)], [roundComment(head, "merge", "2026-11-23T10:01:00Z"), roundComment(head, "fix", "2026-11-23T10:02:00Z")], LANE_APP],
    ["the marker is another author's", [EXIT_NOTE, verdictHold(81)], [roundComment(head, "merge", "2026-11-23T10:02:00Z", 777)], LANE_APP],
    ["only a person clears the hold", [EXIT_NOTE, personHold(81)], [roundComment(head, "merge", "2026-11-23T10:02:00Z")], LANE_APP],
    ["CI Status fails for something else too", [EXIT_NOTE, verdictHold(81), { annotation_level: "failure", message: "lint failed" }], [roundComment(head, "merge", "2026-11-23T10:02:00Z")], LANE_APP],
    ["no lanes App id", [EXIT_NOTE, verdictHold(81)], [roundComment(head, "merge", "2026-11-23T10:02:00Z")], undefined],
  ];
  for (const [label, notes, comments, laneAppId] of cases) {
    const node = gateRed(81);
    const record = emptyRecord();
    markHandled(record, CHECK, node.headRefOid);
    const api = fakeApi({ nodes: [node], checks: reviewedHead(node), annotations: { 901: notes }, comments: new Map([[81, comments]]), jobs: GATE_JOBS });
    await run(api, { record, laneAppId });
    assert.deepEqual(api.calls.reruns, [], label);
  }
});

test("a head whose rollup shows no failed CI Status reads nothing for a re-run", async () => {
  const node = pr(82);
  const record = emptyRecord();
  markHandled(record, CHECK, node.headRefOid);
  const api = fakeApi({ nodes: [node], checks: reviewedHead(node), comments: new Map([[82, [roundComment(node.headRefOid, "merge", "2026-11-23T10:02:00Z")]]]) });
  await run(api, { record, laneAppId: LANE_APP });
  assert.deepEqual([api.calls.checks, api.calls.comments, api.calls.reruns], [[], [], []]);
});

test("a CI Status check run whose job its run does not list warns and re-runs nothing", async () => {
  const node = gateRed(83);
  const record = emptyRecord();
  markHandled(record, CHECK, node.headRefOid);
  const api = fakeApi({
    nodes: [node],
    checks: reviewedHead(node),
    annotations: { 901: [EXIT_NOTE, verdictHold(83)] },
    comments: new Map([[83, [roundComment(node.headRefOid, "merge", "2026-11-23T10:02:00Z")]]]),
    jobs: { 600: [{ id: 901, check_run_url: "https://api.github.com/repos/o/r/check-runs/902" }] },
  });
  const lines = [];
  await run(api, { record, laneAppId: LANE_APP, log: (line) => lines.push(line) });
  assert.deepEqual(api.calls.reruns, []);
  assert.ok(lines.some((line) => line.startsWith("::warning::#83: could not re-run CI Status") && line.includes("names no job")), lines.join("\n"));
});
