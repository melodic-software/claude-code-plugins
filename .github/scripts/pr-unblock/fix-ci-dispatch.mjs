// Starts the pr-unblock lane's fix-ci activity for each open pull request the
// lanes App opened, or a trusted actor opened (an App's at once, a person's
// once idle; the base config's `adoption` section), whose head's lanes failed
// (the `ci-lanes` commit status ci-status records, not ci-status itself, which
// a review-lane hold or a pending review also fails) or whose pr-test-windows
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
// A head whose lanes passed but whose pr-test-windows run failed is a
// candidate too. A head is skipped while a re-run of its tested run is
// queued or going, while an infra-only first failure's one re-run by the
// lost-run reconciler is due (infra-failure.mjs reconcilerOwns,
// RERUN_DUE_MINUTES), and when its tested run ended cancelled with no check on
// the head that fix-ci-context counts as failing (its failingChecks, over the
// same check-run read), which would only post not-applicable (the reconciler
// re-runs a cancelled first attempt); a real
// failure (a test, lint or typecheck step), an infra failure that failed
// again, and a run or field that cannot be read go to fix-ci, with the cause
// logged.
// The fix-ci-context job decides the round cap. Logs carry PR numbers, SHAs,
// run ids, counts and failed job and step names (control characters dropped,
// 80 characters each at most) only.

import { AGGREGATE_JOBS, FAILED, infraCause, infraOnly, RERUN_DUE_MINUTES, reconcilerOwns, reconcilerRetries, stepsKnown, stepsUnread } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { emptyRecord, isHandled, markHandled } from "./dispatch-record.mjs";
import { runTitle } from "./feedback-dispatch.mjs";
import { failingChecks } from "./fix-ci-context.mjs";
import { prHold } from "./gate-source.mjs";
import { serverFailure } from "./request-budget.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  activity: "fix-ci",
  checkName: "pr-unblock / fix-ci",
  // The run whose failure counts: pr-require-checks when its lanes failed,
  // else the advisory pr-test-windows, which ci-status does not aggregate but
  // the merge gate holds on.
  requiredWorkflow: ".github/workflows/pr-require-checks.yml",
  advisoryWorkflow: ".github/workflows/pr-test-windows.yml",
  // The GitHub Actions app, as in dispatch.mjs: only its runs count.
  actionsAppId: 15368,
  holdLabels: Object.freeze(["do-not-merge", "needs-human"]),
  // No owner is adopted unless the config lists one.
  adoption: Object.freeze({ ownerIds: Object.freeze([]), idleHours: 24 }),
  // Failed or not-applicable fix-ci runs one head gets across base moves:
  // limits.limit-stops-per-head's default, which dispatch.mjs passes resolved.
  maxRunsPerHead: 3,
});

// The neutral check fix-ci-not-run posts when fix-ci-context found no failing
// check to fix (report-check-run's `Skipped: <reason>` title).
const NOT_APPLICABLE = "Skipped: not-applicable";
// The neutral check a run skipped on a held PR posts.
const HELD_SKIP = "Skipped: awaiting-human";

const RUN_ID = /^[1-9][0-9]{0,14}$/;
const MAX_PAGES = 20;
// A body line starting "Hold:", as babysit's BODY_MERGE_HOLD_RE reads it
// (babysit_merge.py): any case, after any non-newline whitespace, NBSP
// included, with a bare CR as a line break too.
const HOLD_LINE = /(?:^|(?<=[\r\n]))[^\S\r\n]*hold:/i;

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
        number isDraft isCrossRepository baseRefName headRefOid updatedAt body
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
                    ... on StatusContext { context state creator { __typename ... on Bot { databaseId } } }
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

// The fix-ci runs that count: an untrusted-trigger skip ran nothing.
const counted = (runs) => runs.filter((run) => !(run.conclusion === "NEUTRAL" && String(run.title ?? "").startsWith("Skipped: untrusted-trigger")));

// A run that failed, found no failing check to fix, or skipped on a PR held
// then may be retried; any other run (going, pushed a fix, escalated) handles
// the head.
const heldSkip = (run) => run.conclusion === "NEUTRAL" && run.title === HELD_SKIP;
const retryable = (run) => run.status === "COMPLETED" && (run.conclusion === "FAILURE" || heldSkip(run) || (run.conclusion === "NEUTRAL" && run.title === NOT_APPLICABLE));

// The number of counted fix-ci runs when every one may be retried and they
// reach maxRunsPerHead, the head's hard end; else 0.
export function capCount(runs, maxRunsPerHead = DEFAULTS.maxRunsPerHead) {
  const kept = counted(runs);
  return kept.length >= maxRunsPerHead && kept.every(retryable) ? kept.length : 0;
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
  // node.requiredRun, the head's tested pr-require-checks run (pr-test-windows
  // when only an advisory check failed) and its latest jobs, and, when that run
  // ended cancelled, node.headCheckRuns, every REST check run on the head, are
  // attached by dispatchCiFixes just before it would dispatch.
  const required = node.requiredRun;
  if (required !== undefined) {
    if (advisory && required.run?.conclusion !== "failure") {
      return "ci-lanes passed and no pr-test-windows run failed";
    }
    const owned = reconcilerOwns(required, now);
    if (owned !== "") {
      return owned;
    }
    if (cancelled(required) && node.headCheckRuns !== undefined && failingChecks(node.headCheckRuns).length === 0) {
      return `tested run ${required.run.id} attempt ${required.run.run_attempt} ended cancelled and no check failed for fix-ci to fix`;
    }
  }
  // node.fixCiRuns, every fix-ci run on the head (the rollup holds only the
  // newest), is attached by dispatchCiFixes just before it would dispatch.
  const runs = counted(node.fixCiRuns ?? checks.filter((run) => run.name === checkName));
  if (runs.length === 0) {
    return "";
  }
  // A held skip (a held PR stopped above) counts toward the per-head cap with
  // the rest, so a hold the run reads and this dispatcher does not stops there.
  if (!runs.every(retryable)) {
    return `head already has a ${checkName} check run`;
  }
  // The cap counts the REST runs alone, so the dispatcher that read them warns
  // and records the head.
  if (node.fixCiRuns !== undefined && capCount(runs, maxRunsPerHead) > 0) {
    return `head's ${checkName} ran ${runs.length} time(s), the most one head gets`;
  }
  // Only a run on the current base tip counts: one that ended before the tip
  // was committed ran against an older base (an unreadable time counts).
  const current = runs.filter((run) => !heldSkip(run) && !(Date.parse(run.completedAt ?? "") < baseAt));
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
  actionsAppId = DEFAULTS.actionsAppId,
  holdLabels = DEFAULTS.holdLabels,
  gateLabel = null,
  adoption = DEFAULTS.adoption,
  record = emptyRecord(),
  now = Date.now(),
}) {
  if (!Number.isSafeInteger(appSenderId) || appSenderId < 1) {
    throw new Error("the lanes App sender id is not a user id");
  }
  const candidates = [];
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
      const reason = skipReason(node, { base, appSenderId, actionsAppId, checkName, holdLabels, gateLabel, restarts, maxRunsPerHead, baseAt, adoption, now });
      if (reason === "") {
        candidates.push(node);
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
  const dispatched = [];
  let failed = 0;
  if (candidates.length === 0) {
    return { dispatched, failed };
  }
  let active;
  try {
    active = (await api.listWorkflowRuns(workflow)).filter((run) => run.status !== "completed");
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
      fixCiRuns = (await api.listCheckRuns({ sha: node.headRefOid, checkName, appId: actionsAppId })).map(fromRest);
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
    let headCheckRuns;
    if (cancelled(requiredRun)) {
      try {
        headCheckRuns = await api.listCommitCheckRuns(node.headRefOid);
      } catch (error) {
        if (error.rateLimited || serverFailure(error)) {
          log(`::warning::#${node.number}: could not read its head's check runs: ${error.message}; skipped, a later run retries`);
          continue;
        }
        log(`::warning::#${node.number}: could not read its head's check runs (${error.message}); dispatching fix-ci under its caps`);
      }
    }
    const reason = skipReason({ ...node, requiredRun, laneGate, fixCiRuns, headCheckRuns }, { base, appSenderId, actionsAppId, checkName, holdLabels, gateLabel, restarts, maxRunsPerHead, baseAt, adoption, now });
    if (reason !== "") {
      log(`skip fix-ci #${node.number}: ${reason}`);
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
      log(`dispatched fix-ci #${node.number} head ${node.headRefOid} workflow_run_id=${id} (cause: ${failureCause(requiredRun, now)})`);
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: dispatch failed: ${error.message}`);
    }
  }
  return { dispatched, failed };
}
