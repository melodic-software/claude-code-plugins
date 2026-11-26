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
import { emptyRecord, isHandled, markHandled, sendDispatch, startOf } from "./dispatch-record.mjs";
import { STOP_RESOLVED } from "./escalation-routes.mjs";
import { ACTIONS_BOT_ID, DISPATCH_HOLDS } from "../lib/lane-vocabulary.mjs";
import { isPrUnblockTitle } from "../lib/run-title.mjs";
import { HOLD_LINE } from "./feedback-dispatch.mjs";
import { DEFAULTS as DOCS_FIX_DEFAULTS } from "./fix-docs-dispatch.mjs";
import { failingChecks } from "./fix-ci-context.mjs";
import { traceOnlyFailure } from "./declare-test-scope.mjs";
import { DEPENDABOT_ID } from "./dependency-classify.mjs";
import { prHold, reviewReader } from "./gate-source.mjs";
import { HEAD_LAG_STOP, KILL_SWITCH_STOP, killSwitchStop, laneStop, releasesHead } from "./limit-stop.mjs";
import { serverFailure } from "./request-budget.mjs";
import { deadlineWarning } from "./verify-cap.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  activity: "fix-ci",
  checkName: "pr-unblock / fix-ci",
  stopCheckName: "pr-unblock / apply-patch",
  requiredWorkflow: ".github/workflows/pr-require-checks.yml",
  advisoryWorkflow: ".github/workflows/pr-test-platforms.yml",
  actionsAppId: 15368,
  holdLabels: DISPATCH_HOLDS,
  adoption: Object.freeze({ ownerIds: Object.freeze([]), idleHours: 24 }),
  maxRunsPerHead: 3,
});

const NOTHING_TO_FIX = new Set(["Skipped: not-applicable", STOP_RESOLVED]);
const HELD_SKIP = "Skipped: awaiting-human";

const MAX_PAGES = 20;

export function adoptableOwnerIds(trustedIds, excludedAuthorIds = DOCS_FIX_DEFAULTS.excludedAuthorIds) {
  return [...trustedIds].filter((id) => !excludedAuthorIds.includes(id));
}

export function humanGatedLabel(text) {
  if (text === null) {
    return "needs-human";
  }
  const label = JSON.parse(text)?.config?.role_labels?.["human-gated"];
  return typeof label === "string" && label.trim() !== "" ? label.trim() : "needs-human";
}

function headChecks(node, actionsAppId) {
  const commit = node.commits?.nodes?.[0]?.commit;
  if (!commit || commit.oid !== node.headRefOid || commit.statusCheckRollup?.contexts?.pageInfo?.hasNextPage) {
    return null;
  }
  return (commit.statusCheckRollup?.contexts?.nodes ?? []).filter(
    (context) => context?.__typename === "CheckRun" && context.checkSuite?.app?.databaseId === actionsAppId,
  );
}

const fromRest = (run) => ({
  name: run.name,
  status: String(run.status ?? "").toUpperCase(),
  conclusion: run.conclusion ? String(run.conclusion).toUpperCase() : null,
  title: run.output?.title ?? null,
  completedAt: run.completed_at ?? null,
});

const tokenRefused = (run) =>
  run?.status === "completed" && run.conclusion === "failure" && String(run.output?.summary ?? "").startsWith("The run job did not succeed: lane-token-denied:");

const asRest = (run) => ({
  status: String(run.status ?? "").toLowerCase(),
  conclusion: run.conclusion ? String(run.conclusion).toLowerCase() : null,
  output: { title: run.title ?? null },
});

export function withStops(runs, stopRuns) {
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

const counted = (runs) => runs.filter((run) => !(run.conclusion === "NEUTRAL" && String(run.title ?? "").startsWith("Skipped: untrusted-trigger")));

const paused = (run) => run.conclusion === "NEUTRAL" && (run.title === HELD_SKIP || run.title === KILL_SWITCH_STOP || run.title === HEAD_LAG_STOP);
const retryable = (run) => run.status === "COMPLETED" && (run.conclusion === "FAILURE" || paused(run) || (run.conclusion === "NEUTRAL" && NOTHING_TO_FIX.has(run.title)));

export function capCount(runs, maxRunsPerHead = DEFAULTS.maxRunsPerHead) {
  const kept = counted(runs);
  const spent = kept.reduce((sum, run) => sum + (run.spent ?? 1), 0);
  return spent >= maxRunsPerHead && kept.every(retryable) ? spent : 0;
}

function ownerIdle(node, idleHours, now) {
  if (node.author?.__typename === "Bot") {
    return true;
  }
  const commit = node.commits?.nodes?.[0]?.commit;
  const since = now - idleHours * 3_600_000;
  return commit?.oid === node.headRefOid && Date.parse(node.updatedAt) <= since && Date.parse(commit.committedDate) <= since;
}

function lanesStatus(node) {
  const contexts = node.commits?.nodes?.[0]?.commit?.statusCheckRollup?.contexts?.nodes ?? [];
  return contexts.find((context) => context?.__typename === "StatusContext" && context.context === "ci-lanes");
}

function lanesState(node) {
  const status = lanesStatus(node);
  return status?.creator?.__typename === "Bot" && status.creator.databaseId === ACTIONS_BOT_ID ? status.state : null;
}

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
  const checks = (contexts.nodes ?? []).filter((context) => context?.__typename === "CheckRun" && !AGGREGATE_JOBS.has(context.name));
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
  return failedState(stop?.state) ? stop : null;
}

const failedState = (state) => ["FAILURE", "ERROR"].includes(state);
const lanesFailed = (node) => failedState(lanesState(node));
const cancelled = (required) => required?.run?.status === "completed" && required.run.conclusion === "cancelled";

const advisoryFailed = (node, checks, checkName) =>
  lanesState(node) === "SUCCESS" &&
  checks.some((run) => run.name !== checkName && !AGGREGATE_JOBS.has(run.name) && run.status === "COMPLETED" && run.conclusion === "FAILURE");

const logName = (name) => String(name ?? "").replace(/[\x00-\x1f\x7f]+/g, " ").slice(0, 80);

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
    ownedBranches = [],
    now = Date.now(),
  },
) {
  if (node.isDraft !== false || node.isCrossRepository !== false || node.baseRefName !== base) {
    return "not a ready same-repository PR into the base";
  }
  if (ownedBranches.includes(node.headRefName)) {
    return `head branch ${node.headRefName} is rebuilt by its own workflow`;
  }
  const owner = node.author?.databaseId !== appSenderId;
  if (owner && !adoption.ownerIds.includes(node.author?.databaseId)) {
    return "not opened by the lanes App or an adoptable owner";
  }
  if (owner && adoption.held) {
    return adoption.held;
  }
  const labels = (node.labels?.nodes ?? []).map((label) => label?.name);
  if (labels.some((name) => holdLabels.includes(name) && name !== gateLabel)) {
    return "held";
  }
  if (gateLabel !== null && labels.includes(gateLabel) && node.laneGate !== undefined && node.laneGate !== "") {
    return node.laneGate;
  }
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
  const required = node.requiredRun;
  if (required !== undefined) {
    if (advisory && required.run?.conclusion !== "failure") {
      return "ci-lanes passed and no pr-test-platforms run failed";
    }
    const owned = reconcilerOwns(required, now);
    if (owned !== "") {
      return owned;
    }
    if (cancelled(required) && node.headFailing !== undefined && node.headFailing.every((run) => run.conclusion === "cancelled") && !(node.timeLimited?.length > 0)) {
      return `tested run ${required.run.id} attempt ${required.run.run_attempt} ended cancelled and no check failed for fix-ci to fix`;
    }
  }
  const runs = counted(node.fixCiRuns ?? checks.filter((run) => run.name === checkName));
  if (runs.length === 0) {
    return "";
  }
  if (node.fixCiRuns === undefined && runs.every((run) => run.status === "COMPLETED") && checks.some((run) => run.name === stopCheckName && (run.conclusion === "FAILURE" || releasesHead(asRest(run))))) {
    return "";
  }
  if (!runs.every(retryable)) {
    return `head already has a ${checkName} check run`;
  }
  const capped = node.fixCiRuns === undefined ? 0 : capCount(runs, maxRunsPerHead);
  if (capped > 0) {
    return `head's ${checkName} ran ${capped} time(s), the most one head gets`;
  }
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
  ownedBranches = [],
  record = emptyRecord(),
  now = Date.now(),
  verifyCapped = () => null,
}) {
  if (!Number.isSafeInteger(appSenderId) || appSenderId < 1) {
    throw new Error("the lanes App sender id is not a user id");
  }
  const candidates = [];
  const stale = [];
  let after;
  let baseAt;
  for (let page = 1; ; page += 1) {
    const { rateLimit, pullRequests, baseCommittedAt } = await api.listCiFixCandidates({ base, after });
    log(`fix-ci listing page ${page}: rateLimit.cost=${rateLimit?.cost} remaining=${rateLimit?.remaining}`);
    baseAt ??= Date.parse(baseCommittedAt ?? "");
    for (const node of pullRequests.nodes) {
      if (isHandled(record, checkName, node.headRefOid)) {
        if (failedState(lanesStatus(node)?.state)) {
          log(`skip fix-ci #${node.number}: head ${node.headRefOid} reached the per-head cap (recorded)`);
        }
        continue;
      }
      const reason = skipReason(node, { base, appSenderId, actionsAppId, checkName, stopCheckName, holdLabels, gateLabel, restarts, maxRunsPerHead, baseAt, adoption, ownedBranches, now });
      if (reason === "") {
        candidates.push(node);
      } else if (staleStop(node, { base, appSenderId, holdLabels, gateLabel })) {
        stale.push(node);
      } else if (failedState(lanesStatus(node)?.state)) {
        log(`skip fix-ci #${node.number}: ${reason}`);
      }
    }
    if (!pullRequests.pageInfo.hasNextPage) {
      break;
    }
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
    log(`::warning::${workflow} run listing ${error.rateLimited ? "is rate limited" : "could not be read"} (${error.message}); no fix-ci dispatched, a later run retries`);
    return { dispatched, failed };
  }
  let sent = 0;
  const send = async (node, cause) => {
    sent += 1;
    const id = await sendDispatch(api, log, {
      workflow,
      base,
      node,
      label: "fix-ci ",
      note: () => ` (cause: ${cause()})`,
      inputs: { "pr-number": String(node.number), activity, "dispatcher-run-id": String(runId) },
    });
    if (id === null) {
      failed += 1;
    } else {
      dispatched.push({ number: node.number, workflowRunId: id });
    }
  };
  for (const node of candidates) {
    const inFlight = active.find((run) => isPrUnblockTitle(run.display_title, activity, node.number));
    if (inFlight) {
      log(`skip fix-ci #${node.number}: ${workflow} run ${inFlight.id} is not done yet`);
      continue;
    }
    if (sent >= maxDispatch) {
      log(`defer fix-ci #${node.number}: ${maxDispatch} fix-ci dispatches this run; left for a later run`);
      continue;
    }
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
      log(`::warning::#${node.number}: could not read where its ${gateLabel} label came from: ${error.message}; skipped, a later run retries`);
      continue;
    }
    const path = lanesFailed(node) ? DEFAULTS.requiredWorkflow : DEFAULTS.advisoryWorkflow;
    let requiredRun;
    try {
      requiredRun = await api.readRequiredRun(node.headRefOid, path);
    } catch (error) {
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
    const early = skipReason(
      { ...node, requiredRun, laneGate, fixCiRuns: [] },
      { base, appSenderId, actionsAppId, checkName, stopCheckName, holdLabels, gateLabel, restarts, maxRunsPerHead, baseAt, adoption, ownedBranches, now },
    );
    if (early !== "" && !headChecks(node, actionsAppId)?.some((run) => run.name === checkName)) {
      log(`skip fix-ci #${node.number}: ${early}`);
      continue;
    }
    let fixCiRuns;
    try {
      fixCiRuns = withStops(
        await api.listCheckRuns({ sha: node.headRefOid, checkName, appId: actionsAppId }),
        await api.listCheckRuns({ sha: node.headRefOid, checkName: stopCheckName, appId: actionsAppId }),
      );
    } catch (error) {
      if (error.rateLimited) {
        log(`::warning::#${node.number}: its ${checkName} run read is rate limited (${error.message}); no fix-ci dispatched, a later run retries`);
      } else {
        log(`::warning::#${node.number}: could not read its ${checkName} runs: ${error.message}; skipped, a later run retries`);
      }
      continue;
    }
    const capped = capCount(fixCiRuns, maxRunsPerHead);
    if (capped > 0) {
      log(`::warning::#${node.number}: head ${node.headRefOid}'s ${checkName} ran ${capped} time(s), the most one head gets; no fix-ci until a new push`);
      markHandled(record, checkName, node.headRefOid);
      continue;
    }
    if (early !== "") {
      log(`skip fix-ci #${node.number}: ${early}`);
      continue;
    }
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
            log(`::warning::#${node.number}: could not read its cancelled checks' annotations: ${error.message}; skipped, a later run retries`);
          }
          continue;
        }
      }
    }
    const reason = skipReason(
      { ...node, requiredRun, laneGate, fixCiRuns, headFailing, timeLimited },
      { base, appSenderId, actionsAppId, checkName, stopCheckName, holdLabels, gateLabel, restarts, maxRunsPerHead, baseAt, adoption, ownedBranches, now },
    );
    if (reason !== "") {
      log(`skip fix-ci #${node.number}: ${reason}`);
      continue;
    }
    const verifyCap = node.author?.databaseId === appSenderId ? await verifyCapped({ number: node.number, head: node.headRefOid, base: node.baseRefOid }) : null;
    if (verifyCap) {
      const warning = deadlineWarning(node.number, verifyCap);
      if (warning) {
        log(warning);
      }
      log(`skip fix-ci #${node.number}: pr-verify's FAILs are at the cap or cannot all be read (${verifyCap}); pr-merge closes it for a fresh attempt, so no fix-ci round`);
      continue;
    }
    if (fixCiRuns.some((run) => run.conclusion === "NEUTRAL" && run.title === HEAD_LAG_STOP)) {
      log(`refire: #${node.number}: head ${node.headRefOid}'s ${checkName} was stopped head-lag; sending it again`);
    }
    const limit = timeLimited.length > 0 ? `, time limit in ${timeLimited.join(", ")}` : "";
    await send(node, () => `${failureCause(requiredRun, now)}${limit}`);
  }
  for (const node of stale) {
    const stoppedAt = Date.parse(staleStop(node, { base, appSenderId, holdLabels, gateLabel }).createdAt ?? "");
    const since = runs.find((run) => isPrUnblockTitle(run.display_title, activity, node.number) && !(Date.parse(run.created_at ?? "") < stoppedAt));
    if (since) {
      log(`skip fix-ci #${node.number}: ${workflow} run ${since.id} started after the fix-ci stop on head ${node.headRefOid}`);
      continue;
    }
    if (sent >= maxDispatch) {
      log(`defer fix-ci #${node.number}: ${maxDispatch} fix-ci dispatches this run; left for a later run`);
      continue;
    }
    await send(node, () => "a fix-ci stop with nothing left failing");
  }
  return { dispatched, failed };
}

export const TEST_SCOPE_DEFAULTS = Object.freeze({
  activity: "fix-test-scope",
  checkName: "pr-unblock / fix-test-scope",
  holdLabels: Object.freeze(["do-not-merge", "needs-session"]),
  maxDispatch: 2,
});

export function testScopeSkip(node, { base = DEFAULTS.base, actionsAppId = DEFAULTS.actionsAppId, holdLabels = TEST_SCOPE_DEFAULTS.holdLabels } = {}) {
  if (node.isDraft !== false || node.isCrossRepository !== false || node.baseRefName !== base) {
    return "not a ready same-repository PR into the base";
  }
  if (node.author?.databaseId === DEPENDABOT_ID) {
    return "opened by Dependabot";
  }
  if ((node.labels?.nodes ?? []).some((label) => holdLabels.includes(label?.name))) {
    return "held";
  }
  const checks = headChecks(node, actionsAppId);
  if (!checks) {
    return "head commit or its checks not listed whole";
  }
  if (!lanesFailed(node)) {
    return "ci-lanes has not failed";
  }
  return checks.some((run) => run.name === TEST_SCOPE_DEFAULTS.checkName) ? `head already has a ${TEST_SCOPE_DEFAULTS.checkName} check run` : "";
}

export async function dispatchTestScope({
  api,
  runId,
  log,
  listed,
  record = emptyRecord(),
  base = DEFAULTS.base,
  workflow = DEFAULTS.workflow,
  actionsAppId = DEFAULTS.actionsAppId,
  maxDispatch = TEST_SCOPE_DEFAULTS.maxDispatch,
}) {
  const { activity, checkName } = TEST_SCOPE_DEFAULTS;
  const dispatched = [];
  let failed = 0;
  const candidates = listed.filter((node) => !isHandled(record, checkName, node.headRefOid) && testScopeSkip(node, { base, actionsAppId }) === "").sort((a, b) => a.number - b.number);
  let active = null;
  let sent = 0;
  for (const node of candidates) {
    if (sent >= maxDispatch) {
      log(`defer ${activity} #${node.number}: ${maxDispatch} dispatches this run; left for a later run`);
      continue;
    }
    try {
      if (!traceOnlyFailure(await api.readRequiredRun(node.headRefOid, DEFAULTS.requiredWorkflow))) {
        continue;
      }
      if ((await api.listCheckRuns({ sha: node.headRefOid, checkName, appId: actionsAppId })).length > 0) {
        markHandled(record, checkName, node.headRefOid);
        continue;
      }
      active ??= (await api.listWorkflowRuns(workflow)).filter((run) => run.status !== "completed");
      const inFlight = active.find((run) => isPrUnblockTitle(run.display_title, activity, node.number));
      if (inFlight) {
        log(`skip ${activity} #${node.number}: ${workflow} run ${inFlight.id} is not done yet`);
        continue;
      }
    } catch (error) {
      log(`::warning::#${node.number}: could not read its required run, ${checkName} runs or runs: ${error.message}; skipped, a later run retries`);
      continue;
    }
    sent += 1;
    const id = await sendDispatch(api, log, { workflow, base, node, label: `${activity} `, errorLabel: `${activity} `, inputs: { "pr-number": String(node.number), activity, "dispatcher-run-id": String(runId) } });
    if (id === null) {
      failed += 1;
    } else {
      dispatched.push({ number: node.number, workflowRunId: id });
    }
  }
  return { dispatched, failed };
}
