// Each signal fires on a positive and stays quiet on a negative. Thresholds
// come from the signal list the lane implements (over 90%, over 2 ejections a
// day, held over 24 hours, 0 merges for 3 hours); annotation and status-page
// shapes are copied from real pr-merge, broker and githubstatus.com output.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { closing } from "../intake-triage/apply-verdict.mjs";
import { closing as resolverClosing, HELD_STEP } from "../pr-verify/resolve-pr.mjs";
import {
  auditFindings,
  ceilingFindings,
  detect,
  ejectionFindings,
  heldFindings,
  holdJob,
  HOLD_LANES,
  holdRule,
  laneHoldFindings,
  mainRedFindings,
  parseBudget,
  parseHold,
  platformFindings,
  POST_MERGE_UNREADABLE_SWEEPS,
  LISTING_HELD_SWEEPS,
  listingHeldFindings,
  postMergeUnreadableFindings,
  stalledFindings,
  throttleFindings,
  throughputFindings,
  laneVariableFindings,
} from "./signals.mjs";
import { VARIABLES_CHANGED, VARIABLES_UNREAD } from "../work-unblock/publish-lane-level.mjs";

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
        "lane-token-denied: the broker answered 503 with reason github-rate-limited; GitHub's primary rate limit (core) resets at 2026-10-19T16:00:00Z, past the 1-minute retry budget",
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
        name: "Test Bash (3/4)",
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
        name: "Test Python",
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
  failedSteps: ["Test Bash (1/4) / Run the suites"],
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

test("signal 9: a failed stop, which adds no label, fires its own key", () => {
  const found = detect({ ...base, laneStops: [stop(1, "failed", 42)] });
  assert.deepEqual(found.map((f) => f.key), ["lane-stop:failed"]);
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

// collect.mjs hands on only stops past STALLED_HOURS with no attempt since;
// one finding names each, and its fingerprint moves only with the set.
test("stalled stops are one finding, a fact per PR, whose fingerprint moves with the stopped heads only", () => {
  const stop = (pr, extra = {}) => ({ pr, head: "a".repeat(40), activity: "fix-ci", reason: "ci-fix-invalid", stoppedAt: "2026-10-19T12:00:00Z", url: `https://github.com/o/r/pull/${pr}#c`, ...extra });
  assert.deepEqual(stalledFindings({ stalledStops: [] }), []);
  const [f] = stalledFindings({ stalledStops: [stop(9), stop(4, { activity: "resolve-conflicts", reason: "conflict-patch-invalid" })] });
  assert.equal(f.key, "stalled-lane-stop");
  assert.equal(f.signal, "10 stalled lane stop");
  assert.match(f.title, /^Stalled: 2 pull request stops/);
  assert.deepEqual(f.facts, [
    "#4 resolve-conflicts conflict-patch-invalid since 2026-10-19T12:00:00Z: https://github.com/o/r/pull/4#c",
    "#9 fix-ci ci-fix-invalid since 2026-10-19T12:00:00Z: https://github.com/o/r/pull/9#c",
  ]);
  const [again] = stalledFindings({ stalledStops: [stop(4, { activity: "resolve-conflicts", reason: "conflict-patch-invalid", stoppedAt: "later" }), stop(9)] });
  assert.equal(again.fingerprint, f.fingerprint, "the stop's time is not evidence");
  const [moved] = stalledFindings({ stalledStops: [stop(9, { head: "b".repeat(40) })] });
  assert.notEqual(moved.fingerprint, f.fingerprint);
  assert.ok(detect({ ...base, stalledStops: [stop(9)] }).some((x) => x.key === "stalled-lane-stop"));
});

// collect.mjs hands on the newest reports, newest first, stopping at the first
// readable one: code is the post-merge-code file's text.
// The reason a real exit-3 report carried (pr-merge run 41067582241, 2026-10-30).
const CAP = "unreadable: post-merge-detect-silent-revert.yml push runs: total_count 1239, 1000 returned, at the 1000-run search cap";
const report = (runId, code = "3", reason = CAP) => ({
  runId,
  url: `https://github.com/o/r/actions/runs/${runId}`,
  code,
  reason,
  createdAt: `2026-10-30T${String(11 + (runId % 10)).padStart(2, "0")}:00:00Z`,
});

const heldSweep = (runId, reason = "failed 3 times") => ({
  runId,
  url: `https://github.com/o/r/actions/runs/${runId}`,
  reason,
  createdAt: `2026-10-30T${String(11 + (runId % 10)).padStart(2, "0")}:00:00Z`,
});

test("signal 12: 3 held sweeps stay quiet, the 4th in a row fires one finding naming why", () => {
  assert.equal(LISTING_HELD_SWEEPS, 4);
  assert.deepEqual(listingHeldFindings({ heldSweeps: [heldSweep(3), heldSweep(2), heldSweep(1)] }), []);
  assert.deepEqual(listingHeldFindings({}), []);
  const found = detect({ ...base, heldSweeps: [heldSweep(5), heldSweep(4), heldSweep(3), heldSweep(2), heldSweep(1)] });
  assert.equal(found.length, 1);
  const [f] = found;
  assert.equal(f.key, "listing-held");
  assert.equal(f.signal, "12 listing held");
  assert.match(f.summary, /failed 3 times/);
  assert.match(f.summary, /actions\/runs\/5/);
  assert.equal(f.facts.length, 4);
  assert.equal(f.observedAt, heldSweep(5).createdAt);
});

test("signal 3: a listing a rate limit held in the window counts, though its run is green", () => {
  const at = (runId, reason, createdAt) => ({ ...heldSweep(runId, reason), createdAt });
  const limited = "rate limited (the core pool until 2026-10-19T17:00:00Z)";
  const found = throttleFindings({
    ...base,
    heldSweeps: [at(2, limited, "2026-10-19T16:30:00Z"), at(1, "failed 3 times (count mismatch)", "2026-10-19T16:15:00Z")],
  });
  assert.deepEqual(found.map((f) => f.key), ["throttle:rate-limited"]);
  assert.match(found[0].summary, /^1 occurrences across 1 runs/);
  assert.match(found[0].facts[0], /actions\/runs\/2: rate limited \(the core pool/);
  assert.deepEqual(throttleFindings({ ...base, heldSweeps: [at(2, "failed 3 times", "2026-10-19T16:30:00Z")] }), []);
  // Before the window, as every other signal 3 source.
  assert.deepEqual(throttleFindings({ ...base, heldSweeps: [at(2, limited, "2026-10-19T12:00:00Z")] }), []);
});

test("signal 12: the fingerprint holds while the cause holds, through new runs and reset times", () => {
  const fp = (sweeps) => listingHeldFindings({ heldSweeps: sweeps })[0].fingerprint;
  const limited = (id, at) => heldSweep(id, `rate limited (core until 2026-10-30T${at}:00:00Z)`);
  const now = [limited(4, "10"), limited(3, "10"), limited(2, "09"), limited(1, "09")];
  assert.equal(fp(now), fp([limited(5, "11"), ...now.slice(0, 3)]));
  assert.notEqual(fp(now), fp([heldSweep(5), ...now.slice(0, 3)]));
});

test("signal 11: 3 unreadable sweeps stay quiet, the 4th in a row fires one finding naming the read error", () => {
  assert.equal(POST_MERGE_UNREADABLE_SWEEPS, 4);
  assert.deepEqual(postMergeUnreadableFindings({ postMergeReports: [report(3), report(2), report(1)] }), []);
  const found = detect({ ...base, postMergeReports: [report(4), report(3), report(2), report(1)] });
  assert.equal(found.length, 1);
  const [f] = found;
  assert.equal(f.key, "post-merge-unreadable");
  assert.equal(f.signal, "11 post-merge unreadable");
  assert.match(f.summary, /at the 1000-run search cap/);
  assert.match(f.summary, /actions\/runs\/4/);
  assert.equal(f.facts.length, 4);
  assert.equal(f.observedAt, report(4).createdAt);
});

test("signal 11: a readable sweep among the newest 4 clears it, whatever its code", () => {
  for (const code of ["0", "5", "1", "2", "4"]) {
    assert.deepEqual(postMergeUnreadableFindings({ postMergeReports: [report(4, code, null), report(3), report(2), report(1)] }), [], code);
    assert.deepEqual(postMergeUnreadableFindings({ postMergeReports: [report(4), report(3, code, null), report(2), report(1)] }), [], code);
  }
  assert.deepEqual(postMergeUnreadableFindings({}), []);
});

test("signal 11: the fingerprint holds while the cause holds, through new runs and counts", () => {
  const fp = (reports) => postMergeUnreadableFindings({ postMergeReports: reports })[0].fingerprint;
  const later = [5, 4, 3, 2].map((id) => report(id, "3", CAP.replace("1239", "1302")));
  assert.equal(fp([report(4), report(3), report(2), report(1)]), fp(later));
  assert.notEqual(fp(later), fp([report(5, "3", "pull requests: HTTP 502"), report(4), report(3), report(2)]));
});

// The three hold notices as their scripts print them (report-outcome.mjs,
// label-unblocked.mjs reportHold, handoff-evidence.sh), title and message.
const FAULT = ["report-outcome", "issue #812 stopped on a fault (outcome-unread), and every retry since a person last added agent-ready was one too; it keeps agent-ready and a later run tries again"];
const LISTING = ["label-unblocked", "the closed-issue listing failed (GET /repos/o/r/issues: HTTP 502); holding, and the next sweep reads it again"];
const HANDOFF = ["Handoff evidence hold", "handoff evidence for fix-docs still missing after 3 reads: read-failed; no fallback starts, and the next dispatcher tick sends the PR again"];

test("signal 13: each lane's hold notice parses, and other notices do not", () => {
  assert.deepEqual(parseHold(...FAULT), { item: "#812", reason: "fault outcome-unread" });
  assert.deepEqual(parseHold(...LISTING), { item: null, reason: "closed-issue listing failed" });
  assert.deepEqual(parseHold(...HANDOFF), { item: null, reason: "fix-docs handoff evidence missing" });
  assert.equal(parseHold("api-budget", LISTING[1]), null);
  assert.equal(parseHold("report-outcome", "could not read this issue's earlier work (HTTP 502); the model is skipped, and a later run reads it again"), null);
  assert.equal(parseHold(undefined, "handoff evidence for fix-docs still missing after 3 reads: x; the outputs stay empty"), null);
});

// label-unblocked.mjs failedFor's notice for one issue's faulted read.
test("signal 13: work-unblock's held issue read parses to the issue and the status", () => {
  const issueHold = (message) => parseHold("label-unblocked", message);
  assert.deepEqual(issueHold("#20: GET /repos/o/r/issues/20 failed with status 503; holding, and the next sweep reads it again"), { item: "#20", reason: "read fault HTTP 503" });
  // A network fault names no status.
  assert.deepEqual(issueHold("#7: fetch failed; holding, and the next sweep reads it again"), { item: "#7", reason: "read fault" });
  // The run-ending error for the same issue, and another title, are no hold.
  assert.equal(issueHold("#20: GET /repos/o/r/issues/20 failed with status 404"), null);
  assert.equal(parseHold("report-outcome", "#20: fetch failed; holding, and the next sweep reads it again"), null);
});

// apply-verdict.mjs closing's own annotation line, split as the runner splits
// `::notice title=<title>::<message>`, so producer and parser are one contract.
const annotation = (line) => /^::notice title=([^:]+)::(.*)$/.exec(line).slice(1);
const verdictHold = (closed) => parseHold(...annotation(closed.lines[0]));

test("signal 13: intake-triage's held verdict parses to a fixed reason with no item", () => {
  assert.deepEqual(verdictHold(closing({ error: new GitHubError(502, "GET /repos/o/r/issues/7") })), { item: null, reason: "fault HTTP 502" });
  const admission = { admission: { outcome: "error", fault: true, reasons: ["GET /repos/o/r/issues/7/timeline failed with status 503"] } };
  assert.deepEqual(verdictHold(closing({ result: admission })), { item: null, reason: "admission fault HTTP 503" });
  // A network fault names no status.
  assert.deepEqual(verdictHold(closing({ error: new TypeError("fetch failed") })), { item: null, reason: "fault" });
  // Its error line and another title's held: text are no hold.
  const red = closing({ error: new Error("models.issue-dimensions maps no option 7") }).lines[0];
  assert.equal(parseHold("apply-verdict", /::(.*)$/.exec(red)[1]), null);
  assert.equal(parseHold("pr-verify-capture", "held: pr-verify-capture could not resolve the pull request: x failed with status 502"), null);
  assert.equal(parseHold("apply-verdict", "apply-verdict does not apply (off); nothing written"), null);
});

test("signal 13: work-resolve-issue's WIP cap hold parses to a fixed reason per cause with no item", () => {
  // check-wip-cap.mjs's notice template and its causes, read from the script,
  // so producer and parser are one contract.
  const script = readFileSync(new URL("../../actions/check-wip-cap/check-wip-cap.mjs", import.meta.url), "utf8");
  const template = /`(WIP cap hold: \$\{unread\}[^`]*)`/.exec(script)[1];
  for (const [unread, reason] of [
    ["the base config could not be read", "WIP cap base config unread"],
    ["the open lane PRs could not be listed", "WIP cap open listing failed"],
  ]) {
    assert.ok(script.includes(`"${unread}"`), unread);
    assert.deepEqual(parseHold("WIP cap hold", template.replace("${unread}", unread)), { item: null, reason });
  }
  // pick-slot's step names a check that did not finish, read from the workflow itself.
  const workflow = readFileSync(new URL("../../workflows/work-resolve-issue.yml", import.meta.url), "utf8");
  const step = /run: echo "(::notice title=WIP cap hold::[^"]*)"/.exec(workflow)[1];
  assert.deepEqual(parseHold(...annotation(step)), { item: null, reason: "WIP cap check unfinished" });
  // A pause that was read is no hold.
  assert.equal(parseHold("admission paused", "admission paused: reason=wip countable=13 wip_cap=12 held=0 held_cap=10"), null);
  assert.ok(HOLD_LANES.find((l) => l.lane === "work-resolve-issue").jobs.includes("pick-slot"));
});

test("signal 13: pr-refine's unread PR head or hold parses to the PR and a fixed reason", () => {
  // fix-docs-head-held's step, read from the workflow itself, so producer and
  // parser are one contract.
  const workflow = readFileSync(new URL("../../workflows/pr-refine.yml", import.meta.url), "utf8");
  const template = /echo "(::notice title=PR head hold::[^"]*)"/.exec(workflow)[1].replace("$PR_NUMBER", "7");
  const step = template.replace("$what", "head");
  assert.deepEqual(parseHold(...annotation(step)), { item: "#7", reason: "PR head unread" });
  // lane-hold.mjs's fault hold: the step names the hold, not the head.
  assert.match(workflow, /\[\[ \$HOLD_UNREAD != true \]\] \|\| what="human-gated hold"/);
  assert.deepEqual(parseHold(...annotation(template.replace("$what", "human-gated hold"))), { item: "#7", reason: "PR hold unread" });
  assert.equal(parseHold("PR head hold", "no PR head SHA read for #7; fix-docs does not run"), null);
  assert.equal(parseHold("Handoff evidence hold", annotation(step)[1]), null);
  assert.ok(HOLD_LANES.find((l) => l.lane === "pr-refine").jobs.includes("fix-docs-head-held"));
  // A hold notice is read at notice level only.
  assert.equal(parseHold(...annotation(step), "warning"), null);
  // The same job's notice for a plan that could not read the changed files.
  const files = [...workflow.matchAll(/echo "(::notice title=PR head hold::[^"]*)"/g)].map((m) => m[1]).find((line) => line.includes("changed files"));
  assert.deepEqual(parseHold(...annotation(files.replace("$PR_NUMBER", "9"))), { item: "#9", reason: "PR files unread" });
});

test("signal 13: pr-refine's refine-failed warning parses to the pass and its closed reason, read from record-passes on red runs too", () => {
  assert.deepEqual(parseHold("refine-failed", "pass=fix-docs reason=apply-docs-patch-failure", "warning"), { item: null, reason: "fix-docs failed: apply-docs-patch-failure" });
  assert.equal(parseHold("refine-failed", "pass=fix-docs reason=apply-docs-patch-failure"), null, "notice level");
  assert.equal(parseHold("refine-failed", "pass=fix-docs reason=the run said: x", "warning"), null, "free text");
  const lane = HOLD_LANES.find((l) => l.lane === "pr-refine");
  assert.ok(lane.jobs.includes("record-passes"));
  assert.deepEqual(lane.statuses, ["success", "failure"]);
  // record-passes, in the workflow, runs the script that prints the warning.
  const workflow = readFileSync(new URL("../../workflows/pr-refine.yml", import.meta.url), "utf8");
  assert.match(workflow, /\n {2}record-passes:\n[\s\S]*?run: node \.base\/\.github\/scripts\/pr-refine\/log-pass-records\.mjs\n/);
});

test("signal 13: pr-verify's resolver and trigger-gate holds parse to fixed reasons with no item", () => {
  // Each from its producer: resolve-pr.mjs closing, and pr-verify.yml's
  // `Note the hold` step after the trigger gate in each of its three jobs.
  const resolver = resolverClosing(new GitHubError(502, "GET /repos/o/r/pulls/7"), {});
  assert.deepEqual(parseHold(...annotation(resolver.lines[0])), { item: null, reason: "resolver fault" });
  const workflow = readFileSync(new URL("../../workflows/pr-verify.yml", import.meta.url), "utf8");
  const gates = [...workflow.matchAll(/echo "(::notice title=pr-verify::held: pr-verify's trigger gate[^"]*)"/g)].map((m) => m[1]);
  assert.equal(gates.length, 3);
  for (const line of gates) assert.deepEqual(parseHold(...annotation(line)), { item: null, reason: "trigger gate fault" });
  // A notice that is no hold, and another lane's title, parse to nothing.
  assert.equal(parseHold("pr-verify", "pr-verify judged #7: PASS"), null);
  assert.equal(parseHold("intake-sweep", annotation(gates[0])[1]), null);
  const lane = HOLD_LANES.find((l) => l.lane === "pr-verify");
  assert.deepEqual([lane.workflow, lane.holdStep], ["pr-verify.yml", HELD_STEP]);
  for (const job of lane.jobs) assert.match(workflow, new RegExp(`\\n  ${job}:\\n`), job);
});

test("signal 13: pr-review-main's unread file-list hold parses to a fixed reason, in every select step", () => {
  // Each `Select a lane-source pull request` step's notice, read from the
  // workflow itself, so producer and parser are one contract.
  const workflow = readFileSync(new URL("../../workflows/pr-review-main.yml", import.meta.url), "utf8");
  const notices = [...workflow.matchAll(/echo "(::notice title=pr-review-main::held: [^"]*)"/g)].map((m) => m[1].replace("$retry_call_unknown", "HTTP 502"));
  assert.equal(notices.length, 4, "the trigger job's select step and each of three legs'");
  for (const line of notices) assert.deepEqual(parseHold(...annotation(line)), { item: null, reason: "file list unread" });
  // Another title's text, and a pr-review-main notice that is no hold, parse to nothing.
  assert.equal(parseHold("pr-verify", annotation(notices[0])[1]), null);
  assert.equal(parseHold("pr-review-main", "the file list read 12 files"), null);
  const lane = HOLD_LANES.find((l) => l.lane === "pr-review-main");
  assert.deepEqual([lane.workflow, lane.holdStep], ["pr-review-main.yml", "Note the hold"]);
  for (const job of lane.jobs) assert.match(workflow, new RegExp(`\\n  ${job}:\\n`), job);
  // A matrix leg is listed as `<job> (<values>)` and counts as that job.
  assert.equal(holdJob(lane.names, "Review (claude-review, claude-review)"), true);
  assert.equal(holdJob(lane.names, "Trigger"), true);
  assert.equal(holdJob(lane.names, "Review Handoffs"), false);
  assert.equal(holdJob(lane.names, "Record"), false);
  // A run from before the job rename lists the ids.
  assert.equal(holdJob(lane.jobs, "review (claude-review, claude-review)"), true);
  assert.equal(holdJob(lane.jobs, "trigger"), true);
  assert.equal(holdJob(lane.jobs, "review-handoffs"), false);
});

test("signal 13: each hold lane's names are its jobs' names in its workflow, in the order of its ids", () => {
  for (const { lane, workflow: file, jobs, names } of HOLD_LANES) {
    const workflow = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
    assert.equal(names.length, jobs.length, lane);
    jobs.forEach((id, i) => {
      const [caller, callee] = id.split(" / ");
      const [nameCaller, nameCallee] = names[i].split(" / ");
      assert.match(workflow, new RegExp(`\\n  ${caller}:\\n(?:(?: {4,}.*)?\\n)*? {4}name: ${nameCaller}\\n`), `${lane} ${id}`);
      assert.equal(callee === undefined, nameCallee === undefined, `${lane} ${id}`);
    });
  }
});

test("signal 13: pr-merge's lane token hold parses to one fixed reason, for either cause, read from the action", () => {
  // The notice the action prints, read from the action itself, so producer
  // and parser are one contract.
  const action = readFileSync(new URL("../../actions/request-lane-token/action.yml", import.meta.url), "utf8");
  const [, msg] = /^ +msg="(lane-token-held: [^"]*)"$/m.exec(action) ?? [];
  assert.ok(msg, "the action builds a lane-token-held message");
  assert.match(action, /^ +echo "::notice title=Lane token hold::\$msg"$/m);
  // The budget cause appends the rate-limit clause; the 3-request cap appends nothing.
  const pastBudget = "; GitHub's secondary rate limit (core) resets at 2026-11-06T21:00:00Z, past the 1-minute retry budget";
  for (const clause of [pastBudget, ""]) {
    const line = `::notice title=Lane token hold::${msg.replace("${rate_limit}", clause)}`;
    assert.deepEqual(parseHold(...annotation(line)), { item: null, reason: "lane token rate-limited" }, clause || "attempt cap");
  }
  // Another title's text, and the kill-switch stop's notice, parse to nothing.
  assert.equal(parseHold("pr-merge", msg), null);
  assert.equal(parseHold("Lane token hold", "lane-token-stopped: the broker refused the token because a lanes kill switch is on"), null);
  const lane = HOLD_LANES.find((l) => l.lane === "pr-merge");
  assert.equal(lane.workflow, "pr-merge.yml");
  assert.equal(lane.holdStep, undefined, "no pr-merge step runs only on a hold");
  // Each job named is one whose token step opts into the hold.
  const workflow = readFileSync(new URL("../../workflows/pr-merge.yml", import.meta.url), "utf8");
  for (const job of lane.jobs) {
    const body = new RegExp(`\\n  ${job}:\\n((?: {4,}.*\\n|\\n)+)`).exec(workflow)?.[1] ?? "";
    assert.match(body, /uses: \.\/\.base\/\.github\/actions\/request-lane-token[^\n]*\n {8}with:\n(?: {10}.*\n)*? {10}rate-limit-hold-ok: true\n/, job);
  }
  assert.equal([...workflow.matchAll(/^ {10}rate-limit-hold-ok: true$/gm)].length, lane.jobs.length, "every opted-in token step's job is listed");
});

const held = (lane, runId, { item = null, reason = "closed-issue listing failed", hour = 10 } = {}) => ({
  lane,
  runId,
  url: `https://github.com/o/r/actions/runs/${runId}`,
  item,
  reason,
  at: `2026-10-19T${String(hour).padStart(2, "0")}:47:00Z`,
});

test("signal 13: a repeated hold raises it and a single hold does not", () => {
  const rule = holdRule({ threshold: 2 });
  const once = held("work-resolve-issue", 1, { item: "#812", reason: "fault outcome-unread" });
  assert.deepEqual(laneHoldFindings({ laneHolds: [once], holdRule: rule }), []);
  const again = { ...once, runId: 2, url: "https://github.com/o/r/actions/runs/2", at: "2026-10-19T14:47:00Z" };
  const found = detect({ ...base, laneHolds: [once, again], holdRule: rule });
  assert.equal(found.length, 1);
  const [f] = found;
  assert.equal(f.key, "lane-hold:work-resolve-issue");
  assert.equal(f.signal, "13 lane holds");
  assert.equal(f.area, "Issue lane (work-resolve-issue)");
  assert.match(f.summary, /^2 green work-resolve-issue runs held on a fault in the last 24 hours, at or over the threshold of 2/);
  assert.match(f.summary, /Held more than once: #812 2 times\./);
  assert.deepEqual(f.facts, [
    "2026-10-19T14:47:00Z #812 https://github.com/o/r/actions/runs/2: fault outcome-unread",
    "2026-10-19T10:47:00Z #812 https://github.com/o/r/actions/runs/1: fault outcome-unread",
  ]);
  assert.equal(f.observedAt, again.at);
});

test("signal 13: the default threshold counts each lane on its own, and no rule fires nothing", () => {
  const rule = holdRule({});
  assert.deepEqual(rule, { threshold: 4, windowHours: 24 });
  const three = [1, 2, 3].map((id) => held("work-unblock", id, { hour: 9 + id }));
  const others = [4, 5].map((id) => held("pr-refine", id, { reason: "fix-docs handoff evidence missing" }));
  assert.deepEqual(laneHoldFindings({ laneHolds: [...three, ...others], holdRule: rule }), []);
  const four = [...three, held("work-unblock", 9, { hour: 15 })];
  assert.deepEqual(laneHoldFindings({ laneHolds: [...four, ...others], holdRule: rule }).map((f) => [f.key, f.facts.length]), [["lane-hold:work-unblock", 4]]);
  assert.deepEqual(laneHoldFindings({ laneHolds: four }), []);
  assert.throws(() => holdRule({ threshold: 1 }), /threshold of 2 to 100/);
  assert.throws(() => holdRule({ "window-hours": 1.5 }), /window-hours of 1 to 168/);
});

test("signal 13: intake-triage's held verdicts raise its own finding at the threshold", () => {
  const rule = holdRule({});
  const three = [1, 2, 3].map((id) => held("intake-triage", id, { reason: "fault HTTP 502", hour: 9 + id }));
  assert.deepEqual(laneHoldFindings({ laneHolds: three, holdRule: rule }), []);
  const [f, ...rest] = laneHoldFindings({ laneHolds: [...three, held("intake-triage", 4, { reason: "admission fault HTTP 503", hour: 14 })], holdRule: rule });
  assert.deepEqual(rest, []);
  assert.equal(f.key, "lane-hold:intake-triage");
  assert.equal(f.area, "Intake lane (intake-triage apply-verdict)");
  assert.match(f.summary, /^4 green intake-triage runs held on a fault in the last 24 hours/);
});

test("signal 13: the fingerprint holds while the reasons hold, through new runs", () => {
  const rule = holdRule({ threshold: 2 });
  const fp = (holds) => laneHoldFindings({ laneHolds: holds, holdRule: rule })[0].fingerprint;
  const two = [held("work-unblock", 1), held("work-unblock", 2, { hour: 11 })];
  assert.equal(fp(two), fp([...two, held("work-unblock", 3, { hour: 12 })]));
  assert.notEqual(fp(two), fp([...two, held("work-unblock", 3, { reason: "open listing failed" })]));
});

test("signal 11: a reason from the report reaches the issue inert", () => {
  const [f] = postMergeUnreadableFindings({
    postMergeReports: [report(4, "3", "bad ```\n@someone [x](http://e)"), report(3), report(2), report(1)],
  });
  assert.doesNotMatch(f.summary, /`|\n/);
  for (const line of f.facts) assert.doesNotMatch(line, /`|\n/);
});

test("signal 14 fires on publish-lane-level's variable check annotations and on nothing else", () => {
  const run = (id, annotations, failedSteps = []) => ({ id, url: `https://github.com/o/r/actions/runs/${id}`, name: "Work Unblock", event: "schedule", annotations, failedSteps });
  const found = laneVariableFindings({
    laneVariableRuns: [
      run(41, [{ level: "failure", message: `${VARIABLES_CHANGED} created CLAUDE_LANES_DISABLED` }]),
      run(42, [{ level: "failure", message: `${VARIABLES_UNREAD} the repository variables were not listed after the publish (502)` }]),
      run(43, [{ level: "warning", message: `${VARIABLES_CHANGED} changed LANES_BROKER_URL` }, { level: "failure", message: "Process completed with exit code 1." }]),
    ],
  });
  assert.equal(found.length, 1);
  assert.equal(found[0].key, "lane-variables");
  assert.equal(found[0].signal, "14 lane variables");
  assert.deepEqual(found[0].facts, [
    "Work Unblock https://github.com/o/r/actions/runs/41: lane-variables-changed: created CLAUDE_LANES_DISABLED",
    "Work Unblock https://github.com/o/r/actions/runs/42: lane-variables-unread: the repository variables were not listed after the publish (502)",
  ]);
  assert.match(found[0].summary, /^2 publish-lane-level runs/);
  assert.deepEqual(laneVariableFindings({ laneVariableRuns: [run(43, [{ level: "failure", message: "Process completed with exit code 1." }])] }), []);
  assert.deepEqual(laneVariableFindings({}), []);
});

test("signal 14 fires on a variable check step that timed out with no annotation", () => {
  const [found] = laneVariableFindings({
    laneVariableRuns: [
      { id: 44, url: "https://github.com/o/r/actions/runs/44", name: "Work Unblock", event: "schedule", annotations: [{ level: "failure", message: "The action has timed out." }], failedSteps: ["Check no other repository variable changed: cancelled"] },
    ],
  });
  assert.deepEqual(found.facts, ["Work Unblock https://github.com/o/r/actions/runs/44: Check no other repository variable changed: cancelled, with no check annotation"]);
});
