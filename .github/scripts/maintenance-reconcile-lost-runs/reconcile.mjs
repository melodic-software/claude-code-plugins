#!/usr/bin/env node
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { deferResets } from "../../actions/check-kill-switch/stop-record.mjs";
import { createGitHub, paginate } from "../lib/github-client.mjs";
import { listChangedAt } from "../lib/trusted-actors.mjs";
import { callers, jobNames, laneJob } from "../lib/lane-registry.mjs";
import { annotationsPath, firstAttemptJobsPath, graphqlCall, isObject, jobsKey, serveFirstAttemptJobs, slimJob } from "../lib/run-jobs.mjs";
import { loadTrustedList, RECONCILER_ATTEMPT_CAP, rerunRecordName } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { escapeCommand, ghDownloadArtifact, newestTrustedArtifact } from "../pr-merge/rotation.mjs";
import { HELD_STEP, refsIssue, resolvePull, specFromBodyApps } from "../pr-verify/resolve-pr.mjs";
import { checkUpstreamStatus } from "../../actions/check-upstream-status/check-upstream-status.mjs";
import { ACTIONS, componentStatus, fetchStatus } from "./component-status.mjs";
import { followUp } from "./followup.mjs";
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
  setupFailed,
  stepsKnown,
  testedRun,
} from "./infra-failure.mjs";

const STATUS_URL = ACTIONS.url;
export const NPM_STATUS_URL = "https://status.npmjs.org/api/v2/status.json";
export const GITHUB_STATUS_URL = "https://www.githubstatus.com/api/v2/status.json";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RECORD = /^reconcile-rerun-[1-9][0-9]{0,19}-([1-9][0-9]{0,4})-[0-9a-f]{40}$/;
const isRecordName = (name) => {
  const attempt = Number(RECORD.exec(name)?.[1]);
  return attempt >= 2 && attempt <= RECONCILER_ATTEMPT_CAP;
};

export { LOST };

export const LANE_LOST = new Set([...LOST, "failure"]);
export const REVIEW_SWITCHES = new Map([
  [".github/workflows/pr-review-hosted.yml", "CLAUDE_REVIEW_DISABLED"],
  [".github/workflows/pr-review-security-hosted.yml", "CLAUDE_SECURITY_REVIEW_DISABLED"],
]);
export const GATED_REVIEWS = new Set(REVIEW_SWITCHES.keys());
export const CI_WORKFLOWS = new Set([
  ".github/workflows/pr-require-checks.yml",
  ".github/workflows/pr-test-platforms.yml",
  ".github/workflows/pr-check-managed-files-hosted.yml",
  ...GATED_REVIEWS,
]);
export const GATE_JOBS = new Set([...GATED_REVIEWS].flatMap((path) => jobNames(path.slice(".github/workflows/".length), "check-kill-switch")));
export const UPSTREAM_STOP_STEP = "Stop on upstream status";
export const REVIEW_STOP_STEP = "Report the kill switch";
const PR_REVIEW_CLI = "melodic-software/ci-workflows/.github/workflows/pr-review-cli.yml";
export const REVIEW_JOB_PREFIXES =[...GATED_REVIEWS].flatMap((path) => {
  const workflow = path.slice(".github/workflows/".length);
  return callers(workflow, PR_REVIEW_CLI).flatMap((id) => jobNames(workflow, id));
});
// GitHub re-runs a run up to 30 days after its initial run
// (https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs).
export const RERUN_WINDOW_DAYS = 30;
export const TOO_OLD_DAYS = 80;
export const RECORDED_UPSTREAMS = new Set([".github/workflows/pr-require-checks.yml"]);
export const INTAKE = ".github/workflows/intake-triage.yml";
export const INTAKE_LABEL_JOBS = jobNames("intake-triage.yml", "intake-label-needs-triage");
const isIntakeLabelJob = (job) => INTAKE_LABEL_JOBS.some((name) => String(job?.name ?? "").startsWith(`${name} / `));
export const VERDICT_DISPATCH = ".github/workflows/pr-dispatch-feedback.yml";
export const VERDICT_JOBS = new Set(jobNames("pr-dispatch-feedback.yml", "post-verify-notes"));
export const VERDICT_STOP_STEP = "Stop on the kill switch";
const NOT_RERUN = new Set(["success", "skipped", "neutral"]);
const INTAKE_JOBS_WINDOW_MS = 2 * 3_600_000;
export const JUDGE_STEP = "Judge the pull request";
export const JUDGE_PREDECESSOR = "Write the prompt and schema";
export const WRITE_STEP = "Write the verdict";
export const REVIEW_STEP = "Review chunk 1";
export const RATE_STEP = "Rate the pull request";
export const RATE_WRITE_STEP = "Write the rating";
export const RATER = ".github/workflows/pr-rate-merge-risk.yml";
const LANES = new Map([
  [".github/workflows/pr-verify.yml", { judge: JUDGE_STEP, write: WRITE_STEP, triggers: ["success", "failure"], gated: false, faultHeld: true }],
  [".github/workflows/pr-review-main.yml", { judge: REVIEW_STEP, write: WRITE_STEP, triggers: ["success"], gated: true, faultHeld: true }],
  [RATER, { judge: RATE_STEP, write: RATE_WRITE_STEP, triggers: ["success"], gated: false, faultHeld: true }],
]);
const lanesWhere = (flag) => new Set([...LANES].filter(([, lane]) => lane[flag]).map(([path]) => path));
export const RECORDED_LANES = new Map([...LANES].map(([path, { judge, write }]) => [path, { judge, write }]));
export const LANE_TRIGGERS = new Map([...LANES].map(([path, { triggers }]) => [path, new Set(triggers)]));
export const GATED_LANES = lanesWhere("gated");
export const FAULT_HELD_LANES = lanesWhere("faultHeld");
export const RATER_SWITCH_STEP = "Check the kill switch";
export const RATER_RESOLVE_STEP = "Resolve the pull request";
export const RATER_LEGS = ["rate-merge-risk", "rate-merge-risk-subscription", "rate-merge-risk-fallback"].map((id) => laneJob("pr-rate-merge-risk.yml", id).name);
export const FAULT_HELD_HOURS = 6;
export const FAULT_HELD_READS = 100;
export const MAX_IN_FLIGHT = 3;
export const DEFER_MAX = 12;
export const RECORD_SLOTS = MAX_IN_FLIGHT + DEFER_MAX;
export const WRITE_GAP_MS = 1000;
export const LANE_RUN_PAGES = 5;
export const LANE_LIST_STATUSES = [...LANE_LOST, "requested", "pending", "waiting", "queued", "in_progress"];
export const SHARED_LIST_STATUSES = new Set(LANE_LIST_STATUSES.filter((s) => s !== "cancelled" && s !== "failure"));

export const SETTLED_ARTIFACT = "reconcile-settled-runs";
export const SETTLED_FILE = "settled.json";
const WORKFLOW_PATH = ".github/workflows/maintenance-reconcile-lost-runs.yml";
export const SETTLED_VERSION = 4;

class RateLimited extends Error {}
export const passRateLimit = (error) => {
  if (error instanceof RateLimited) {
    throw error;
  }
};

export const upstreamGate = (readStatus) => {
  let gate;
  return async () =>
    (gate ??= checkUpstreamStatus({ fetchStatus: readStatus }).then(
      (result) => (result.degraded === "true" ? `the upstream gate still reads ${escapeCommand(result.reason)}` : ""),
      (error) => `the upstream gate could not be read (${escapeCommand(error?.message ?? error)})`,
    ));
};

const carriedJobsEntry = (e) =>
  Number.isSafeInteger(e?.id) &&
  e.id > 0 &&
  Number.isSafeInteger(e.attempt) &&
  e.attempt > 0 &&
  SHA.test(e.head ?? "") &&
  typeof e.updated_at === "string" &&
  Array.isArray(e.jobs) &&
  e.jobs.every(isObject) &&
  (e.held === undefined || e.held === true) &&
  (e.deferred === undefined || (e.deferred === true && e.held === true && e.reset !== undefined)) &&
  (e.reset === undefined || (Number.isSafeInteger(e.reset) && e.reset > 0));

const isTime = (value) => typeof value === "string" && !Number.isNaN(Date.parse(value));
const passesKey = (pr, head) => `${pr}:${head}`;
const carriedPassesEntry = (e) =>
  Number.isSafeInteger(e?.pr) &&
  e.pr > 0 &&
  SHA.test(e.head ?? "") &&
  isTime(e.expires_at) &&
  Array.isArray(e.runs) &&
  e.runs.length > 0 &&
  e.runs.every((r) => Number.isSafeInteger(r?.id) && r.id > 0 && isTime(r.started_at));

const positiveId = (value) => Number.isSafeInteger(value) && value > 0;
export const waitingReview = (e) => positiveId(e?.checksRunId) && positiveId(e.reviewRunId) && positiveId(e.pr) && SHA.test(e.head ?? "") && GATED_REVIEWS.has(e.path);

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
    (data.held_since !== undefined && !isTime(data.held_since)) ||
    (data.waiting_reviews !== undefined && (!Array.isArray(data.waiting_reviews) || !data.waiting_reviews.every(waitingReview)))
  ) {
    throw new Error("the settled runs file has an unexpected shape");
  }
  return {
    runs: new Map(data.runs.map((r) => [r.id, r.reason])),
    jobs: new Map(data.jobs.map((e) => [jobsKey(e.id, e.attempt), e])),
    passes: new Map((data.passes ?? []).map((e) => [passesKey(e.pr, e.head), e])),
    waiting: data.waiting_reviews ?? [],
    ...(data.held_since !== undefined ? { heldSince: Date.parse(data.held_since) } : {}),
  };
}

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

const wholeListing = (listing) =>
  Array.isArray(listing?.jobs) && listing.jobs.length === listing.total_count && listing.jobs.every((job) => job?.status === "completed" && job.conclusion != null);

const workflowFile = (path) => path.slice(path.lastIndexOf("/") + 1);
const createdSince = (ms) => encodeURIComponent(`>=${new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z")}`);

async function firstAttemptJobs(call, repo, id) {
  const listing = await call("GET", firstAttemptJobsPath(repo, id));
  if (!Array.isArray(listing?.jobs) || listing.total_count > 100) {
    throw new Error("its job listing is not one complete page");
  }
  return listing;
}

export const actionsStatus = (page) => componentStatus(page, ACTIONS.name);

const newerFirst = (a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || b.id - a.id;

export function newestByWorkflow(runs) {
  const newest = new Map();
  for (const r of runs) {
    const seen = newest.get(r.path);
    if (!seen || newerFirst(r, seen) < 0) {
      newest.set(r.path, r);
    }
  }
  return [...newest.values()];
}

function ciRunsByWorkflow(runs) {
  const byPath = new Map();
  for (const r of runs.filter((run) => CI_WORKFLOWS.has(run.path) && run.event === "pull_request")) {
    byPath.set(r.path, [...(byPath.get(r.path) ?? []), r]);
  }
  return [...byPath.values()].map((list) => list.sort(newerFirst));
}

const isLost = (r, since) => r.status === "completed" && LOST.has(r.conclusion) && r.run_attempt === 1 && Date.parse(r.created_at) >= since;
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
const isFaultHeld = (r, since) =>
  FAULT_HELD_LANES.has(r.path) &&
  r.event === "workflow_run" &&
  r.head_branch === "main" &&
  SHA.test(r.head_sha ?? "") &&
  r.status === "completed" &&
  r.conclusion === "success" &&
  r.run_attempt === 1 &&
  Date.parse(r.created_at) >= since;
const HELD_NOTE = /^held: /;
export const heldNoted = (annotations) =>
  Array.isArray(annotations) && annotations.some((a) => a?.annotation_level === "notice" && HELD_NOTE.test(String(a.message ?? "")));
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
export const KILL_SWITCH_NOTE = "the lanes kill switch is on";
export const isRedChecks = (r) => RECORDED_UPSTREAMS.has(r?.path) && r.event === "pull_request" && r.status === "completed" && r.conclusion === "failure";
const isFailedChecks = (r) => isRedChecks(r) && r.run_attempt === 1;
const isRunningChecks = (r) => RECORDED_UPSTREAMS.has(r?.path) && r.event === "pull_request" && r.status !== "completed";
export const onlyAggregateFailed = (jobs) =>
  Array.isArray(jobs) && jobs.every((job) => !FAILED.has(job?.conclusion) || AGGREGATE_JOBS.has(job.name))
    ? gateEntries(jobs).find((job) => job.conclusion === "failure" && Number.isSafeInteger(job.id))
    : undefined;
export const killSwitchNoted = (annotations) =>
  Array.isArray(annotations) && annotations.some((a) => a?.annotation_level === "failure" && String(a.message ?? "").includes(KILL_SWITCH_NOTE));
export const REVIEW_STOP_NOTE = "a kill switch was on when it started";
export const reviewStopNoted = (annotations) =>
  Array.isArray(annotations) && annotations.some((a) => a?.annotation_level === "failure" && String(a.message ?? "").includes(REVIEW_STOP_NOTE));
export const RATE_HELD_NOTE = "on a GitHub API rate limit, so it ran no review that counts";
export const rateHeldNoted = (annotations) =>
  Array.isArray(annotations) && annotations.some((a) => a?.annotation_level === "failure" && String(a.message ?? "").includes(RATE_HELD_NOTE));
export const EXIT_NOTE = /^Process completed with exit code [0-9]+\.$/;
const failureCauses = (annotations) =>
  (Array.isArray(annotations) ? annotations : []).filter((a) => a?.annotation_level === "failure" && !EXIT_NOTE.test(String(a.message ?? "")));
const stopCause = (a) => reviewStopNoted([a]) || rateHeldNoted([a]);
export const onlyReviewStopsNoted = (annotations) => {
  const causes = failureCauses(annotations);
  return causes.length > 0 && causes.every(stopCause);
};
const RERUN_TAIL = String.raw`(?:ci-status re-runs when the review finishes\.|ci-status waited [0-9]+s for it; pr-dispatch-feedback re-runs ci-status a few minutes after the review finishes, so no manual re-run is needed\.)`;
export const PENDING_REVIEW_NOTE = new RegExp(String.raw`^'[^']+' has not finished on [0-9a-f]{40} \(https:\/\/[^ ]+\)\. ${RERUN_TAIL}$`);
const MISSING_TAIL = String.raw`(?:${RERUN_TAIL}|ci-status does not wait for a lane with no run; pr-dispatch-feedback re-runs ci-status a few minutes after the review finishes, so no manual re-run is needed\.)`;
export const MISSING_REVIEW_NOTE = new RegExp(String.raw`^'[^']+' is missing: no [a-z-]+\.yml run on [0-9a-f]{40} yet\. ${MISSING_TAIL}$`);
export const pendingReviewNoted = (annotations) => {
  const failures = (Array.isArray(annotations) ? annotations : []).filter((a) => a?.annotation_level === "failure").map((a) => String(a.message ?? ""));
  const pending = failures.filter((m) => PENDING_REVIEW_NOTE.test(m) || MISSING_REVIEW_NOTE.test(m)).length;
  const exits = failures.filter((m) => EXIT_NOTE.test(m)).length;
  return pending > 0 && exits <= 1 && pending + exits === failures.length;
};
export const FLOOR_NOTE =
  /(?:was not sent: GitHub's .+? rate limit holds until |hit GitHub's .+? rate limit(?: \(status [0-9]+\))?: no call to it before |at or under its stop-floor share [0-9.]+ \(status [0-9]+\): no call to it before |GitHub's .+? rate limit blocks '.+?' until )/;
const FLOOR_COMPANION = /^could not /;
export const floorNoted = (annotations) => {
  const failures = (Array.isArray(annotations) ? annotations : []).filter((a) => a?.annotation_level === "failure").map((a) => String(a.message ?? ""));
  return failures.some((m) => FLOOR_NOTE.test(m)) && failures.every((m) => FLOOR_NOTE.test(m) || FLOOR_COMPANION.test(m) || EXIT_NOTE.test(m));
};
const jqUri = (text) => encodeURIComponent(text).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
const literal = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const TARGET_FORMS = [
  [/#([1-9][0-9]*)\b/g, (id) => `/(?:pulls|issues)/${id}(?![0-9])`],
  [/\brun ([1-9][0-9]*)\b/g, (id) => `/actions/runs/${id}(?![0-9])`],
  [/\bjob ([1-9][0-9]*)\b/g, (id) => `/(?:check-runs|actions/jobs)/${id}(?![0-9])`],
  [/\b([0-9a-f]{40})\b/g, (id) => `[/=]${id}(?![0-9a-f])`],
  [/^could not read the push history of (.+); re-run this run\.$/g, (branch) => `[?&]ref=${literal(jqUri(`refs/heads/${branch}`))}(?=[&' ]|$)`],
];
const namedCalls = (message) => TARGET_FORMS.flatMap(([named, call]) => [...message.matchAll(named)].map((m) => new RegExp(call(m[1]))));
const floorCompanion = (message, floors) => FLOOR_COMPANION.test(message) && namedCalls(message).some((call) => floors.some((f) => call.test(f)));
const HUMAN_GATED_NOTE = /^#[1-9][0-9]* carries '[^']+'(?: \(.*\))?\. Removing the label approves this pull request; ci-status re-runs on the unlabel\.$/;
const CONTRACT_HOLD_NOTE = /^check-contract: this PR carries the '[^']+' (?:label; remove it to merge|hold label; a person removes it to release the hold)\.$/;
const CONTRACT_FAILED_NOTE = "ci-status: the pull-request contract or the draft policy failed; see the step above.";
export const reviewStopsAmidGateNotes = (annotations) => {
  const causes = failureCauses(annotations);
  const messages = causes.map((a) => String(a.message ?? ""));
  const floors = messages.filter((m) => FLOOR_NOTE.test(m));
  const contractHeld = messages.some((m) => CONTRACT_HOLD_NOTE.test(m));
  const holdNote = (m) => HUMAN_GATED_NOTE.test(m) || CONTRACT_HOLD_NOTE.test(m) || (contractHeld && m === CONTRACT_FAILED_NOTE);
  const gateNote = (a) => {
    const m = String(a.message ?? "");
    return stopCause(a) || killSwitchNoted([a]) || PENDING_REVIEW_NOTE.test(m) || MISSING_REVIEW_NOTE.test(m) || FLOOR_NOTE.test(m) || floorCompanion(m, floors) || holdNote(m);
  };
  return causes.some(stopCause) && causes.every(gateNote);
};
const FLOOR_TIME = /(?:until|before) ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z)( \(fallback)?/g;
const namedReset = (annotations, counts) => {
  const named = (Array.isArray(annotations) ? annotations : [])
    .filter((a) => counts(a) && FLOOR_NOTE.test(String(a.message ?? "")))
    .flatMap((a) => [...String(a.message).matchAll(FLOOR_TIME)].map((m) => ({ at: Date.parse(m[1]), guess: m[2] !== undefined })))
    .filter((t) => !Number.isNaN(t.at));
  const real = named.filter((t) => !t.guess);
  return Math.max(0, ...(real.length > 0 ? real : named).map((t) => t.at));
};
export const floorReset = (annotations) => namedReset(annotations, (a) => a?.annotation_level === "failure");
export const heldReset = (annotations) => namedReset(annotations, () => true);
export const RATE_WINDOW_MS = 3_600_000;
export const PENDING_BACKOFF_MINUTES = 20;
const isUnreviewed = (r) => GATED_REVIEWS.has(r?.path) && r.event === "pull_request" && r.status === "completed" && r.conclusion === "success" && r.run_attempt === 1;
const isRetryable = (r, now) => reconcilerRetries(r, now) && now - Date.parse(r.updated_at) >= INFRA_BACKOFF_MINUTES * 60_000;
const lostNow = (item, r, since) => {
  if (r?.head_sha !== item.head) {
    return false;
  }
  if (item.kind === "infra" || item.kind === "flake" || item.kind === "floor" || item.kind === "switch" || item.kind === "pending" || item.kind === "upstream") {
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

export function classify(runs, since) {
  const newest = newestByWorkflow(runs);
  const ci = newest.filter((r) => CI_WORKFLOWS.has(r.path));
  const plain = ci.filter((r) => !GATED_REVIEWS.has(r.path));
  return {
    rerun: plain.filter((r) => r.event === "pull_request" && isLost(r, since)),
    again: plain.filter((r) => r.event === "pull_request" && isLostAgain(r, since)),
    lane: newest.filter((r) => (!CI_WORKFLOWS.has(r.path) || GATED_REVIEWS.has(r.path)) && isLost(r, since)),
    inFlight: plain.some((r) => r.status !== "completed" && r.run_attempt > 1),
  };
}

export const reconciledPull = (p, repo) => p?.state === "open" && p.draft !== true && p.base?.ref === "main" && p.head?.repo?.full_name === repo && SHA.test(p.head?.sha ?? "");

export const ciRecoveryFirst = (own, since) => {
  const { rerun, inFlight } = classify(own, since);
  return (
    inFlight ||
    rerun.length > 0 ||
    newestByWorkflow(own).some(
      (r) => CI_WORKFLOWS.has(r.path) && !GATED_REVIEWS.has(r.path) && !RECORDED_UPSTREAMS.has(r.path) && r.event === "pull_request" && r.status === "completed" && r.conclusion === "failure" && r.run_attempt === 1,
    )
  );
};

const nextAttempt = (item) => (item.attempt ?? 1) + 1;
const withRecord = (item) =>
  item.kind === "upstream" ||
  (RECORDED_UPSTREAMS.has(item.path) && (item.kind === "ci" || item.kind === "spec" || item.kind === "too-old" || item.attempt === 1))
    ? { ...item, record: rerunRecordName(item.id, nextAttempt(item), item.head) }
    : item;
const recorded = (item) => item.kind === "lane" || item.kind === "fault-held" || item.record !== undefined;

const byMergeCriticality = (a, b) => Number(b.auto_merge != null) - Number(a.auto_merge != null) || a.number - b.number;
const byAge = (a, b) => Date.parse(a.created_at) - Date.parse(b.created_at) || a.id - b.id;

const MATCH_BEFORE_MS = 60_000;
const MATCH_AFTER_MS = 15 * 60_000;
const OWNED_AFTER_MS = 2 * 3_600_000;

const checksDone = (own) => {
  const done = own.filter((r) => RECORDED_UPSTREAMS.has(r.path) && r.event === "pull_request" && r.status === "completed" && isTime(r.updated_at));
  return done.length > 0 ? Math.max(...done.map((r) => Date.parse(r.updated_at))) : undefined;
};

const laneStarts = (own) => {
  const starts = new Map();
  for (const r of own) {
    if (RECORDED_UPSTREAMS.has(r.path) && r.event === "pull_request" && r.status === "completed" && isTime(r.updated_at)) {
      for (const [lanePath, conclusions] of LANE_TRIGGERS) {
        if (conclusions.has(r.conclusion)) {
          starts.set(lanePath, Math.max(starts.get(lanePath) ?? 0, Date.parse(r.updated_at)));
        }
      }
    }
  }
  return starts;
};

const followsNoOpenHead = (run, openChecks) => {
  const starts = openChecks.map((c) => c.starts.get(run.path)).filter((t) => t !== undefined);
  const created = Date.parse(run.created_at);
  return starts.length > 0 && !starts.some((t) => created >= t - MATCH_BEFORE_MS && created <= t + OWNED_AFTER_MS);
};

function laneOrder(lanes, openChecks, drop) {
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
  const superseded = drop ? lanes.filter((l) => l.kind === "lane" && followsNoOpenHead(l, openChecks)) : [];
  const rest = lanes.filter((l) => !matched.has(l) && !superseded.includes(l));
  const owned = lanes.filter((l) => matched.has(l)).sort(byAge);
  return { order: [...owned.filter((l) => l.kind === "fault-held"), ...owned.filter((l) => l.kind !== "fault-held"), ...rest.sort(byAge)], superseded };
}

export const withAnnotations = (call, repo, jobs, wanted = () => true) =>
  Promise.all(
    jobs.map(async (job) =>
      wanted(job) && !stepsKnown(job) && Number.isSafeInteger(job?.id)
        ? { ...job, annotations: await call("GET", annotationsPath(repo, job.id)) }
        : job,
    ),
  );

const floorFailed = async (call, repo, jobs) => {
  const lanes = jobs.filter((job) => FAILED.has(job?.conclusion) && !AGGREGATE_JOBS.has(job.name));
  if (lanes.length === 0 || !lanes.every((job) => job.conclusion === "failure" && Number.isSafeInteger(job.id))) {
    return undefined;
  }
  const notes = [];
  for (const job of lanes) {
    const annotations = job.annotations ?? (await call("GET", annotationsPath(repo, job.id)));
    if (!floorNoted(annotations)) {
      return undefined;
    }
    notes.push(...annotations);
  }
  return floorReset(notes);
};
const beforeReset = (reset, now) => reset !== undefined && now <= reset + RATE_RESET_GRACE_MS;
const sayReset = (reset) => `waiting for the rate-limit reset at ${new Date(reset).toISOString()}`;

const NOT_STARTED = "before any of its jobs started";
export const PASS_MINUTES = 30;

export const upstreamStopped = (jobs) =>
  Array.isArray(jobs) &&
  jobs.filter((job) => FAILED.has(job?.conclusion)).length === 1 &&
  jobs.some(
    (job) =>
      GATE_JOBS.has(job?.name) &&
      job.conclusion === "failure" &&
      Array.isArray(job.steps) &&
      job.steps.some((step) => step?.name === UPSTREAM_STOP_STEP && step.conclusion === "failure"),
  );

export const reviewStopped = (jobs) =>
  Array.isArray(jobs) &&
  !jobs.some((job) => REVIEW_JOB_PREFIXES.some((prefix) => (job?.name ?? "").startsWith(prefix)) && job.conclusion !== "skipped") &&
  jobs.some((job) => GATE_JOBS.has(job?.name) && job.conclusion === "success" && job.steps?.some((step) => step?.name === REVIEW_STOP_STEP && step.conclusion === "success"));

const CLAUDE_REVIEW_STEP = "Claude review";
const APPLY_HOLD_STEP = "Apply the hold";
const LEG_HOLD_NOTE = "this leg holds and runs no review";
const RATE_REFUSAL = /\b(?:403|429)\b.*x-ratelimit-remaining[:=] *0\b/i;
const RATE_RESET = /x-ratelimit-reset[:=] *([0-9]{9,12})/gi;
export const rateHeld = async (jobs, notesOf) => {
  if (!Array.isArray(jobs) || jobs.some((job) => job?.steps?.some((step) => (step?.name === CLAUDE_REVIEW_STEP || step?.name === APPLY_HOLD_STEP) && step.conclusion === "success"))) {
    return undefined;
  }
  const legs = jobs.filter((job) => job?.conclusion === "success" && Number.isSafeInteger(job.id) && job.steps?.some((step) => step?.name === CLAUDE_REVIEW_STEP && step.conclusion === "skipped")).slice(0, 3);
  for (const leg of legs) {
    const messages = (await notesOf(leg)).map((a) => String(a?.message ?? ""));
    if (!messages.some((m) => m.includes(LEG_HOLD_NOTE))) {
      continue;
    }
    const resets = messages.filter((m) => RATE_REFUSAL.test(m)).flatMap((m) => [...m.matchAll(RATE_RESET)].map((match) => Number(match[1])));
    return resets.length > 0 ? Math.max(...resets) : undefined;
  }
  return undefined;
};
export const RATE_RESET_GRACE_MS = 60_000;
export const DEFER_STEP = "Note the deferral";
export const DEFERRED = "success (deferred)";
export const deferReset = async (jobs, notesOf) => {
  const gate = jobs.find((job) => GATE_JOBS.has(job?.name) && Number.isSafeInteger(job.id) && job.steps?.some((step) => step?.name === REVIEW_STOP_STEP && step.conclusion === "success"));
  const resets = gate ? deferResets(await notesOf(gate)) : [];
  return resets.length > 0 ? Math.max(...resets) : undefined;
};

/**
 * The review items of one head (`own`, its runs) whose newest hosted review a
 * kill switch stopped, or a rate limit held, once nothing would stop it
 * again: its lane's switch is off, it is inside RERUN_WINDOW_DAYS, a defer or
 * rate-limit reset it names is RATE_RESET_GRACE_MS past, and the upstream gate
 * (`gateHold`) lets it run. A wait is named through `say` or `waitReset`.
 */
export async function stoppedReviews({ call, repo, own, pull, env, now, readJobs, say, waitReset, gateHold }) {
  const items = [];
  for (const [path, name] of REVIEW_SWITCHES) {
    const r = newestByWorkflow(own).find((candidate) => candidate.path === path);
    if (!isUnreviewed(r)) {
      continue;
    }
    if (env[name]?.toLowerCase() === "true") {
      say(`#${pull.number}: review run ${r.id} (${r.path}) waits for ${name}`);
      continue;
    }
    if (now - Date.parse(r.created_at) >= RERUN_WINDOW_DAYS * 86_400_000) {
      continue;
    }
    const jobs = await readJobs(r);
    const stopped = reviewStopped(jobs);
    const notesOf = (job) => job.annotations ?? call("GET", annotationsPath(repo, job.id));
    const defer = stopped ? await deferReset(jobs, notesOf) : undefined;
    if (beforeReset(defer === undefined ? undefined : defer * 1000, now)) {
      waitReset(`#${pull.number}: review run ${r.id} (${r.path})`, defer * 1000, "was deferred on the GITHUB_TOKEN budget");
      continue;
    }
    if (!stopped) {
      const reset = await rateHeld(jobs, notesOf);
      if (reset === undefined) {
        continue;
      }
      if (now <= reset * 1000 + RATE_RESET_GRACE_MS) {
        say(`#${pull.number}: review run ${r.id} (${r.path}) held on a GitHub API rate limit; waiting for its reset at ${new Date(reset * 1000).toISOString()}`);
        continue;
      }
    }
    const hold = await gateHold();
    if (hold) {
      say(`#${pull.number}: review run ${r.id} (${r.path}) ${defer !== undefined ? "was deferred on the GITHUB_TOKEN budget" : stopped ? "was stopped by a kill switch" : "held on a GitHub API rate limit"}; waiting, ${hold}`);
      continue;
    }
    const conclusion = defer !== undefined ? DEFERRED : stopped ? "success (kill switch stop)" : "success (rate-limit hold)";
    items.push({ kind: "review", pr: pull.number, id: r.id, path: r.path, conclusion, attempt: 1, head: pull.head.sha, record: rerunRecordName(r.id, 2, pull.head.sha) });
  }
  return items;
}

async function holdReason(call, repo, run, { judge, write }, settled, carry = new Map(), keep = new Map()) {
  const key = jobsKey(run.id, 1);
  const current = run.status === "completed" && run.run_attempt === 1 && SHA.test(run.head_sha ?? "") && typeof run.updated_at === "string";
  const carried = current ? carry.get(key) : undefined;
  const hit = carried?.head === run.head_sha && carried?.updated_at === run.updated_at;
  const listing = hit
    ? { total_count: carried.jobs.length, jobs: carried.jobs }
    : await call("GET", firstAttemptJobsPath(repo, run.id));
  if (!Array.isArray(listing?.jobs) || listing.total_count > 100) {
    throw new Error("its job listing is not one complete page");
  }
  if (hit) {
    keep.set(key, carried);
  } else if (current && wholeListing(listing) && listing.jobs.length > 0 && listing.jobs.every((job) => stepsKnown(job))) {
    keep.set(key, { id: run.id, attempt: 1, head: run.head_sha, updated_at: run.updated_at, jobs: listing.jobs.map(slimJob) });
  }
  const jobs = await withAnnotations(call, repo, listing.jobs);
  const cut = jobs.filter((job) => !stepsKnown(job));
  if (!cut.every((job) => job?.conclusion === "failure" && (lostRunnerNoted(job) || setupFailed(job)))) {
    if (current && settled && wholeListing(listing)) {
      return { reason: TRUNCATED_STEPS, settle: true };
    }
    throw new Error("a job's steps did not list in full, so which steps ran is unknown");
  }
  const started = jobs
    .flatMap((job) => (Array.isArray(job?.steps) ? job.steps : []))
    .filter((s) => s?.conclusion != null && s.conclusion !== "skipped");
  if (cut.some((job) => job.steps?.some((s) => s?.name === JUDGE_PREDECESSOR || s?.name === judge))) {
    return { reason: "after its judge step may have started", settle: true };
  }
  if (started.some((s) => s.name === write)) {
    return { reason: WRITTEN, settle: true };
  }
  return started.length === 0 ? { reason: NOT_STARTED, settle: wholeListing(listing) && cut.length === 0 && (jobs.length > 0 || settled) } : { jobs };
}

export const WRITTEN = "after its verdict write started, so a re-run would judge the head again";
export const TRUNCATED_STEPS = "its job steps never listed in full, so which steps ran is unknown";

async function faultHeld(call, repo, run, carry = new Map(), keep = new Map()) {
  const key = jobsKey(run.id, 1);
  const carried = carry.get(key);
  if (carried?.held === true && carried.head === run.head_sha && carried.updated_at === run.updated_at) {
    keep.set(key, carried);
    return { held: true, final: false, reset: carried.reset, deferred: carried.deferred === true };
  }
  const listing = await firstAttemptJobs(call, repo, run.id);
  if (run.path === RATER) {
    const whole = wholeListing(listing) && listing.jobs.every((job) => stepsKnown(job));
    const ran = listing.jobs.filter((job) => Array.isArray(job?.steps) && job.steps.length > 0);
    const legs = ran.map((job) => RATER_LEGS.indexOf(job.name));
    const last = legs.includes(-1) ? undefined : ran[legs.indexOf(Math.max(...legs))];
    const stopped =
      last !== undefined &&
      last.steps.some((step) => step?.name === RATER_SWITCH_STEP && step.conclusion === "success") &&
      last.steps.some((step) => step?.name === RATER_RESOLVE_STEP && step.conclusion === "skipped");
    if (stopped && whole && typeof run.updated_at === "string") {
      keep.set(key, { id: run.id, attempt: 1, head: run.head_sha, updated_at: run.updated_at, jobs: listing.jobs.map(slimJob), held: true });
    }
    return { held: stopped && whole, final: whole && !stopped };
  }
  const ran = (name) => listing.jobs.filter((job) => Number.isSafeInteger(job?.id) && Array.isArray(job.steps) && job.steps.some((step) => step?.name === name && step.conclusion === "success"));
  const marked = ran(HELD_STEP);
  const deferring = ran(DEFER_STEP);
  const steps = listing.jobs.flatMap((job) => (Array.isArray(job?.steps) ? job.steps : []));
  if (marked.length + deferring.length > 0 && steps.some((step) => step?.name === WRITE_STEP && step.conclusion != null && step.conclusion !== "skipped")) {
    return { held: false, final: true, written: true };
  }
  const whole = typeof run.updated_at === "string" && wholeListing(listing) && listing.jobs.every((j) => stepsKnown(j));
  for (const job of deferring) {
    const annotations = await call("GET", annotationsPath(repo, job.id));
    const resets = deferResets(Array.isArray(annotations) ? annotations : []).map((s) => s * 1000);
    if (resets.length > 0) {
      const reset = Math.max(...resets);
      if (whole) {
        keep.set(key, { id: run.id, attempt: 1, head: run.head_sha, updated_at: run.updated_at, jobs: listing.jobs.map(slimJob), held: true, deferred: true, reset });
      }
      return { held: true, final: false, reset, deferred: true };
    }
  }
  if (deferring.length > 0) {
    return { held: false, final: false };
  }
  for (const job of marked) {
    const annotations = await call("GET", annotationsPath(repo, job.id));
    if (heldNoted(annotations)) {
      const reset = heldReset(annotations) || undefined;
      if (whole) {
        keep.set(key, { id: run.id, attempt: 1, head: run.head_sha, updated_at: run.updated_at, jobs: listing.jobs.map(slimJob), held: true, ...(reset === undefined ? {} : { reset }) });
      }
      return { held: true, final: false, reset };
    }
  }
  return { held: false, final: wholeListing(listing) && listing.jobs.every((job) => stepsKnown(job)) };
}

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

const PREFILTER_ISSUE = "updatedAt lastEditedAt comments(first: 100) { totalCount nodes { updatedAt } }";
const PREFILTER_PULL = `body lastEditedAt closingIssuesReferences(first: 10) { totalCount nodes { ${PREFILTER_ISSUE} repository { nameWithOwner } } }`;

const issueMoved = (issue, after) => {
  const comments = issue?.comments;
  if (!Array.isArray(comments?.nodes) || comments.totalCount !== comments.nodes.length) {
    return true;
  }
  return after(issue.updatedAt) || (issue.lastEditedAt != null && after(issue.lastEditedAt)) || comments.nodes.some((c) => after(c?.updatedAt));
};

export async function prefilterSpec(call, repo, candidates, listAt) {
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
    if (listAt === null || (listAt && after(listAt)) || c.starts.some((s) => Number.isNaN(Date.parse(s ?? ""))) || !pr || !Array.isArray(closing?.nodes) || closing.totalCount !== closing.nodes.length) {
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

async function plan({ repo, call, say, since, now, readStatus, judgeSpec, laneApp, listChanged, settled = new Map(), carriedJobs = new Map(), carriedPasses = new Map(), heldFrom, env = {} }) {
  const settle = [];
  const keepJobs = new Map();
  const keepPasses = [];
  const waiting = [];
  const prefetchedReads = new Map();
  const batches = { failed: false };
  const send = call;
  call = async (method, apiPath, ...rest) => (method === "GET" && prefetchedReads.has(apiPath) ? prefetchedReads.get(apiPath) : send(method, apiPath, ...rest));
  const prefetch = (runs) => serveFirstAttemptJobs(graphqlCall(send), repo, runs, prefetchedReads, batches);
  const carriedHit = (r, held = false) => {
    const carried = carriedJobs.get(jobsKey(r.id, 1));
    return carried?.head === r.head_sha && carried?.updated_at === r.updated_at && (!held || carried.held === true);
  };
  const sayHeld = (r, held) => {
    const why = held === NOT_STARTED ? "; a newer run judges the head, so it is not re-run" : "; not re-run";
    say(`lane run ${r.id} (${r.path}) ended ${r.conclusion} ${held}${why}`);
  };
  const pulls = (await paginate(call, `/repos/${repo}/pulls?state=open&base=main`, 5))
    .filter((p) => reconciledPull(p, repo))
    .sort(byMergeCriticality);
  let failed = 0;
  let waits = 0;
  const waitReset = (what, reset, how = "failed at the rate-limit floor") => {
    waits += 1;
    say(`${what} ${how}; ${sayReset(reset)}`);
  };
  let inFlight = 0;
  const ready = [];
  const openChecks = [];
  let everyHeadRead = true;
  const passed = [];
  const specCandidates = [];
  const tooOld = [];
  let upstream;
  const gateHold = upstreamGate(readStatus);
  const upstreamHold = async () =>
    (upstream ??= (async () => {
      for (const url of [NPM_STATUS_URL, GITHUB_STATUS_URL]) {
        const indicator = await readStatus(url).then(
          (page) => page?.status?.indicator,
          () => "unreadable",
        );
        if (indicator !== "none") {
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
      const own = listing.workflow_runs.filter((r) => r.head_repository?.full_name === repo);
      const done = checksDone(own);
      if (done !== undefined) {
        openChecks.push({ head: pull.head.sha, done, starts: laneStarts(own) });
      }
      const { rerun, again, lane, inFlight: busy } = classify(own, since);
      inFlight += busy ? 1 : 0;
      for (const r of lane) {
        say(`#${pull.number}: lane run ${r.id} (${r.path}) ended ${r.conclusion}; a re-run of this lane needs a person`);
      }
      for (const r of again) {
        say(
          `#${pull.number}: run ${r.id} (${r.path}) ended ${r.conclusion} again at attempt ${r.run_attempt}; not re-run: fix-ci takes a job past its time limit, any other cause waits for a push or a person's re-run`,
        );
      }
      const set = rerun.map((r) => ({ kind: "ci", pr: pull.number, id: r.id, path: r.path, conclusion: r.conclusion, head: pull.head.sha }));
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
          listed.jobs.length > 0 &&
          listed.jobs.every((job) => stepsKnown(job) && (job.run_attempt === undefined || job.run_attempt === r.run_attempt))
        ) {
          keepJobs.set(key, { id: r.id, attempt: r.run_attempt, head: r.head_sha, updated_at: r.updated_at, jobs: listed.jobs.map(slimJob) });
        }
        return withAnnotations(call, repo, listed.jobs, (job) => job?.conclusion === "failure");
      };
      const checks = newestByWorkflow(own).find((r) => RECORDED_UPSTREAMS.has(r.path));
      if (isRunningChecks(checks)) {
        for (const [path, name] of REVIEW_SWITCHES) {
          const r = newestByWorkflow(own).find((candidate) => candidate.path === path);
          if (
            isUnreviewed(r) &&
            env[name]?.toLowerCase() !== "true" &&
            now - Date.parse(r.created_at) < RERUN_WINDOW_DAYS * 86_400_000 &&
            reviewStopped(await readJobs(r))
          ) {
            waits += 1;
            waiting.push({ checksRunId: checks.id, reviewRunId: r.id, pr: pull.number, head: pull.head.sha, path: r.path });
            say(`#${pull.number}: review run ${r.id} (${r.path}) was stopped by a kill switch; waiting for checks run ${checks.id} (${checks.path}) to finish`);
          }
        }
      }
      if (busy) {
        continue;
      }
      const tested = [];
      for (const runs of ciRunsByWorkflow(own)) {
        if (GATED_REVIEWS.has(runs[0].path) && !reconcilerRetries(runs[0], now)) {
          continue;
        }
        tested.push(await testedRun(runs, readJobs));
      }
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
            const reset = RECORDED_UPSTREAMS.has(r.path) ? await floorFailed(call, repo, jobs) : undefined;
            if (beforeReset(reset, now)) {
              waitReset(`#${pull.number}: run ${r.id} (${r.path})`, reset);
              continue;
            }
            const floor = reset !== undefined;
            set.push({ kind: floor ? "floor" : "flake", pr: pull.number, id: r.id, path: r.path, conclusion: floor ? "failure (rate-limit floor)" : "failure", attempt: 1, head: pull.head.sha });
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
      const headReviews = () => stoppedReviews({ call, repo, own, pull, env, now, readJobs, say, waitReset, gateHold });
      if (set.length === 0 && isRedChecks(checks)) {
        const status = onlyAggregateFailed(tested.find((t) => t?.run?.id === checks.id)?.jobs ?? (await readJobs(checks)));
        const notes = status && (status.annotations ?? (await call("GET", annotationsPath(repo, status.id))));
        const switchNoted = notes && laneApp !== undefined && pull.user?.id === laneApp && pull.user?.type === "Bot" && killSwitchNoted(notes);
        if (reviewStopsAmidGateNotes(notes)) {
          set.push(...(await headReviews()));
        } else if (isFailedChecks(checks) && switchNoted) {
          set.push({ kind: "switch", pr: pull.number, id: checks.id, path: checks.path, conclusion: "failure (kill switch)", attempt: 1, head: pull.head.sha });
        } else if (checks.run_attempt >= 2 && switchNoted) {
          say(`#${pull.number}: ci-status failed on the kill switch at attempt ${checks.run_attempt}; a re-run needs a person on the trusted-actor list`);
        } else if (reconcilerRetries(checks, now) && floorNoted(notes)) {
          const reset = floorReset(notes);
          if (beforeReset(reset, now)) {
            waitReset(`#${pull.number}: ci-status of run ${checks.id}`, reset);
          } else {
            set.push({ kind: "floor", pr: pull.number, id: checks.id, path: checks.path, conclusion: "failure (rate-limit floor)", attempt: 1, head: pull.head.sha });
          }
        } else if (isFailedChecks(checks) && notes && pendingReviewNoted(notes)) {
          const reviews = [...GATED_REVIEWS].map((path) =>
            own.filter((r) => r.path === path && r.event === "pull_request").reduce((a, r) => (a && a.id > r.id ? a : r), undefined),
          );
          const last = Math.max(...reviews.map((r) => Date.parse(r?.updated_at)));
          if (reviews.every((r) => r?.status === "completed") && now - last >= PENDING_BACKOFF_MINUTES * 60_000) {
            set.push({ kind: "pending", pr: pull.number, id: checks.id, path: checks.path, conclusion: "failure (review since finished)", attempt: 1, head: pull.head.sha });
          }
        }
      }
      if (set.some((item) => item.kind === "floor" || item.kind === "switch")) {
        set.push(...(await headReviews()));
      }
      if (set.length === 0 && judgeSpec && isPassedChecks(checks)) {
        const earliest = Math.min(...own.filter((r) => RECORDED_UPSTREAMS.has(r.path)).map((r) => Date.parse(r.created_at)));
        passed.push({ pull, checks, starts: [Number.isNaN(earliest) ? null : new Date(earliest).toISOString()] });
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
      everyHeadRead &&= openChecks.at(-1)?.head === pull.head.sha;
      noteFailure(`#${pull.number}`, error);
    }
  }
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
  const toRead = [];
  let listAt;
  if (passed.length > 0 && listChanged) {
    listAt = await listChanged().catch((error) => {
      passRateLimit(error);
      say(`the standards trusted list's last change could not be read, so every passed head's spec is read: ${error?.message ?? error}`);
      return null;
    });
  }
  for (const candidate of await prefilterSpec(call, repo, passed, listAt)) {
    const carried = carriedPasses.get(passesKey(candidate.pull.number, candidate.pull.head.sha));
    if (carried && Date.parse(carried.expires_at) > now) {
      specCandidates.push({ ...candidate, starts: carried.runs.map((r) => r.started_at), carried });
    } else {
      toRead.push(candidate);
    }
  }
  await readPasses(toRead, specCandidates, knownStarts);
  const moved = await prefilterSpec(call, repo, specCandidates, listAt);
  const kept = new Set(moved);
  keepPasses.push(...specCandidates.filter((c) => c.carried && !kept.has(c)).map((c) => c.carried));
  const reread = [];
  await readPasses(moved.filter((c) => c.carried), reread, new Map());
  for (const { pull, checks, starts } of [...moved.filter((c) => !c.carried), ...(await prefilterSpec(call, repo, reread, listAt))]) {
    if (checks.run_attempt > 1 && !starts.some((s) => Date.parse(s) > Date.parse(checks.run_started_at))) {
      say(`#${pull.number}: run ${checks.id} (${checks.path}) attempt ${checks.run_attempt} has no pass since it started; waiting for pr-verify's verdict on it`);
      continue;
    }
    try {
      if ((await judgeSpec(checks)).reason === "spec-changed") {
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
  const specPrs = new Set(ready.flat().filter((item) => item.kind === "spec").map((item) => item.pr));
  for (const { pull, checks } of tooOld.filter(({ pull }) => !specPrs.has(pull.number))) {
    try {
      if ((await judgeSpec(checks)).reason === "ok") {
        ready.push([withRecord({ kind: "too-old", pr: pull.number, id: checks.id, path: checks.path, conclusion: "success", attempt: 1, head: pull.head.sha })]);
      }
    } catch (error) {
      sayUnchecked(pull, "verdict", error);
    }
  }
  const position = new Map(pulls.map((p, i) => [p.number, i]));
  ready.sort((a, b) => position.get(a[0].pr) - position.get(b[0].pr));
  const created = createdSince(since);
  const lanes = [];
  const laneRuns = new Map([...RECORDED_LANES.keys()].map((lanePath) => [lanePath, new Map()]));
  const laneFailures = new Map();
  const runsPage = async (...args) => {
    const page = await call(...args);
    if (!Array.isArray(page?.workflow_runs)) {
      throw new Error("its run listing is not a page of runs");
    }
    return page.workflow_runs;
  };
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
  await prefetch(
    [...laneRuns]
      .filter(([lanePath]) => !laneFailures.has(lanePath))
      .flatMap(([lanePath, runs]) => [...runs.values()].filter((r) => r.path === lanePath && isLostLane(r, since) && !settled.has(r.id) && !carriedHit(r))),
  );
  for (const [lanePath, lane] of RECORDED_LANES) {
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
          const held = await holdReason(call, repo, r, lane, now - Date.parse(r.updated_at) >= PASS_MINUTES * 60_000, carriedJobs, keepJobs);
          if (held.reason !== undefined) {
            if (held.settle) {
              settle.push({ id: r.id, reason: held.reason });
            }
            sayHeld(r, held.reason);
            continue;
          }
          const reset = now - Date.parse(r.updated_at) <= RATE_WINDOW_MS ? await floorFailed(call, repo, held.jobs) : undefined;
          if (beforeReset(reset, now)) {
            waitReset(`lane run ${r.id} (${r.path})`, reset);
          } else {
            unpublished.push(r);
          }
        } catch (error) {
          noteFailure(`lane run ${r.id}`, error);
        }
      }
      const hold = unpublished.length > 0 && GATED_LANES.has(lanePath) ? await gateHold() : "";
      if (hold) {
        for (const r of unpublished) {
          say(`lane run ${r.id} (${r.path}) ended ${r.conclusion}; waiting, ${hold}`);
        }
        unpublished.length = 0;
      }
      lanes.push(
        ...unpublished.map((r) => ({ kind: "lane", id: r.id, path: r.path, conclusion: r.conclusion, head: r.head_sha, created_at: r.created_at, record: rerunRecordName(r.id, 2, r.head_sha) })),
      );
    } catch (error) {
      noteFailure(lanePath, error);
    }
  }

  const recent = now - FAULT_HELD_HOURS * 3_600_000;
  const heldStart = Math.max(since, Math.min(recent, heldFrom ?? recent));
  let heldSince = recent;
  const heldCreated = createdSince(heldStart);
  const listed = [];
  for (const lanePath of FAULT_HELD_LANES) {
    try {
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
    let unowned = 0;
    for (const r of listed.filter((run) => isFaultHeld(run, heldStart)).sort(byAge)) {
      if (settled.has(r.id)) {
        settle.push({ id: r.id, reason: settled.get(r.id) });
      } else if (everyHeadRead && followsNoOpenHead(r, openChecks)) {
        unowned += 1;
      } else {
        unread.push(r);
      }
    }
    if (unowned > 0) {
      say(`${unowned} succeeded runs follow no open pull request's newest checks run, so they are not read for a hold`);
    }
    await prefetch(unread.slice(0, FAULT_HELD_READS).filter((r) => !carriedHit(r, true)));
    for (const [i, r] of unread.entries()) {
      if (i === FAULT_HELD_READS) {
        say(`${unread.length - i} succeeded runs wait for the next pass's hold check`);
        heldSince = Math.min(heldSince, Date.parse(r.created_at));
        break;
      }
      try {
        const { held, final, written, reset, deferred } = await faultHeld(call, repo, r, carriedJobs, keepJobs);
        if (written) {
          settle.push({ id: r.id, reason: WRITTEN });
          sayHeld(r, WRITTEN);
        } else if (held) {
          heldSince = Math.min(heldSince, Date.parse(r.created_at));
          const hold = beforeReset(reset, now) || !GATED_LANES.has(r.path) ? "" : await gateHold();
          if (beforeReset(reset, now)) {
            waitReset(`lane run ${r.id} (${r.path})`, reset, deferred ? "was deferred on the GITHUB_TOKEN budget" : "held on a GitHub rate limit");
          } else if (hold) {
            say(`lane run ${r.id} (${r.path}) held on a GitHub fault; waiting, ${hold}`);
          } else {
            const conclusion = deferred ? DEFERRED : r.path === RATER ? "success (kill switch stop)" : r.conclusion;
            lanes.push({ kind: "fault-held", id: r.id, path: r.path, conclusion, head: r.head_sha, created_at: r.created_at, record: rerunRecordName(r.id, 2, r.head_sha) });
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

  const intake = [];
  let candidates = [];
  try {
    const listed = await paginate(runsPage, `/repos/${repo}/actions/workflows/${workflowFile(INTAKE)}/runs?created=${created}&status=failure`, LANE_RUN_PAGES);
    candidates = listed.filter((r) => isFailedIntake(r, since) && now - Date.parse(r.updated_at) <= INTAKE_JOBS_WINDOW_MS).sort(byAge);
  } catch (error) {
    noteFailure(INTAKE, error);
  }
  await prefetch(candidates.filter((r) => !settled.has(r.id)));
  for (const r of candidates) {
    if (settled.has(r.id)) {
      settle.push({ id: r.id, reason: "" });
      continue;
    }
    try {
      const listing = await firstAttemptJobs(call, repo, r.id);
      const rerun = listing.jobs.filter((job) => !NOT_RERUN.has(job?.conclusion));
      if (rerun.length > 0 && rerun.every(isIntakeLabelJob)) {
        intake.push({ kind: "intake", id: r.id, path: r.path, conclusion: r.conclusion, head: r.head_sha });
      } else if (rerun.length > 0 && wholeListing(listing)) {
        settle.push({ id: r.id, reason: "" });
      }
    } catch (error) {
      noteFailure(`intake run ${r.id}`, error);
    }
  }

  const verdicts = [];
  let stopped = [];
  try {
    const listed = await paginate(runsPage, `/repos/${repo}/actions/workflows/${workflowFile(VERDICT_DISPATCH)}/runs?created=${created}&status=failure`, LANE_RUN_PAGES);
    stopped = listed.filter((r) => isStoppedVerdict(r, since)).sort(byAge);
  } catch (error) {
    noteFailure(VERDICT_DISPATCH, error);
  }
  await prefetch(stopped.filter((r) => !settled.has(r.id)));
  for (const r of stopped) {
    if (settled.has(r.id)) {
      settle.push({ id: r.id, reason: "" });
      continue;
    }
    try {
      const listing = await firstAttemptJobs(call, repo, r.id);
      const rerun = listing.jobs.filter((job) => !NOT_RERUN.has(job?.conclusion));
      const failedSteps = (rerun[0]?.steps ?? []).filter((step) => step?.conclusion === "failure").map((step) => step.name);
      const oneStep = rerun.length === 1 && VERDICT_JOBS.has(rerun[0].name) && failedSteps.length === 1;
      const reset = oneStep && failedSteps[0] !== VERDICT_STOP_STEP && wholeListing(listing) && stepsKnown(rerun[0]) ? await floorFailed(call, repo, rerun) : undefined;
      if (oneStep && failedSteps[0] === VERDICT_STOP_STEP) {
        verdicts.push({ kind: "verdict", id: r.id, path: r.path, conclusion: r.conclusion, head: r.head_sha });
      } else if (beforeReset(reset, now)) {
        waitReset(`verdict run ${r.id}`, reset);
      } else if (reset !== undefined) {
        verdicts.push({ kind: "verdict", floor: true, id: r.id, path: r.path, conclusion: r.conclusion, head: r.head_sha });
      } else if (wholeListing(listing) && (rerun.length > 1 || (rerun.length === 1 && (!VERDICT_JOBS.has(rerun[0].name) || stepsKnown(rerun[0]))))) {
        settle.push({ id: r.id, reason: "" });
      }
    } catch (error) {
      noteFailure(`verdict run ${r.id}`, error);
    }
  }

  let room = Math.max(0, MAX_IN_FLIGHT - inFlight);
  let uploads = MAX_IN_FLIGHT;
  const items = [];
  let deferred = 0;
  const isReview = (item) => item.kind === "review";
  const places = (set) => (set.some((item) => !isReview(item)) ? 1 : 0) + set.filter(isReview).length;
  const NO_UPLOAD = "no record upload left this pass";
  const short = (set) =>
    room === 0
      ? `all ${MAX_IN_FLIGHT} re-run places taken`
      : set.filter(recorded).length > uploads
        ? NO_UPLOAD
        : places(set) > room
          ? `only ${room} of ${MAX_IN_FLIGHT} re-run places left`
          : "";
  let deferRoom = DEFER_MAX;
  const banded = (item) => isReview(item) || (item.kind === "fault-held" && item.conclusion === DEFERRED);
  const takeDeferred = (what, set) => {
    const band = set.filter(banded);
    if (band.length === 0 || !band.every((item) => item.conclusion === DEFERRED)) {
      return set;
    }
    if (band.length > deferRoom) {
      deferred += 1;
      say(`${what}: its deferred ${band.some(isReview) ? "reviews wait" : "run waits"}, only ${deferRoom} of ${DEFER_MAX} recovery places left this pass`);
    } else {
      items.push(...band);
      deferRoom -= band.length;
    }
    return set.filter((item) => !banded(item));
  };
  const place = (what, whole) => {
    const set = takeDeferred(what, whole);
    if (set.length === 0) {
      return;
    }
    const core = set.filter((item) => !isReview(item));
    const split = short(set) === NO_UPLOAD && places(set) <= room && core.length > 0 && core.length < set.length && short(core) === "";
    if (split) {
      deferred += 1;
      say(`${what}: its stopped reviews deferred, ${short(set)}`);
    }
    const taken = split ? core : set;
    const why = short(taken);
    if (why === "") {
      items.push(...taken);
      room -= places(taken);
      uploads -= taken.filter(recorded).length;
    } else {
      deferred += taken.some((item) => item.kind !== "flake") ? 1 : 0;
      say(`${what}: deferred, ${why}`);
    }
  };
  const flakeOnly = (set) => set.every((item) => item.kind === "flake");
  for (const set of ready.filter((s) => !flakeOnly(s))) {
    place(`#${set[0].pr}`, set);
  }
  const { order, superseded } = laneOrder(lanes, openChecks, everyHeadRead);
  for (const lane of superseded) {
    say(`lane run ${lane.id} (${lane.path}) ended ${lane.conclusion}; it follows no open pull request's newest checks run, so it judges no open head (its PR closed, its head moved, or its head's checks completed again since); not re-run`);
  }
  for (const lane of order) {
    place(`lane run ${lane.id} (${lane.path})`, [lane]);
  }
  for (const set of ready.filter(flakeOnly)) {
    place(`#${set[0].pr}`, set);
  }
  items.push(...intake, ...verdicts);
  const selected = new Set(ready.flat().map((item) => item.id));
  return {
    items,
    failed,
    deferred: deferred + waits,
    settle,
    heldSince,
    jobs: [...keepJobs.values()],
    passes: [...new Map(keepPasses.map((e) => [passesKey(e.pr, e.head), e])).values()],
    waiting: waiting.filter((w) => !selected.has(w.reviewRunId)),
  };
}

const RUN_ONLY_KINDS = new Set(["lane", "fault-held", "intake", "verdict"]);
const FAILED_JOBS_WHY = new Map([
  ["intake", ""],
  ["verdict", ""],
  ["infra", ", which failed on infra only"],
  ["flake", ", its one re-run before fix-ci takes it"],
  ["floor", ", which failed only where the GITHUB_TOKEN hit its rate-limit floor"],
  ["switch", ": ci-status failed while the lanes kill switch was on"],
  ["pending", ": ci-status failed on a review that has since finished"],
  ["upstream", ": the upstream-status gate stopped its review, and the gate lets it run now"],
]);

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
              ? `${where}: re-ran run ${item.id} (${item.path}), whose pr-verify verdict ${item.floor ? "the GITHUB_TOKEN's rate-limit floor" : "the lanes kill switch"} kept from its PR`
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
            ? `${where}: re-ran review run ${item.id} (${item.path}), which ${item.conclusion === "success (rate-limit hold)" ? "held on a GitHub API rate limit" : item.conclusion === DEFERRED ? "the defer gate stopped until the GITHUB_TOKEN window reset" : "a kill switch stopped"}; its completion re-runs ci-status`
            : item.kind === "fault-held"
            ? `${where}: re-ran run ${item.id} (${item.path}), which ${item.path === RATER ? "the lanes kill switch stopped before it rated" : item.conclusion === DEFERRED ? "the defer gate stopped until the GITHUB_TOKEN window reset" : "held on a GitHub fault"}`
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

function recordOutputs(items) {
  const names = items.filter(recorded).map((item) => item.record);
  if (names.length > RECORD_SLOTS || !names.every(isRecordName)) {
    throw new Error("the plan's record names are malformed");
  }
  return Object.fromEntries(Array.from({ length: RECORD_SLOTS }, (_, i) => [`record-${i + 1}`, names[i] ?? ""]));
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
    let clean = false;
    const write = () => {
      writeFileSync(env.PLAN_PATH, JSON.stringify(result));
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
    if (env.FOLLOWUP === "true") {
      result = await followUp({ repo, call, say, now, env, readStatus });
      if (result.items.some(recorded) && !env.RECORD_PATH) {
        throw new Error("RECORD_PATH is not set");
      }
      write();
      return finish(0);
    }
    let judgeSpec;
    let laneApp;
    let listTime;
    const listChanged = env.STANDARDS_SHA ? () => (listTime ??= listChangedAt(call, env.STANDARDS_SHA)) : undefined;
    const listChangedOrNone =
      listChanged &&
      (() =>
        listChanged().catch((error) => {
          passRateLimit(error);
          return undefined;
        }));
    if (env.TRUSTED_ACTORS_PATH) {
      const trusted = loadTrustedList(env.TRUSTED_ACTORS_PATH);
      laneApp = env.LANE_IDENTITY ? trusted.logins.get(env.LANE_IDENTITY.toLowerCase()) : undefined;
      const readRefs = injected ? github : createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, keepGraphQLErrors: true });
      judgeSpec = (upstreamRun) =>
        resolvePull({
          github: call,
          readRefs,
          repository: repo,
          upstreamRun,
          humans: trusted.humans,
          verifyAuthors: env.VERIFY_AUTHORS ?? "lane",
          laneIdentity: env.LANE_IDENTITY,
          ownerIds: [...trusted.ids],
          specFromBodyApps: specFromBodyApps(env.SPEC_FROM_BODY_APPS),
          trustedListChangedAt: listChangedOrNone,
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
    const { settle, jobs, passes, heldSince, deferred, waiting, ...planned } = await plan({
      repo,
      call,
      say,
      since,
      now,
      readStatus,
      judgeSpec,
      laneApp,
      listChanged,
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
    clean = result.failed === 0 && deferred === 0;
    write();
    if (env.SETTLED_PATH) {
      writeFileSync(env.SETTLED_PATH, JSON.stringify({ version: SETTLED_VERSION, repository: repo, runs: [...new Map(settle.map((r) => [r.id, r])).values()], jobs, passes, held_since: new Date(heldSince).toISOString(), waiting_reviews: waiting }));
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
