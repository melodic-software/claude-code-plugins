import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { createGitHubApi } from "./dispatch.mjs";
import { failingChecks } from "./gate-source.mjs";
import { emptyRecord, isHandled } from "./dispatch-record.mjs";
import { RERUN_DUE_MINUTES } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { DEFAULTS, dispatchCiFixes, humanGatedLabel, LIST_QUERY, skipReason, staleStop } from "./fix-ci-dispatch.mjs";

// The lanes App bot's user id and the GitHub Actions app id
// (.github/standards/trusted-actors/trusted-actors.json; dispatch.mjs).
const APP = 337595936;
const ACTIONS = 15368;

// pr-require-checks run 39710654665's latest jobs (recorded, trimmed): two
// time-limit cancels and a real lint-shell failure. Without lint-shell its
// failures are infra only.
const MIXED_JOBS = JSON.parse(readFileSync(new URL("../maintenance-reconcile-lost-runs/fixtures/jobs-39710654665.json", import.meta.url), "utf8")).jobs;
const INFRA_JOBS = MIXED_JOBS.filter((job) => job.name !== "lint-shell");

// A tested pr-require-checks run that failed, an hour before NOW unless named.
const NOW = Date.parse("2026-10-22T12:00:00Z");
const REQUIRED = ".github/workflows/pr-require-checks.yml";
const ADVISORY = ".github/workflows/pr-test-platforms.yml";
const tested = (attempt, hoursAgo = 1) => ({
  id: 40119285048,
  status: "completed",
  conclusion: "failure",
  run_attempt: attempt,
  created_at: new Date(NOW - hoursAgo * 3_600_000).toISOString(),
  updated_at: new Date(NOW - hoursAgo * 3_600_000).toISOString(),
});
// A tested run whose re-run is queued or going: the same run id at its next attempt.
const rerunning = (attempt, status) => ({ ...tested(attempt), status, conclusion: null });

const check = (name, conclusion, extra = {}) => ({
  __typename: "CheckRun",
  name,
  status: conclusion ? "COMPLETED" : "IN_PROGRESS",
  conclusion,
  title: null,
  checkSuite: { app: { databaseId: ACTIONS } },
  ...extra,
});

// A rollup check run as the REST check-runs listing returns it.
const toRest = (run) => ({
  name: run.name,
  status: run.status.toLowerCase(),
  conclusion: run.conclusion?.toLowerCase() ?? null,
  output: { title: run.title ?? null },
  completed_at: run.completedAt ?? null,
});

// The head's ci-lanes commit status as the GraphQL rollup returns it: the
// creator recorded live from a pull request's ci-lanes status, which GraphQL
// reports as login `github-actions`, not REST's `github-actions[bot]`.
const ACTIONS_BOT = Object.freeze({ __typename: "Bot", login: "github-actions", databaseId: 41898282 });
const lanes = (state, creator = ACTIONS_BOT) => ({ __typename: "StatusContext", context: "ci-lanes", state, creator });

// A lanes App PR whose head's lanes failed and has no fix-ci run yet.
function pr(number, { checks = [lanes("FAILURE")], ...overrides } = {}) {
  const head = String(number).padStart(40, "a");
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { login: "melodic-automation-lanes", databaseId: APP },
    labels: { nodes: [] },
    commits: { nodes: [{ commit: { oid: head, statusCheckRollup: { contexts: { nodes: checks } } } }] },
    ...overrides,
  };
}

function fakeApi({
  pages = [[]],
  cost = 1,
  workflowRuns = [],
  failDispatch = new Set(),
  runIds = new Map(),
  requiredRuns = new Map(),
  baseCommittedAt,
  comments = new Map(),
  labelEvents = new Map(),
  reviewComments = new Map(),
  history = new Map(),
  stops = new Map(),
  annotations = new Map(),
  commitRuns = new Map(),
} = {}) {
  const calls = { list: 0, runs: 0, dispatch: [], jobs: [], paths: [], timeline: [], history: [], stops: [], annotations: [], commit: [] };
  return {
    calls,
    // One check run's annotations, by its id; none unless the test names it.
    async listAnnotations(id) {
      calls.annotations.push(id);
      const rows = annotations.get(id);
      if (rows instanceof Error) {
        throw rows;
      }
      return rows ?? [];
    },
    // Every check run on the head over REST: the test's rows for the head,
    // else the rollup's runs in REST's shape, ids in rollup order.
    async listCommitCheckRuns(sha) {
      calls.commit.push(sha);
      const rows = commitRuns.get(sha);
      if (rows instanceof Error) {
        throw rows;
      }
      if (rows) {
        return rows;
      }
      const node = pages.flat().find((pull) => pull.headRefOid === sha);
      return (node?.commits.nodes[0].commit.statusCheckRollup.contexts.nodes ?? [])
        .filter((run) => run.__typename === "CheckRun")
        .map((run, index) => ({ id: index + 1, ...toRest(run) }));
    },
    // The head's check runs of one name and app over REST, every one of them:
    // the test's history for the head, else the rollup's runs in REST's shape.
    async listCheckRuns({ sha, checkName, appId }) {
      // The push job's checks: `stops` for the head.
      if (checkName === "pr-unblock / apply-patch") {
        calls.stops.push(sha);
        return stops.get(sha) ?? [];
      }
      calls.history.push(sha);
      const rows = history.get(sha);
      if (rows instanceof Error) {
        throw rows;
      }
      if (rows) {
        return rows;
      }
      const node = pages.flat().find((pull) => pull.headRefOid === sha);
      return (node?.commits.nodes[0].commit.statusCheckRollup.contexts.nodes ?? [])
        .filter((run) => run.__typename === "CheckRun" && run.name === checkName && run.checkSuite?.app?.databaseId === appId)
        .map(toRest);
    },
    // The REST issue timeline: its comments, then its label events.
    async listTimeline(number) {
      calls.timeline.push(number);
      return [...(comments.get(number) ?? []).map((comment) => ({ event: "commented", ...comment })), ...(labelEvents.get(number) ?? [])];
    },
    // The REST review comments and reviews, with an inline reply's in_reply_to_id.
    async listReviewComments(number) {
      return reviewComments.get(number) ?? [];
    },
    async listReviews() {
      return [];
    },
    // The head's tested run of the workflow at path and its latest jobs; a
    // real failure at attempt 2 (its one re-run spent) unless the test names
    // the head, or the head and path.
    async readRequiredRun(sha, path = REQUIRED) {
      calls.jobs.push(sha);
      calls.paths.push(path);
      const required = requiredRuns.get(`${sha} ${path}`) ?? requiredRuns.get(sha) ?? { run: tested(2), jobs: MIXED_JOBS };
      if (required instanceof Error) {
        throw required;
      }
      return required;
    },
    async listCiFixCandidates({ after }) {
      calls.list += 1;
      const index = after === undefined ? 0 : Number(after);
      return {
        rateLimit: { cost, remaining: 4990 },
        pullRequests: { nodes: pages[index], pageInfo: { hasNextPage: index + 1 < pages.length, endCursor: String(index + 1) } },
        baseCommittedAt,
      };
    },
    async listWorkflowRuns() {
      calls.runs += 1;
      if (workflowRuns instanceof Error) {
        throw workflowRuns;
      }
      return workflowRuns;
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      calls.dispatch.push({ workflow, ref, inputs });
      if (failDispatch.has(inputs["pr-number"])) {
        throw new Error("dispatch failed");
      }
      return { workflowRunId: runIds.has(inputs["pr-number"]) ? runIds.get(inputs["pr-number"]) : 7000 + Number(inputs["pr-number"]) };
    },
  };
}

async function run(apiOptions, options = {}) {
  const api = fakeApi(apiOptions);
  const lines = [];
  const result = await dispatchCiFixes({
    api,
    runId: "4242",
    log: (line) => lines.push(line),
    appSenderId: APP,
    maxDispatch: 2,
    restarts: 1,
    now: NOW,
    ...options,
  });
  return { api, lines, result };
}

test("a lanes App PR whose ci-status failed is dispatched fix-ci with the dispatcher's run id", async () => {
  const { api, result } = await run({ pages: [[pr(5)]] });
  assert.deepEqual(result, { dispatched: [{ number: 5, workflowRunId: "7005" }], failed: 0 });
  assert.deepEqual(api.calls.dispatch, [
    {
      workflow: "pr-unblock.yml",
      ref: "refs/heads/main",
      inputs: { "pr-number": "5", activity: "fix-ci", "dispatcher-run-id": "4242" },
    },
  ]);
});

// Owner decision 2026-10-29: a PR whose pr-verify FAILs are at the cap gets
// no fix-ci round, read by the gate's reader (verify-cap.mjs); the next
// candidate still does.
test("a PR whose pr-verify FAILs are at the cap gets no fix-ci round", async () => {
  const asked = [];
  const verifyCapped = (request) => {
    asked.push(request);
    return request.number === 5 ? "verify:repeated-fail: fails at 3 heads, the cap is 3" : null;
  };
  const base = "c".repeat(40);
  const { api, lines, result } = await run({ pages: [[pr(5, { baseRefOid: base }), pr(6, { baseRefOid: base })]] }, { verifyCapped });
  assert.deepEqual(result, { dispatched: [{ number: 6, workflowRunId: "7006" }], failed: 0 });
  assert.deepEqual(
    api.calls.dispatch.map((call) => call.inputs["pr-number"]),
    ["6"],
  );
  assert.deepEqual(asked, [
    { number: 5, head: pr(5).headRefOid, base },
    { number: 6, head: pr(6).headRefOid, base },
  ]);
  assert.match(lines.join("\n"), /^skip fix-ci #5: .*verify:repeated-fail/m);
});

test("a capped head is recorded, so the next run skips it without reading the verifier again", async () => {
  const record = emptyRecord();
  let reads = 0;
  const verifyCapped = () => {
    reads += 1;
    return "verify:repeated-fail";
  };
  await run({ pages: [[pr(5)]] }, { verifyCapped, record });
  const { api } = await run({ pages: [[pr(5)]] }, { verifyCapped, record });
  assert.equal(reads, 1);
  assert.deepEqual(api.calls.dispatch, []);
});

test("a head whose sibling FAIL run cannot be read is skipped but not recorded", async () => {
  const record = emptyRecord();
  let reads = 0;
  const verifyCapped = () => {
    reads += 1;
    return "verify:unreadable: a FAIL run of a pull request for the same issue";
  };
  await run({ pages: [[pr(5)]] }, { verifyCapped, record });
  const { api } = await run({ pages: [[pr(5)]] }, { verifyCapped, record });
  assert.equal(reads, 2);
  assert.deepEqual(api.calls.dispatch, []);
});

// A listing that does not fit in verify-cap's limit (babysit_verify_evidence.py
// DEADLINE_UNREADABLE) recurs every run while pr-merge's carried listing is
// missing or stale, so its skip is a warning annotation, not a plain line.
test("a head skipped because the listing did not fit warns with the reader's detail; a sibling skip does not", async () => {
  const deadline = "verify:unreadable: the artifact listing does not fit in the caller's limit: repository artifacts: 10450 artifacts in 105 pages need 112 s";
  const { api, lines } = await run({ pages: [[pr(5)]] }, { verifyCapped: () => deadline });
  assert.deepEqual(api.calls.dispatch, []);
  assert.deepEqual(
    lines.filter((line) => line.startsWith("::warning title=verify-deadline-skip::")),
    [`::warning title=verify-deadline-skip::#5: ${deadline}`],
  );
  const sibling = await run({ pages: [[pr(5)]] }, { verifyCapped: () => "verify:unreadable: a FAIL run of a pull request for the same issue" });
  assert.deepEqual(sibling.api.calls.dispatch, []);
  assert.ok(!sibling.lines.some((line) => line.includes("verify-deadline-skip")), sibling.lines.join("\n"));
});

// A fork PR that pushed the same commit lists its runs under the same head SHA.
// Its newer run, still going, would read as a re-run in flight and hold fix-ci
// off (reconcilerOwns); readRequiredRun keeps it out of the tested run.
test("a fork's newer run at the same head SHA does not suppress a fix-ci dispatch", async () => {
  const own = { ...tested(2), path: REQUIRED, head_repository: { full_name: "octo/repo" } };
  const fork = { ...rerunning(1, "in_progress"), id: 40119285049, path: REQUIRED, created_at: new Date(NOW - 600_000).toISOString(), head_repository: { full_name: "someone/repo" } };
  const responses = [{ total_count: 2, workflow_runs: [fork, own] }, { total_count: MIXED_JOBS.length, jobs: MIXED_JOBS }];
  const rest = createGitHubApi({
    token: "t0ken",
    repository: "octo/repo",
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch: async () => ({ ok: true, status: 200, json: async () => responses.shift() }),
  });
  const api = { ...fakeApi({ pages: [[pr(5)]] }), readRequiredRun: (sha, path) => rest.readRequiredRun(sha, path) };
  const result = await dispatchCiFixes({ api, runId: "4242", log: () => {}, appSenderId: APP, maxDispatch: 2, restarts: 1, now: NOW });
  assert.deepEqual(result, { dispatched: [{ number: 5, workflowRunId: "7005" }], failed: 0 });
});

test("other authors, drafts, forks, other bases and held PRs are left alone", async () => {
  const { result } = await run({
    pages: [
      [
        pr(1, { author: { login: "octocat", databaseId: 4242 } }),
        pr(2, { isDraft: true }),
        pr(3, { isCrossRepository: true }),
        pr(4, { baseRefName: "release" }),
        pr(6, { labels: { nodes: [{ name: "needs-human" }] } }),
        pr(7, { labels: { nodes: [{ name: "do-not-merge" }] } }),
        pr(8, { author: { login: "melodic-automation-lanes" } }),
      ],
    ],
  });
  assert.deepEqual(result.dispatched, []);
});

test("a head whose ci-lanes passed, is pending, is missing or came from another writer is left alone", async () => {
  const { result } = await run({
    pages: [
      [
        pr(1, { checks: [lanes("SUCCESS")] }),
        pr(2, { checks: [lanes("PENDING")] }),
        pr(3, { checks: [] }),
        pr(4, { checks: [lanes("FAILURE", "someone")] }),
        pr(5, { commits: { nodes: [] } }),
        // More checks than the page holds could hide an earlier fix-ci run.
        pr(6, {
          commits: {
            nodes: [{ commit: { oid: "6".padStart(40, "a"), statusCheckRollup: { contexts: { nodes: [lanes("FAILURE")], pageInfo: { hasNextPage: true } } } } }],
          },
        }),
      ],
    ],
  });
  assert.deepEqual(result.dispatched, []);
});

test("a head that already has a fix-ci run is skipped, unless every run failed within the restart count", async () => {
  const fix = (conclusion, extra) => check("pr-unblock / fix-ci", conclusion, extra);
  const failed = lanes("FAILURE");
  const { result } = await run({
    pages: [
      [
        pr(1, { checks: [failed, fix("SUCCESS")] }),
        pr(2, { checks: [failed, fix("NEUTRAL")] }),
        pr(3, { checks: [failed, fix(null)] }),
        pr(4, { checks: [failed, fix("FAILURE")] }),
        pr(5, { checks: [failed, fix("FAILURE"), fix("FAILURE")] }),
        // An untrusted-trigger skip did not run the lane.
        pr(6, { checks: [failed, fix("NEUTRAL", { title: "Skipped: untrusted-trigger" })] }),
        // Another app's run under the lane's name counts for nothing.
        pr(7, { checks: [failed, fix("SUCCESS", { checkSuite: { app: { databaseId: 999 } } })] }),
      ],
    ],
  }, { maxDispatch: 10 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [4, 6, 7],
  );
});

// A head's fix-ci runs that failed or found nothing to fix count toward
// fix-ci-restarts only on the base they ran against: once the base tip moves
// past them the head is dispatched again, until limit-stops-per-head (3) such
// runs stand on it. A new head carries none of the old head's runs.
test("a new base dispatches a failed or not-applicable head again, within the per-head cap", async () => {
  const BASE_AT = "2026-10-22T11:00:00Z";
  const before = { completedAt: "2026-10-22T10:00:00Z" };
  const after = { completedAt: "2026-10-22T11:30:00Z" };
  const fix = (conclusion, extra) => check("pr-unblock / fix-ci", conclusion, extra);
  const notApplicable = (extra) => fix("NEUTRAL", { title: "Skipped: not-applicable", ...extra });
  const failed = lanes("FAILURE");
  const { api, result } = await run(
    {
      pages: [
        [
          pr(1, { checks: [failed, notApplicable(before)] }),
          pr(2, { checks: [failed, notApplicable(after)] }),
          pr(3, { checks: [failed, fix("FAILURE", before), fix("FAILURE", before)] }),
          pr(4, { checks: [failed, fix("FAILURE", after), fix("FAILURE", after)] }),
          pr(5, { checks: [failed, fix("FAILURE", before), fix("FAILURE", before), notApplicable(before)] }),
          pr(6, { checks: [failed, fix("SUCCESS", before)] }),
          pr(7, { checks: [failed] }),
        ],
      ],
      baseCommittedAt: BASE_AT,
    },
    { maxDispatch: 10 },
  );
  assert.deepEqual(result.dispatched.map((d) => d.number), [1, 3, 7]);
  assert.equal(api.calls.list, 1, "the base tip comes with the listing");
});

// fix-ci-context skips stop-resolved on any head it finds settled with none
// failing, which leaves nothing to fix there, as a not-applicable skip does.
test("a stop-resolved head goes again on a new base, as a not-applicable one does", async () => {
  const resolved = (completedAt) => check("pr-unblock / fix-ci", "NEUTRAL", { title: "Skipped: stop-resolved", completedAt });
  const failed = lanes("FAILURE");
  const { result } = await run(
    {
      pages: [[pr(1, { checks: [failed, resolved("2026-10-22T10:00:00Z")] }), pr(2, { checks: [failed, resolved("2026-10-22T11:30:00Z")] })]],
      baseCommittedAt: "2026-10-22T11:00:00Z",
    },
    { maxDispatch: 10 },
  );
  assert.deepEqual(result.dispatched.map((d) => d.number), [1]);
});

// GitHub's rollup lists only a check name's newest run, so the head's earlier
// fix-ci runs are in the REST listing alone. A head context skips each time
// (no failing check it counts) on a base that moves before every dispatcher
// run is dispatched three times, then stopped at the cap: one warning on the
// run that finds the cap, and the dispatch record (carried from run to run)
// keeps every later run from reading the head at all.
test("a head fix-ci-context skips after every base move is dispatched three times, then warned about once and never read again", async () => {
  const head = "9".padStart(40, "a");
  const history = [];
  const record = emptyRecord();
  const warning = "::warning::#9: head " + head + "'s pr-unblock / fix-ci ran 3 time(s), the most one head gets; no fix-ci until a new push";
  const cycles = [];
  for (let hour = 1; hour <= 8; hour += 1) {
    const at = (minute) => `2026-10-22T${String(hour).padStart(2, "0")}:${minute}:00Z`;
    const newest = history.length === 0 ? [] : [check("pr-unblock / fix-ci", "NEUTRAL", { title: "Skipped: not-applicable", completedAt: history.at(-1).completed_at })];
    const { api, lines } = await run(
      {
        pages: [[pr(9, { checks: [lanes("FAILURE"), ...newest] })]],
        history: new Map([[head, [...history]]]),
        baseCommittedAt: at("00"),
      },
      { record },
    );
    const dispatched = lines.some((line) => line.startsWith("dispatched fix-ci #9 "));
    if (dispatched) {
      history.push({ name: "pr-unblock / fix-ci", status: "completed", conclusion: "neutral", output: { title: "Skipped: not-applicable" }, completed_at: at("30") });
    }
    cycles.push({ dispatched, warned: lines.filter((line) => line === warning).length, calls: api.calls });
  }
  assert.deepEqual(cycles.map((cycle) => cycle.dispatched), [true, true, true, false, false, false, false, false]);
  assert.deepEqual(cycles.map((cycle) => cycle.warned), [0, 0, 0, 1, 0, 0, 0, 0]);
  assert.ok(isHandled(record, "pr-unblock / fix-ci", head), "the capped head is recorded");
  // Run 4 read the head's runs and stopped before its required run; runs 5-8
  // make no read past the listing.
  assert.deepEqual([cycles[3].calls.history, cycles[3].calls.jobs], [[head], []]);
  for (const { calls } of cycles.slice(4)) {
    assert.deepEqual({ runs: calls.runs, timeline: calls.timeline, history: calls.history, jobs: calls.jobs }, { runs: 0, timeline: [], history: [], jobs: [] });
  }
});

// #9022 L3: fix-ci's retry one model rung up (pr-unblock.yml fix-ci-rung-up and
// its subscription and fallback legs) runs pr-run-activity-read.yml as lane
// pr-unblock, activity fix-ci, whose report job posts `<lane> / <activity>`:
// the name this dispatcher counts. So a dispatch that rang up leaves two
// counted runs on its head, and the per-head cap bounds rung-ups too: a head
// gets at most two. Both runs failing is the case the cap decides; a run that
// passed or escalated stops the head sooner.
test("a rung-up retry's check is the counted fix-ci check, so it spends one of the head's runs toward the cap", async () => {
  const unblock = readFileSync(new URL("../../workflows/pr-unblock.yml", import.meta.url), "utf8").split("\n");
  for (const job of ["fix-ci-rung-up", "fix-ci-rung-up-subscription", "fix-ci-rung-up-fallback"]) {
    const start = unblock.indexOf(`  ${job}:`);
    assert.notEqual(start, -1, job);
    const end = unblock.findIndex((line, i) => i > start && /^ {2}[a-z][\w-]*:$/.test(line));
    const block = unblock.slice(start + 1, end === -1 ? undefined : end);
    assert.ok(block.some((line) => line.startsWith("    uses: ./.github/workflows/pr-run-activity-read.yml")), job);
    assert.ok(block.includes('      model-rung: "1"'), job);
    const [lane, activity] = ["lane", "activity"].map((key) => block.find((line) => line.startsWith(`      ${key}: `))?.slice(`      ${key}: `.length));
    assert.equal(`${lane} / ${activity}`, DEFAULTS.checkName, job);
  }

  const head = "9".padStart(40, "a");
  const failedRun = (completedAt) => ({ name: DEFAULTS.checkName, status: "completed", conclusion: "failure", output: { title: null }, completed_at: completedAt });
  // One dispatch on the old base: the rung-0 run and its rung-up retry.
  const rungUpRound = [failedRun("2026-10-22T09:30:00Z"), failedRun("2026-10-22T09:50:00Z")];
  const dispatchOn = (history) =>
    run(
      {
        pages: [[pr(9, { checks: [lanes("FAILURE"), check(DEFAULTS.checkName, "FAILURE", { completedAt: history.at(-1).completed_at })] })]],
        history: new Map([[head, history]]),
        baseCommittedAt: "2026-10-22T11:00:00Z",
      },
      { record: emptyRecord() },
    );
  const second = await dispatchOn(rungUpRound);
  assert.deepEqual(second.result.dispatched.map((d) => d.number), [9], "the rung-up round spent two of three runs; a new base dispatches once more");
  const third = await dispatchOn([...rungUpRound, failedRun("2026-10-22T11:30:00Z")]);
  assert.deepEqual(third.result.dispatched, []);
  assert.ok(third.lines.includes(`::warning::#9: head ${head}'s ${DEFAULTS.checkName} ran 3 time(s), the most one head gets; no fix-ci until a new push`), third.lines.join("\n"));
});

// #9828: its tested run ended cancelled (a job past its timeout), which
// fix-ci-context does not count as failing, so every run posted not-applicable
// while each base move dispatched it again.
test("a head whose tested run ended cancelled is not dispatched across base moves; a failed one still is, up to the cap", async () => {
  const cycle = async (conclusion) => {
    const head = "9".padStart(40, "a");
    const history = [];
    const record = emptyRecord();
    const dispatches = [];
    for (let hour = 1; hour <= 8; hour += 1) {
      const at = (minute) => `2026-10-22T${String(hour).padStart(2, "0")}:${minute}:00Z`;
      const newest = history.length === 0 ? [] : [check("pr-unblock / fix-ci", "NEUTRAL", { title: "Skipped: not-applicable", completedAt: history.at(-1).completed_at })];
      const { lines } = await run(
        {
          pages: [[pr(9, { checks: [lanes("FAILURE"), check("test-bash (3)", "CANCELLED"), check("ci-status", "FAILURE"), ...newest] })]],
          history: new Map([[head, [...history]]]),
          requiredRuns: new Map([[head, { run: { ...tested(2), conclusion }, jobs: conclusion === "failure" ? MIXED_JOBS : null }]]),
          baseCommittedAt: at("00"),
        },
        { record },
      );
      const dispatched = lines.some((line) => line.startsWith("dispatched fix-ci #9 "));
      if (dispatched) {
        history.push({ name: "pr-unblock / fix-ci", status: "completed", conclusion: "neutral", output: { title: "Skipped: not-applicable" }, completed_at: at("30") });
      }
      dispatches.push({ dispatched, lines });
    }
    return dispatches;
  };
  const cancelled = await cycle("cancelled");
  assert.deepEqual(cancelled.map((c) => c.dispatched), [false, false, false, false, false, false, false, false]);
  assert.ok(cancelled[0].lines.includes("skip fix-ci #9: tested run 40119285048 attempt 2 ended cancelled and no check failed for fix-ci to fix"), cancelled[0].lines.join("\n"));
  const failed = await cycle("failure");
  assert.deepEqual(failed.map((c) => c.dispatched), [true, true, true, false, false, false, false, false]);
});

test("a cancelled tested run with a check fix-ci-context counts as failing is still dispatched", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const cancelledRun = { run: { ...tested(2), conclusion: "cancelled" }, jobs: null };
  const { lines, result } = await run(
    {
      pages: [
        [
          pr(5, { checks: [lanes("FAILURE"), check("test-bash (3)", "TIMED_OUT")] }),
          pr(6, { checks: [lanes("FAILURE"), check("lint-repo", "FAILURE")] }),
          pr(7, { checks: [lanes("FAILURE"), check("test-node", "STARTUP_FAILURE")] }),
        ],
      ],
      requiredRuns: new Map([5, 6, 7].map((number) => [head(number), cancelledRun])),
    },
    { maxDispatch: 5 },
  );
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5, 6, 7],
  );
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #5 ") && line.endsWith("(cause: tested run completed/cancelled)")), lines.join("\n"));
});

// #9828's head c1184e03 as recorded: pr-require-checks run 40118648493 ended
// cancelled at attempt 2, its check run 120950643531 (test-bash (3)) cancelled
// past its 9-minute limit, which only its annotations show, and ci-status
// failed. fix-ci takes the slow or hanging test; a check cancelled with the
// cancel note alone (a fail-fast sibling) still leaves the head skipped.
const TIME_LIMITED = JSON.parse(readFileSync(new URL("../maintenance-reconcile-lost-runs/fixtures/annotations-120950643531.json", import.meta.url), "utf8"));
const CANCEL_ONLY = TIME_LIMITED.filter((a) => a.message === "The operation was canceled.");
const stranded = (number, notes) => {
  const head = String(number).padStart(40, "a");
  return {
    pages: [[pr(number, { checks: [lanes("FAILURE"), check("test-bash (3)", "CANCELLED"), check("ci-status", "FAILURE")] })]],
    requiredRuns: new Map([[head, { run: { ...tested(2), id: 40118648493, conclusion: "cancelled" }, jobs: null }]]),
    commitRuns: new Map([
      [
        head,
        [
          { id: 120950643531, ...toRest(check("test-bash (3)", "CANCELLED")) },
          { id: 120952904939, ...toRest(check("ci-status", "FAILURE")) },
        ],
      ],
    ]),
    annotations: new Map([[120950643531, notes]]),
  };
};

test("a head whose tested run ended cancelled with a check past its time limit is dispatched, naming the check", async () => {
  const { api, lines, result } = await run(stranded(9828, TIME_LIMITED));
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [9828],
  );
  // Only the cancelled lane check's annotations are read, not ci-status's.
  assert.deepEqual(api.calls.annotations, [120950643531]);
  assert.ok(
    lines.some((line) => line.startsWith("dispatched fix-ci #9828 ") && line.endsWith("(cause: tested run completed/cancelled, time limit in test-bash (3))")),
    lines.join("\n"),
  );
});

test("a cancelled check with no time-limit note leaves the head skipped; an unreadable note dispatches nothing", async () => {
  const skipped = await run(stranded(9828, CANCEL_ONLY));
  assert.deepEqual(skipped.result.dispatched, []);
  assert.ok(skipped.lines.includes("skip fix-ci #9828: tested run 40118648493 attempt 2 ended cancelled and no check failed for fix-ci to fix"), skipped.lines.join("\n"));
  const unreadable = await run(stranded(9828, Object.assign(new Error("HTTP 502"), { status: 502 })));
  assert.deepEqual(unreadable.result, { dispatched: [], failed: 1 });
  assert.ok(unreadable.lines.some((line) => line.startsWith("::error::#9828: could not read its cancelled checks' annotations")), unreadable.lines.join("\n"));
});

// A cancelled tested run's failed job that a later contract-only run skipped:
// the rollup shows only the skip, and fix-ci-context still finds the failure.
test("a cancelled tested run whose failed job a later run skipped is dispatched", async () => {
  const head = "8".padStart(40, "a");
  const rest = (id, conclusion) => ({ id, name: "test-bash (3)", status: "completed", conclusion, output: { title: null }, completed_at: "2026-10-22T10:00:00Z" });
  const { lines, result, api } = await run({
    pages: [[pr(8, { checks: [lanes("FAILURE"), check("test-bash (3)", "SKIPPED"), check("ci-status", "FAILURE")] })]],
    requiredRuns: new Map([[head, { run: { ...tested(2), conclusion: "cancelled" }, jobs: MIXED_JOBS }]]),
    commitRuns: new Map([[head, [rest(1, "failure"), rest(2, "skipped")]]]),
  });
  assert.deepEqual(result.dispatched.map((d) => d.number), [8], lines.join("\n"));
  assert.deepEqual(api.calls.commit, [head]);
});

test("a cancelled tested run whose head's check runs cannot be read waits on a server error and dispatches on another error", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const serverError = Object.assign(new Error("HTTP 502"), { status: 502 });
  const { lines, result } = await run(
    {
      pages: [[pr(3, { checks: [lanes("FAILURE"), check("test-bash (3)", "SKIPPED")] }), pr(4, { checks: [lanes("FAILURE"), check("test-bash (3)", "SKIPPED")] })]],
      requiredRuns: new Map([3, 4].map((number) => [head(number), { run: { ...tested(2), conclusion: "cancelled" }, jobs: null }])),
      commitRuns: new Map([
        [head(3), serverError],
        [head(4), new Error("not JSON")],
      ]),
    },
    { maxDispatch: 5 },
  );
  assert.deepEqual(result.dispatched.map((d) => d.number), [4], lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("::warning::#3: could not read its head's check runs: HTTP 502; skipped")), lines.join("\n"));
});

test("a head whose fix-ci runs include a run that is not retryable is not capped, and an untrusted-trigger skip does not count", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const rest = (conclusion, title = null) => ({ name: "pr-unblock / fix-ci", status: "completed", conclusion, output: { title }, completed_at: "2026-10-22T10:00:00Z" });
  const record = emptyRecord();
  const { lines } = await run(
    {
      pages: [[pr(1), pr(2), pr(3)]],
      history: new Map([
        [head(1), [rest("failure"), rest("failure"), rest("failure")]],
        [head(2), [rest("failure"), rest("failure"), rest("success")]],
        [head(3), [rest("failure"), rest("failure"), rest("neutral", "Skipped: untrusted-trigger")]],
      ]),
    },
    { record, maxDispatch: 5, restarts: 5 },
  );
  assert.deepEqual(lines.filter((line) => line.startsWith("::warning::")), [
    "::warning::#1: head " + head(1) + "'s pr-unblock / fix-ci ran 3 time(s), the most one head gets; no fix-ci until a new push",
  ]);
  assert.deepEqual([1, 2, 3].map((number) => isHandled(record, "pr-unblock / fix-ci", head(number))), [true, false, false]);
});

test("a head whose fix-ci runs cannot be read is not dispatched: a rate limit or a 5xx waits, any other error fails", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const limited = Object.assign(new Error("GET check-runs returned 403"), { rateLimited: true });
  const outage = Object.assign(new Error("GET check-runs returned 502"), { status: 502 });
  const { lines, result } = await run(
    { pages: [[pr(1), pr(2), pr(3)]], history: new Map([[head(1), limited], [head(2), new Error("GET check-runs returned 404")], [head(3), outage]]) },
    { maxDispatch: 5 },
  );
  assert.deepEqual(result, { dispatched: [], failed: 1 });
  assert.ok(lines.includes("::warning::#1: its pr-unblock / fix-ci run read is rate limited (GET check-runs returned 403); no fix-ci dispatched, a later run retries"), lines.join("\n"));
  assert.ok(lines.includes("::error::#2: could not read its pr-unblock / fix-ci runs (GET check-runs returned 404); left for a later run"), lines.join("\n"));
  assert.ok(lines.includes("::warning::#3: could not read its pr-unblock / fix-ci runs: GET check-runs returned 502; skipped, a later run retries"), lines.join("\n"));
});

const APP_USER = { login: "melodic-automation-lanes[bot]", id: APP, type: "Bot" };
const PERSON = { login: "kyle-sexton", id: 153232337, type: "User" };
const labeledBy = (actor) => [{ event: "labeled", actor, label: { name: "needs-human" }, created_at: "2026-10-22T10:00:00Z" }];
// report-escalation.sh's comment, with the reason it names.
const escalationComment = (reason) => [
  {
    user: APP_USER,
    created_at: "2026-10-22T10:00:05Z",
    body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`${reason}\``,
  },
];
const humanGated = { labels: { nodes: [{ name: "needs-human" }] } };

test("needs-human from another lane's escalation does not hold fix-ci; fix-ci's own, a person's or do-not-merge does", async () => {
  const { api, lines, result } = await run(
    {
      pages: [
        [
          pr(1, humanGated),
          pr(2, humanGated),
          pr(3, humanGated),
          pr(4, { labels: { nodes: [{ name: "needs-human" }, { name: "do-not-merge" }] } }),
        ],
      ],
      labelEvents: new Map([
        [1, labeledBy(APP_USER)],
        [2, labeledBy(APP_USER)],
        [3, labeledBy(PERSON)],
        [4, labeledBy(APP_USER)],
      ]),
      comments: new Map([
        [1, escalationComment("feedback-disputed")],
        [2, escalationComment("ci-fix-escalated")],
        [4, escalationComment("feedback-disputed")],
      ]),
    },
    { gateLabel: "needs-human", maxDispatch: 10 },
  );
  assert.deepEqual(result.dispatched.map((d) => d.number), [1]);
  assert.ok(lines.includes("skip fix-ci #2: held by needs-human: fix-ci escalated it"), lines.join("\n"));
  assert.deepEqual(api.calls.timeline, [1, 2, 3], "a do-not-merge PR needs no timeline read");
});

test("a person's inline review-thread reply, seen only in the review comments, holds fix-ci past another lane's escalation", async () => {
  // GitHub's timeline has no event for a reply inside an existing review thread.
  const reply = (user) => [{ id: 2, in_reply_to_id: 1, user, body: "Wait.", created_at: "2026-10-22T11:00:00Z", updated_at: "2026-10-22T11:00:00Z" }];
  const { lines, result } = await run(
    {
      pages: [[pr(1, humanGated), pr(2, humanGated)]],
      labelEvents: new Map([
        [1, labeledBy(APP_USER)],
        [2, labeledBy(APP_USER)],
      ]),
      comments: new Map([
        [1, escalationComment("feedback-disputed")],
        [2, escalationComment("feedback-disputed")],
      ]),
      reviewComments: new Map([
        [1, reply(PERSON)],
        [2, reply(APP_USER)],
      ]),
    },
    { gateLabel: "needs-human", maxDispatch: 10 },
  );
  assert.deepEqual(result.dispatched.map((d) => d.number), [2], "a bot's inline reply does not hold");
  assert.ok(lines.includes("skip fix-ci #1: held by needs-human: a person commented or reviewed since needs-human went on"), lines.join("\n"));
});

test("an awaiting-human skip left while the PR was held does not hold it once the hold is gone, but counts toward the per-head cap", async () => {
  const held = check("pr-unblock / fix-ci", "NEUTRAL", { title: "Skipped: awaiting-human" });
  const { result } = await run({ pages: [[pr(1, { checks: [lanes("FAILURE"), held] }), pr(2, { checks: [lanes("FAILURE"), held, held, held] })]] });
  assert.deepEqual(result.dispatched.map((d) => d.number), [1], "three held skips reach the cap of three");
});

test("a hold that cannot be read counts as a failed dispatch", async () => {
  const api = fakeApi({ pages: [[pr(1, humanGated)]] });
  api.listTimeline = async () => {
    throw Object.assign(new Error("GET timeline returned 404"), { status: 404 });
  };
  const result = await dispatchCiFixes({ api, runId: "1", log: () => {}, appSenderId: APP, maxDispatch: 2, restarts: 1, gateLabel: "needs-human", now: NOW });
  assert.deepEqual(result, { dispatched: [], failed: 1 });
});

test("a hold read GitHub still answers 5xx after its retries skips that PR with a warning and fails nothing", async () => {
  const api = fakeApi({ pages: [[pr(1, humanGated), pr(2)]] });
  api.listTimeline = async () => {
    throw Object.assign(new Error("GET timeline returned 502"), { status: 502 });
  };
  const lines = [];
  const result = await dispatchCiFixes({ api, runId: "1", log: (line) => lines.push(line), appSenderId: APP, maxDispatch: 2, restarts: 1, gateLabel: "needs-human", now: NOW });
  assert.deepEqual(result, { dispatched: [{ number: 2, workflowRunId: "7002" }], failed: 0 });
  assert.ok(lines.some((line) => line.startsWith("::warning::#1:") && line.includes("502")));
});

test("a restart count of 0 never dispatches a head again", async () => {
  const { result } = await run(
    { pages: [[pr(4, { checks: [lanes("FAILURE"), check("pr-unblock / fix-ci", "FAILURE")] })]] },
    { restarts: 0 },
  );
  assert.deepEqual(result.dispatched, []);
});

test("at most maxDispatch PRs are dispatched, lowest number first; the rest wait for a later run", async () => {
  const { lines, result } = await run({ pages: [[pr(30), pr(10)], [pr(20)]] });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [10, 20],
  );
  assert.ok(lines.some((line) => line.startsWith("defer fix-ci #30")), lines.join("\n"));
});

test("each listing page is one GraphQL query, and its rate-limit cost is logged", async () => {
  const { api, lines } = await run({ pages: [[pr(1)], [pr(2)]], cost: 3 });
  assert.equal(api.calls.list, 2);
  assert.deepEqual(
    lines.filter((line) => line.startsWith("fix-ci listing")),
    ["fix-ci listing page 1: rateLimit.cost=3 remaining=4990", "fix-ci listing page 2: rateLimit.cost=3 remaining=4990"],
  );
});

test("a listing that repeats its cursor stops instead of looping", async () => {
  const api = fakeApi();
  let calls = 0;
  api.listCiFixCandidates = async () => {
    calls += 1;
    return { rateLimit: { cost: 1 }, pullRequests: { nodes: [], pageInfo: { hasNextPage: true, endCursor: "same" } } };
  };
  const lines = [];
  await dispatchCiFixes({ api, runId: "1", log: (line) => lines.push(line), appSenderId: APP, maxDispatch: 2, restarts: 1 });
  assert.equal(calls, 2);
  assert.ok(lines.some((line) => line.includes("listing stopped after page 2")), lines.join("\n"));
});

test("a fix-ci run for the PR that is not done yet holds the dispatch", async () => {
  const { api, result } = await run({
    pages: [[pr(5), pr(6)]],
    workflowRuns: [
      { id: 1, status: "in_progress", display_title: "pr-unblock fix-ci #5" },
      { id: 2, status: "completed", display_title: "pr-unblock fix-ci #6" },
    ],
  });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [6],
  );
  assert.equal(api.calls.runs, 1);
});

test("a rate-limited run listing defers with a warning; any other listing error fails", async () => {
  const limited = Object.assign(new Error("GET runs returned 403"), { rateLimited: true });
  const deferred = await run({ pages: [[pr(5)]], workflowRuns: limited });
  assert.deepEqual(deferred.result, { dispatched: [], failed: 0 });
  assert.ok(deferred.lines.some((line) => line.startsWith("::warning::") && line.includes("rate limited")));
  const broken = await run({ pages: [[pr(5)]], workflowRuns: new Error("GET runs returned 404") });
  assert.deepEqual(broken.result, { dispatched: [], failed: 1 });
  assert.ok(broken.lines.some((line) => line.startsWith("::error::") && line.includes("404")));
});

test("no candidate reads no workflow runs", async () => {
  const { api } = await run({ pages: [[pr(1, { isDraft: true })]] });
  assert.equal(api.calls.runs, 0);
});

test("a failed dispatch, or one with no usable run id, counts as failed and still uses the cap", async () => {
  const { result } = await run({ pages: [[pr(1), pr(2), pr(3)]], failDispatch: new Set(["1"]), runIds: new Map([["2", undefined]]) });
  assert.deepEqual(result, { dispatched: [], failed: 2 });
});

// Owner decision Q22 (2026-10-22): a non-draft PR by an adoptable owner
// account is a candidate once both it and its head commit are 24 hours idle.
const OWNER = 153232337;
const hoursAgo = (hours) => new Date(NOW - hours * 3_600_000).toISOString();
const ADOPTION = { ownerIds: [OWNER], idleHours: 24 };

function ownerPr(number, { updated = 25, committed = 25, committedDate = hoursAgo(committed), ...overrides } = {}) {
  const node = pr(number, { author: { login: "kyle-sexton", databaseId: OWNER }, updatedAt: hoursAgo(updated), ...overrides });
  node.commits.nodes[0].commit.committedDate = committedDate;
  return node;
}

// capped_close closes only the lanes App's pull requests: an adopted owner's
// PR at the cap keeps its fix-ci round, and the cap is not read for it.
test("an adopted owner PR at the verify cap still gets its fix-ci round", async () => {
  const asked = [];
  const verifyCapped = (request) => {
    asked.push(request);
    return "verify:repeated-fail: fails at 3 heads, the cap is 3";
  };
  const { result } = await run({ pages: [[ownerPr(9)]] }, { adoption: ADOPTION, now: NOW, verifyCapped });
  assert.deepEqual(result.dispatched.map((d) => d.number), [9]);
  assert.deepEqual(asked, []);
});

// Owner decision 2026-10-22: a trusted App's PR (the release App here) does
// not wait out the idle window; a person's still does.
test("a listed bot's PR is adopted with no idle wait, a listed person's waits", () => {
  const RELEASE = 337859524;
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: { ownerIds: [OWNER, RELEASE], idleHours: 24 }, now: NOW };
  const bot = { __typename: "Bot", login: "melodic-plugin-release", databaseId: RELEASE };
  assert.equal(skipReason(ownerPr(1, { updated: 0, committed: 0, author: bot }), options), "");
  assert.equal(skipReason(ownerPr(2, { updated: 0, committed: 0, author: { __typename: "User", login: "kyle-sexton", databaseId: OWNER } }), options), "owner PR or its head commit active in the last 24 hour(s)");
  assert.equal(skipReason(ownerPr(3, { updated: 0, committed: 0, author: { ...bot, databaseId: 4242 } }), options), "not opened by the lanes App or an adoptable owner");
});

// release-publish-plugins.yml rebuilds release/plugins, so a fix-ci push there
// answers 422 (#11840's runs 41308756974, 41312571464): the release PR is
// never dispatched, and a lanes App PR on that branch neither.
test("a PR from a head branch a workflow owns and rebuilds is skipped before any read", async () => {
  const RELEASE = 337859524;
  const bot = { __typename: "Bot", login: "melodic-plugin-release", databaseId: RELEASE };
  const release = ownerPr(1, { updated: 0, committed: 0, author: bot, headRefName: "release/plugins" });
  const options = { adoption: { ownerIds: [RELEASE], idleHours: 24 }, ownedBranches: ["release/plugins"], now: NOW };
  const { api, lines, result } = await run({ pages: [[release, pr(2, { headRefName: "release/plugins" }), pr(3, { headRefName: "feat/x" })]] }, options);
  assert.deepEqual(result, { dispatched: [{ number: 3, workflowRunId: "7003" }], failed: 0 });
  assert.deepEqual(api.calls.jobs, [pr(3).headRefOid]);
  assert.ok(lines.includes("skip fix-ci #1: head branch release/plugins is rebuilt by its own workflow"), lines.join("\n"));
  assert.ok(lines.includes("skip fix-ci #2: head branch release/plugins is rebuilt by its own workflow"), lines.join("\n"));
});

test("an adoptable owner's PR idle 25 hours whose ci-status failed is dispatched", async () => {
  const { result } = await run({ pages: [[ownerPr(9)]] }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(result, { dispatched: [{ number: 9, workflowRunId: "7009" }], failed: 0 });
});

test("an owner PR active within the idle window is skipped with a reason", () => {
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: ADOPTION, now: NOW };
  assert.equal(skipReason(ownerPr(1, { updated: 2, committed: 2 }), options), "owner PR or its head commit active in the last 24 hour(s)");
  // Idle means both: an old PR with a fresh commit, or the reverse, is active.
  assert.equal(skipReason(ownerPr(2, { updated: 25, committed: 2 }), options), "owner PR or its head commit active in the last 24 hour(s)");
  assert.equal(skipReason(ownerPr(3, { updated: 2, committed: 25 }), options), "owner PR or its head commit active in the last 24 hour(s)");
  assert.equal(skipReason(ownerPr(4), options), "");
});

test("owner drafts, holds, unlisted or spoofed users and unreadable dates are left alone, each for its reason", async () => {
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: ADOPTION, now: NOW };
  const unlisted = "not opened by the lanes App or an adoptable owner";
  const active = "owner PR or its head commit active in the last 24 hour(s)";
  const cases = [
    [ownerPr(1, { isDraft: true }), "not a ready same-repository PR into the base"],
    [ownerPr(2, { labels: { nodes: [{ name: "do-not-merge" }] } }), "held"],
    [ownerPr(3, { labels: { nodes: [{ name: "needs-human" }] } }), "held"],
    [ownerPr(4, { body: "Closes #1\n\nHold: until the demo\n" }), "held by a Hold: line"],
    [ownerPr(5, { author: { login: "octocat", databaseId: 4242 } }), unlisted],
    // The id decides, never the login.
    [ownerPr(6, { author: { login: "kyle-sexton", databaseId: 4242 } }), unlisted],
    [ownerPr(7, { author: null }), unlisted],
    // An unreadable date is not proof of idleness.
    [ownerPr(8, { updatedAt: "not a date" }), active],
    [ownerPr(9, { committedDate: "not a date" }), active],
  ];
  for (const [node, reason] of cases) {
    assert.equal(skipReason(node, options), reason, `#${node.number}`);
  }
  const { result } = await run({ pages: [cases.map(([node]) => node)] }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(result.dispatched, []);
  const none = await run({ pages: [[ownerPr(10)]] }, { now: NOW });
  assert.deepEqual(none.result.dispatched, [], "with no adoption list no owner PR is adopted");
});

test("adoption.held skips every owner PR with its reason and leaves lanes App PRs alone", () => {
  const held = "base tracker config unreadable, so its human-gated label is unknown";
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: { ...ADOPTION, held }, now: NOW };
  assert.equal(skipReason(ownerPr(15), options), held);
  assert.equal(skipReason(pr(16), options), "");
});

test("a listed owner id is adopted whatever its login", async () => {
  const { result } = await run({ pages: [[ownerPr(11, { author: { login: "someone-else", databaseId: OWNER } })]] }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(result.dispatched.map((d) => d.number), [11]);
});

test("a Hold: line holds an owner PR in any case, after any whitespace, and after a bare CR", () => {
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: ADOPTION, now: NOW };
  for (const body of ["  Hold: demo", "hold: demo", "x\rHold: y", " Hold: z", "\u00a0Hold: nbsp", "Closes #1\r\n\tHOLD: tab"]) {
    assert.equal(skipReason(ownerPr(12, { body }), options), "held by a Hold: line", JSON.stringify(body));
  }
  // Not a line start, or a newline before the word on the same "line": no hold.
  for (const body of ["Closes #1. Hold: not at a line start", "Holding: no colon after hold", "x\n\nThe word hold: mid-line"]) {
    assert.equal(skipReason(ownerPr(12, { body }), options), "", JSON.stringify(body));
  }
});

test("the human-gated label comes from the tracker config, else needs-human", () => {
  assert.equal(humanGatedLabel(null), "needs-human");
  assert.equal(humanGatedLabel('{"config":{"lease_ttl_hours":24}}'), "needs-human");
  assert.equal(humanGatedLabel('{"config":{"role_labels":{"human-gated":"  human-gated  "}}}'), "human-gated");
  assert.equal(humanGatedLabel('{"config":{"role_labels":{"human-gated":"   "}}}'), "needs-human");
  assert.equal(humanGatedLabel('{"config":"x"}'), "needs-human");
  assert.throws(() => humanGatedLabel("{not json"));
});

test("lanes App PRs keep their rules: no idle wait, and a Hold: line does not hold them", async () => {
  const fresh = pr(8, { body: "Closes #1\n\nHold: a human merges this\n", updatedAt: hoursAgo(0) });
  const { result } = await run({ pages: [[fresh]] }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(result.dispatched.map((d) => d.number), [8]);
});

test("the adapter sends one query naming the PR, its last commit's check rollup and rateLimit cost", async () => {
  const requests = [];
  const api = createGitHubApi({
    token: "t",
    repository: "octo/repo",
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch: async (url, init) => {
      requests.push({ url, body: JSON.parse(init.body) });
      return new Response(
        JSON.stringify({
          data: {
            rateLimit: { cost: 4, remaining: 9 },
            repository: { ref: { target: { committedDate: "2026-10-22T11:00:00Z" } }, pullRequests: { nodes: [], pageInfo: { hasNextPage: false, endCursor: null } } },
          },
        }),
        { status: 200 },
      );
    },
  });
  const page = await api.listCiFixCandidates({ base: "main" });
  assert.equal(page.rateLimit.cost, 4);
  assert.equal(page.baseCommittedAt, "2026-10-22T11:00:00Z");
  assert.ok(LIST_QUERY.includes("ref(qualifiedName: $base) { target { ... on Commit { committedDate } } }"));
  assert.ok(LIST_QUERY.includes("title completedAt checkSuite"));
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, "https://api.example/graphql");
  assert.equal(requests[0].body.query, LIST_QUERY);
  assert.deepEqual(requests[0].body.variables, { owner: "octo", name: "repo", base: "main", after: null });
  for (const field of ["rateLimit", "cost", "statusCheckRollup", "commits(last: 1)", "databaseId", "... on User { databaseId }", "updatedAt", "committedDate", "body", "... on StatusContext { context state createdAt creator { __typename ... on Bot { databaseId } } }"]) {
    assert.ok(LIST_QUERY.includes(field), field);
  }
});

test("the adapter reads a head's check runs as fix-ci-context does: every run, 100 a page, at most 3 pages", async () => {
  const urls = [];
  const api = createGitHubApi({
    token: "t",
    repository: "octo/repo",
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch: async (url) => {
      urls.push(url);
      return new Response(JSON.stringify({ check_runs: Array.from({ length: 100 }, (_, index) => ({ id: urls.length * 100 + index })) }), { status: 200 });
    },
  });
  const runs = await api.listCommitCheckRuns("a".repeat(40));
  assert.equal(runs.length, 300);
  assert.deepEqual(
    urls,
    [1, 2, 3].map((page) => `https://api.example/repos/octo/repo/commits/${"a".repeat(40)}/check-runs?filter=all&per_page=100&page=${page}`),
  );
});

// A contract-only pr-require-checks run posts a lane skipped after the real
// run failed it; a latest-only listing returned only the skip, and the
// dispatcher read the head as not failing where fix-ci-context must agree.
test("the adapter's listing keeps a lane's failure under a later skip of it", async () => {
  const api = createGitHubApi({
    token: "t",
    repository: "octo/repo",
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch: async (url) => {
      const skipped = { id: 2, name: "test-node", status: "completed", conclusion: "skipped" };
      const all = new URL(url).searchParams.get("filter") === "all";
      const check_runs = all ? [{ id: 1, name: "test-node", status: "completed", conclusion: "failure" }, skipped] : [skipped];
      return new Response(JSON.stringify({ check_runs }), { status: 200 });
    },
  });
  assert.deepEqual(failingChecks(await api.listCommitCheckRuns("a".repeat(40))).map((run) => run.id), [1]);
});

test("a head whose ci-status failed on infra only gets no fix-ci run, and takes no place under the cap", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const { api, lines, result } = await run({ pages: [[pr(5), pr(6), pr(7)]], requiredRuns: new Map([[head(5), { run: tested(1), jobs: INFRA_JOBS }]]) });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [6, 7],
  );
  assert.deepEqual(api.calls.jobs, [head(5), head(6), head(7)]);
  assert.ok(lines.includes("skip fix-ci #5: infra failure, re-run job re-runs it once"), lines.join("\n"));
});

test("an adopted owner PR whose ci-status failed on infra only is the reconciler's too", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([[head(13), { run: tested(1), jobs: INFRA_JOBS }]]);
  const { lines, result } = await run({ pages: [[ownerPr(13), ownerPr(14)]], requiredRuns }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [14],
  );
  assert.ok(lines.includes("skip fix-ci #13: infra failure, re-run job re-runs it once"), lines.join("\n"));
});

// A gate never hangs on one API field: a required run that cannot be read is
// no reason to wait, so fix-ci takes the head under its usual caps.
test("a head whose required run's jobs cannot be read is dispatched fix-ci, and the log says why", async () => {
  const head = "5".padStart(40, "a");
  const unreadable = Object.assign(new Error("GET returned 404"), { status: 404 });
  const { lines, result } = await run({ pages: [[pr(5)]], requiredRuns: new Map([[head, unreadable]]) });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5],
  );
  assert.ok(lines.some((line) => line.startsWith("::warning::#5: could not read its required run's jobs (GET returned 404); dispatching fix-ci")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #5 ") && line.endsWith("(cause: required run unreadable)")), lines.join("\n"));
});

// An outage is no reason to spend a model run either: a required-run read
// GitHub still answers 5xx after its retries skips that head for a later run.
test("a required-run read GitHub still answers 5xx after its retries skips that head with a warning and fails nothing", async () => {
  const outage = Object.assign(new Error("GET https://api.example/runs returned 502"), { status: 502 });
  const { api, lines, result } = await run({ pages: [[pr(5), pr(6)]], requiredRuns: new Map([["5".padStart(40, "a"), outage]]) });
  assert.deepEqual(result, { dispatched: [{ number: 6, workflowRunId: "7006" }], failed: 0 });
  assert.deepEqual(api.calls.dispatch.map((call) => call.inputs["pr-number"]), ["6"]);
  assert.ok(lines.some((line) => line.startsWith("::warning::#5:") && line.includes("502") && line.includes("skipped")), lines.join("\n"));
});

test("an unreadable required run still keeps the per-head cap, the restart count and an in-flight run", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const fix = check("pr-unblock / fix-ci", "FAILURE");
  // #1's three failures ran on an older base, so only the per-head cap stops it.
  const oldFix = check("pr-unblock / fix-ci", "FAILURE", { completedAt: "2026-10-22T09:00:00Z" });
  const failed = lanes("FAILURE");
  const requiredRuns = new Map([1, 2, 3].map((number) => [head(number), new Error("GET returned 502")]));
  const { api, lines, result } = await run(
    {
      pages: [[pr(1, { checks: [failed, oldFix, oldFix, oldFix] }), pr(2, { checks: [failed, fix, fix] }), pr(3)]],
      requiredRuns,
      workflowRuns: [{ id: 99, status: "in_progress", display_title: "pr-unblock fix-ci #3" }],
      baseCommittedAt: "2026-10-22T10:00:00Z",
    },
    { maxDispatch: 5 },
  );
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(api.calls.dispatch, []);
  assert.ok(lines.includes(`::warning::#1: head ${head(1)}'s pr-unblock / fix-ci ran 3 time(s), the most one head gets; no fix-ci until a new push`), lines.join("\n"));
  assert.ok(!api.calls.jobs.includes(head(1)), "the cap stops #1 before its required run is read");
  assert.ok(lines.some((line) => line.startsWith("skip fix-ci #2:")), lines.join("\n"));
});

// Rule: fix-ci skips a failed head only while a re-run of its tested run is
// actually queued or going on that head; that re-run's result decides.
test("a head whose tested run is being re-run waits for the re-run's result", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(5), { run: rerunning(2, "queued"), jobs: null }],
    [head(6), { run: rerunning(2, "in_progress"), jobs: null }],
    [head(7), { run: rerunning(3, "waiting"), jobs: null }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6), pr(7)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(result.dispatched, []);
  assert.ok(lines.includes("skip fix-ci #5: run 40119285048 attempt 2 is queued; its result decides"), lines.join("\n"));
  assert.ok(lines.includes("skip fix-ci #6: run 40119285048 attempt 2 is in_progress; its result decides"), lines.join("\n"));
  assert.ok(lines.includes("skip fix-ci #7: run 40119285048 attempt 3 is waiting; its result decides"), lines.join("\n"));
});

// Once per head: an infra-only failure gets one re-run, then fix-ci.
test("an infra-only head gets one re-run; once it failed again at attempt 2, fix-ci takes it", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(5), { run: tested(1), jobs: INFRA_JOBS }],
    [head(6), { run: tested(2), jobs: INFRA_JOBS }],
    [head(7), { run: tested(3), jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6), pr(7)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [6, 7],
  );
  assert.ok(lines.includes("skip fix-ci #5: infra failure, re-run job re-runs it once"), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #6 ") && line.endsWith("(cause: infra failure at attempt 2)")), lines.join("\n"));
});

// The re-run job runs half-hourly and can defer a head; an infra-only first
// failure no re-run picked up within RERUN_DUE_MINUTES is fix-ci's, not a
// silent wait.
test("an infra-only first failure that no re-run picked up in time is fix-ci's", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const minutesAgo = (minutes) => new Date(NOW - minutes * 60_000).toISOString();
  const run1 = (minutes) => ({ ...tested(1), created_at: minutesAgo(minutes), updated_at: minutesAgo(minutes) });
  const requiredRuns = new Map([
    [head(5), { run: run1(RERUN_DUE_MINUTES + 1), jobs: INFRA_JOBS }],
    [head(6), { run: run1(RERUN_DUE_MINUTES - 1), jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5],
  );
  assert.ok(lines.includes("skip fix-ci #6: infra failure, re-run job re-runs it once"), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #5 ") && line.endsWith(`(cause: infra failure at attempt 1, no re-run within ${RERUN_DUE_MINUTES} min)`)), lines.join("\n"));
});

test("an infra-only head past the reconciler's 24-hour lookback is fix-ci's", async () => {
  // The reconciler re-runs only runs created in the last 24 hours (LOOKBACK_HOURS).
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(5), { run: tested(1, 25), jobs: INFRA_JOBS }],
    [head(6), { run: { ...tested(1, 23), updated_at: new Date(NOW - 60_000).toISOString() }, jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6)]], requiredRuns });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5],
  );
  assert.ok(lines.includes("skip fix-ci #6: infra failure, re-run job re-runs it once"), lines.join("\n"));
});

// A test assertion, lint or typecheck failure (a failed step that is not an
// install or a stop) goes straight to fix-ci: no re-run is waited for unless
// one is actually queued.
test("a real failure goes straight to fix-ci at attempt 1, and the log names its job and step", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const typos = [
    { name: "lint-repo", conclusion: "failure", steps: [{ name: "Set up job", conclusion: "success" }, { name: "Check spelling", conclusion: "failure" }] },
    { name: "ci-status", conclusion: "failure", steps: [] },
  ];
  const requiredRuns = new Map([
    [head(5), { run: tested(1), jobs: MIXED_JOBS }],
    [head(6), { run: tested(2), jobs: MIXED_JOBS }],
    [head(7), { run: tested(1, 25), jobs: MIXED_JOBS }],
    // Only ci-status failed.
    [head(8), { run: tested(1), jobs: [{ name: "lint-repo", conclusion: "success" }, { name: "ci-status", conclusion: "failure" }] }],
    [head(9), { run: tested(1), jobs: typos }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6), pr(7), pr(8), pr(9)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5, 6, 7, 8, 9],
  );
  assert.ok(!lines.some((line) => line.includes("first failure")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #9 ") && line.endsWith("(cause: code failure in lint-repo / Check spelling)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #8 ") && line.endsWith("(cause: no failed lane job)")), lines.join("\n"));
});

// Missing or malformed data fails toward recovery: fix-ci is dispatched and
// the log says what could not be classified.
test("a tested run that is missing or malformed dispatches fix-ci with the reason logged", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(1), { run: null, jobs: [] }],
    [head(2), { run: tested(1), jobs: null }],
    [head(3), { run: { ...tested(1), status: undefined }, jobs: INFRA_JOBS }],
    [head(4), { run: { ...tested(1), updated_at: "not a date" }, jobs: INFRA_JOBS }],
    [head(5), { run: { ...tested(1), run_attempt: "1" }, jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(1), pr(2), pr(3), pr(4), pr(5)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [1, 2, 3, 4, 5],
  );
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #1 ") && line.endsWith("(cause: no tested run found)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #2 ") && line.endsWith("(cause: failed jobs unreadable)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #3 ") && line.endsWith("(cause: infra failure, run field status unreadable)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #4 ") && line.endsWith("(cause: infra failure, run field updated_at unreadable)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #5 ") && line.endsWith("(cause: infra failure, run field run_attempt unreadable)")), lines.join("\n"));
});

// pr-test-platforms is not in ci-status, but the merge gate holds a PR on any
// failing check, such as a macOS test_tunnel flake.
test("a failed advisory pr-test-platforms run with ci-status green is fix-ci's unless a re-run of it is going", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const advisory = [lanes("SUCCESS"), check("test-macos-planning-shared", "FAILURE")];
  const requiredRuns = new Map([
    [`${head(5)} ${ADVISORY}`, { run: tested(1), jobs: MIXED_JOBS }],
    [`${head(6)} ${ADVISORY}`, { run: tested(2), jobs: MIXED_JOBS }],
    [`${head(7)} ${ADVISORY}`, { run: { ...tested(2), conclusion: "success" }, jobs: [] }],
    [`${head(8)} ${ADVISORY}`, { run: rerunning(2, "in_progress"), jobs: null }],
  ]);
  const prs = [5, 6, 7, 8].map((number) => pr(number, { checks: advisory }));
  const { api, lines, result } = await run({ pages: [prs], requiredRuns }, { maxDispatch: 4 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5, 6],
  );
  assert.deepEqual(api.calls.paths, [ADVISORY, ADVISORY, ADVISORY, ADVISORY]);
  assert.ok(lines.includes("skip fix-ci #7: ci-lanes passed and no pr-test-platforms run failed"), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("skip fix-ci #8:")), lines.join("\n"));
});

test("a green ci-status with only a failed fix-ci run, or no failure, is left alone", async () => {
  const { api, result } = await run({
    pages: [[pr(5, { checks: [lanes("SUCCESS"), check("pr-unblock / fix-ci", "FAILURE")] }), pr(6, { checks: [lanes("SUCCESS"), check("lint", "SUCCESS")] })]],
  });
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(api.calls.paths, []);
});

// ci-status also fails while a review lane is pending, missing or holding the
// PR, with no label on it; none of that is a CI fix. Only ci-lanes counts.
test("a red ci-status over green or absent ci-lanes summons no fix-ci", async () => {
  const red = check("ci-status", "FAILURE");
  const { api, lines, result } = await run({
    pages: [[pr(1, { checks: [red, lanes("SUCCESS")] }), pr(2, { checks: [red] }), pr(3, { checks: [red, lanes("PENDING")] })]],
  });
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(api.calls.paths, []);
  assert.equal(skipReason(pr(1, { checks: [red, lanes("SUCCESS")] }), { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: [], restarts: 1, now: NOW }), "ci-lanes has not failed");
  assert.ok(!lines.some((line) => line.includes("fix-ci #")), lines.join("\n"));
});

test("a ci-lanes failure or error from the GitHub Actions bot is dispatched, whatever ci-status says", async () => {
  const { api, result } = await run({
    pages: [[pr(1, { checks: [check("ci-status", "SUCCESS"), lanes("FAILURE")] }), pr(2, { checks: [lanes("ERROR")] })]],
  }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [1, 2],
  );
  assert.deepEqual(api.calls.paths, [REQUIRED, REQUIRED]);
});

test("a ci-lanes failure set by any other actor, or with no creator, is not trusted, and its skip is logged", async () => {
  const untrusted = [
    { __typename: "User", login: "octocat", databaseId: 583231 },
    { __typename: "User", login: "github-actions", databaseId: 41898282 },
    { __typename: "Bot", login: "github-actions", databaseId: 1 },
    { __typename: "Bot", login: "github-actions[bot]" },
    null,
  ];
  const { api, lines, result } = await run({
    pages: [[...untrusted.map((creator, index) => pr(index + 1, { checks: [lanes("FAILURE", creator)] })), pr(9, { checks: [{ ...lanes("FAILURE"), creator: undefined }] })]],
  }, { maxDispatch: 9 });
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(api.calls.paths, []);
  for (const number of [1, 2, 3, 4, 5, 9]) {
    assert.ok(lines.includes(`skip fix-ci #${number}: ci-lanes failed but the GitHub Actions bot did not set it`), lines.join("\n"));
  }
});

test("a listed head with failed lanes that is skipped logs why; a passing or pending one stays quiet", async () => {
  const { lines, result } = await run({
    pages: [[pr(1, { isDraft: true }), pr(2, { checks: [lanes("SUCCESS")] }), pr(3, { checks: [lanes("PENDING")] }), pr(4, { checks: [] }), pr(5, { isDraft: true, checks: [lanes("ERROR")] })]],
  });
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(
    lines.filter((line) => line.includes("fix-ci #")),
    ["skip fix-ci #1: not a ready same-repository PR into the base", "skip fix-ci #5: not a ready same-repository PR into the base"],
  );
});

// A rate-limited read is no reason to spend a model run: the head waits for a
// later dispatcher run, as a rate-limited workflow listing does.
test("a rate-limited required-run read dispatches nothing and says so", async () => {
  const head = "5".padStart(40, "a");
  const limited = Object.assign(new Error("GET https://api.example/runs returned 403"), { rateLimited: true });
  const { api, lines, result } = await run({ pages: [[pr(5)]], requiredRuns: new Map([[head, limited]]) });
  assert.deepEqual(result, { dispatched: [], failed: 0 });
  assert.deepEqual(api.calls.dispatch, []);
  assert.ok(lines.some((line) => line.startsWith("::warning::#5: its required run read is rate limited")), lines.join("\n"));
});

// Job and step names come from the PR head's workflow file, so the log line
// that carries them can hold no workflow command.
test("a failed job or step name with a newline or control character cannot start a workflow command in the log", async () => {
  const head = "5".padStart(40, "a");
  const evil = [
    { name: "lint\n::error::x", conclusion: "failure", steps: [{ name: "Set up job", conclusion: "success" }, { name: `run\r\n::add-mask::y\u0007${"z".repeat(300)}`, conclusion: "failure" }] },
  ];
  const { lines, result } = await run({ pages: [[pr(5)]], requiredRuns: new Map([[head, { run: tested(1), jobs: evil }]]) });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5],
  );
  const line = lines.find((l) => l.startsWith("dispatched fix-ci #5 "));
  assert.ok(line, lines.join("\n"));
  assert.ok(!/[\r\n\x00-\x1f]/.test(line), JSON.stringify(line));
  assert.ok(line.length < 400, String(line.length));
  assert.ok(line.includes("(cause: code failure in lint ::error::x / run ::add-mask::y"), line);
});

// A job whose steps never listed is not shown as a code failure once the
// re-read window has passed.
test("a failed job whose steps never listed is logged as such past the deadline", async () => {
  const head = "5".padStart(40, "a");
  const old = new Date(NOW - (RERUN_DUE_MINUTES + 5) * 60_000).toISOString();
  const unlisted = [{ name: "lint-repo", status: "completed", conclusion: "failure", runner_id: 7, steps: [] }];
  const { lines, result } = await run({ pages: [[pr(5)]], requiredRuns: new Map([[head, { run: { ...tested(2), updated_at: old }, jobs: unlisted }]]) });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5],
  );
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #5 ") && line.endsWith(`(cause: steps unlisted past ${RERUN_DUE_MINUTES} min in lint-repo)`)), lines.join("\n"));
});

// A fix-ci run whose push job stopped on a reason routed to a failing status
// (a lane-stopped skip on pr-unblock / apply-patch) counts as a failed run:
// the head is retried under fix-ci-restarts and the per-head cap, as a run
// that failed is.
test("a fix-ci run its push job stopped is retried on the same head once, then left at fix-ci-restarts", async () => {
  const head = "7".padStart(40, "a");
  const at = (time) => `2026-10-22T${time}:00Z`;
  const fixCi = (time) => ({ name: "pr-unblock / fix-ci", status: "completed", conclusion: "success", output: { title: "Fixed" }, started_at: at(time), completed_at: at(time) });
  const stop = (time) => ({ name: "pr-unblock / apply-patch", status: "completed", conclusion: "neutral", output: { title: "Skipped: lane-stopped" }, started_at: at(time) });
  const once = await run({ pages: [[pr(7)]], history: new Map([[head, [fixCi("10:00")]]]), stops: new Map([[head, [stop("10:05")]]]) });
  assert.ok(once.lines.some((line) => line.startsWith("dispatched fix-ci #7 ")), once.lines.join("\n"));
  const twice = await run({
    pages: [[pr(7)]],
    history: new Map([[head, [fixCi("10:00"), fixCi("10:30")]]]),
    stops: new Map([[head, [stop("10:05"), stop("10:35")]]]),
  });
  assert.ok(twice.lines.some((line) => line.includes("failed 2 time(s) on this base, past 1 restart(s)")), twice.lines.join("\n"));
  // A push job that did not stop leaves the run handling the head.
  const pushed = await run({ pages: [[pr(7)]], history: new Map([[head, [fixCi("10:00")]]]), stops: new Map([[head, [{ ...stop("10:05"), output: { title: "Pushed" }, conclusion: "success" }]]]) });
  assert.ok(pushed.lines.some((line) => line.includes("head already has a pr-unblock / fix-ci check run")), pushed.lines.join("\n"));
  // A select job's own stop (the round cap) on the fix-ci check is final.
  const capped = await run({ pages: [[pr(7)]], history: new Map([[head, [{ ...stop("10:00"), name: "pr-unblock / fix-ci" }]]]) });
  assert.ok(capped.lines.some((line) => line.includes("head already has a pr-unblock / fix-ci check run")), capped.lines.join("\n"));
});

// A kill switch turned on after the fix-ci model run stops its push job at
// the broker (request-lane-token kill-switch-ok): the apply-patch check skips
// kill-switch, so the attempt did no work. It is retried like a held skip,
// spending no fix-ci restart, and so is a kill-switch stop of fix-ci itself.
test("a fix-ci run the kill switch stopped is retried on the same head without spending a restart", async () => {
  const head = "7".padStart(40, "a");
  const at = (time) => `2026-10-22T${time}:00Z`;
  const fixCi = (time) => ({ name: "pr-unblock / fix-ci", status: "completed", conclusion: "success", output: { title: "Fixed" }, started_at: at(time), completed_at: at(time) });
  const killed = (name, time) => ({ name, status: "completed", conclusion: "neutral", output: { title: "Skipped: kill-switch" }, started_at: at(time), completed_at: at(time) });
  const twice = await run({
    pages: [[pr(7)]],
    history: new Map([[head, [fixCi("10:00"), fixCi("10:30")]]]),
    stops: new Map([[head, [killed("pr-unblock / apply-patch", "10:05"), killed("pr-unblock / apply-patch", "10:35")]]]),
  });
  assert.ok(twice.lines.some((line) => line.startsWith("dispatched fix-ci #7 ")), twice.lines.join("\n"));
  const own = await run({ pages: [[pr(7)]], history: new Map([[head, [killed("pr-unblock / fix-ci", "10:00")]]]) });
  assert.ok(own.lines.some((line) => line.startsWith("dispatched fix-ci #7 ")), own.lines.join("\n"));
});

// fix-ci and the in-run fix-ci-rung-up each post a fix-ci check in one
// workflow run (the run id in each check's external_id; the API returns each
// check's details_url as the check run's own page). When the rung-up's
// push job stops, the pair
// is one stopped attempt: the first check's "Passed: no changes" does not
// leave the head handled. The pair still spends two of the head's
// maxRunsPerHead places, one per model run.
test("a fix-ci run whose rung-up push job stopped is one failed attempt, retried on the same head", async () => {
  const head = "7".padStart(40, "a");
  const at = (time) => `2026-10-22T${time}:00Z`;
  const checkPage = (time) => `https://github.com/o/r/runs/9${time.replace(":", "")}`;
  const fixCi = (time, suite, title) => ({ name: "pr-unblock / fix-ci", status: "completed", conclusion: "success", output: { title }, started_at: at(time), completed_at: at(time), details_url: checkPage(time), external_id: `pr-unblock:fix-ci:${suite}:1` });
  const stop = (time, suite) => ({ name: "pr-unblock / apply-patch", status: "completed", conclusion: "neutral", output: { title: "Skipped: lane-stopped" }, started_at: at(time), details_url: checkPage(time), external_id: `pr-unblock:apply-patch:${suite}:1` });
  const pair = [fixCi("10:00", 1, "Passed: no changes"), fixCi("10:10", 1, "Fixed")];
  const once = await run({ pages: [[pr(7)]], history: new Map([[head, pair]]), stops: new Map([[head, [stop("10:15", 1)]]]) });
  assert.ok(once.lines.some((line) => line.startsWith("dispatched fix-ci #7 ")), once.lines.join("\n"));
  // A stop in another workflow run marks only that run.
  const other = await run({ pages: [[pr(7)]], history: new Map([[head, pair]]), stops: new Map([[head, [stop("10:15", 2)]]]) });
  assert.ok(other.lines.some((line) => line.includes("head already has a pr-unblock / fix-ci check run")), other.lines.join("\n"));
  // A stopped pair and one failed run are three model runs, the per-head cap.
  const failed = { ...fixCi("11:00", 3, null), conclusion: "failure" };
  const capped = await run({ pages: [[pr(7)]], history: new Map([[head, [...pair, failed]]]), stops: new Map([[head, [stop("10:15", 1)]]]) });
  assert.ok(capped.lines.includes(`::warning::#7: head ${head}'s pr-unblock / fix-ci ran 3 time(s), the most one head gets; no fix-ci until a new push`), capped.lines.join("\n"));
  assert.deepEqual(capped.api.calls.dispatch, []);
  // Two stopped pairs are four model runs, past the cap.
  const twice = await run({
    pages: [[pr(7)]],
    history: new Map([[head, [...pair, fixCi("11:00", 3, "Passed: no changes"), fixCi("11:10", 3, "Fixed")]]]),
    stops: new Map([[head, [stop("10:15", 1), stop("11:15", 3)]]]),
  });
  assert.ok(twice.lines.some((line) => line.includes("ran 4 time(s), the most one head gets")), twice.lines.join("\n"));
});

// #10902's escalated head: the rollup holds only the newest fix-ci check, the
// rung-up's SUCCESS "Passed: no changes", which reads as a run that handled
// the head. The rollup's newest apply-patch check is a lane stop, so the
// listing pass leaves the head to the REST read, which ties that stop to the
// fix-ci check's run attempt, and the head gets its one same-head retry.
test("an escalated head whose rollup shows a passed fix-ci check is retried once from the REST lane stop", async () => {
  const head = "7".padStart(40, "a");
  const passed = { title: "Passed: no changes", completedAt: "2026-10-22T08:50:00Z" };
  const rollup = [lanes("FAILURE"), check("pr-unblock / fix-ci", "SUCCESS", passed), check("pr-unblock / apply-patch", "NEUTRAL", { title: "Skipped: lane-stopped" })];
  const fixCi = { ...toRest(check("pr-unblock / fix-ci", "SUCCESS", passed)), started_at: "2026-10-22T08:40:00Z", external_id: "pr-unblock:fix-ci:40843021992:1" };
  const stop = { ...toRest(check("pr-unblock / apply-patch", "NEUTRAL", { title: "Skipped: lane-stopped" })), started_at: "2026-10-22T08:50:00Z", external_id: "pr-unblock:apply-patch:40843021992:1" };
  const { api, lines } = await run({ pages: [[pr(7, { checks: rollup })]], history: new Map([[head, [fixCi]]]), stops: new Map([[head, [stop]]]) });
  assert.deepEqual(api.calls.dispatch.map((call) => call.inputs["pr-number"]), ["7"], lines.join("\n"));
  // With no lane stop, the passed check handles the head.
  const handled = await run({ pages: [[pr(7, { checks: rollup })]], history: new Map([[head, [fixCi]]]) });
  assert.deepEqual(handled.api.calls.dispatch, []);
  assert.ok(handled.lines.includes("skip fix-ci #7: head already has a pr-unblock / fix-ci check run"), handled.lines.join("\n"));
  // With no stop in the rollup, the listing pass skips the head unread.
  const unread = await run({ pages: [[pr(7, { checks: rollup.slice(0, 2) })]], history: new Map([[head, [fixCi]]]) });
  assert.deepEqual([unread.api.calls.dispatch, unread.api.calls.history], [[], []]);
});

// Run 41217248303's refusal, on the push job instead of its report job: the
// model's patch never landed, so the passed fix-ci check does not handle the
// head. Any other push job failure still does.
test("a head whose apply-patch failed on a token refusal is retried; any other apply-patch failure is not", async () => {
  const head = "7".padStart(40, "a");
  const passed = { title: "Passed: 1 commit", completedAt: "2026-10-22T08:50:00Z" };
  const failed = check("pr-unblock / apply-patch", "FAILURE", { title: "Failed" });
  const rollup = [lanes("FAILURE"), check("pr-unblock / fix-ci", "SUCCESS", passed), failed];
  const fixCi = { ...toRest(check("pr-unblock / fix-ci", "SUCCESS", passed)), started_at: "2026-10-22T08:40:00Z", external_id: "pr-unblock:fix-ci:41217248303:1" };
  const stop = (summary) => {
    const rest = toRest(failed);
    return { ...rest, output: { ...rest.output, summary }, started_at: "2026-10-22T08:50:00Z", external_id: "pr-unblock:apply-patch:41217248303:1" };
  };
  const refused = stop("The run job did not succeed: lane-token-denied: the broker answered 403 with reason workflow-modified: .github/workflows/pr-unblock-dispatch.yml differs from refs/heads/main");
  const { api, lines } = await run({ pages: [[pr(7, { checks: rollup })]], history: new Map([[head, [fixCi]]]), stops: new Map([[head, [refused]]]) });
  assert.deepEqual(api.calls.dispatch.map((call) => call.inputs["pr-number"]), ["7"], lines.join("\n"));
  const other = await run({ pages: [[pr(7, { checks: rollup })]], history: new Map([[head, [fixCi]]]), stops: new Map([[head, [stop("The run job did not succeed.")]]]) });
  assert.deepEqual(other.api.calls.dispatch, []);
  assert.ok(other.lines.includes("skip fix-ci #7: head already has a pr-unblock / fix-ci check run"), other.lines.join("\n"));
});

// A re-run is the same run id at its next attempt (external_id
// `<lane>:<activity>:<run id>:<run attempt>`), so a stop marks only the
// attempt it followed.
test("a stop in a run's first attempt leaves the head handled when the re-run fixed it", async () => {
  const head = "7".padStart(40, "a");
  const at = (time) => `2026-10-22T${time}:00Z`;
  const fixCi = (time, attempt) => ({ name: "pr-unblock / fix-ci", status: "completed", conclusion: "success", output: { title: "Fixed" }, started_at: at(time), completed_at: at(time), external_id: `pr-unblock:fix-ci:40700900804:${attempt}` });
  const stop = (time, attempt) => ({ name: "pr-unblock / apply-patch", status: "completed", conclusion: "neutral", output: { title: "Skipped: lane-stopped" }, started_at: at(time), external_id: `pr-unblock:apply-patch:40700900804:${attempt}` });
  const rerun = await run({ pages: [[pr(7)]], history: new Map([[head, [fixCi("10:00", 1), fixCi("10:30", 2)]]]), stops: new Map([[head, [stop("10:05", 1)]]]) });
  assert.ok(rerun.lines.some((line) => line.includes("head already has a pr-unblock / fix-ci check run")), rerun.lines.join("\n"));
  assert.deepEqual(rerun.api.calls.dispatch, []);
  // A stop in the same attempt still marks it.
  const same = await run({ pages: [[pr(7)]], history: new Map([[head, [fixCi("10:00", 1)]]]), stops: new Map([[head, [stop("10:05", 1)]]]) });
  assert.ok(same.lines.some((line) => line.startsWith("dispatched fix-ci #7 ")), same.lines.join("\n"));
});

// A head whose fix-ci stop still fails after its checks went green (a flaky
// check re-run past ci-fix-escalated): fix-ci runs once more there, finds
// nothing failing, and report-stop-status clears the status.
const fixCiStop = (state = "FAILURE", creator = ACTIONS_BOT) => ({ __typename: "StatusContext", context: "pr-unblock/fix-ci", state, createdAt: "2026-10-22T11:00:00Z", creator });
const settled = (checks, extra = {}) =>
  pr(9, { ...extra, commits: { nodes: [{ commit: { oid: "9".padStart(40, "a"), statusCheckRollup: { contexts: { nodes: checks, pageInfo: { hasNextPage: false } } } } }] } });
const green = [lanes("SUCCESS"), check("lint", "SUCCESS"), check("ci-status", "FAILURE"), fixCiStop()];

test("a head whose fix-ci stop fails with every check passed is dispatched fix-ci once", async () => {
  const { api, result } = await run({ pages: [[settled(green)]] });
  assert.deepEqual(result, { dispatched: [{ number: 9, workflowRunId: "7009" }], failed: 0 });
  assert.deepEqual(api.calls.dispatch.map((call) => call.inputs), [{ "pr-number": "9", activity: "fix-ci", "dispatcher-run-id": "4242" }]);
  const error = await run({ pages: [[settled([lanes("SUCCESS"), fixCiStop("ERROR")])]] });
  assert.equal(error.api.calls.dispatch.length, 1);
});

test("a fix-ci stop is left on a head with a check failing or going, a run since the stop, another account's status or a hold label", async () => {
  for (const [label, page, options] of [
    ["a check is going", settled([lanes("SUCCESS"), check("lint", null), fixCiStop()]), {}],
    ["the stop passed", settled([lanes("SUCCESS"), fixCiStop("SUCCESS")]), {}],
    ["another account's status", settled([lanes("SUCCESS"), fixCiStop("FAILURE", { __typename: "User", databaseId: 1 })]), {}],
    ["do-not-merge", settled(green, { labels: { nodes: [{ name: "do-not-merge" }] } }), {}],
    ["a person's PR", settled(green, { author: { login: "someone", databaseId: 1 } }), {}],
    ["a run since the stop", settled(green), { workflowRuns: [{ id: 3, status: "completed", display_title: "pr-unblock fix-ci #9", created_at: "2026-10-22T11:30:00Z" }] }],
  ]) {
    const { api } = await run({ pages: [[page]], ...options });
    assert.deepEqual(api.calls.dispatch, [], label);
  }
  // A failing check is a fix to make, not a stop to clear.
  const opts = { base: "main", appSenderId: APP, holdLabels: ["do-not-merge"], gateLabel: "needs-human" };
  assert.equal(staleStop(settled([lanes("SUCCESS"), check("lint", "FAILURE"), fixCiStop()]), opts), null);
  assert.equal(staleStop(settled(green), opts).state, "FAILURE");
  // A run from before the stop does not hold it.
  const older = await run({ pages: [[settled(green)]], workflowRuns: [{ id: 2, status: "completed", display_title: "pr-unblock fix-ci #9", created_at: "2026-10-22T10:00:00Z" }] });
  assert.equal(older.api.calls.dispatch.length, 1);
});
