// Starts the pr-unblock lane's fix-ci activity for each open pull request the
// lanes App opened, or a trusted actor opened (an App's at once, a person's
// once idle; the base config's `adoption` section), whose head's lanes failed
// (the `ci-lanes` commit status ci-status records, not ci-status itself, which
// a review-lane hold or a pending review also fails) or whose pr-test-platforms
// run failed, from the same
// dispatcher run
// as dispatch.mjs (pr-unblock-dispatch.yml), so the trigger gate and the
// broker check it as they check a resolve-conflicts dispatch.
//
// The listing is one GraphQL query per page of 50 pull requests: each one's
// author, labels, body, last update, and its last commit's date and check
// rollup. Its rateLimit.cost
// is logged, the baseline for what the listing spends; the same query reads
// when the base tip was committed. A head is dispatched when it has no
// pr-unblock / fix-ci check run from the GitHub Actions app, or when every
// such run failed or found no failing check, fewer than
// `limit-stops-per-head` of them stand on it, and since the base tip at most
// `fix-ci-restarts` failed and none found nothing; at most `fix-ci-per-run`
// per dispatcher run, lowest PR number first. The rollup lists only a check
// name's newest run, so before it dispatches a head the dispatcher reads the
// head's fix-ci runs over REST, and the per-head count comes from those.
// A head at the cap gets one `::warning::` and goes into the dispatch record
// (dispatch-record.mjs), so later runs skip it before any read; the next push
// makes a new head.
// A head whose lanes passed but whose pr-test-platforms run failed is a
// candidate too. A head is skipped while a re-run of its tested run is
// queued or going, while an infra-only first failure's one re-run by the
// lost-run reconciler is due (infra-failure.mjs reconcilerOwns,
// RERUN_DUE_MINUTES; a lost first attempt's too), and when its tested run
// ended cancelled with no check on the head that fix-ci-context counts as
// failing (its failingChecks, over the same check-run read), which would only
// post a skip; a check cancelled past its time limit counts, read from
// its annotations (#9828); a real
// failure (a test, lint or typecheck step), an infra failure that failed
// again, and a run or field that cannot be read go to fix-ci, with the cause
// logged.
// The fix-ci-context job decides the round cap. Logs carry PR numbers, SHAs,
// run ids, counts and failed job and step names (control characters dropped,
// 80 characters each at most) only.

import {
  AGGREGATE_JOBS,
  FAILED,
  infraCause,
  infraOnly,
  RERUN_DUE_MINUTES,
  reconcilerOwns,
  reconcilerRetries,
  stepsKnown,
  stepsUnread,
  timeLimitNoted,
} from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { postingAttempt } from "../../actions/report-check-run/posting-run.mjs";
import { emptyRecord, isHandled, markHandled } from "./dispatch-record.mjs";
import { STOP_RESOLVED } from "./escalation-routes.mjs";
import { HOLD_LINE, runTitle } from "./feedback-dispatch.mjs";
import { failingChecks } from "./fix-ci-context.mjs";
import { prHold, reviewReader } from "./gate-source.mjs";
import { KILL_SWITCH_STOP, killSwitchStop, laneStop, releasesHead } from "./limit-stop.mjs";
import { serverFailure } from "./request-budget.mjs";
import { final as capFinal, deadlineWarning } from "./verify-cap.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  activity: "fix-ci",
  checkName: "pr-unblock / fix-ci",
  // The push job's check: a lane-stopped skip there (a stop routed to a
  // failing status after the model turn) counts the fix-ci run before it as
  // a failed one, which the per-head cap and the restarts retry.
  stopCheckName: "pr-unblock / apply-patch",
  // The run whose failure counts: pr-require-checks when its lanes failed,
  // else the advisory pr-test-platforms, which ci-status does not aggregate but
  // the merge gate holds on.
  requiredWorkflow: ".github/workflows/pr-require-checks.yml",
  advisoryWorkflow: ".github/workflows/pr-test-platforms.yml",
  // The GitHub Actions app, as in dispatch.mjs: only its runs count.
  actionsAppId: 15368,
  holdLabels: Object.freeze(["do-not-merge", "needs-human"]),
  // No owner is adopted unless the config lists one.
  adoption: Object.freeze({ ownerIds: Object.freeze([]), idleHours: 24 }),
  // Failed or nothing-to-fix fix-ci runs one head gets across base moves:
  // limits.limit-stops-per-head's default, which dispatch.mjs passes resolved.
  maxRunsPerHead: 3,
});

// The neutral checks fix-ci-not-run posts when fix-ci-context found no failing
// check to fix (report-check-run's `Skipped: <reason>` title).
const NOTHING_TO_FIX = new Set(["Skipped: not-applicable", STOP_RESOLVED]);
// The neutral check a run skipped on a held PR posts.
const HELD_SKIP = "Skipped: awaiting-human";

const RUN_ID = /^[1-9][0-9]{0,14}$/;
const MAX_PAGES = 20;

// The tracker's human-gated label from .work-item-tracker.json's text, as
// pr-merge.yml resolves it: config.role_labels["human-gated"] trimmed, or
// needs-human when the file is absent (null) or maps none. Invalid JSON throws.
export function humanGatedLabel(text) {
  if (text === null) {
    return "needs-human";
  }
  const label = JSON.parse(text)?.config?.role_labels?.["human-gated"];
  return typeof label === "string" && label.trim() !== "" ? label.trim() : "needs-human";
}

export const LIST_QUERY = `query($owner: String!, $name: String!, $base: String!, $after: String) {
  rateLimit { cost remaining }
  repository(owner: $owner, name: $name) {
    ref(qualifiedName: $base) { target { ... on Commit { committedDate } } }
    pullRequests(states: OPEN, baseRefName: $base, first: 50, after: $after) {
      nodes {
        number isDraft isCrossRepository baseRefName baseRefOid headRefOid updatedAt body
        author { __typename login ... on Bot { databaseId } ... on User { databaseId } }
        labels(first: 100) { nodes { name } }
        commits(last: 1) {
          nodes {
            commit {
              oid committedDate
              statusCheckRollup {
                contexts(first: 100) {
                  nodes {
                    __typename
                    ... on CheckRun { name status conclusion title completedAt checkSuite { app { databaseId } } }
                    ... on StatusContext { context state createdAt creator { __typename ... on Bot { databaseId } } }
                  }
                  pageInfo { hasNextPage }
                }
              }
            }
          }
        }
      }
      pageInfo { hasNextPage endCursor }
    }
  }
}`;

// The check runs the GitHub Actions app posted on the PR's head.
function headChecks(node, actionsAppId) {
  const commit = node.commits?.nodes?.[0]?.commit;
  // A cut-off list could hide ci-lanes or an earlier fix-ci run.
  if (!commit || commit.oid !== node.headRefOid || commit.statusCheckRollup?.contexts?.pageInfo?.hasNextPage) {
    return null;
  }
  return (commit.statusCheckRollup?.contexts?.nodes ?? []).filter(
    (context) => context?.__typename === "CheckRun" && context.checkSuite?.app?.databaseId === actionsAppId,
  );
}

// A REST check run in the rollup's shape, as skipReason reads it.
const fromRest = (run) => ({
  name: run.name,
  status: String(run.status ?? "").toUpperCase(),
  conclusion: run.conclusion ? String(run.conclusion).toUpperCase() : null,
  title: run.output?.title ?? null,
  completedAt: run.completed_at ?? null,
});

// A push job check that failed because the broker refused its lane token:
// report-check-run's summary of the run job's failure-reason, which
// request-lane-token starts with lane-token-denied.
const tokenRefused = (run) =>
  run?.status === "completed" && run.conclusion === "failure" && String(run.output?.summary ?? "").startsWith("The run job did not succeed: lane-token-denied:");

// A rollup check run in the REST shape limit-stop.mjs reads.
const asRest = (run) => ({
  status: String(run.status ?? "").toLowerCase(),
  conclusion: run.conclusion ? String(run.conclusion).toLowerCase() : null,
  output: { title: run.title ?? null },
});

// The head's fix-ci runs (REST) in the rollup's shape, one per run attempt:
// fix-ci and the in-run fix-ci-rung-up both post a fix-ci check, and the pair
// is one attempt, read from its last check, that spends one place under the
// per-head cap for each of its checks (`spent`). An attempt a lane-stopped push job
// check (`stopRuns`, REST) followed reads as a failure: the run stopped, so
// the head may be retried under the same caps a failed run is, and so does one
// whose push job failed on a token refusal, which pushed nothing. One a
// kill-switch push job check followed reads as that kill-switch skip, which
// did no work: it is retried like a held skip, spending no restart. A check's
// attempt is the workflow run attempt postingAttempt names; not its check
// suite, which GitHub picks for a check created over the API. A stop marks
// only its own run attempt, so a re-run is a new attempt; a check with no
// readable attempt falls back to timing, a stop after it and before the next
// fix-ci check started.
export function withStops(runs, stopRuns) {
  const startOf = (run) => Date.parse(run.started_at ?? "");
  const stops = stopRuns.filter((run) => laneStop(run) || tokenRefused(run));
  const kills = stopRuns.filter(killSwitchStop);
  const starts = runs.map(startOf).sort((a, b) => a - b);
  const stoppedAt = (run, stops) => {
    const from = startOf(run);
    const until = starts.find((start) => start > from) ?? Infinity;
    return stops.some((stop) =>
      postingAttempt(stop) !== null && postingAttempt(run) !== null
        ? postingAttempt(stop) === postingAttempt(run)
        : startOf(stop) > from && startOf(stop) < until,
    );
  };
  const attempts = new Map();
  for (const run of runs) {
    const key = postingAttempt(run) ?? Symbol();
    const attempt = attempts.get(key) ?? { last: run, stopped: false, killed: false, spent: 0 };
    if (startOf(run) >= startOf(attempt.last)) {
      attempt.last = run;
    }
    attempt.spent += 1;
    attempt.stopped ||= stoppedAt(run, stops);
    attempt.killed ||= stoppedAt(run, kills);
    attempts.set(key, attempt);
  }
  const as = (stopped, killed) => (stopped ? { conclusion: "FAILURE" } : killed ? { conclusion: "NEUTRAL", title: KILL_SWITCH_STOP } : {});
  return [...attempts.values()].map(({ last, stopped, killed, spent }) => ({ ...fromRest(last), ...as(stopped, killed), spent }));
}

// The fix-ci runs that count: an untrusted-trigger skip ran nothing.
const counted = (runs) => runs.filter((run) => !(run.conclusion === "NEUTRAL" && String(run.title ?? "").startsWith("Skipped: untrusted-trigger")));

// A run that failed, found no failing check to fix, skipped on a PR held
// then, or that the kill switch stopped (paused) may be retried; any other
// run (going, pushed a fix, escalated) handles the head.
const paused = (run) => run.conclusion === "NEUTRAL" && (run.title === HELD_SKIP || run.title === KILL_SWITCH_STOP);
const retryable = (run) => run.status === "COMPLETED" && (run.conclusion === "FAILURE" || paused(run) || (run.conclusion === "NEUTRAL" && NOTHING_TO_FIX.has(run.title)));

// The number of counted fix-ci model runs when every attempt may be retried
// and they reach maxRunsPerHead, the head's hard end; else 0. An attempt
// spends one place for each fix-ci check it posted, so a rung-up pair spends
// two.
export function capCount(runs, maxRunsPerHead = DEFAULTS.maxRunsPerHead) {
  const kept = counted(runs);
  const spent = kept.reduce((sum, run) => sum + (run.spent ?? 1), 0);
  return spent >= maxRunsPerHead && kept.every(retryable) ? spent : 0;
}

// An owner PR is idle when neither it nor its head commit changed in the last
// idleHours; an unreadable date is not idle. An App's PR never waits: only a
// person may still be working on it.
function ownerIdle(node, idleHours, now) {
  if (node.author?.__typename === "Bot") {
    return true;
  }
  const commit = node.commits?.nodes?.[0]?.commit;
  const since = now - idleHours * 3_600_000;
  return commit?.oid === node.headRefOid && Date.parse(node.updatedAt) <= since && Date.parse(commit.committedDate) <= since;
}

// The GitHub Actions bot's user id. GraphQL reports its login as
// `github-actions`, REST as `github-actions[bot]`; the id is the same in both.
const ACTIONS_BOT_ID = 41898282;

// The head's `ci-lanes` commit status, whoever set it.
function lanesStatus(node) {
  const contexts = node.commits?.nodes?.[0]?.commit?.statusCheckRollup?.contexts?.nodes ?? [];
  return contexts.find((context) => context?.__typename === "StatusContext" && context.context === "ci-lanes");
}

// The ci-lanes state when the GitHub Actions bot set it, else null: the
// lanes' verdict alone. ci-status itself also fails on a hold label, a
// pending or missing review and the PR contract, none of which a CI fix mends.
// The pr-unblock/fix-ci status that still fails on a head with nothing left to
// fix, else null: a lanes App PR, not a draft, held by no label, whose ci-lanes
// passed and whose whole rollup lists every check run completed and none
// failing but ci-status, which that status itself fails. A flaky check re-run
// green past ci-fix-escalated or ci-fix-round-cap leaves such a status; a
// fix-ci run there finds nothing failing (fix-ci-context.mjs `resolved`) and
// report-stop-status clears it.
const PASSING = new Set(["SUCCESS", "NEUTRAL", "SKIPPED"]);
export function staleStop(node, { base, appSenderId, holdLabels, gateLabel }) {
  const contexts = node.commits?.nodes?.[0]?.commit?.statusCheckRollup?.contexts;
  if (
    node.isDraft !== false ||
    node.isCrossRepository !== false ||
    node.baseRefName !== base ||
    node.author?.databaseId !== appSenderId ||
    contexts?.pageInfo?.hasNextPage !== false ||
    (node.labels?.nodes ?? []).some((label) => holdLabels.includes(label?.name) || label?.name === gateLabel) ||
    lanesState(node) !== "SUCCESS"
  ) {
    return null;
  }
  const checks = (contexts.nodes ?? []).filter((context) => context?.__typename === "CheckRun" && context.name !== "ci-status");
  if (checks.some((run) => run.status !== "COMPLETED" || !PASSING.has(run.conclusion))) {
    return null;
  }
  const stop = (contexts.nodes ?? []).find(
    (context) =>
      context?.__typename === "StatusContext" &&
      context.context === "pr-unblock/fix-ci" &&
      context.creator?.__typename === "Bot" &&
      context.creator.databaseId === ACTIONS_BOT_ID,
  );
  return stop?.state === "FAILURE" || stop?.state === "ERROR" ? stop : null;
}

function lanesState(node) {
  const status = lanesStatus(node);
  return status?.creator?.__typename === "Bot" && status.creator.databaseId === ACTIONS_BOT_ID ? status.state : null;
}

const failedState = (state) => ["FAILURE", "ERROR"].includes(state);
const lanesFailed = (node) => failedState(lanesState(node));
const cancelled = (required) => required?.run?.status === "completed" && required.run.conclusion === "cancelled";

// The lanes passed and another check failed: an advisory lane's, if any.
const advisoryFailed = (node, checks, checkName) =>
  lanesState(node) === "SUCCESS" &&
  checks.some((run) => run.name !== checkName && run.name !== "ci-status" && run.status === "COMPLETED" && run.conclusion === "FAILURE");

// A job or step name comes from the PR head's workflow file: control characters
// are dropped and the length capped, so it cannot start a workflow command in
// the log of a job that holds actions: write.
const logName = (name) => String(name ?? "").replace(/[\x00-\x1f\x7f]+/g, " ").slice(0, 80);

// What failed on the tested run, for the dispatch log: a real failure's job and
// first failed step, an infra failure's attempt, or what could not be read.
export function failureCause(required, now = Date.now()) {
  if (required === undefined) {
    return "required run unreadable";
  }
  const { run, jobs } = required;
  if (!run) {
    return "no tested run found";
  }
  if (run.conclusion !== "failure") {
    return `tested run ${run.status}/${run.conclusion}`;
  }
  if (!Array.isArray(jobs)) {
    return "failed jobs unreadable";
  }
  const failed = jobs.filter((job) => FAILED.has(job?.conclusion) && !AGGREGATE_JOBS.has(job.name));
  if (failed.length === 0) {
    return "no failed lane job";
  }
  if (infraOnly(jobs)) {
    const bad = [
      ["status", run.status === "completed"],
      ["run_attempt", Number.isInteger(run.run_attempt)],
      ["updated_at", !Number.isNaN(Date.parse(run.updated_at))],
    ].find(([, ok]) => !ok)?.[0];
    if (bad !== undefined) {
      return `infra failure, run field ${bad} unreadable`;
    }
    return reconcilerRetries(run, now)
      ? `infra failure at attempt 1, no re-run within ${RERUN_DUE_MINUTES} min`
      : `infra failure at attempt ${run.run_attempt}`;
  }
  if (stepsUnread(jobs)) {
    const unlisted = failed.filter((job) => job?.conclusion === "failure" && !stepsKnown(job));
    return `steps unlisted past ${RERUN_DUE_MINUTES} min in ${unlisted.map((job) => logName(job.name)).join(", ")}`;
  }
  const real = failed.filter((job) => infraCause(job) === "");
  const step = (job) => (Array.isArray(job.steps) ? job.steps.find((s) => s?.conclusion === "failure")?.name : undefined);
  return `code failure in ${real.map((job) => [job.name, step(job)].filter(Boolean).map(logName).join(" / ")).join(", ")}`;
}

// Why a listed PR is not dispatched, or "" when it is a candidate.
export function skipReason(
  node,
  {
    base,
    appSenderId,
    actionsAppId,
    checkName,
    stopCheckName = DEFAULTS.stopCheckName,
    holdLabels,
    gateLabel = null,
    restarts,
    maxRunsPerHead = DEFAULTS.maxRunsPerHead,
    baseAt = NaN,
    adoption = DEFAULTS.adoption,
    now = Date.now(),
  },
) {
  if (node.isDraft !== false || node.isCrossRepository !== false || node.baseRefName !== base) {
    return "not a ready same-repository PR into the base";
  }
  const owner = node.author?.databaseId !== appSenderId;
  if (owner && !adoption.ownerIds.includes(node.author?.databaseId)) {
    return "not opened by the lanes App or an adoptable owner";
  }
  // adoption.held, when set, is why no owner PR is adopted this run.
  if (owner && adoption.held) {
    return adoption.held;
  }
  // The human-gated gateLabel holds only as node.laneGate says (gate-source.mjs
  // prHold, attached by dispatchCiFixes just before it would dispatch); every
  // other hold label holds.
  const labels = (node.labels?.nodes ?? []).map((label) => label?.name);
  if (labels.some((name) => holdLabels.includes(name) && name !== gateLabel)) {
    return "held";
  }
  if (gateLabel !== null && labels.includes(gateLabel) && node.laneGate !== undefined && node.laneGate !== "") {
    return node.laneGate;
  }
  // The lanes App's own PRs carry `Hold: a human merges this`, which holds the
  // merge, not a CI fix; an owner's Hold: line holds the lane off entirely.
  if (owner && HOLD_LINE.test(String(node.body ?? ""))) {
    return "held by a Hold: line";
  }
  if (owner && !ownerIdle(node, adoption.idleHours, now)) {
    return `owner PR or its head commit active in the last ${adoption.idleHours} hour(s)`;
  }
  const checks = headChecks(node, actionsAppId);
  if (!checks) {
    return "head commit or its checks not listed whole";
  }
  const advisory = advisoryFailed(node, checks, checkName);
  if (!lanesFailed(node) && !advisory) {
    return failedState(lanesStatus(node)?.state) ? "ci-lanes failed but the GitHub Actions bot did not set it" : "ci-lanes has not failed";
  }
  // node.requiredRun, the head's tested pr-require-checks run (pr-test-platforms
  // when only an advisory check failed) and its latest jobs, and, when that run
  // ended cancelled, node.headCheckRuns, every REST check run on the head, are
  // attached by dispatchCiFixes just before it would dispatch.
  const required = node.requiredRun;
  if (required !== undefined) {
    if (advisory && required.run?.conclusion !== "failure") {
      return "ci-lanes passed and no pr-test-platforms run failed";
    }
    const owned = reconcilerOwns(required, now);
    if (owned !== "") {
      return owned;
    }
    // node.headFailing, fix-ci-context's failingChecks over the head's check
    // runs, and node.timeLimited, the cancelled ones past their time limit,
    // are attached by dispatchCiFixes with node.requiredRun.
    if (cancelled(required) && node.headFailing !== undefined && node.headFailing.every((run) => run.conclusion === "cancelled") && !(node.timeLimited?.length > 0)) {
      return `tested run ${required.run.id} attempt ${required.run.run_attempt} ended cancelled and no check failed for fix-ci to fix`;
    }
  }
  // node.fixCiRuns, every fix-ci run on the head (the rollup holds only the
  // newest), is attached by dispatchCiFixes just before it would dispatch.
  const runs = counted(node.fixCiRuns ?? checks.filter((run) => run.name === checkName));
  if (runs.length === 0) {
    return "";
  }
  // The rollup's newest push job check names no run attempt: when it is a
  // lane or kill-switch stop, which turns the fix-ci run before it into a
  // failed or paused one (withStops), the REST read decides the head. So
  // does a failed one: the rollup has no summary to tell a token refusal by.
  if (node.fixCiRuns === undefined && runs.every((run) => run.status === "COMPLETED") && checks.some((run) => run.name === stopCheckName && (run.conclusion === "FAILURE" || releasesHead(asRest(run))))) {
    return "";
  }
  // A held skip (a held PR stopped above) or a kill-switch stop counts toward
  // the per-head cap with the rest, so a hold the run reads and this
  // dispatcher does not, or a switch that keeps flipping mid-run, stops there.
  if (!runs.every(retryable)) {
    return `head already has a ${checkName} check run`;
  }
  // The cap counts the REST runs alone, so the dispatcher that read them warns
  // and records the head.
  const capped = node.fixCiRuns === undefined ? 0 : capCount(runs, maxRunsPerHead);
  if (capped > 0) {
    return `head's ${checkName} ran ${capped} time(s), the most one head gets`;
  }
  // Only a run on the current base tip counts: one that ended before the tip
  // was committed ran against an older base (an unreadable time counts).
  const current = runs.filter((run) => !paused(run) && !(Date.parse(run.completedAt ?? "") < baseAt));
  if (current.some((run) => run.conclusion !== "FAILURE")) {
    return `head's ${checkName} found no failing check on this base`;
  }
  return current.length <= restarts ? "" : `head's ${checkName} failed ${current.length} time(s) on this base, past ${restarts} restart(s)`;
}

export async function dispatchCiFixes({
  api,
  runId,
  log,
  appSenderId,
  maxDispatch,
  restarts,
  maxRunsPerHead = DEFAULTS.maxRunsPerHead,
  base = DEFAULTS.base,
  workflow = DEFAULTS.workflow,
  activity = DEFAULTS.activity,
  checkName = DEFAULTS.checkName,
  stopCheckName = DEFAULTS.stopCheckName,
  actionsAppId = DEFAULTS.actionsAppId,
  holdLabels = DEFAULTS.holdLabels,
  gateLabel = null,
  adoption = DEFAULTS.adoption,
  record = emptyRecord(),
  now = Date.now(),
  // verify-cap.mjs verifyCapReader: the cap refusal, or null.
  verifyCapped = () => null,
}) {
  if (!Number.isSafeInteger(appSenderId) || appSenderId < 1) {
    throw new Error("the lanes App sender id is not a user id");
  }
  const candidates = [];
  const stale = [];
  let after;
  // When the base tip was committed, from the first page: a fix-ci run that
  // ended before it ran against an older base.
  let baseAt;
  for (let page = 1; ; page += 1) {
    const { rateLimit, pullRequests, baseCommittedAt } = await api.listCiFixCandidates({ base, after });
    log(`fix-ci listing page ${page}: rateLimit.cost=${rateLimit?.cost} remaining=${rateLimit?.remaining}`);
    baseAt ??= Date.parse(baseCommittedAt ?? "");
    for (const node of pullRequests.nodes) {
      // A recorded head reached the per-head cap and was warned about once.
      if (isHandled(record, checkName, node.headRefOid)) {
        if (failedState(lanesStatus(node)?.state)) {
          log(`skip fix-ci #${node.number}: head ${node.headRefOid} reached the per-head cap (recorded)`);
        }
        continue;
      }
      const reason = skipReason(node, { base, appSenderId, actionsAppId, checkName, stopCheckName, holdLabels, gateLabel, restarts, maxRunsPerHead, baseAt, adoption, now });
      if (reason === "") {
        candidates.push(node);
      } else if (staleStop(node, { base, appSenderId, holdLabels, gateLabel })) {
        stale.push(node);
      } else if (failedState(lanesStatus(node)?.state)) {
        // A head whose lanes failed, whoever set the status, is the one a
        // silent skip would hide.
        log(`skip fix-ci #${node.number}: ${reason}`);
      }
    }
    if (!pullRequests.pageInfo.hasNextPage) {
      break;
    }
    // 20 pages is 1,000 open pull requests; a repeated cursor ends it too.
    if (page === MAX_PAGES || pullRequests.pageInfo.endCursor === after) {
      log(`::warning::fix-ci listing stopped after page ${page}; later pull requests wait for a later run`);
      break;
    }
    after = pullRequests.pageInfo.endCursor;
  }
  candidates.sort((a, b) => a.number - b.number);
  stale.sort((a, b) => a.number - b.number);
  const dispatched = [];
  let failed = 0;
  if (candidates.length === 0 && stale.length === 0) {
    return { dispatched, failed };
  }
  let active;
  let runs;
  try {
    runs = await api.listWorkflowRuns(workflow);
    active = runs.filter((run) => run.status !== "completed");
  } catch (error) {
    if (error.rateLimited) {
      log(`::warning::${workflow} run listing is rate limited (${error.message}); no fix-ci dispatched, a later run retries`);
      return { dispatched, failed };
    }
    log(`::error::could not list ${workflow} runs: ${error.message}`);
    return { dispatched, failed: 1 };
  }
  // Every dispatch call counts against the cap: one that failed or returned no
  // usable id may still have started a run.
  let sent = 0;
  for (const node of candidates) {
    const inFlight = active.find((run) => run.display_title === runTitle(activity, node.number));
    if (inFlight) {
      log(`skip fix-ci #${node.number}: ${workflow} run ${inFlight.id} is not done yet`);
      continue;
    }
    if (sent >= maxDispatch) {
      log(`defer fix-ci #${node.number}: ${maxDispatch} fix-ci dispatches this run; left for a later run`);
      continue;
    }
    // The human-gated label holds unless another lane's escalation put it on.
    let laneGate;
    try {
      const labels = (node.labels?.nodes ?? []).map((label) => label?.name);
      const hold = await prHold({
        labels,
        holdLabels,
        gateLabel,
        head: node.headRefOid,
        activity,
        appId: appSenderId,
        readTimeline: () => api.listTimeline(node.number),
        readReviews: reviewReader(api, node.number),
      });
      laneGate = hold.held ? hold.why : "";
    } catch (error) {
      if (serverFailure(error)) {
        log(`::warning::#${node.number}: could not read where its ${gateLabel} label came from: ${error.message}; skipped, a later run retries`);
        continue;
      }
      failed += 1;
      log(`::error::#${node.number}: could not read where its ${gateLabel} label came from (${error.message}); left for a later run`);
      continue;
    }
    // The per-head cap is the loop's hard end, so a head whose runs cannot be
    // read is not dispatched.
    let fixCiRuns;
    try {
      fixCiRuns = withStops(
        await api.listCheckRuns({ sha: node.headRefOid, checkName, appId: actionsAppId }),
        await api.listCheckRuns({ sha: node.headRefOid, checkName: stopCheckName, appId: actionsAppId }),
      );
    } catch (error) {
      if (error.rateLimited) {
        log(`::warning::#${node.number}: its ${checkName} run read is rate limited (${error.message}); no fix-ci dispatched, a later run retries`);
      } else if (serverFailure(error)) {
        log(`::warning::#${node.number}: could not read its ${checkName} runs: ${error.message}; skipped, a later run retries`);
      } else {
        failed += 1;
        log(`::error::#${node.number}: could not read its ${checkName} runs (${error.message}); left for a later run`);
      }
      continue;
    }
    // A capped head stops here for good: one warning, then the record keeps
    // later runs from reading it again.
    const capped = capCount(fixCiRuns, maxRunsPerHead);
    if (capped > 0) {
      log(`::warning::#${node.number}: head ${node.headRefOid}'s ${checkName} ran ${capped} time(s), the most one head gets; no fix-ci until a new push`);
      markHandled(record, checkName, node.headRefOid);
      continue;
    }
    // A re-run going, or an infra-only first failure's re-run still due,
    // decides before a model run; an unreadable run waits on nothing.
    const path = lanesFailed(node) ? DEFAULTS.requiredWorkflow : DEFAULTS.advisoryWorkflow;
    let requiredRun;
    try {
      requiredRun = await api.readRequiredRun(node.headRefOid, path);
    } catch (error) {
      // A rate limit is no reason to spend a model run: a later run retries.
      if (error.rateLimited) {
        log(`::warning::#${node.number}: its required run read is rate limited (${error.message}); no fix-ci dispatched, a later run retries`);
        continue;
      }
      if (serverFailure(error)) {
        log(`::warning::#${node.number}: could not read its required run's jobs: ${error.message}; skipped, a later run retries`);
        continue;
      }
      log(`::warning::#${node.number}: could not read its required run's jobs (${error.message}); dispatching fix-ci under its caps`);
    }
    // A cancelled tested run can hide a failed job behind a later skipped run
    // of it, which the rollup does not show: read what fix-ci-context reads.
    // When only cancelled checks fail, read whether one ran past its time
    // limit, which fix-ci takes (#9828).
    let headFailing;
    const timeLimited = [];
    if (cancelled(requiredRun)) {
      try {
        headFailing = failingChecks(await api.listCommitCheckRuns(node.headRefOid));
      } catch (error) {
        if (error.rateLimited || serverFailure(error)) {
          log(`::warning::#${node.number}: could not read its head's check runs: ${error.message}; skipped, a later run retries`);
          continue;
        }
        log(`::warning::#${node.number}: could not read its head's check runs (${error.message}); dispatching fix-ci under its caps`);
      }
      if (headFailing?.every((run) => run.conclusion === "cancelled")) {
        try {
          for (const run of headFailing) {
            if (timeLimitNoted(await api.listAnnotations(run.id))) {
              timeLimited.push(logName(run.name));
            }
          }
        } catch (error) {
          if (error.rateLimited) {
            log(`::warning::#${node.number}: its annotation read is rate limited (${error.message}); no fix-ci dispatched, a later run retries`);
          } else {
            failed += 1;
            log(`::error::#${node.number}: could not read its cancelled checks' annotations (${error.message}); left for a later run`);
          }
          continue;
        }
      }
    }
    const reason = skipReason(
      { ...node, requiredRun, laneGate, fixCiRuns, headFailing, timeLimited },
      { base, appSenderId, actionsAppId, checkName, stopCheckName, holdLabels, gateLabel, restarts, maxRunsPerHead, baseAt, adoption, now },
    );
    if (reason !== "") {
      log(`skip fix-ci #${node.number}: ${reason}`);
      continue;
    }
    // Last, as it costs a full verifier read: a push past the FAIL cap could
    // never merge, so pr-merge closes the pull request for a fresh attempt.
    // It closes only the lanes App's: an adopted owner's is never skipped.
    const verifyCap = node.author?.databaseId === appSenderId ? await verifyCapped({ number: node.number, head: node.headRefOid, base: node.baseRefOid }) : null;
    if (verifyCap) {
      const warning = deadlineWarning(node.number, verifyCap);
      if (warning) {
        log(warning);
      }
      log(`skip fix-ci #${node.number}: pr-verify's FAILs are at the cap or cannot all be read (${verifyCap}); pr-merge closes it for a fresh attempt, so no fix-ci round`);
      // The cap never clears for the head: later runs skip it before any
      // read. A sibling read that failed is read again next run.
      if (capFinal(verifyCap)) {
        markHandled(record, checkName, node.headRefOid);
      }
      continue;
    }
    sent += 1;
    try {
      const { workflowRunId } = await api.dispatchWorkflow({
        workflow,
        ref: `refs/heads/${base}`,
        inputs: { "pr-number": String(node.number), activity, "dispatcher-run-id": String(runId) },
      });
      const id = String(workflowRunId);
      if (!RUN_ID.test(id)) {
        failed += 1;
        log(`::error::#${node.number}: dispatch returned no valid workflow_run_id`);
        continue;
      }
      dispatched.push({ number: node.number, workflowRunId: id });
      const limit = timeLimited.length > 0 ? `, time limit in ${timeLimited.join(", ")}` : "";
      log(`dispatched fix-ci #${node.number} head ${node.headRefOid} workflow_run_id=${id} (cause: ${failureCause(requiredRun, now)}${limit})`);
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: dispatch failed: ${error.message}`);
    }
  }
  // Once per stop: a fix-ci run for the PR created after the failing status
  // holds the head.
  for (const node of stale) {
    const stoppedAt = Date.parse(staleStop(node, { base, appSenderId, holdLabels, gateLabel }).createdAt ?? "");
    const since = runs.find((run) => run.display_title === runTitle(activity, node.number) && !(Date.parse(run.created_at ?? "") < stoppedAt));
    if (since) {
      log(`skip fix-ci #${node.number}: ${workflow} run ${since.id} started after the fix-ci stop on head ${node.headRefOid}`);
      continue;
    }
    if (sent >= maxDispatch) {
      log(`defer fix-ci #${node.number}: ${maxDispatch} fix-ci dispatches this run; left for a later run`);
      continue;
    }
    sent += 1;
    try {
      const { workflowRunId } = await api.dispatchWorkflow({
        workflow,
        ref: `refs/heads/${base}`,
        inputs: { "pr-number": String(node.number), activity, "dispatcher-run-id": String(runId) },
      });
      const id = String(workflowRunId);
      if (!RUN_ID.test(id)) {
        failed += 1;
        log(`::error::#${node.number}: dispatch returned no valid workflow_run_id`);
        continue;
      }
      dispatched.push({ number: node.number, workflowRunId: id });
      log(`dispatched fix-ci #${node.number} head ${node.headRefOid} workflow_run_id=${id} (cause: a fix-ci stop with nothing left failing)`);
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: dispatch failed: ${error.message}`);
    }
  }
  return { dispatched, failed };
}
