#!/usr/bin/env node
// reconcile.mjs: re-runs PR CI and lane runs a GitHub outage ended without a
// result. A run that ended cancelled, timed_out or startup_failure, on its
// first attempt, is re-run once with the job's own token. Its attempt number is
// the record: a run at attempt 2 or later was already re-run, by this script
// or a person, and is never touched again: a CI run lost again is named in the
// summary with who takes it. No model.
//
// These kinds are re-run:
// - CI: a CI workflow's newest run on an open PR's current head. These
//   workflows check no re-runner, but pr-verify, which runs after
//   pr-require-checks, trusts its attempt 2 by github-actions[bot] only through
//   this workflow's record of it, so each re-run that makes that attempt
//   carries one, as a lane re-run does.
// - Infra: the same run when it ended failure and every failure is one an
//   outside outage explains (infra-failure.mjs). Only its failed jobs are
//   re-run, through rerun-failed-jobs, once, at attempt 1 only,
//   INFRA_BACKOFF_MINUTES after the attempt ended, and only while npm's and
//   GitHub's status pages show indicator none. At attempt 2 fix-ci takes it.
// - Flake: the same run when it ended failure on anything else, at attempt 1
//   only: its failed jobs are re-run once, at the next half-hourly run, so a
//   flaky test the diff did not cause can pass. pr-unblock's fix-ci does not
//   wait for this re-run unless it is already queued or going, so it may run
//   beside a fix-ci run (CI minutes, no model).
// - Lane: a pr-verify or pr-review-main run whose first attempt ended as above
//   or failure (a judgment that broke, a review every credential leg stopped
//   on, or a pr-verify run the kill switch stopped, which fails), and whose
//   verdict write never started in any job: a judgment that finished is never
//   taken again, so a FAIL the write or upload then lost is held for a person,
//   with the reason in the summary. Its trigger check trusts a re-run
//   github-actions[bot] starts only through this workflow's record of it, the
//   artifact rerunRecordName(run id, attempt, head SHA) (check-trusted-trigger's README). The
//   plan step names each record, the workflow uploads them, and only then does
//   the act step re-run the run, so the record exists before the re-run. The
//   same holds for each CI re-run that carries a record.
// - Held: a pr-verify or pr-review-main run whose first attempt a GitHub
//   fault held green (resolve-pr.mjs closing; pr-review-main's unread file
//   list): it succeeded with a `held: ` notice and no verdict. Re-run once, as
//   a lane run is, with the same record, so a hold is retried on the next pass
//   that reads; one where any job's verdict write started is held for a
//   person, and a pr-review-main run waits out the upstream gate, as a lost
//   lane run does. Their succeeded runs are listed
//   from FAULT_HELD_HOURS back, or from the carried `held_since` when that is
//   earlier: the last pass that read, or the oldest first attempt that pass
//   saw still going, inside the lookback. At most FAULT_HELD_READS of them
//   have their jobs read a pass. A run held again at attempt 2 waits for the
//   head's next checks run.
// - Spec: a pr-require-checks run that passed, at attempt 1, on a head with a
//   pr-verify pass that the spec has since changed under (an issue edit or a
//   new spec comment after the pass: resolve-pr's `spec-changed`, the same
//   read pr-verify makes). The gate refuses that pass `verify:spec-changed`;
//   the recorded re-run starts pr-verify, which judges the head against the
//   spec as it is now. One batched GraphQL read of the linked issues' and
//   their comments' times (`prefilterSpec`) keeps that full read off heads
//   whose spec nobody touched since the pass; the same read, run first against
//   the head's earliest checks run, keeps the pass reads off heads whose spec
//   nobody touched since then. A spec can change again after the re-run's
//   pass, so a passed run is re-run at each attempt below
//   RECONCILER_ATTEMPT_CAP, each re-run recorded at the attempt it starts;
//   one at the cap is named for a person. A run past attempt 1 is taken only
//   once a pass started after its attempt did, so it is not re-run again
//   while pr-verify still judges it. An edit or label later starts a new
//   attempt-1 run.
// - Too old: the same passed run, at attempt 1 only, inside GitHub's re-run window, on a pull
//   request created more than TOO_OLD_DAYS ago whose head has no counted
//   verdict (its pass expired: resolve-pr's `ok`). The gate refuses it
//   `verify:too-old` until a fresh pass at the head; the recorded re-run
//   starts pr-verify, which judges the head. A head a spec re-run takes is
//   left to it.
// - Switch: a lanes App PR whose newest pr-require-checks run failed, at
//   attempt 1, only in ci-status, with ci-status's note that the lanes kill
//   switch was on (KILL_SWITCH_NOTE). ci-status fails every lanes App PR while
//   the switch is on, and nothing else re-runs it once the switch is lifted.
//   This script reads nothing while the switch is on, so the first run after
//   it is lifted re-runs that ci-status, recorded as a CI re-run, with no
//   lookback: the switch may have been on for days. A run at attempt 2 or
//   later is left to a person: this kind re-runs only a first attempt.
// - Pending: any PR whose newest pr-require-checks run failed, at attempt 1,
//   only in ci-status, and only on its notes that a review lane had not
//   finished or had no run yet (PENDING_REVIEW_NOTE, MISSING_REVIEW_NOTE),
//   while the newest pull_request run of each
//   hosted review on the head has since completed, the last of them at least
//   PENDING_BACKOFF_MINUTES ago. rerun-ci-status re-runs that ci-status when
//   the review completes, unless it was lost or held it: it holds a lanes App
//   PR's while the kill switch is on. Re-run as a Stop is, with no lookback.
// - Verdict: a pr-feedback-dispatch.yml run, at attempt 1, whose only failed
//   job is post-verify-notes and whose only failed step there is its
//   kill-switch stop (VERDICT_STOP_STEP): a pr-verify verdict finished while
//   the switch was on, so its notes, or its pr-verify-failed label added or
//   removed, never reached the PR. Its failed jobs are re-run once, over the
//   whole lookback, taking no place under MAX_IN_FLIGHT. The re-run's
//   dispatch job sends no address-feedback round, which the lanes trust only
//   from an attempt-1 dispatcher; it records the head instead, and the next
//   pr-unblock-dispatch tick sends the round (feedback-dispatch.mjs
//   recoverDeferred).
// - Upstream: a pull_request run of a hosted review caller (GATED_REVIEWS), at
//   attempt 1, whose only failed job is kill-switch and whose failed step
//   there is UPSTREAM_STOP_STEP: the upstream-status gate skipped the review
//   while GitHub Actions or npm listed an outage, so the head has no review.
//   Its failed jobs are re-run once, inside the lookback, only while that gate
//   would now let it run (check-upstream-status.mjs). The re-run carries a
//   record, which pr-feedback-dispatch.yml's rerun-ci-status reads, so
//   pr-verify's gate accepts the ci-status re-run the review's completion causes.
//   A person's re-run of the review becomes attempt 3, which the merge gate
//   never binds. The reusable's bot check reads `github.actor`, which a
//   re-run keeps
//   (https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#github-context),
//   and the merge gate binds the re-run (babysit_review_evidence
//   `_upstream_stopped`). Any other failure or loss of these runs is not
//   re-run here.
// - Review: a hosted review run whose first attempt a kill switch stopped, on a
//   head whose newest pr-require-checks run failed only in ci-status with its
//   note of that stop (REVIEW_STOP_NOTE), at any attempt: rerun-ci-status
//   re-runs ci-status when a stopped run completes. ci-status reads the
//   newest review run, so re-running ci-status alone stays red. The whole
//   review run is re-run, as none of its jobs failed. Its completion re-runs
//   ci-status, which that listener records on the strength of this workflow's
//   record. Only attempt 2 binds in the merge
//   gate (babysit_review_evidence `_kill_switch_stopped`), so the one re-run
//   waits until nothing would stop it again: the lane's own switch, read as its
//   caller reads it (REVIEW_SWITCHES, only `true`, in any case, stops), and the upstream
//   gate. One lane per head per pass, so a place holds one record; the other
//   lane goes on the next pass. No lookback: a switch may be on for days, up
//   to GitHub's RERUN_WINDOW_DAYS.
// Other lost lane runs (a review lane run lost any other way, refine) are listed
// in the summary for a person: a review re-run would trade one review for
// another, and refine's lanes token broker refuses a re-run
// github-actions[bot] starts. Their own paths recover them instead: the babysit
// merge gate re-runs a lost review run under the owner's token, and the
// dispatchers send refine and feedback dispatch a fresh attempt-1 run
// (fix-docs-dispatch.mjs for a PR's first lost run, feedback-dispatch.mjs). A merge-group run is not
// covered: a re-run puts no PR back in the queue, and pr-merge re-enqueues its
// own PRs once their checks pass.
//
// A run's attempt-1 jobs never change once it completed, so a lost lane run
// held for good, and a failed intake or verdict run that is not one to re-run,
// is read once: its id is carried in the SETTLED_ARTIFACT this pass uploads,
// and the next pass, reading the newest scheduled or hand-started run of
// main's copy of this workflow that holds one, skips each carried id its
// listing still shows. A run to re-run is never carried (a deferred one still
// gets its place later, and a re-run that fails is tried again), nor one whose
// failed job's steps did not list in full. A carry that is missing or cannot be
// read reads every run, as before.
//
// The same file carries each open PR's latest-attempt job reads (readJobs),
// keyed on the run id and attempt, and used only while the head's live listing
// shows that run completed at that attempt, head and updated_at: a new run or
// attempt reads its jobs again. Only a whole, final listing whose every job's
// steps listed in full is carried, so it carries no annotation, and a red head
// re-reads nothing until it changes. A lost lane run's attempt-1 job read is
// carried the same way while the run stays at attempt 1, so a lane run deferred
// for want of a place is read once, not on every pass until it gets one.
// It also carries each passed head's pass read (passStarts): the runs that
// uploaded its passes, when each started, and when the first pass expires,
// only from whole listings with every start read. Until that expiry the head
// is pre-filtered on the carried starts; a pass the carry lacks or a re-run
// attempt only moves the newest start later, so a carried read is trusted
// only when the pre-filter drops it, and one it keeps is read again live.
// Every decision still runs on each pass against the jobs, now and the status
// pages, and act re-reads each run before it writes.
//
// Nothing is read from GitHub while githubstatus.com shows Actions as anything
// but operational, or the status cannot be read, so a re-run never adds load
// mid-incident. At most MAX_IN_FLIGHT re-runs are in flight at once (PR CI
// sets and recorded lane runs, counting those already running), in three
// bands, the PR sets in each merge-critical (auto-merge set) first, then
// oldest PR: PR sets with anything but a flake re-run, then lane runs, then
// flake-only sets. Nothing else re-runs a lane run, while fix-ci does not wait
// for a flake re-run. A lane run's listing does not name its PR, so lane runs
// go oldest first among those whose creation matches an open head's newest
// checks completion (laneOrder), then the rest oldest first: a run for a
// closed PR, or a second run for one head, takes no place before a live one,
// and the newer runs each kill-switch trip adds no longer push the oldest
// live ones back pass after pass. One pass uploads at most MAX_IN_FLIGHT
// records, so what would pass that waits too.
// Writes are at least WRITE_GAP_MS apart. The first rate-limit error stops the
// run.
//
// Environment:
//   MODE                 `plan` (read, choose, name records) or `act` (re-run the plan)
//   PLAN_PATH            the plan file plan writes and act reads
//   RECORD_PATH          the file plan writes for the record uploads
//   GH_TOKEN             the job's GITHUB_TOKEN (actions: write, pull-requests: read)
//   GITHUB_REPOSITORY    owner/repo
//   TRUSTED_ACTORS_PATH  the default branch's trusted-actor list; unset checks no
//                        spec and no kill-switch stop
//   VERIFY_AUTHORS, LANE_IDENTITY, SPEC_FROM_BODY_APPS  as pr-verify.yml passes
//                        resolve-pr; LANE_IDENTITY also names the lanes App
//   KILL_SWITCH         `proceed` from the kill-switch step; anything else stops
//   CLAUDE_REVIEW_DISABLED, CLAUDE_SECURITY_REVIEW_DISABLED  each lane's switch,
//                        as its caller reads it: only `true`, in any case, stops, and unset
//                        reads empty
//   STATUS_URL           the status page's components endpoint (default githubstatus.com)
//   SETTLED_PATH         plan reads the last pass's settled runs and job reads, then writes
//                        this pass's there for the upload; unset carries nothing
//   GITHUB_RUN_ID, RUNNER_TEMP  this run, and where the last carry is downloaded
//   GITHUB_OUTPUT        plan writes record-1 to record-3 there (empty when unused)
//   GITHUB_STEP_SUMMARY  the outcome is listed there when set
//   GITHUB_API_URL
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, loadTrustedList, paginate, RECONCILER_ATTEMPT_CAP, rerunRecordName } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { ghDownloadArtifact, newestTrustedArtifact } from "../pr-merge/rotation.mjs";
import { HELD_STEP, refsIssue, resolvePull, specFromBodyApps } from "../pr-verify/resolve-pr.mjs";
import { checkUpstreamStatus } from "../../actions/check-upstream-status/check-upstream-status.mjs";
import { ACTIONS, componentStatus, fetchStatus } from "./component-status.mjs";
import {
  AGGREGATE_JOBS,
  FAILED,
  firstFailure,
  gateEntries,
  INFRA_BACKOFF_MINUTES,
  infraOnly,
  LOOKBACK_HOURS,
  LOST,
  lostRunnerNoted,
  reconcilerRetries,
  stepsKnown,
  testedRun,
} from "./infra-failure.mjs";

const STATUS_URL = ACTIONS.url;
// A failed run's failed jobs are re-run only while both pages show indicator none.
export const NPM_STATUS_URL = "https://status.npmjs.org/api/v2/status.json";
export const GITHUB_STATUS_URL = "https://www.githubstatus.com/api/v2/status.json";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RECORD = /^reconcile-rerun-[1-9][0-9]{0,19}-([1-9][0-9]{0,4})-[0-9a-f]{40}$/;
// A record name check-trusted-trigger takes: attempt 2 to RECONCILER_ATTEMPT_CAP.
const isRecordName = (name) => {
  const attempt = Number(RECORD.exec(name)?.[1]);
  return attempt >= 2 && attempt <= RECONCILER_ATTEMPT_CAP;
};

export { LOST };

// A recorded lane run is also lost when it failed: a judgment that broke after
// it started, or a run the kill switch stopped, leaves the head with no verdict.
export const LANE_LOST = new Set([...LOST, "failure"]);
// Workflows with no trigger-actor check, which a github-actions[bot] re-run passes.
// The hosted review callers among them are re-run only for an upstream stop
// (GATED_REVIEWS).
export const GATED_REVIEWS = new Set([".github/workflows/pr-review-hosted.yml", ".github/workflows/pr-review-security-hosted.yml"]);
export const CI_WORKFLOWS = new Set([
  ".github/workflows/pr-require-checks.yml",
  ".github/workflows/pr-test-platforms.yml",
  ".github/workflows/pr-check-managed-files-hosted.yml",
  ...GATED_REVIEWS,
]);
// The hosted review callers' kill-switch job and the step that fails it while
// the upstream-status gate skips the review.
export const GATE_JOB = "kill-switch";
export const UPSTREAM_STOP_STEP = "Stop on upstream status";
// The step that job runs when a kill switch stops the review, and the caller's
// job names for the review itself (`pr-review`, or a reusable's `pr-review / x`).
export const REVIEW_STOP_STEP = "Report the kill switch";
const REVIEW_JOB = /^pr-review/;
// Each hosted review's own switch, by the name its caller reads from `vars`.
export const REVIEW_SWITCHES = new Map([
  [".github/workflows/pr-review-hosted.yml", "CLAUDE_REVIEW_DISABLED"],
  [".github/workflows/pr-review-security-hosted.yml", "CLAUDE_SECURITY_REVIEW_DISABLED"],
]);
// GitHub re-runs a run up to 30 days after its initial run
// (https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs).
export const RERUN_WINDOW_DAYS = 30;
// babysit_verify_evidence.py TOO_OLD_DAYS: past it, the gate refuses a pull
// request with no counted verdict at its head `verify:too-old`
// (reconcile.test.mjs keeps the two equal).
export const TOO_OLD_DAYS = 80;
// The CI workflows a recorded lane runs after on workflow_run. A re-run that
// makes attempt 2 of one is recorded too: the lane trusts that attempt's
// github-actions[bot] only through its record. A later attempt gets none, and
// the lane refuses it.
export const RECORDED_UPSTREAMS = new Set([".github/workflows/pr-require-checks.yml"]);
// The intake run an issue's opening starts, and its floor-label job. A first
// attempt whose floor label failed (most often on a rate limit) left the
// issue unlabeled, and nothing else starts it again, so its failed jobs are
// re-run once, but only when that job is the run's only failed one: the
// re-run starts every failed job again, and the run's other jobs (the model
// triage, the gates) must not run again as github-actions[bot]. Adding the
// label is idempotent, so the re-run is safe whatever the failure was. A run
// where the floor label and another job both failed (a rate limit can fail
// both) is left alone. When that failure kept the issue from a `status:`
// label, the hourly triage sweep (maintenance-audit-lane-runs/triage-sweep.mjs,
// issues a listed human or the lanes App opened) dispatches intake for it and
// labels it needs-triage after 2 dispatches leave it untriaged. Otherwise, and
// once a dispatch triages it, the issue stays without the floor label.
export const INTAKE = ".github/workflows/intake-triage.yml";
export const INTAKE_LABEL_JOB = "intake-label-needs-triage";
// pr-feedback-dispatch's job that applies a pr-verify verdict to its PR, and
// the step that fails that job while the lanes kill switch is on: the failed
// first attempt is the record of a verdict not yet applied. Re-running its
// failed jobs, once, applies it (verify-notes.mjs posts only what is missing).
// A job that failed at any other step (a refused dequeue, a verdict name no
// reader takes) is a red for a person, never re-run here.
export const VERDICT_DISPATCH = ".github/workflows/pr-feedback-dispatch.yml";
export const VERDICT_JOB = "post-verify-notes";
export const VERDICT_STOP_STEP = "Stop on the kill switch";
// A job's conclusions that rerun-failed-jobs leaves alone.
const NOT_RERUN = new Set(["success", "skipped", "neutral"]);
// A run left alone stays a failed first attempt for the whole lookback, so
// its jobs are listed only while it ended this recently (four passes).
const INTAKE_JOBS_WINDOW_MS = 2 * 3_600_000;
// A lost lane run whose steps listed in full is re-run once when it was lost
// before or during its judgment (a cut list is held below). One whose verdict
// write (WRITE_STEP) started is held: that step runs once a judgment finished
// (every judge step truly succeeded, a chunk left a fail the head can count, a
// chunk's result did not count, or the final judge stopped on run-claude-cli's
// credential scan), so the judgment may be a FAIL that the write
// or upload lost, and a re-run would sample the head a second time. The judge step's
// own conclusion cannot show this: it is continue-on-error, so it lists
// success even when it broke. A FAIL
// the first attempt uploaded counts whatever the run's conclusion, so a second
// judgment cannot clear it, and attempt 2 is never re-run. Cancelling
// a run is not what prevents this: the lanes App token has no actions: write,
// but the ci-status job in pr-require-checks.yml does hold it. A run none of
// whose jobs started is left alone: GitHub
// cancels a pending run when a newer one for the same PR head queues behind
// it, and that newer run judges the head.
export const JUDGE_STEP = "Judge the pull request";
// The step before JUDGE_STEP. A cut list that reaches it or the judge step
// cannot show a runner loss from an annotation: the judge step's log may echo
// model or PR text that reads as one.
export const JUDGE_PREDECESSOR = "Write the prompt and schema";
// The step after JUDGE_STEP, which runs only once a judgment finished.
export const WRITE_STEP = "Write the verdict";
// pr-review-main's first judge step, between the same predecessor and the
// verdict write; its later chunks' review steps follow it, so a cut list that
// reaches one also reaches the predecessor.
export const REVIEW_STEP = "Review chunk 1";
// Lane workflows whose trigger check takes this workflow's record
// (reconciler-workflow) and that mint no broker token, each with its judge
// step. Each starts on workflow_run from main, so its runs are listed by
// workflow, not by PR head; the trigger check binds the re-run to the one open
// PR whose head is still the upstream run's.
export const RECORDED_LANES = new Map([
  [".github/workflows/pr-verify.yml", JUDGE_STEP],
  [".github/workflows/pr-review-main.yml", REVIEW_STEP],
]);
// The recorded lanes whose workflow runs the upstream-status gate; pr-verify.yml
// runs none, so no outage holds its re-run.
export const GATED_LANES = new Set([".github/workflows/pr-review-main.yml"]);
// The recorded lanes that hold green on a GitHub fault, each with HELD_STEP
// and a `held: ` notice: pr-verify's resolver (resolve-pr.mjs closing) and
// pr-review-main's file-list read (its `Select a lane-source pull request`
// steps). Also how far back their succeeded runs are listed for a hold. The
// listing starts earlier when the last pass that read did, since a pass idle
// through an outage reads nothing and carries nothing, and holds cluster in
// exactly those outages, or when a run created earlier was still going then
// (pr-verify's three jobs can take about 17 hours).
export const FAULT_HELD_LANES = new Set([".github/workflows/pr-verify.yml", ".github/workflows/pr-review-main.yml"]);
export const FAULT_HELD_HOURS = 6;
// The succeeded runs whose jobs one pass reads, oldest first; the rest wait
// for the next pass, so a pass after a long outage adds a bounded load.
export const FAULT_HELD_READS = 100;
export const MAX_IN_FLIGHT = 3;
export const WRITE_GAP_MS = 1000;
// Pages of 100 read per status query of a lane's run listing; a listing that
// does not fit is a failure, never a partial read.
export const LANE_RUN_PAGES = 5;
// The lane listing is read once per status, so the many succeeded runs are
// never listed: the lost conclusions, and every status short of completed (the
// runs a re-run may have put in flight). Earlier statuses are read first, so a
// run that starts between two queries is still listed by the later one.
export const LANE_LIST_STATUSES = [...LANE_LOST, "requested", "pending", "waiting", "queued", "in_progress"];
// The statuses few runs repository-wide hold (0-15 a day, against hundreds
// cancelled or failed): each is read in one repository-wide listing, split by
// workflow path, for every lane at once. A listing that does not fit one page
// is read per lane instead, never in part.
export const SHARED_LIST_STATUSES = new Set(LANE_LIST_STATUSES.filter((s) => s !== "cancelled" && s !== "failure"));

// The artifact that carries settled runs from one pass to the next.
export const SETTLED_ARTIFACT = "reconcile-settled-runs";
export const SETTLED_FILE = "settled.json";
const WORKFLOW_PATH = ".github/workflows/maintenance-reconcile-lost-runs.yml";
// Bump whenever the rules that settle a run change, so no pass skips a run
// settled under the old rules.
export const SETTLED_VERSION = 3;

class RateLimited extends Error {}
// Rethrows a rate limit, which stops the run; the caller handles any other error.
const passRateLimit = (error) => {
  if (error instanceof RateLimited) {
    throw error;
  }
};

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const jobsKey = (id, attempt) => `${id}:${attempt}`;
// A carried job read, {id, attempt, head, updated_at, jobs}.
const carriedJobsEntry = (e) =>
  Number.isSafeInteger(e?.id) &&
  e.id > 0 &&
  Number.isSafeInteger(e.attempt) &&
  e.attempt > 0 &&
  SHA.test(e.head ?? "") &&
  typeof e.updated_at === "string" &&
  Array.isArray(e.jobs) &&
  e.jobs.every(isObject);

const isTime = (value) => typeof value === "string" && !Number.isNaN(Date.parse(value));
const passesKey = (pr, head) => `${pr}:${head}`;
// A carried pass read, {pr, head, runs: [{id, started_at}], expires_at}: the
// runs that uploaded the head's unexpired passes and when each started, and
// when the first of those passes expires.
const carriedPassesEntry = (e) =>
  Number.isSafeInteger(e?.pr) &&
  e.pr > 0 &&
  SHA.test(e.head ?? "") &&
  isTime(e.expires_at) &&
  Array.isArray(e.runs) &&
  e.runs.length > 0 &&
  e.runs.every((r) => Number.isSafeInteger(r?.id) && r.id > 0 && isTime(r.started_at));

// The carried runs, id to hold reason ("" for an intake or verdict run), the
// carried job reads by jobsKey and the carried pass reads by passesKey (none
// when the file has no `passes`), or an error for any other shape.
export function parseSettled(text, repo) {
  const data = JSON.parse(text);
  if (
    data?.version !== SETTLED_VERSION ||
    data.repository !== repo ||
    !Array.isArray(data.runs) ||
    !data.runs.every((r) => Number.isSafeInteger(r?.id) && r.id > 0 && typeof r.reason === "string") ||
    !Array.isArray(data.jobs) ||
    !data.jobs.every(carriedJobsEntry) ||
    (data.passes !== undefined && (!Array.isArray(data.passes) || !data.passes.every(carriedPassesEntry))) ||
    (data.held_since !== undefined && !isTime(data.held_since))
  ) {
    throw new Error("the settled runs file has an unexpected shape");
  }
  return {
    runs: new Map(data.runs.map((r) => [r.id, r.reason])),
    jobs: new Map(data.jobs.map((e) => [jobsKey(e.id, e.attempt), e])),
    passes: new Map((data.passes ?? []).map((e) => [passesKey(e.pr, e.head), e])),
    // Where the next held-run listing starts (plan's heldSince), if carried.
    ...(data.held_since !== undefined ? { heldSince: Date.parse(data.held_since) } : {}),
  };
}

// The newest trusted pass's settled runs, job reads and pass reads, empty when no pass carries any.
// The carry is fetched by the artifact id the lookup's listing gave, so it is
// never listed a second time.
async function readSettled({ repo, runId, call, download }) {
  const found = await newestTrustedArtifact({ repo, runId, actions: call, name: SETTLED_ARTIFACT, workflow: WORKFLOW_PATH });
  if (found === undefined) {
    return { runs: new Map(), jobs: new Map(), passes: new Map() };
  }
  if (found.artifactId === undefined) {
    throw new Error(`run ${found.runId}'s ${SETTLED_ARTIFACT} artifact has no id`);
  }
  return parseSettled(download(found.artifactId), repo);
}

// True when a job listing is whole and final: every job it counts is listed,
// completed, with a conclusion. Only such a read is carried.
const wholeListing = (listing) =>
  Array.isArray(listing?.jobs) && listing.jobs.length === listing.total_count && listing.jobs.every((job) => job?.status === "completed" && job.conclusion != null);

// A job with only the fields the rules read (stepsKnown, infraCause and the
// stop and contract checks), so a carried read decides as a live one does.
const slimJob = (job) => ({
  id: job.id,
  name: job.name,
  status: job.status,
  conclusion: job.conclusion,
  runner_id: job.runner_id,
  steps: Array.isArray(job.steps) ? job.steps.map((s) => ({ name: s?.name, number: s?.number, status: s?.status, conclusion: s?.conclusion })) : job.steps,
});

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// A workflow path's file name, as the per-workflow runs endpoint takes it.
const workflowFile = (path) => path.slice(path.lastIndexOf("/") + 1);
// A runs listing's `created` filter for runs created at or after `ms`, to the second.
const createdSince = (ms) => encodeURIComponent(`>=${new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z")}`);

// A run's first-attempt job listing, which must fit one page.
async function firstAttemptJobs(call, repo, id) {
  const listing = await call("GET", `/repos/${repo}/actions/runs/${id}/attempts/1/jobs?per_page=100`);
  if (!Array.isArray(listing?.jobs) || listing.total_count > 100) {
    throw new Error("its job listing is not one complete page");
  }
  return listing;
}

// The Actions component's status, or undefined when the page has none.
export const actionsStatus = (page) => componentStatus(page, ACTIONS.name);

const newerFirst = (a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || b.id - a.id;

// The newest run of each workflow on one head.
function newestByWorkflow(runs) {
  const newest = new Map();
  for (const r of runs) {
    const seen = newest.get(r.path);
    if (!seen || newerFirst(r, seen) < 0) {
      newest.set(r.path, r);
    }
  }
  return [...newest.values()];
}

// Each CI workflow's pull_request runs on one head, newest first.
function ciRunsByWorkflow(runs) {
  const byPath = new Map();
  for (const r of runs.filter((run) => CI_WORKFLOWS.has(run.path) && run.event === "pull_request")) {
    byPath.set(r.path, [...(byPath.get(r.path) ?? []), r]);
  }
  return [...byPath.values()].map((list) => list.sort(newerFirst));
}

const isLost = (r, since) => r.status === "completed" && LOST.has(r.conclusion) && r.run_attempt === 1 && Date.parse(r.created_at) >= since;
// A CI run lost again after its one re-run: never re-run here.
const isLostAgain = (r, since) => r.status === "completed" && LOST.has(r.conclusion) && r.run_attempt > 1 && Date.parse(r.created_at) >= since;
const isFailedIntake = (r, since) =>
  r.path === INTAKE && r.event === "issues" && r.status === "completed" && r.conclusion === "failure" && r.run_attempt === 1 && Date.parse(r.created_at) >= since;
const isStoppedVerdict = (r, since) =>
  r.path === VERDICT_DISPATCH && r.event === "workflow_run" && r.status === "completed" && r.conclusion === "failure" && r.run_attempt === 1 && Date.parse(r.created_at) >= since;
const isLostLane = (r, since) =>
  r.event === "workflow_run" &&
  r.head_branch === "main" &&
  SHA.test(r.head_sha ?? "") &&
  r.status === "completed" &&
  LANE_LOST.has(r.conclusion) &&
  r.run_attempt === 1 &&
  Date.parse(r.created_at) >= since;
// A pr-verify or pr-review-main run that may have held green on a GitHub
// fault: it concludes success, so it is never lost, and only its jobs tell
// (faultHeld). Only its first attempt is re-run, as a lost lane run's is.
const isFaultHeld = (r, since) =>
  FAULT_HELD_LANES.has(r.path) &&
  r.event === "workflow_run" &&
  r.head_branch === "main" &&
  SHA.test(r.head_sha ?? "") &&
  r.status === "completed" &&
  r.conclusion === "success" &&
  r.run_attempt === 1 &&
  Date.parse(r.created_at) >= since;
// The resolver's notice when a fault held it, read as triage-sweep.mjs
// classifyRun reads apply-verdict's.
const HELD_NOTE = /^held: /;
export const heldNoted = (annotations) =>
  Array.isArray(annotations) && annotations.some((a) => a?.annotation_level === "notice" && HELD_NOTE.test(String(a.message ?? "")));
// The checks run whose re-run starts pr-verify again: a pr-require-checks
// pull_request run that passed, at any attempt up to RECONCILER_ATTEMPT_CAP.
// Only one below the cap is re-run (`belowCap`), so the attempt its re-run
// starts is one pr-verify's gate takes; one at the cap is named for a person.
const isPassedChecks = (r) =>
  RECORDED_UPSTREAMS.has(r?.path) &&
  r.event === "pull_request" &&
  r.status === "completed" &&
  r.conclusion === "success" &&
  Number.isInteger(r.run_attempt) &&
  r.run_attempt >= 1 &&
  r.run_attempt <= RECONCILER_ATTEMPT_CAP;
const belowCap = (r) => r.run_attempt < RECONCILER_ATTEMPT_CAP;
const atCap = (pull, checks, why) =>
  `#${pull.number}: run ${checks.id} (${checks.path}) is at attempt ${checks.run_attempt}, the most this workflow records, and ${why}; a person re-runs it`;
// The error ci-status's lanes-hold step writes for a lanes App PR while the
// kill switch is on (pr-require-checks.yml; reconcile.test.mjs pins it there).
export const KILL_SWITCH_NOTE = "the lanes kill switch is on";
const isRedChecks = (r) => RECORDED_UPSTREAMS.has(r?.path) && r.event === "pull_request" && r.status === "completed" && r.conclusion === "failure";
// The checks run a lifted kill switch leaves red: failed on its first attempt.
const isFailedChecks = (r) => isRedChecks(r) && r.run_attempt === 1;
// The failed ci-status job when it is the run's only failed job, else undefined.
const onlyAggregateFailed = (jobs) =>
  Array.isArray(jobs) && jobs.every((job) => !FAILED.has(job?.conclusion) || AGGREGATE_JOBS.has(job.name))
    ? gateEntries(jobs).find((job) => job.conclusion === "failure" && Number.isSafeInteger(job.id))
    : undefined;
// True when one of the ci-status job's check-run annotations is the kill-switch
// error: a re-run with the switch off passes that step.
export const killSwitchNoted = (annotations) =>
  Array.isArray(annotations) && annotations.some((a) => a?.annotation_level === "failure" && String(a.message ?? "").includes(KILL_SWITCH_NOTE));
// The error ci-status's review-lane step writes for a lane a kill switch
// stopped (pr-require-checks.yml; reconcile.test.mjs pins it there).
export const REVIEW_STOP_NOTE = "a kill switch was on when it started";
export const reviewStopNoted = (annotations) =>
  Array.isArray(annotations) && annotations.some((a) => a?.annotation_level === "failure" && String(a.message ?? "").includes(REVIEW_STOP_NOTE));
// The note GitHub adds for a step that exits non-zero.
const EXIT_NOTE = /^Process completed with exit code [0-9]+\.$/;
// The errors ci-status's review-lane step writes for a review still running,
// or with no run yet, when it read the head (pr-require-checks.yml;
// reconcile.test.mjs pins both there).
// Each ends in the step's re-run note: since the step waits for a review
// (#12447) it names the wait; a run from before writes the older tail.
const RERUN_TAIL = String.raw`(?:ci-status re-runs when the review finishes\.|ci-status waited [0-9]+s for it; pr-feedback-dispatch re-runs ci-status a few minutes after the review finishes, so no manual re-run is needed\.)`;
export const PENDING_REVIEW_NOTE = new RegExp(String.raw`^'[^']+' has not finished on [0-9a-f]{40} \(https:\/\/[^ ]+\)\. ${RERUN_TAIL}$`);
const MISSING_TAIL = String.raw`(?:${RERUN_TAIL}|ci-status does not wait for a lane with no run; pr-feedback-dispatch re-runs ci-status a few minutes after the review finishes, so no manual re-run is needed\.)`;
export const MISSING_REVIEW_NOTE = new RegExp(String.raw`^'[^']+' is missing: no [a-z-]+\.yml run on [0-9a-f]{40} yet\. ${MISSING_TAIL}$`);
// True when ci-status's only failure is its review-lane step on reviews not
// done: one or more pending or missing notes and that step's one exit note.
export const pendingReviewNoted = (annotations) => {
  const failures = (Array.isArray(annotations) ? annotations : []).filter((a) => a?.annotation_level === "failure").map((a) => String(a.message ?? ""));
  const pending = failures.filter((m) => PENDING_REVIEW_NOTE.test(m) || MISSING_REVIEW_NOTE.test(m)).length;
  const exits = failures.filter((m) => EXIT_NOTE.test(m)).length;
  return pending > 0 && exits <= 1 && pending + exits === failures.length;
};
// How long after the last review completes before a Pending re-run: at least
// rerun-ci-status's `timeout-minutes: 15` (reconcile.test.mjs pins it), so its
// own re-run has had the time to land. Under its `queue: max` concurrency that
// job may still start later, so this narrows the race without closing it. A
// late rerun-ci-status after a review lane does not re-run again: its
// started_at check ends it on a ci-status attempt that started after the lanes
// finished (a pr-unblock upstream with a full status page skips that check).
// What overlap remains is two POSTs inside check-then-act gaps (its
// `"completed $attempt"` re-read, act's lostNow attempt check), which GitHub
// would refuse while the first re-run is going (UNVERIFIED) rather than start
// a third attempt. Should both land, the extra attempt has no record of its
// own, so pr-verify refuses it: the head is stranded, never let through.
export const PENDING_BACKOFF_MINUTES = 20;
// A hosted review run a kill switch may have stopped: it reads success with no
// job failed, so only its jobs can tell (`reviewStopped`).
const isUnreviewed = (r) => GATED_REVIEWS.has(r?.path) && r.event === "pull_request" && r.status === "completed" && r.conclusion === "success" && r.run_attempt === 1;
// A failed run whose failed jobs may be re-run now, if its failures are infra only.
const isRetryable = (r, now) => reconcilerRetries(r, now) && now - Date.parse(r.updated_at) >= INFRA_BACKOFF_MINUTES * 60_000;
const lostNow = (item, r, since) => {
  if (r?.head_sha !== item.head) {
    return false;
  }
  if (item.kind === "infra" || item.kind === "flake" || item.kind === "switch" || item.kind === "pending" || item.kind === "upstream") {
    return r.status === "completed" && r.conclusion === "failure" && r.run_attempt === item.attempt;
  }
  if (item.kind === "review") {
    return isUnreviewed(r);
  }
  if (item.kind === "intake") {
    return isFailedIntake(r, since);
  }
  if (item.kind === "verdict") {
    return isStoppedVerdict(r, since);
  }
  if (item.kind === "spec" || item.kind === "too-old") {
    return isPassedChecks(r) && belowCap(r) && r.run_attempt === item.attempt && (item.kind === "spec" || r.run_attempt === 1);
  }
  if (item.kind === "fault-held") {
    return isFaultHeld(r, since);
  }
  return item.kind === "lane" ? isLostLane(r, since) : isLost(r, since);
};

// What one PR's head holds: CI runs to re-run, CI runs lost again after
// their re-run, lost lane runs, and whether a CI re-run is already in flight.
export function classify(runs, since) {
  const newest = newestByWorkflow(runs);
  const ci = newest.filter((r) => CI_WORKFLOWS.has(r.path));
  const plain = ci.filter((r) => !GATED_REVIEWS.has(r.path));
  return {
    rerun: plain.filter((r) => r.event === "pull_request" && isLost(r, since)),
    again: plain.filter((r) => r.event === "pull_request" && isLostAgain(r, since)),
    lane: newest.filter((r) => (!CI_WORKFLOWS.has(r.path) || GATED_REVIEWS.has(r.path)) && isLost(r, since)),
    // A hosted review re-run takes no CI slot: it holds no PR's CI back.
    inFlight: plain.some((r) => r.status !== "completed" && r.run_attempt > 1),
  };
}

// A CI item with its record, when its re-run makes attempt 2 of a recorded
// upstream, or of a stopped hosted review, whose completion re-runs ci-status
// (pr-feedback-dispatch.yml rerun-ci-status). One PR holds one run per
// workflow, so a place holds at most three records: pr-require-checks' and
// both hosted reviews'.
// The attempt an item's re-run starts: the one after the attempt it read (a
// lane or CI item, read at attempt 1, names none).
const nextAttempt = (item) => (item.attempt ?? 1) + 1;
const withRecord = (item) =>
  item.kind === "upstream" ||
  (RECORDED_UPSTREAMS.has(item.path) && (item.kind === "ci" || item.kind === "spec" || item.kind === "too-old" || item.attempt === 1))
    ? { ...item, record: rerunRecordName(item.id, nextAttempt(item), item.head) }
    : item;
// The items the record uploads cover: every lane re-run, a held one included,
// and each recorded CI re-run.
const recorded = (item) => item.kind === "lane" || item.kind === "fault-held" || item.record !== undefined;

const byMergeCriticality = (a, b) => Number(b.auto_merge != null) - Number(a.auto_merge != null) || a.number - b.number;
const byAge = (a, b) => Date.parse(a.created_at) - Date.parse(b.created_at) || a.id - b.id;

// How far a lane run's creation may sit from the completion of the checks run
// that started it. Judgment from one measured pair: checks run done at
// 04:13:36Z, its pr-verify run created at 04:13:40Z (4 s); the 15 minutes
// after allow for a backed-up workflow_run queue. To re-measure, take
// pr-verify runs from a busy hour, read UPSTREAM_RUN_ID from each verify job's
// log, and compare the run's created_at with that checks run's updated_at.
const MATCH_BEFORE_MS = 60_000;
const MATCH_AFTER_MS = 15 * 60_000;

// When a head's newest completed pull_request checks run finished, the one
// whose completion started the head's live lane runs.
const checksDone = (own) => {
  const done = own
    .filter((r) => RECORDED_UPSTREAMS.has(r.path) && r.event === "pull_request" && r.status === "completed" && isTime(r.updated_at))
    .map((r) => Date.parse(r.updated_at));
  return done.length > 0 ? Math.max(...done) : undefined;
};

// The lane items in place order: those matched to an open head, oldest first,
// then the rest, oldest first. A lane run's listing names main's tip, not its
// PR, so a run is matched by time: each open head's checks completion takes the
// closest run of each lane created inside the match window, and each run is
// taken once, so a duplicate run for a head and a run whose PR is gone sort
// last. The match sets the order only; check-trusted-trigger and resolve-pr
// still bind the re-run to its PR.
function laneOrder(lanes, openChecks) {
  const pairs = [];
  for (const lane of lanes) {
    for (const { head, done } of openChecks) {
      const gap = Date.parse(lane.created_at) - done;
      if (gap >= -MATCH_BEFORE_MS && gap <= MATCH_AFTER_MS) {
        pairs.push({ lane, key: `${head} ${lane.path}`, distance: Math.abs(gap) });
      }
    }
  }
  pairs.sort((a, b) => a.distance - b.distance || a.lane.id - b.lane.id);
  const matched = new Set();
  const taken = new Set();
  for (const { lane, key } of pairs) {
    if (!matched.has(lane) && !taken.has(key)) {
      matched.add(lane);
      taken.add(key);
    }
  }
  return [...lanes.filter((l) => matched.has(l)).sort(byAge), ...lanes.filter((l) => !matched.has(l)).sort(byAge)];
}

// A job whose steps did not list in full may have lost its runner, which cuts
// the list at the running step; its check-run annotations tell
// (infra-failure.mjs lostRunnerNoted). Reads them for each such job `wanted` picks.
const withAnnotations = (call, repo, jobs, wanted = () => true) =>
  Promise.all(
    jobs.map(async (job) =>
      wanted(job) && !stepsKnown(job) && Number.isSafeInteger(job?.id)
        ? { ...job, annotations: await call("GET", `/repos/${repo}/check-runs/${job.id}/annotations?per_page=100`) }
        : job,
    ),
  );

const NOT_STARTED = "before any of its jobs started";
// The schedule's interval: a listing of no jobs read this long after its run
// last changed is final, as one read sooner may not yet show them.
export const PASS_MINUTES = 30;

// True when the upstream-status gate alone failed a hosted review run: its one
// failed job is the kill-switch job, failed at UPSTREAM_STOP_STEP.
export const upstreamStopped = (jobs) =>
  Array.isArray(jobs) &&
  jobs.filter((job) => FAILED.has(job?.conclusion)).length === 1 &&
  jobs.some(
    (job) =>
      job?.name === GATE_JOB &&
      job.conclusion === "failure" &&
      Array.isArray(job.steps) &&
      job.steps.some((step) => step?.name === UPSTREAM_STOP_STEP && step.conclusion === "failure"),
  );

// True when a kill switch stopped a hosted review run: ci-status's `stopped`
// and the merge gate's `_kill_switch_stopped`, read from the steps. A list cut
// short proves nothing, so that head stays with a person (ci-status names it).
export const reviewStopped = (jobs) =>
  Array.isArray(jobs) &&
  !jobs.some((job) => REVIEW_JOB.test(job?.name ?? "") && job.conclusion !== "skipped") &&
  jobs.some((job) => job?.name === GATE_JOB && job.conclusion === "success" && job.steps?.some((step) => step?.name === REVIEW_STOP_STEP && step.conclusion === "success"));

// Why the run's first attempt must not be re-run, with whether that hold is
// final (`settle`), or undefined when it may be re-run: no job started any
// step, or a verdict write started. An unreadable listing throws. A judge
// hold rests on a cut that a lost runner left, which stays cut for good, and
// a write hold on a step that started, which stays started; both are final.
// A not-started hold is final only on a whole listing whose steps all listed,
// and, when it lists no job, only once `settled` (the run's last change is a
// pass interval old).
// A run still at attempt 1 is read from `carry` (the carried job reads, by
// jobsKey) while its listing shows the same head and updated_at, and a whole
// read whose every job's steps listed is put in `keep`, so a run deferred for
// want of a place is not read again each pass until it gets one.
async function holdReason(call, repo, run, judge, settled, carry = new Map(), keep = new Map()) {
  const key = jobsKey(run.id, 1);
  const current = run.status === "completed" && run.run_attempt === 1 && SHA.test(run.head_sha ?? "") && typeof run.updated_at === "string";
  const carried = current ? carry.get(key) : undefined;
  const hit = carried?.head === run.head_sha && carried?.updated_at === run.updated_at;
  const listing = hit
    ? { total_count: carried.jobs.length, jobs: carried.jobs }
    : await call("GET", `/repos/${repo}/actions/runs/${run.id}/attempts/1/jobs?per_page=100`);
  if (!Array.isArray(listing?.jobs) || listing.total_count > 100) {
    throw new Error("its job listing is not one complete page");
  }
  if (hit) {
    keep.set(key, carried);
  } else if (current && wholeListing(listing) && listing.jobs.length > 0 && listing.jobs.every((job) => stepsKnown(job))) {
    keep.set(key, { id: run.id, attempt: 1, head: run.head_sha, updated_at: run.updated_at, jobs: listing.jobs.map(slimJob) });
  }
  const jobs = await withAnnotations(call, repo, listing.jobs);
  // A job whose steps did not list in full (stepsKnown) throws too, so the
  // next pass reads it again, unless it lost its runner: then its list ends at
  // the step that was running. Only a failed job's annotation counts.
  const cut = jobs.filter((job) => !stepsKnown(job));
  if (!cut.every((job) => job?.conclusion === "failure" && lostRunnerNoted(job))) {
    throw new Error("a job's steps did not list in full, so which steps ran is unknown");
  }
  const started = jobs
    .flatMap((job) => (Array.isArray(job?.steps) ? job.steps : []))
    .filter((s) => s?.conclusion != null && s.conclusion !== "skipped");
  // An annotation can be echoed text, so a cut list that reaches the judge
  // step or its predecessor stays held rather than read as a lost runner.
  if (cut.some((job) => job.steps?.some((s) => s?.name === JUDGE_PREDECESSOR || s?.name === judge))) {
    return { reason: "after its judge step may have started", settle: true };
  }
  // The judge step is continue-on-error, so it lists success even when it
  // broke; the verdict write runs only on its true success. Once that write
  // started, the judgment may be a FAIL the run then failed to write or
  // upload, and a re-run would judge the head a second time.
  if (started.some((s) => s.name === WRITE_STEP)) {
    return { reason: WRITTEN, settle: true };
  }
  return started.length === 0 ? { reason: NOT_STARTED, settle: wholeListing(listing) && cut.length === 0 && (jobs.length > 0 || settled) } : undefined;
}

// Whether a succeeded first attempt held on a GitHub fault: a job that ran
// HELD_STEP, which runs only then, with the lane's `held: ` notice among its
// check-run annotations (heldNoted), so only a held run's annotations are
// read. `final` when no hold shows on a whole listing whose every job's steps
// listed, which a completed attempt never changes. A held run where any job's
// verdict write started is `written`: a later leg held after another wrote,
// and a re-run would judge that head again (holdReason holds it the same
// way). An unreadable listing throws.
export const WRITTEN = "after its verdict write started, so a re-run would judge the head again";
async function faultHeld(call, repo, run) {
  const listing = await firstAttemptJobs(call, repo, run.id);
  const marked = listing.jobs.filter(
    (job) => Number.isSafeInteger(job?.id) && Array.isArray(job.steps) && job.steps.some((step) => step?.name === HELD_STEP && step.conclusion === "success"),
  );
  const steps = listing.jobs.flatMap((job) => (Array.isArray(job?.steps) ? job.steps : []));
  if (marked.length > 0 && steps.some((step) => step?.name === WRITE_STEP && step.conclusion != null && step.conclusion !== "skipped")) {
    return { held: false, final: true, written: true };
  }
  for (const job of marked) {
    if (heldNoted(await call("GET", `/repos/${repo}/check-runs/${job.id}/annotations?per_page=100`))) {
      return { held: true, final: false };
    }
  }
  return { held: false, final: wholeListing(listing) && listing.jobs.every((job) => stepsKnown(job)) };
}

// The start times of the runs that uploaded the PR's unexpired pr-verify
// PASS or PASS-NOTES at the head, by the exact names write-verdict.mjs
// artifactName writes, as resolve-pr looks them up; empty when it has none. A
// run that cannot be read gives null; a run whose start `known` holds (a
// carried read) is not read again. resolve-pr's full read checks each pass's
// origin; these feed only the pre-filter. `carry` is the read to carry to the
// next pass (carriedPassesEntry), only when both listings were whole, every
// pass names its expiry and every start was read.
async function passStarts(call, repo, number, head, known = new Map()) {
  const ids = new Set();
  let whole = true;
  let expires = Infinity;
  for (const name of ["pass", "pass-notes"].map((verdict) => `pr-verify-${number}-${head}-${verdict}`)) {
    const page = await call("GET", `/repos/${repo}/actions/artifacts?name=${name}&per_page=100`);
    whole &&= Array.isArray(page?.artifacts) && Number.isInteger(page.total_count) && page.total_count <= page.artifacts.length;
    for (const a of page?.artifacts ?? []) {
      if (a?.name === name && a.expired === false && Number.isSafeInteger(a.workflow_run?.id)) {
        ids.add(a.workflow_run.id);
        expires = Math.min(expires, Date.parse(a.expires_at ?? ""));
      }
    }
  }
  const runs = [];
  for (const id of ids) {
    let started = known.get(id);
    if (started === undefined) {
      const run = await call("GET", `/repos/${repo}/actions/runs/${id}`).catch((error) => {
        passRateLimit(error);
        return null;
      });
      started = run?.run_started_at ?? null;
    }
    runs.push({ id, started_at: started });
  }
  const entry = { pr: number, head, runs, expires_at: Number.isFinite(expires) ? new Date(expires).toISOString() : "" };
  return { starts: runs.map((r) => r.started_at), carry: whole && carriedPassesEntry(entry) ? entry : undefined };
}

// The times resolve-pr's `specChanged` weighs, read with the same comment page
// as its ISSUE_FIELDS, plus the issue's own `updatedAt`.
const PREFILTER_ISSUE = "updatedAt lastEditedAt comments(first: 100) { totalCount nodes { updatedAt } }";
const PREFILTER_PULL = `body lastEditedAt closingIssuesReferences(first: 10) { totalCount nodes { ${PREFILTER_ISSUE} repository { nameWithOwner } } }`;

// Whether an issue may have changed after its pass: its `updatedAt`, a body
// edit or any comment's `updatedAt` is after it, or its comments do not fit
// the page read.
const issueMoved = (issue, after) => {
  const comments = issue?.comments;
  if (!Array.isArray(comments?.nodes) || comments.totalCount !== comments.nodes.length) {
    return true;
  }
  return after(issue.updatedAt) || (issue.lastEditedAt != null && after(issue.lastEditedAt)) || comments.nodes.some((c) => after(c?.updatedAt));
};

// The candidates whose spec may have changed after their newest pass: the
// pre-filter that keeps resolve-pr's full read (about a dozen REST calls and
// one GraphQL query) off a PR whose spec nobody touched. One GraphQL query
// reads every candidate's closing issues' `updatedAt`, body `lastEditedAt`
// and each comment's `updatedAt` (the comment times `specChanged` reads, so
// no claim about what moves an issue's `updatedAt` is relied on), and, for a
// PR that is its own spec, its body's `lastEditedAt`; a second reads the same
// for the `Refs:` issue of each PR that closes none. A candidate is kept when
// any of those times is after its newest pass started, or when anything it
// needs cannot be read in full. It decides nothing: resolve-pr's
// `specChanged` still decides skip or re-run.
export async function prefilterSpec(call, repo, candidates) {
  if (candidates.length === 0) {
    return [];
  }
  const [owner, name] = repo.split("/");
  const query = (fields) => `query { repository(owner: ${JSON.stringify(owner)}, name: ${JSON.stringify(name)}) { ${fields} } }`;
  const keep = new Set();
  let pulls;
  try {
    const answer = await call("POST", "/graphql", { query: query(candidates.map((c, i) => `p${i}: pullRequest(number: ${c.pull.number}) { ${PREFILTER_PULL} }`).join(" ")) });
    pulls = answer?.data?.repository;
  } catch (error) {
    passRateLimit(error);
    return candidates;
  }
  const refs = [];
  candidates.forEach((c, i) => {
    const latest = Math.max(...c.starts.map((s) => Date.parse(s ?? "")));
    const pr = pulls?.[`p${i}`];
    const closing = pr?.closingIssuesReferences;
    const after = (time) => !(Date.parse(time ?? "") <= latest);
    if (c.starts.some((s) => Number.isNaN(Date.parse(s ?? ""))) || !pr || !Array.isArray(closing?.nodes) || closing.totalCount !== closing.nodes.length) {
      keep.add(i);
      return;
    }
    const own = closing.nodes.filter((n) => n?.repository?.nameWithOwner === repo);
    if (own.length > 0) {
      if (own.some((n) => issueMoved(n, after))) keep.add(i);
      return;
    }
    if (pr.lastEditedAt != null && after(pr.lastEditedAt)) {
      keep.add(i);
      return;
    }
    const named = refsIssue(pr.body);
    if (named !== null) refs.push({ i, named, after });
  });
  if (refs.length > 0) {
    try {
      const answer = await call("POST", "/graphql", { query: query(refs.map((r, j) => `r${j}: issue(number: ${r.named}) { ${PREFILTER_ISSUE} }`).join(" ")) });
      refs.forEach((r, j) => {
        if (issueMoved(answer?.data?.repository?.[`r${j}`], r.after)) keep.add(r.i);
      });
    } catch (error) {
      passRateLimit(error);
      refs.forEach((r) => keep.add(r.i));
    }
  }
  return candidates.filter((_, i) => keep.has(i));
}

// Reads every open PR's head and the recorded lanes' runs, and returns the
// re-runs to make in order, with a record name on each lane re-run and each
// recorded CI re-run.
async function plan({ repo, call, say, since, now, readStatus, judgeSpec, laneApp, settled = new Map(), carriedJobs = new Map(), carriedPasses = new Map(), heldFrom, env = {} }) {
  // The runs to carry to the next pass, {id, reason}: read and settled now, or carried and still listed.
  const settle = [];
  // The job reads to carry to the next pass, by jobsKey: read whole now, or carried and still current.
  const keepJobs = new Map();
  // The pass reads to carry to the next pass: read whole now, or carried and still unexpired.
  const keepPasses = [];
  const sayHeld = (r, held) => {
    const why = held === NOT_STARTED ? "; a newer run judges the head, so it is not re-run" : "; not re-run";
    say(`lane run ${r.id} (${r.path}) ended ${r.conclusion} ${held}${why}`);
  };
  const pulls = (await paginate(call, `/repos/${repo}/pulls?state=open&base=main`, 5))
    .filter((p) => p.state === "open" && p.draft !== true && p.base?.ref === "main" && p.head?.repo?.full_name === repo && SHA.test(p.head?.sha ?? ""))
    .sort(byMergeCriticality);
  let failed = 0;
  let inFlight = 0;
  const ready = [];
  // Each open head's newest checks completion, {head, done}, for laneOrder;
  // taken before any skip, so a busy head still matches its lane runs.
  const openChecks = [];
  // Heads whose checks passed, each with its earliest checks run's creation.
  const passed = [];
  // Heads with a pass whose spec may have changed since (`prefilterSpec`).
  const specCandidates = [];
  // Passed heads of pull requests past TOO_OLD_DAYS, inside the re-run window.
  const tooOld = [];
  // Read once, on the first infra-only run: why its re-run waits, or "" when npm and GitHub are clear.
  let upstream;
  // Read once, on the first upstream-stopped review: why its re-run waits, or
  // "" when the gate would let the review run now.
  let gate;
  const gateHold = async () =>
    (gate ??= checkUpstreamStatus({ fetchStatus: readStatus }).then(
      (result) => (result.degraded === "true" ? `the upstream gate still reads ${escapeCommand(result.reason)}` : ""),
      (error) => `the upstream gate could not be read (${escapeCommand(error?.message ?? error)})`,
    ));
  const upstreamHold = async () =>
    (upstream ??= (async () => {
      for (const url of [NPM_STATUS_URL, GITHUB_STATUS_URL]) {
        const indicator = await readStatus(url).then(
          (page) => page?.status?.indicator,
          () => "unreadable",
        );
        if (indicator !== "none") {
          // The page's text is logged through `say`, so a newline in it must
          // not start a workflow command line.
          return `${new URL(url).host} shows ${escapeCommand(indicator ?? "no indicator")}`;
        }
      }
      return "";
    })());
  const noteFailure = (what, error) => {
    passRateLimit(error);
    failed += 1;
    console.log(`::error title=reconcile::${what}: ${escapeCommand(error?.message ?? error)}`);
  };
  // A pull request whose spec or verdict read failed: the next run reads it again.
  const sayUnchecked = (pull, what, error) => {
    passRateLimit(error);
    say(`#${pull.number}: its ${what} could not be checked (${escapeCommand(error?.message ?? error)}); the next run checks again`);
  };
  for (const pull of pulls) {
    try {
      const listing = await call("GET", `/repos/${repo}/actions/runs?head_sha=${pull.head.sha}&per_page=100`);
      if (!Array.isArray(listing?.workflow_runs) || listing.total_count > 100) {
        throw new Error("its run listing is not one complete page");
      }
      // A fork PR at the same head SHA lists its runs here too: re-running one
      // spends this repository's minutes on the fork's code, and a newer one
      // would hide this repository's run. Only this repository's runs count.
      const own = listing.workflow_runs.filter((r) => r.head_repository?.full_name === repo);
      const done = checksDone(own);
      if (done !== undefined) {
        openChecks.push({ head: pull.head.sha, done });
      }
      const { rerun, again, lane, inFlight: busy } = classify(own, since);
      inFlight += busy ? 1 : 0;
      for (const r of lane) {
        say(`#${pull.number}: lane run ${r.id} (${r.path}) ended ${r.conclusion}; a re-run of this lane needs a person`);
      }
      // The re-run is spent; a job past its time limit is a slow or hanging
      // test, which fix-ci takes from its annotation (infra-failure.mjs
      // timeLimitNoted). Named here, so the head is never red in silence.
      for (const r of again) {
        say(
          `#${pull.number}: run ${r.id} (${r.path}) ended ${r.conclusion} again at attempt ${r.run_attempt}; not re-run: fix-ci takes a job past its time limit, any other cause waits for a push or a person's re-run`,
        );
      }
      if (busy) {
        continue;
      }
      const set = rerun.map((r) => ({ kind: "ci", pr: pull.number, id: r.id, path: r.path, conclusion: r.conclusion, head: pull.head.sha }));
      // A run's latest jobs, with the annotations of a failed job whose steps
      // did not list in full (infraCause reads them).
      // A completed run's carried read is used while the listing shows the
      // same attempt, head and updated_at; a whole, final read is carried.
      const readJobs = async (r) => {
        const key = jobsKey(r.id, r.run_attempt);
        const carried = r.status === "completed" ? carriedJobs.get(key) : undefined;
        if (carried && carried.head === r.head_sha && carried.updated_at === r.updated_at) {
          keepJobs.set(key, carried);
          return carried.jobs;
        }
        const listed = await call("GET", `/repos/${repo}/actions/runs/${r.id}/jobs?filter=latest&per_page=100`);
        if (!Array.isArray(listed?.jobs) || listed.total_count > 100) {
          throw new Error(`run ${r.id}'s job listing is not one complete page`);
        }
        if (
          r.status === "completed" &&
          Number.isSafeInteger(r.run_attempt) &&
          SHA.test(r.head_sha ?? "") &&
          typeof r.updated_at === "string" &&
          wholeListing(listed) &&
          // An empty listing may not have settled yet (holdReason waits
          // PASS_MINUTES on one), so it is read again rather than carried.
          listed.jobs.length > 0 &&
          listed.jobs.every((job) => stepsKnown(job) && (job.run_attempt === undefined || job.run_attempt === r.run_attempt))
        ) {
          keepJobs.set(key, { id: r.id, attempt: r.run_attempt, head: r.head_sha, updated_at: r.updated_at, jobs: listed.jobs.map(slimJob) });
        }
        return withAnnotations(call, repo, listed.jobs, (job) => job?.conclusion === "failure");
      };
      const tested = [];
      for (const runs of ciRunsByWorkflow(own)) {
        // A hosted review run is re-run only as a failed first attempt
        // (`upstream`), so no other one's jobs are read.
        if (GATED_REVIEWS.has(runs[0].path) && !reconcilerRetries(runs[0], now)) {
          continue;
        }
        tested.push(await testedRun(runs, readJobs));
      }
      // A re-run still going under a newer failed contract-only run is in
      // flight too, though classify sees only the newest run.
      if (tested.some((t) => !GATED_REVIEWS.has(t?.run?.path) && t?.run?.status !== "completed" && t?.run?.run_attempt > 1)) {
        inFlight += 1;
        continue;
      }
      for (const { run: r, jobs } of tested.filter(Boolean)) {
        if (!jobs) {
          continue;
        }
        if (GATED_REVIEWS.has(r.path)) {
          if (!firstFailure(r, jobs, now) || !upstreamStopped(jobs)) {
            continue;
          }
          const hold = await gateHold();
          if (hold) {
            say(`#${pull.number}: review run ${r.id} (${r.path}) was stopped by the upstream gate; waiting, ${hold}`);
            continue;
          }
          set.push({ kind: "upstream", pr: pull.number, id: r.id, path: r.path, conclusion: "failure (upstream stop)", attempt: 1, head: pull.head.sha });
          continue;
        }
        if (!infraOnly(jobs)) {
          if (firstFailure(r, jobs, now)) {
            set.push({ kind: "flake", pr: pull.number, id: r.id, path: r.path, conclusion: "failure", attempt: 1, head: pull.head.sha });
          }
          continue;
        }
        if (!isRetryable(r, now)) {
          continue;
        }
        const hold = await upstreamHold();
        if (hold) {
          say(`#${pull.number}: run ${r.id} (${r.path}) failed on infra only; waiting, ${hold}`);
          continue;
        }
        set.push({ kind: "infra", pr: pull.number, id: r.id, path: r.path, conclusion: "failure (infra only)", attempt: r.run_attempt, head: pull.head.sha });
      }
      // The one stopped review lane this head re-runs now, as an item, if any.
      const stoppedReview = async () => {
        for (const [path, name] of REVIEW_SWITCHES) {
          const r = newestByWorkflow(own).find((candidate) => candidate.path === path);
          if (!isUnreviewed(r)) {
            continue;
          }
          if (env[name]?.toLowerCase() === "true") {
            say(`#${pull.number}: review run ${r.id} (${r.path}) waits for ${name}`);
            continue;
          }
          if (now - Date.parse(r.created_at) >= RERUN_WINDOW_DAYS * 86_400_000 || !reviewStopped(await readJobs(r))) {
            continue;
          }
          const hold = await gateHold();
          if (hold) {
            say(`#${pull.number}: review run ${r.id} (${r.path}) was stopped by a kill switch; waiting, ${hold}`);
            continue;
          }
          return { kind: "review", pr: pull.number, id: r.id, path: r.path, conclusion: "success (kill switch stop)", attempt: 1, head: pull.head.sha, record: rerunRecordName(r.id, 2, pull.head.sha) };
        }
        return undefined;
      };
      const checks = newestByWorkflow(own).find((r) => RECORDED_UPSTREAMS.has(r.path));
      // A newest checks run that failed only in ci-status: a review a kill
      // switch stopped is re-run once nothing would stop it again, a lanes App
      // PR's that the kill switch failed is re-run now that the switch is off,
      // and any PR's that a running review failed once the reviews are done.
      // The tested run's jobs are reused when it is that run.
      if (set.length === 0 && isRedChecks(checks)) {
        const status = onlyAggregateFailed(tested.find((t) => t?.run?.id === checks.id)?.jobs ?? (await readJobs(checks)));
        const notes = status && (status.annotations ?? (await call("GET", `/repos/${repo}/check-runs/${status.id}/annotations?per_page=100`)));
        // A lanes App PR's ci-status that failed on the kill switch.
        const switchNoted = notes && laneApp !== undefined && pull.user?.id === laneApp && pull.user?.type === "Bot" && killSwitchNoted(notes);
        if (reviewStopNoted(notes)) {
          const review = await stoppedReview();
          if (review) {
            set.push(review);
          }
        } else if (isFailedChecks(checks) && switchNoted) {
          set.push({ kind: "switch", pr: pull.number, id: checks.id, path: checks.path, conclusion: "failure (kill switch)", attempt: 1, head: pull.head.sha });
        } else if (checks.run_attempt >= 2 && switchNoted) {
          say(`#${pull.number}: ci-status failed on the kill switch at attempt ${checks.run_attempt}; a re-run needs a person on the trusted-actor list`);
        } else if (isFailedChecks(checks) && notes && pendingReviewNoted(notes)) {
          // Every PR, not only the lanes App's: a lost rerun-ci-status strands
          // a person's head the same way. ci-status's own pick of each review:
          // the newest pull_request run on the head. Every lane must have one,
          // completed: a lane with none would fail the re-run again.
          const reviews = [...GATED_REVIEWS].map((path) =>
            own.filter((r) => r.path === path && r.event === "pull_request").reduce((a, r) => (a && a.id > r.id ? a : r), undefined),
          );
          const last = Math.max(...reviews.map((r) => Date.parse(r?.updated_at)));
          if (reviews.every((r) => r?.status === "completed") && now - last >= PENDING_BACKOFF_MINUTES * 60_000) {
            set.push({ kind: "pending", pr: pull.number, id: checks.id, path: checks.path, conclusion: "failure (review since finished)", attempt: 1, head: pull.head.sha });
          }
        }
      }
      // A pass the spec has since changed under: re-running the head's
      // passed checks starts pr-verify, which judges it again (resolve-pr's
      // `spec-changed`). Below RECONCILER_ATTEMPT_CAP only, so each passed
      // checks run is re-run at most RECONCILER_ATTEMPT_CAP - 1 times; a
      // later edit or label starts a new attempt-1 run.
      // Every pass at this head came from a pr-verify run that a checks run
      // at this head started on completing, so it started after the earliest
      // checks run here was created: a spec untouched since then is untouched
      // since every pass. Not the newest checks run, which a label or body
      // edit after the pass starts (pr-verify.yml concurrency).
      if (set.length === 0 && judgeSpec && isPassedChecks(checks)) {
        const earliest = Math.min(...own.filter((r) => RECORDED_UPSTREAMS.has(r.path)).map((r) => Date.parse(r.created_at)));
        passed.push({ pull, checks, starts: [Number.isNaN(earliest) ? null : new Date(earliest).toISOString()] });
        // Too old takes a first attempt only: its "no counted verdict" also
        // holds while pr-verify still judges a re-run attempt, which it could
        // not tell from a verdict that never came.
        if (
          checks.run_attempt === 1 &&
          now - Date.parse(pull.created_at) > TOO_OLD_DAYS * 86_400_000 &&
          now - Date.parse(checks.created_at) < RERUN_WINDOW_DAYS * 86_400_000
        ) {
          tooOld.push({ pull, checks });
        }
      }
      if (set.length > 0) {
        ready.push(set.map(withRecord));
      }
    } catch (error) {
      noteFailure(`#${pull.number}`, error);
    }
  }
  // The pass reads run only for a head whose spec moved after its earliest
  // checks run. A read that fails here re-runs nothing and is no listing
  // failure: the next tick asks again. A rate limit still stops the run.
  const knownStarts = new Map([...carriedPasses.values()].flatMap((e) => e.runs.map((r) => [r.id, r.started_at])));
  const readPasses = async (candidates, into, known) => {
    for (const { pull, checks } of candidates) {
      try {
        const { starts, carry } = await passStarts(call, repo, pull.number, pull.head.sha, known);
        if (carry) {
          keepPasses.push(carry);
        }
        if (starts.length > 0) {
          into.push({ pull, checks, starts });
        }
      } catch (error) {
        sayUnchecked(pull, "spec", error);
      }
    }
  };
  // A head the last pass read whole, with none of its passes expired since,
  // goes to the pre-filter on its carried pass starts. A newer pass or a
  // re-run attempt only moves a head's newest start later, so a carried read
  // the pre-filter drops would be dropped live too, and is carried again; one
  // it keeps is read again in full, carried starts included, and pre-filtered
  // again, as it was before.
  const toRead = [];
  for (const candidate of await prefilterSpec(call, repo, passed)) {
    const carried = carriedPasses.get(passesKey(candidate.pull.number, candidate.pull.head.sha));
    if (carried && Date.parse(carried.expires_at) > now) {
      specCandidates.push({ ...candidate, starts: carried.runs.map((r) => r.started_at), carried });
    } else {
      toRead.push(candidate);
    }
  }
  await readPasses(toRead, specCandidates, knownStarts);
  const moved = await prefilterSpec(call, repo, specCandidates);
  const kept = new Set(moved);
  keepPasses.push(...specCandidates.filter((c) => c.carried && !kept.has(c)).map((c) => c.carried));
  const reread = [];
  await readPasses(moved.filter((c) => c.carried), reread, new Map());
  // Only a candidate whose spec moved after its pass gets resolve-pr's full read.
  for (const { pull, checks, starts } of [...moved.filter((c) => !c.carried), ...(await prefilterSpec(call, repo, reread))]) {
    // A re-run attempt is judged by the pr-verify run its completion starts;
    // until that run's pass lands, the old passes still read spec-changed.
    // So a checks run past attempt 1 is taken only once a pass started after
    // its attempt did, and none is re-run again while that judgment runs.
    if (checks.run_attempt > 1 && !starts.some((s) => Date.parse(s) > Date.parse(checks.run_started_at))) {
      say(`#${pull.number}: run ${checks.id} (${checks.path}) attempt ${checks.run_attempt} has no pass since it started; waiting for pr-verify's verdict on it`);
      continue;
    }
    try {
      if ((await judgeSpec(checks.id)).reason === "spec-changed") {
        if (!belowCap(checks)) {
          say(atCap(pull, checks, "its spec changed after the pass"));
          continue;
        }
        ready.push([withRecord({ kind: "spec", pr: pull.number, id: checks.id, path: checks.path, conclusion: "success", attempt: checks.run_attempt, head: pull.head.sha })]);
      }
    } catch (error) {
      sayUnchecked(pull, "spec", error);
    }
  }
  // A pull request past TOO_OLD_DAYS whose head has no counted verdict (an
  // expired pass): the gate refuses it `verify:too-old` until a fresh pass at
  // the head, so its passed checks run is re-run once, at attempt 1, recorded, and
  // pr-verify judges the head (resolve-pr's `ok`). A head a spec re-run
  // already takes is skipped.
  const specPrs = new Set(ready.flat().filter((item) => item.kind === "spec").map((item) => item.pr));
  for (const { pull, checks } of tooOld.filter(({ pull }) => !specPrs.has(pull.number))) {
    try {
      if ((await judgeSpec(checks.id)).reason === "ok") {
        ready.push([withRecord({ kind: "too-old", pr: pull.number, id: checks.id, path: checks.path, conclusion: "success", attempt: 1, head: pull.head.sha })]);
      }
    } catch (error) {
      sayUnchecked(pull, "verdict", error);
    }
  }
  // Spec re-runs join the CI sets in the PRs' merge-critical order. A PR
  // holds at most one entry: a spec re-run only when it has no CI set.
  const position = new Map(pulls.map((p, i) => [p.number, i]));
  ready.sort((a, b) => position.get(a[0].pr) - position.get(b[0].pr));
  const created = createdSince(since);
  const lanes = [];
  // Each lane's runs by id, or the error its listing failed with. Statuses
  // are read in LANE_LIST_STATUSES order for every lane together, so each
  // lane still reads its earlier statuses first and a later read overwrites
  // an earlier one.
  const laneRuns = new Map([...RECORDED_LANES.keys()].map((lanePath) => [lanePath, new Map()]));
  const laneFailures = new Map();
  const runsPage = async (...args) => {
    const page = await call(...args);
    if (!Array.isArray(page?.workflow_runs)) {
      throw new Error("its run listing is not a page of runs");
    }
    return page.workflow_runs;
  };
  // One repository-wide page of the runs in `status`, or undefined when it is
  // not whole or cannot be read, so each lane lists that status itself. The
  // lane listing filters only on `created` and `status`, both of which this
  // endpoint takes; the workflow path is split here.
  const sharedRuns = async (status) => {
    try {
      const page = await call("GET", `/repos/${repo}/actions/runs?created=${created}&status=${status}&per_page=100`);
      if (Array.isArray(page?.workflow_runs) && Number.isInteger(page.total_count) && page.total_count <= page.workflow_runs.length) {
        return page.workflow_runs;
      }
    } catch (error) {
      passRateLimit(error);
    }
    return undefined;
  };
  for (const status of LANE_LIST_STATUSES) {
    const open = [...laneRuns.keys()].filter((lanePath) => !laneFailures.has(lanePath));
    if (open.length === 0) {
      break;
    }
    const shared = SHARED_LIST_STATUSES.has(status) ? await sharedRuns(status) : undefined;
    for (const lanePath of open) {
      try {
        const listed =
          shared?.filter((r) => r?.path === lanePath) ??
          (await paginate(runsPage, `/repos/${repo}/actions/workflows/${workflowFile(lanePath)}/runs?created=${created}&status=${status}`, LANE_RUN_PAGES));
        for (const r of listed) {
          laneRuns.get(lanePath).set(r.id, r);
        }
      } catch (error) {
        passRateLimit(error);
        laneFailures.set(lanePath, error);
      }
    }
  }
  for (const [lanePath, judge] of RECORDED_LANES) {
    try {
      if (laneFailures.has(lanePath)) {
        throw laneFailures.get(lanePath);
      }
      const listed = [...laneRuns.get(lanePath).values()];
      const runs = listed.filter((r) => r.path === lanePath);
      inFlight += runs.filter((r) => r.status !== "completed" && r.run_attempt > 1).length;
      const unpublished = [];
      for (const r of runs.filter((run) => isLostLane(run, since))) {
        if (settled.has(r.id)) {
          settle.push({ id: r.id, reason: settled.get(r.id) });
          sayHeld(r, settled.get(r.id));
          continue;
        }
        try {
          const held = await holdReason(call, repo, r, judge, now - Date.parse(r.updated_at) >= PASS_MINUTES * 60_000, carriedJobs, keepJobs);
          if (held) {
            if (held.settle) {
              settle.push({ id: r.id, reason: held.reason });
            }
            sayHeld(r, held.reason);
          } else {
            unpublished.push(r);
          }
        } catch (error) {
          noteFailure(`lane run ${r.id}`, error);
        }
      }
      // A gated lane's re-run during an npm or Actions outage would spend its
      // one re-run on a run the upstream gate stops again.
      const hold = unpublished.length > 0 && GATED_LANES.has(lanePath) ? await gateHold() : "";
      if (hold) {
        for (const r of unpublished) {
          say(`lane run ${r.id} (${r.path}) ended ${r.conclusion}; waiting, ${hold}`);
        }
        unpublished.length = 0;
      }
      // The record's head is the lane run's own head_sha (main's tip), not
      // the pull request's head: the PR binding is the live gate's job
      // (check-trusted-trigger and resolve-pr), never this record's.
      lanes.push(
        ...unpublished.map((r) => ({ kind: "lane", id: r.id, path: r.path, conclusion: r.conclusion, head: r.head_sha, created_at: r.created_at, record: rerunRecordName(r.id, 2, r.head_sha) })),
      );
    } catch (error) {
      noteFailure(lanePath, error);
    }
  }

  // Runs a GitHub fault held green (faultHeld), each re-run once like a lost
  // lane run, and only while the status page shows Actions operational (main
  // reads nothing otherwise). Each lane's listing starts at the carried
  // `heldFrom`, or FAULT_HELD_HOURS back, whichever is earlier, inside the
  // lookback. A run with no hold is settled, so each succeeded run's jobs are
  // read once, at most FAULT_HELD_READS a pass across the lanes, oldest first.
  // `heldSince` is where the next pass starts: FAULT_HELD_HOURS back, or the
  // oldest run this pass did not read.
  const recent = now - FAULT_HELD_HOURS * 3_600_000;
  const heldStart = Math.max(since, Math.min(recent, heldFrom ?? recent));
  let heldSince = recent;
  const heldCreated = createdSince(heldStart);
  const listed = [];
  for (const lanePath of FAULT_HELD_LANES) {
    try {
      // Newest first; past the page cap the newest runs are kept, and the
      // older ones are named, never read.
      for (let page = 1; page <= LANE_RUN_PAGES; page += 1) {
        const batch = await runsPage("GET", `/repos/${repo}/actions/workflows/${workflowFile(lanePath)}/runs?created=${heldCreated}&status=success&per_page=100&page=${page}`);
        listed.push(...batch);
        if (batch.length < 100) {
          break;
        }
        if (page === LANE_RUN_PAGES) {
          say(`${lanePath}: more than ${LANE_RUN_PAGES * 100} succeeded runs since ${new Date(heldStart).toISOString()}; only the newest are read for a hold`);
        }
      }
    } catch (error) {
      noteFailure(`${lanePath} held runs`, error);
      heldSince = heldStart;
    }
  }
  try {
    const unread = [];
    for (const r of listed.filter((run) => isFaultHeld(run, heldStart)).sort(byAge)) {
      if (settled.has(r.id)) {
        settle.push({ id: r.id, reason: settled.get(r.id) });
      } else {
        unread.push(r);
      }
    }
    for (const [i, r] of unread.entries()) {
      if (i === FAULT_HELD_READS) {
        say(`${unread.length - i} succeeded runs wait for the next pass's hold check`);
        heldSince = Math.min(heldSince, Date.parse(r.created_at));
        break;
      }
      try {
        const { held, final, written } = await faultHeld(call, repo, r);
        if (written) {
          settle.push({ id: r.id, reason: WRITTEN });
          sayHeld(r, WRITTEN);
        } else if (held) {
          // Kept in the next pass's listing until its re-run takes a place.
          heldSince = Math.min(heldSince, Date.parse(r.created_at));
          // A gated lane's re-run during an npm or Actions outage would
          // spend its one re-run on a run the upstream gate stops again.
          const hold = GATED_LANES.has(r.path) ? await gateHold() : "";
          if (hold) {
            say(`lane run ${r.id} (${r.path}) held on a GitHub fault; waiting, ${hold}`);
          } else {
            lanes.push({ kind: "fault-held", id: r.id, path: r.path, conclusion: r.conclusion, head: r.head_sha, created_at: r.created_at, record: rerunRecordName(r.id, 2, r.head_sha) });
          }
        } else if (final) {
          settle.push({ id: r.id, reason: "" });
        }
      } catch (error) {
        noteFailure(`held run ${r.id}`, error);
        heldSince = Math.min(heldSince, Date.parse(r.created_at));
      }
    }
  } catch (error) {
    noteFailure("held runs", error);
    heldSince = heldStart;
  }
  // A run still going can hold in a later job (pr-verify's three jobs each run
  // up to 346 minutes) after FAULT_HELD_HOURS have passed, so the next pass
  // lists back to the oldest first attempt not yet completed. The lane listing
  // above already read those runs (LANE_LIST_STATUSES, inside the lookback),
  // so this adds no read; when it failed, the next pass starts where this one did.
  for (const lanePath of FAULT_HELD_LANES) {
    if (laneFailures.has(lanePath)) {
      heldSince = Math.min(heldSince, heldStart);
      continue;
    }
    for (const r of laneRuns.get(lanePath).values()) {
      if (r.status !== "completed" && r.event === "workflow_run" && r.head_branch === "main" && r.run_attempt === 1 && isTime(r.created_at)) {
        heldSince = Math.min(heldSince, Date.parse(r.created_at));
      }
    }
  }

  // A failed floor-label run takes no place: it is one short job, not CI.
  const intake = [];
  let candidates = [];
  try {
    const listed = await paginate(runsPage, `/repos/${repo}/actions/workflows/${workflowFile(INTAKE)}/runs?created=${created}&status=failure`, LANE_RUN_PAGES);
    candidates = listed.filter((r) => isFailedIntake(r, since) && now - Date.parse(r.updated_at) <= INTAKE_JOBS_WINDOW_MS).sort(byAge);
  } catch (error) {
    noteFailure(INTAKE, error);
  }
  for (const r of candidates) {
    if (settled.has(r.id)) {
      settle.push({ id: r.id, reason: "" });
      continue;
    }
    try {
      const listing = await firstAttemptJobs(call, repo, r.id);
      const rerun = listing.jobs.filter((job) => !NOT_RERUN.has(job?.conclusion));
      if (rerun.length > 0 && rerun.every((job) => String(job?.name ?? "").startsWith(`${INTAKE_LABEL_JOB} / `))) {
        intake.push({ kind: "intake", id: r.id, path: r.path, conclusion: r.conclusion, head: r.head_sha });
      } else if (rerun.length > 0 && wholeListing(listing)) {
        settle.push({ id: r.id, reason: "" });
      }
    } catch (error) {
      noteFailure(`intake run ${r.id}`, error);
    }
  }

  // A verdict the kill switch stopped takes no place either: one short job
  // that posts what the verdict holds. Over the whole lookback, since the
  // switch may have been on for hours.
  const verdicts = [];
  let stopped = [];
  try {
    const listed = await paginate(runsPage, `/repos/${repo}/actions/workflows/${workflowFile(VERDICT_DISPATCH)}/runs?created=${created}&status=failure`, LANE_RUN_PAGES);
    stopped = listed.filter((r) => isStoppedVerdict(r, since)).sort(byAge);
  } catch (error) {
    noteFailure(VERDICT_DISPATCH, error);
  }
  for (const r of stopped) {
    if (settled.has(r.id)) {
      settle.push({ id: r.id, reason: "" });
      continue;
    }
    try {
      const listing = await firstAttemptJobs(call, repo, r.id);
      const rerun = listing.jobs.filter((job) => !NOT_RERUN.has(job?.conclusion));
      const failedSteps = (rerun[0]?.steps ?? []).filter((step) => step?.conclusion === "failure").map((step) => step.name);
      if (rerun.length === 1 && rerun[0].name === VERDICT_JOB && failedSteps.length === 1 && failedSteps[0] === VERDICT_STOP_STEP) {
        verdicts.push({ kind: "verdict", id: r.id, path: r.path, conclusion: r.conclusion, head: r.head_sha });
      } else if (wholeListing(listing) && (rerun.length > 1 || (rerun.length === 1 && (rerun[0].name !== VERDICT_JOB || stepsKnown(rerun[0]))))) {
        // A listing with no failed job, a job without its conclusion, or a
        // step list read before it was whole, is read again next pass.
        settle.push({ id: r.id, reason: "" });
      }
    } catch (error) {
      noteFailure(`verdict run ${r.id}`, error);
    }
  }

  // Every item takes one place: a PR's CI set, or one lane run. A set can hold
  // several records, and the workflow has MAX_IN_FLIGHT upload steps, so what
  // does not fit waits for a later pass: a re-run with no record would be refused.
  let room = Math.max(0, MAX_IN_FLIGHT - inFlight);
  let uploads = MAX_IN_FLIGHT;
  const items = [];
  const place = (what, taken) => {
    const records = taken.filter(recorded).length;
    if (room > 0 && records <= uploads) {
      items.push(...taken);
      room -= 1;
      uploads -= records;
    } else {
      say(`${what}: deferred, ${room > 0 ? "no record upload left this pass" : `all ${MAX_IN_FLIGHT} re-run places taken`}`);
    }
  };
  const flakeOnly = (set) => set.every((item) => item.kind === "flake");
  for (const set of ready.filter((s) => !flakeOnly(s))) {
    place(`#${set[0].pr}`, set);
  }
  for (const lane of laneOrder(lanes, openChecks)) {
    place(`lane run ${lane.id} (${lane.path})`, [lane]);
  }
  for (const set of ready.filter(flakeOnly)) {
    place(`#${set[0].pr}`, set);
  }
  items.push(...intake, ...verdicts);
  return { items, failed, settle, heldSince, jobs: [...keepJobs.values()], passes: [...new Map(keepPasses.map((e) => [passesKey(e.pr, e.head), e])).values()] };
}

// The item kinds that name no PR: act labels them by kind and reads no PR.
const RUN_ONLY_KINDS = new Set(["lane", "fault-held", "intake", "verdict"]);
// The item kinds act re-runs only the failed jobs of, each with its summary tail.
const FAILED_JOBS_WHY = new Map([
  ["intake", ""],
  ["verdict", ""],
  ["infra", ", which failed on infra only"],
  ["flake", ", its one re-run before fix-ci takes it"],
  ["switch", ": ci-status failed while the lanes kill switch was on"],
  ["pending", ": ci-status failed on a review that has since finished"],
  ["upstream", ": the upstream-status gate stopped its review, and the gate lets it run now"],
]);

// Re-runs each planned item still lost on a fresh read.
async function act({ repo, call, say, since, sleep, items }) {
  let failed = 0;
  let wrote = false;
  for (const item of items) {
    const where = RUN_ONLY_KINDS.has(item.kind) ? item.kind : `#${item.pr}`;
    try {
      if (recorded(item) && item.record !== rerunRecordName(item.id, nextAttempt(item), item.head)) {
        throw new Error("the plan names no record for it");
      }
      const r = await call("GET", `/repos/${repo}/actions/runs/${item.id}`);
      if (!lostNow(item, r, since)) {
        say(`${where}: run ${item.id} changed since the listing; left alone`);
        continue;
      }
      if (!RUN_ONLY_KINDS.has(item.kind)) {
        // A push since the listing makes this run obsolete, and re-running it
        // would cancel the new head's CI in the PR's concurrency group.
        const current = await call("GET", `/repos/${repo}/pulls/${item.pr}`);
        if (current?.state !== "open" || current.draft === true || current.head?.sha !== item.head) {
          say(`${where}: the PR changed since the listing; run ${item.id} left alone`);
          continue;
        }
      }
      if (wrote) {
        await sleep(WRITE_GAP_MS);
      }
      wrote = true;
      if (FAILED_JOBS_WHY.has(item.kind)) {
        await call("POST", `/repos/${repo}/actions/runs/${item.id}/rerun-failed-jobs`);
        say(
          item.kind === "intake"
            ? `${where}: re-ran the failed jobs of floor-label run ${item.id}, whose first attempt failed`
            : item.kind === "verdict"
              ? `${where}: re-ran run ${item.id} (${item.path}), whose pr-verify verdict the lanes kill switch kept from its PR`
              : `${where}: re-ran the failed jobs of run ${item.id} (${item.path}) attempt ${item.attempt}${FAILED_JOBS_WHY.get(item.kind)}`,
        );
        continue;
      }
      await call("POST", `/repos/${repo}/actions/runs/${item.id}/rerun`);
      say(
        item.kind === "spec"
          ? `${where}: re-ran run ${item.id} (${item.path}) so pr-verify judges the head again: its spec changed after the pass`
          : item.kind === "too-old"
            ? `${where}: re-ran run ${item.id} (${item.path}) so pr-verify judges the head again: the pull request is past ${TOO_OLD_DAYS} days and its head has no verdict`
            : item.kind === "review"
            ? `${where}: re-ran review run ${item.id} (${item.path}), which a kill switch stopped; its completion re-runs ci-status`
            : item.kind === "fault-held"
            ? `${where}: re-ran run ${item.id} (${item.path}), which held on a GitHub fault`
            : `${where}: re-ran run ${item.id} (${item.path}), which ended ${item.conclusion}`,
      );
    } catch (error) {
      passRateLimit(error);
      if (item.kind === "pending") {
        console.log(`::warning title=reconcile::${where} run ${item.id}: ${escapeCommand(error?.message ?? error)}`);
        continue;
      }
      failed += 1;
      console.log(`::error title=reconcile::${where} run ${item.id}: ${escapeCommand(error?.message ?? error)}`);
    }
  }
  return failed;
}

// The plan's record-N outputs, each a record name or empty.
function recordOutputs(items) {
  const names = items.filter(recorded).map((item) => item.record);
  if (names.length > MAX_IN_FLIGHT || !names.every(isRecordName)) {
    throw new Error("the plan's record names are malformed");
  }
  return Object.fromEntries(Array.from({ length: MAX_IN_FLIGHT }, (_, i) => [`record-${i + 1}`, names[i] ?? ""]));
}

export async function main({ env = process.env, github, fetchStatus: readStatus = fetchStatus, sleep = delay, now = Date.now(), download } = {}) {
  const lines = [];
  const say = (line) => {
    console.log(`reconcile: ${line}`);
    lines.push(`- ${line}`);
  };
  const finish = (code) => {
    if (env.GITHUB_STEP_SUMMARY && lines.length > 0) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, `### Lost-run reconciler (${env.MODE})\n\n${lines.join("\n")}\n`);
    }
    return code;
  };
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.MODE !== "plan" && env.MODE !== "act") {
      throw new Error("MODE is neither plan nor act");
    }
    if (!env.PLAN_PATH) {
      throw new Error("PLAN_PATH is not set");
    }
    const repo = env.GITHUB_REPOSITORY;
    let last;
    const injected = github !== undefined;
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, onResponse: (r) => (last = r) });
    const call = async (...args) => {
      try {
        return await github(...args);
      } catch (error) {
        const limited =
          error?.status === 429 ||
          (error?.status === 403 && (last?.headers?.get("x-ratelimit-remaining") === "0" || last?.headers?.has("retry-after")));
        throw limited ? new RateLimited(`rate limited at ${args[0]} ${args[1]}`) : error;
      }
    };
    const since = now - LOOKBACK_HOURS * 3_600_000;

    if (env.MODE === "act") {
      const planned = JSON.parse(readFileSync(env.PLAN_PATH, "utf8"));
      if (!Array.isArray(planned?.items) || !Number.isInteger(planned.failed)) {
        throw new Error("the plan file does not hold a plan");
      }
      const failed = await act({ repo, call, say, since, sleep, items: planned.items });
      if (planned.failed + failed > 0) {
        console.log(`::error title=reconcile::the plan step recorded ${planned.failed} listing failures and ${failed} re-runs failed; see the Find lost runs step`);
        return finish(1);
      }
      return finish(0);
    }

    let result = { items: [], failed: 0 };
    // A full plan that read every listing; the kill switch, an Actions outage
    // or a failed listing leaves it false (the pacer's marker reads it).
    let clean = false;
    const write = () => {
      writeFileSync(env.PLAN_PATH, JSON.stringify(result));
      // A Verdict re-run leaves a pr-feedback-deferred record, so the plan
      // names it first (DEFERRAL_MARKER): the tick reads per-head records only
      // while one is listed.
      const outputs = { ...recordOutputs(result.items), deferral: result.items.some((item) => item.kind === "verdict") ? "true" : "", clean: clean ? "true" : "" };
      if (outputs["record-1"] !== "") {
        writeFileSync(env.RECORD_PATH, JSON.stringify(result.items.filter(recorded)));
      }
      if (env.GITHUB_OUTPUT) {
        writeOutputs(outputs, env.GITHUB_OUTPUT);
      }
    };
    if (env.KILL_SWITCH !== "proceed") {
      say("the lanes kill switch stops this run; nothing read or re-run");
      write();
      return finish(0);
    }
    let status;
    try {
      status = actionsStatus(await readStatus(env.STATUS_URL || STATUS_URL));
    } catch (error) {
      status = `unreadable (${error?.message ?? error})`;
    }
    if (status !== "operational") {
      say(`Actions is ${status ?? "missing from the status page"}; idle until it is operational`);
      write();
      return finish(0);
    }
    // resolve-pr's own read, with pr-verify.yml's inputs: `spec-changed` is
    // exactly a head pr-verify would judge again. Without the trusted list
    // nothing is checked.
    let judgeSpec;
    // The lanes App's account id, from the trusted list by merge.agent-identity.
    let laneApp;
    if (env.TRUSTED_ACTORS_PATH) {
      const trusted = loadTrustedList(env.TRUSTED_ACTORS_PATH);
      laneApp = env.LANE_IDENTITY ? trusted.logins.get(env.LANE_IDENTITY.toLowerCase()) : undefined;
      // The Refs read needs GraphQL errors back to tell a typo from a failure.
      const readRefs = injected ? github : createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, keepGraphQLErrors: true });
      judgeSpec = (upstreamRunId) =>
        resolvePull({
          github: call,
          readRefs,
          repository: repo,
          upstreamRunId,
          humans: trusted.humans,
          verifyAuthors: env.VERIFY_AUTHORS ?? "lane",
          laneIdentity: env.LANE_IDENTITY,
          ownerIds: [...trusted.ids],
          specFromBodyApps: specFromBodyApps(env.SPEC_FROM_BODY_APPS),
        });
    }
    let settled = { runs: new Map(), jobs: new Map(), passes: new Map() };
    if (env.SETTLED_PATH) {
      try {
        download ??= ghDownloadArtifact({ repo, token: env.GH_TOKEN, dir: env.RUNNER_TEMP, name: SETTLED_ARTIFACT, file: SETTLED_FILE });
        settled = await readSettled({ repo, runId: String(env.GITHUB_RUN_ID), call, download });
      } catch (error) {
        passRateLimit(error);
        console.log(`::warning title=reconcile::no settled runs carried, so every run is read: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    const { settle, jobs, passes, heldSince, ...planned } = await plan({
      repo,
      call,
      say,
      since,
      now,
      readStatus,
      judgeSpec,
      laneApp,
      settled: settled.runs,
      carriedJobs: settled.jobs,
      carriedPasses: settled.passes,
      heldFrom: settled.heldSince,
      env,
    });
    result = planned;
    if (result.items.some(recorded) && !env.RECORD_PATH) {
      throw new Error("RECORD_PATH is not set");
    }
    clean = result.failed === 0;
    write();
    if (env.SETTLED_PATH) {
      writeFileSync(env.SETTLED_PATH, JSON.stringify({ version: SETTLED_VERSION, repository: repo, runs: [...new Map(settle.map((r) => [r.id, r])).values()], jobs, passes, held_since: new Date(heldSince).toISOString() }));
    }
    if (lines.length === 0 && result.items.length === 0) {
      say(result.failed > 0 ? `${result.failed} listings failed; what was lost is unknown` : "nothing lost");
    }
    return finish(0);
  } catch (error) {
    console.log(`::error title=reconcile::${escapeCommand(error?.message ?? error)}; the run stops`);
    return finish(1);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
