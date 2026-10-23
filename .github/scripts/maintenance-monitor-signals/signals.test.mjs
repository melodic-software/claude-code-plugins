// Each signal fires on a positive and stays quiet on a negative. Thresholds
// come from the signal list the lane implements (over 90%, over 2 ejections a
// day, held over 24 hours, 0 merges for 3 hours); annotation and status-page
// shapes are copied from real pr-merge, broker and githubstatus.com output.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  auditFindings,
  ceilingFindings,
  detect,
  ejectionFindings,
  heldFindings,
  mainRedFindings,
  parseBudget,
  platformFindings,
  throttleFindings,
  throughputFindings,
} from "./signals.mjs";

const now = new Date("2026-10-19T16:41:00Z");
const windowStart = new Date("2026-10-19T15:36:00Z");
const base = { now, windowStart };

const reading = (name, used, limit, extra = {}) => ({
  runId: 1,
  url: "https://github.com/o/r/actions/runs/1",
  phase: "end",
  name,
  used,
  limit,
  remaining: limit - used,
  ...extra,
});

test("parseBudget reads pr-merge's api-budget notice", () => {
  assert.deepEqual(
    parseBudget(
      "end lane core remaining=4235 used=965 limit=5200 reset=2026-10-19T19:50:58Z graphql remaining=5146 used-since-start=window-rolled",
    ),
    { phase: "end", name: "lane", remaining: 4235, used: 965, limit: 5200 },
  );
  assert.equal(parseBudget("end lane core remaining=unknown used=unknown limit=unknown reset=unknown"), null);
  assert.deepEqual(
    parseBudget(
      "token=lanes-app workflow=.github/workflows/pr-merge.yml job=merge run=1 attempt=1 limit=5200 remaining=494 used=4706 reset=1792378942 resource=core cost=na",
    ),
    { phase: "end", name: "lanes-app", remaining: 494, used: 4706, limit: 5200 },
  );
  assert.equal(parseBudget("token=lanes-app workflow=w job=j run=1 attempt=1 limit=na remaining=na used=na reset=na resource=na cost=na"), null);
  assert.equal(parseBudget("token=lanes-app workflow=w job=j run=1 attempt=1 limit=5000 remaining=1 used=4999 reset=1 resource=graphql cost=na"), null);
});

test("signal 2: a lane reading over 90% fires, 90% exactly stays quiet", () => {
  // 4706 of 5200 is 90.5%.
  const hot = ceilingFindings({ ...base, budgetReadings: [reading("lane", 4706, 5200)] });
  assert.deepEqual(
    hot.map((f) => f.key),
    ["ceiling:lanes-app-rest"],
  );
  assert.match(hot[0].summary, /90\.5%/);
  assert.deepEqual(ceilingFindings({ ...base, budgetReadings: [reading("lane", 4680, 5200)] }), []);
  assert.deepEqual(
    ceilingFindings({ ...base, budgetReadings: [reading("lanes-app", 4706, 5200)] }).map((f) => f.key),
    ["ceiling:lanes-app-rest"],
  );
});

test("signal 2: GITHUB_TOKEN and Actions jobs have their own keys", () => {
  const found = ceilingFindings({
    ...base,
    budgetReadings: [reading("github-token", 951, 1000)],
    jobsInUse: { inProgress: 55, sampledRuns: 9, truncated: false },
  });
  assert.deepEqual(found.map((f) => f.key).sort(), ["ceiling:actions-jobs", "ceiling:github-token"]);
  assert.deepEqual(
    ceilingFindings({ ...base, jobsInUse: { inProgress: 54, sampledRuns: 9, truncated: false } }),
    [],
  );
});

test("signal 2: the fingerprint holds for a day, so a sustained ceiling comments once a day", () => {
  const a = ceilingFindings({ ...base, budgetReadings: [reading("lane", 4800, 5200)] })[0];
  const b = ceilingFindings({
    ...base,
    now: new Date("2026-10-19T20:41:00Z"),
    budgetReadings: [reading("lane", 5000, 5200)],
  })[0];
  const c = ceilingFindings({
    ...base,
    now: new Date("2026-10-20T00:41:00Z"),
    budgetReadings: [reading("lane", 5000, 5200)],
  })[0];
  assert.equal(a.fingerprint, b.fingerprint);
  assert.notEqual(a.fingerprint, c.fingerprint);
});

const denied = (id, message, name = "pr-merge") => ({
  id,
  url: `https://github.com/o/r/actions/runs/${id}`,
  name,
  event: "schedule",
  annotations: [
    { level: "failure", message: "Process completed with exit code 1." },
    { level: "failure", message },
  ],
});

test("signal 3: a broker 500 deny fires under its status and reason", () => {
  const found = throttleFindings({
    ...base,
    failedRuns: [
      denied(39270616578, "lane-token-denied: the broker answered 500 with reason unknown"),
      denied(39268726986, "lane-token-denied: the broker answered 500 with reason unknown"),
    ],
  });
  assert.deepEqual(
    found.map((f) => f.key),
    ["broker-deny:500-unknown"],
  );
  assert.match(found[0].summary, /2 runs/);
});

test("signal 3: a rate-limited deny, a 429 and an exhausted reading are one throttling key", () => {
  const found = throttleFindings({
    ...base,
    failedRuns: [
      denied(
        5,
        "lane-token-denied: the broker answered 503 with reason github-rate-limited; GitHub's primary rate limit (core) resets at 2026-10-19T16:00:00Z, past the 8-minute retry budget",
      ),
      denied(6, "gh: HTTP 429: too many requests", "pr-unblock"),
    ],
    budgetReadings: [reading("lane", 5200, 5200)],
  });
  assert.deepEqual(
    found.map((f) => f.key),
    ["throttle:rate-limited"],
  );
  assert.match(found[0].summary, /3 /);
});

test("signal 3: workflow-modified, a contract-only yield and plain failures stay quiet", () => {
  assert.deepEqual(
    throttleFindings({
      ...base,
      failedRuns: [
        denied(7, "lane-token-denied: the broker answered 403 with reason workflow-modified: .github/workflows/pr-refine.yml differs from refs/heads/main"),
        denied(8, "ci-status: yield-to-full-run: a full run covers this head", "pr-require-checks"),
        denied(9, "Process completed with exit code 2."),
      ],
      budgetReadings: [reading("lane", 100, 5200)],
    }),
    [],
  );
});

const mainRun = (jobs, conclusion = "failure") => ({
  id: 77,
  url: "https://github.com/o/r/actions/runs/77",
  sha: "b78499158b12bf99436750827583d57fda30a031",
  event: "workflow_dispatch",
  conclusion,
  failedJobs: jobs,
});

test("signal 1: main red fires per failing job from its failure-level annotations", () => {
  const found = mainRedFindings({
    ...base,
    mainRun: mainRun([
      {
        name: "test-bash (3/4)",
        conclusion: "failure",
        annotations: [
          { level: "warning", message: "a warning is not evidence" },
          { level: "failure", message: "not ok 12 - scripts/foo.test.sh" },
        ],
      },
    ]),
  });
  assert.deepEqual(
    found.map((f) => f.key),
    ["main-red:test-bash"],
  );
  assert.ok(found[0].facts.some((line) => line.includes("not ok 12")));
  assert.ok(!found[0].facts.some((line) => line.includes("a warning")));
  assert.ok(found[0].facts.includes("flake class: not known"));
});

test("signal 1: a timed-out job is named as the timeout flake class", () => {
  const [finding] = mainRedFindings({
    ...base,
    mainRun: mainRun([
      {
        name: "test-python",
        conclusion: "timed_out",
        annotations: [{ level: "failure", message: "The job has exceeded the maximum execution time of 30m0s" }],
      },
    ]),
  });
  assert.ok(finding.facts.includes("flake class: timeout"));
});

test("signal 1: a green main, or a red job with no failure annotation, stays quiet", () => {
  assert.deepEqual(mainRedFindings({ ...base, mainRun: mainRun([], "success") }), []);
  assert.deepEqual(
    mainRedFindings({
      ...base,
      mainRun: mainRun([{ name: "lint", conclusion: "failure", annotations: [{ level: "notice", message: "x" }] }]),
    }),
    [],
  );
  assert.deepEqual(mainRedFindings({ ...base, mainRun: null }), []);
});

const ejection = (id, pr) => ({
  id,
  url: `https://github.com/o/r/actions/runs/${id}`,
  pr,
  workflow: "pr-require-checks",
  createdAt: "2026-10-19T15:00:00Z",
  failedSteps: ["test-bash (1/4) / Run the suites"],
});

test("signal 4: 3 ejections in a day fire, 2 stay quiet", () => {
  const found = ejectionFindings({ ...base, mergeGroupFailures: [ejection(1, 8225), ejection(2, 8031), ejection(3, 8223)] });
  assert.deepEqual(
    found.map((f) => f.key),
    ["merge-queue-ejections"],
  );
  assert.ok(found[0].facts.some((line) => line.includes("#8225") && line.includes("Run the suites")));
  assert.deepEqual(ejectionFindings({ ...base, mergeGroupFailures: [ejection(1, 8225), ejection(2, 8031)] }), []);
});

const row = (pr, updatedAt, extra = {}) => ({
  pr,
  ready: false,
  enqueued: false,
  merged: false,
  reason: "risk:MED",
  updatedAt,
  ...extra,
});
const sweep = (results, extra = {}) => ({
  runId: 39307260310,
  url: "https://github.com/o/r/actions/runs/39307260310",
  live: true,
  startedAt: "2026-10-19T16:30:00Z",
  candidates: 10,
  results,
  ...extra,
});

test("signal 5: PRs blocked and untouched over 24 hours batch into one issue", () => {
  const found = heldFindings({
    ...base,
    sweep: sweep([
      row(8232, "2026-10-18T11:29:43Z", { reason: "prefilter:needs-human" }),
      row(8057, "2026-10-18T06:28:02Z", { reason: "verify:missing" }),
      row(8056, "2026-10-19T14:19:28Z"),
      row(8100, "2026-10-17T00:00:00Z", { enqueued: true }),
    ]),
  });
  assert.equal(found.length, 1);
  assert.equal(found[0].key, "held-over-24h");
  assert.deepEqual(
    found[0].facts.map((line) => /#(\d+)/.exec(line)?.[1]).filter(Boolean),
    ["8057", "8232"],
  );
  assert.deepEqual(heldFindings({ ...base, sweep: sweep([row(8056, "2026-10-19T14:19:28Z")]) }), []);
});

test("signal 6: a failed scheduled audit fires per workflow, a green one stays quiet", () => {
  const found = auditFindings({
    ...base,
    audits: [
      {
        workflow: "maintenance-audit-test-selection",
        run: { id: 5, url: "https://github.com/o/r/actions/runs/5", conclusion: "failure", createdAt: "2026-10-19T10:43:00Z", failedJobs: ["audit-test-selection"] },
      },
      {
        workflow: "maintenance-check-upstream-drift",
        run: { id: 6, url: "https://github.com/o/r/actions/runs/6", conclusion: "success", createdAt: "2026-10-13T10:29:00Z", failedJobs: [] },
      },
    ],
  });
  assert.deepEqual(
    found.map((f) => f.key),
    ["audit:maintenance-audit-test-selection"],
  );
});

const incident = {
  id: "8tzbpcnl75jp",
  name: "Degraded availability for GitHub Actions, GitHub Pages and Webhooks",
  status: "investigating",
  created_at: "2026-10-19T15:49:25.828Z",
  updated_at: "2026-10-19T16:20:00.000Z",
  shortlink: "https://stspg.io/nrv2k8s68bwn",
  components: ["Webhooks", "Actions", "Pages"],
};

test("signal 7: an Actions incident fires once per incident", () => {
  const found = platformFindings({
    ...base,
    status: { components: [{ name: "Actions", status: "partial_outage" }], incidents: [incident] },
  });
  assert.deepEqual(
    found.map((f) => f.key),
    ["platform:8tzbpcnl75jp"],
  );
});

test("signal 7: a short incident resolved inside the window still fires", () => {
  const found = platformFindings({
    ...base,
    status: { components: [{ name: "Actions", status: "operational" }], incidents: [{ ...incident, status: "resolved" }] },
  });
  assert.equal(found.length, 1);
});

test("signal 7: Actions degraded with no incident fires; other components and old incidents stay quiet", () => {
  assert.deepEqual(
    platformFindings({ ...base, status: { components: [{ name: "Actions", status: "degraded_performance" }], incidents: [] } }).map(
      (f) => f.key,
    ),
    ["platform:actions"],
  );
  assert.deepEqual(
    platformFindings({
      ...base,
      status: {
        components: [
          { name: "Actions", status: "operational" },
          { name: "Copilot", status: "major_outage" },
        ],
        incidents: [
          { ...incident, components: ["Copilot"] },
          { ...incident, id: "old", status: "resolved", created_at: "2026-10-18T09:00:00Z", updated_at: "2026-10-18T10:00:00Z" },
        ],
      },
    }),
    [],
  );
});

test("signal 8: no lane merge for 3 hours with countable PRs fires", () => {
  const found = throughputFindings({
    ...base,
    sweep: sweep([]),
    laneMerges: { lastMergedAt: "2026-10-19T13:30:00Z" },
  });
  assert.deepEqual(
    found.map((f) => f.key),
    ["throughput-zero"],
  );
});

test("signal 8: a recent merge, no countable PR, or a report-only lane stays quiet", () => {
  const quiet = (sweepValue, lastMergedAt) =>
    throughputFindings({ ...base, sweep: sweepValue, laneMerges: { lastMergedAt } });
  assert.deepEqual(quiet(sweep([]), "2026-10-19T14:00:00Z"), []);
  assert.deepEqual(quiet(sweep([], { candidates: 0 }), "2026-10-19T10:00:00Z"), []);
  assert.deepEqual(quiet(sweep([], { live: false }), "2026-10-19T10:00:00Z"), []);
  assert.deepEqual(quiet(null, "2026-10-19T10:00:00Z"), []);
  // A sweep over 70 minutes old means pr-merge is not running (the kill
  // switch, say), which this signal does not judge.
  assert.deepEqual(quiet(sweep([], { startedAt: "2026-10-19T15:00:00Z" }), "2026-10-19T10:00:00Z"), []);
});

test("signal 8: a stall keeps its fingerprint until a merge lands", () => {
  const at = (iso) =>
    throughputFindings({
      ...base,
      now: new Date(iso),
      sweep: sweep([], { startedAt: iso }),
      laneMerges: { lastMergedAt: "2026-10-19T10:00:00Z" },
    })[0].fingerprint;
  assert.equal(at("2026-10-19T14:41:00Z"), at("2026-10-19T18:41:00Z"));
});

const stop = (id, outcome, issue = 7677) => ({
  id,
  outcome,
  issue,
  url: `https://github.com/o/r/issues/${issue}#issuecomment-${id}`,
  createdAt: "2026-10-19T16:00:00Z",
});

test("signal 9: funding, limited and turn-cap stops fire one key each", () => {
  const found = detect({ ...base, laneStops: [stop(1, "funding"), stop(2, "limited"), stop(3, "turn-cap", 42), stop(4, "turn-cap")] });
  assert.deepEqual(found.map((f) => f.key).sort(), ["lane-stop:funding", "lane-stop:limited", "lane-stop:turn-cap"]);
  assert.deepEqual(found.find((f) => f.key === "lane-stop:turn-cap").facts.length, 2);
});

test("signal 9: done, pushback and stopped outcomes stay quiet", () => {
  assert.deepEqual(detect({ ...base, laneStops: [stop(1, "done"), stop(2, "pushback"), stop(3, "stopped")] }), []);
});

test("signal 9: the fingerprint holds for the same stops and changes on a new one", () => {
  const fp = (stops) => detect({ ...base, laneStops: stops })[0].fingerprint;
  assert.equal(fp([stop(1, "limited"), stop(2, "limited")]), fp([stop(2, "limited"), stop(1, "limited")]));
  assert.notEqual(fp([stop(1, "limited")]), fp([stop(1, "limited"), stop(2, "limited")]));
  // A stop seen again in the next run's window overlap keeps the fingerprint.
  assert.equal(fp([stop(1, "limited"), stop(2, "limited")]), fp([stop(2, "limited")]));
});

test("detect runs every signal, and empty data files nothing", () => {
  assert.deepEqual(detect({ ...base }), []);
  const keys = detect({
    ...base,
    budgetReadings: [reading("lane", 4706, 5200)],
    mergeGroupFailures: [ejection(1, 1), ejection(2, 2), ejection(3, 3)],
  }).map((f) => f.key);
  assert.deepEqual(keys.sort(), ["ceiling:lanes-app-rest", "merge-queue-ejections"]);
});

test("every finding has a marker-safe key, a hex fingerprint, an area and inert facts", () => {
  const found = detect({
    ...base,
    failedRuns: [denied(1, "lane-token-denied: the broker answered 500 with reason unknown ```\n@someone [x](http://e)")],
    mainRun: mainRun([{ name: "lint `x` <b>", conclusion: "failure", annotations: [{ level: "failure", message: "bad ``` text" }] }]),
  });
  assert.ok(found.length >= 2);
  for (const f of found) {
    assert.match(f.key, /^[a-z0-9][a-z0-9:._-]{0,79}$/);
    assert.match(f.fingerprint, /^[0-9a-f]{16}$/);
    assert.ok(f.area.length > 0);
    for (const line of f.facts) assert.doesNotMatch(line, /`|\n/);
  }
});
