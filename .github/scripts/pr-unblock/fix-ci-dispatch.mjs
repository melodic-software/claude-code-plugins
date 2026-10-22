// Starts the pr-unblock lane's fix-ci activity for each open pull request the
// lanes App opened, or an adoptable owner opened and left idle (the base
// config's `adoption` section), whose head's ci-status failed, from the same
// dispatcher run
// as dispatch.mjs (pr-unblock-dispatch.yml), so the trigger gate and the
// broker check it as they check a resolve-conflicts dispatch.
//
// The listing is one GraphQL query per page of 50 pull requests: each one's
// author, labels, body, last update, and its last commit's date and check
// rollup. Its rateLimit.cost
// is logged, the baseline for what the listing spends. A head is dispatched
// when it has no pr-unblock / fix-ci check run from the GitHub Actions app,
// or when every such run failed and there are at most `fix-ci-restarts` of
// them; at most `fix-ci-per-run` per dispatcher run, lowest PR number first.
// A head whose pr-require-checks failures are all infra (infra-failure.mjs) is
// skipped while the lost-run reconciler still re-runs it (infra-failure.mjs
// reconcilerRetries: attempt and lookback); past that, fix-ci takes it.
// The fix-ci-context job decides the round cap. Logs carry PR numbers, SHAs,
// run ids and counts only.

import { infraOnly, reconcilerRetries } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { runTitle } from "./feedback-dispatch.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  activity: "fix-ci",
  checkName: "pr-unblock / fix-ci",
  // The GitHub Actions app, as in dispatch.mjs: only its runs count.
  actionsAppId: 15368,
  holdLabels: Object.freeze(["do-not-merge", "needs-human"]),
  // No owner is adopted unless the config lists one.
  adoption: Object.freeze({ ownerIds: Object.freeze([]), idleHours: 24 }),
});

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
    pullRequests(states: OPEN, baseRefName: $base, first: 50, after: $after) {
      nodes {
        number isDraft isCrossRepository baseRefName headRefOid updatedAt body
        author { login ... on Bot { databaseId } ... on User { databaseId } }
        labels(first: 100) { nodes { name } }
        commits(last: 1) {
          nodes {
            commit {
              oid committedDate
              statusCheckRollup {
                contexts(first: 100) {
                  nodes {
                    __typename
                    ... on CheckRun { name status conclusion title checkSuite { app { databaseId } } }
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
  // A cut-off list could hide ci-status or an earlier fix-ci run.
  if (!commit || commit.oid !== node.headRefOid || commit.statusCheckRollup?.contexts?.pageInfo?.hasNextPage) {
    return null;
  }
  return (commit.statusCheckRollup?.contexts?.nodes ?? []).filter(
    (context) => context?.__typename === "CheckRun" && context.checkSuite?.app?.databaseId === actionsAppId,
  );
}

// An owner PR is idle when neither it nor its head commit changed in the last
// idleHours; an unreadable date is not idle.
function ownerIdle(node, idleHours, now) {
  const commit = node.commits?.nodes?.[0]?.commit;
  const since = now - idleHours * 3_600_000;
  return commit?.oid === node.headRefOid && Date.parse(node.updatedAt) <= since && Date.parse(commit.committedDate) <= since;
}

// Why a listed PR is not dispatched, or "" when it is a candidate.
export function skipReason(node, { base, appSenderId, actionsAppId, checkName, holdLabels, restarts, adoption = DEFAULTS.adoption, now = Date.now() }) {
  if (node.isDraft !== false || node.isCrossRepository !== false || node.baseRefName !== base) {
    return "not a ready same-repository PR into the base";
  }
  const owner = node.author?.databaseId !== appSenderId;
  if (owner && !adoption.ownerIds.includes(node.author?.databaseId)) {
    return "not opened by the lanes App or an adoptable owner";
  }
  if ((node.labels?.nodes ?? []).some((label) => holdLabels.includes(label?.name))) {
    return "held";
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
  if (!checks.some((run) => run.name === "ci-status" && run.status === "COMPLETED" && run.conclusion === "FAILURE")) {
    return "ci-status has not failed";
  }
  // node.requiredRun, the head's tested pr-require-checks run and its latest
  // jobs, is attached by dispatchCiFixes just before it would dispatch.
  const required = node.requiredRun;
  if (required !== undefined && infraOnly(required.jobs) && reconcilerRetries(required.run, now)) {
    return "infra failure, re-run job owns it";
  }
  // An untrusted-trigger skip ran nothing, so it does not count.
  const runs = checks.filter(
    (run) => run.name === checkName && !(run.conclusion === "NEUTRAL" && String(run.title ?? "").startsWith("Skipped: untrusted-trigger")),
  );
  if (runs.length === 0) {
    return "";
  }
  if (runs.some((run) => run.status !== "COMPLETED" || run.conclusion !== "FAILURE")) {
    return `head already has a ${checkName} check run`;
  }
  return runs.length <= restarts ? "" : `head's ${checkName} failed ${runs.length} time(s), past ${restarts} restart(s)`;
}

export async function dispatchCiFixes({
  api,
  runId,
  log,
  appSenderId,
  maxDispatch,
  restarts,
  base = DEFAULTS.base,
  workflow = DEFAULTS.workflow,
  activity = DEFAULTS.activity,
  checkName = DEFAULTS.checkName,
  actionsAppId = DEFAULTS.actionsAppId,
  holdLabels = DEFAULTS.holdLabels,
  adoption = DEFAULTS.adoption,
  now = Date.now(),
}) {
  if (!Number.isSafeInteger(appSenderId) || appSenderId < 1) {
    throw new Error("the lanes App sender id is not a user id");
  }
  const candidates = [];
  let after;
  for (let page = 1; ; page += 1) {
    const { rateLimit, pullRequests } = await api.listCiFixCandidates({ base, after });
    log(`fix-ci listing page ${page}: rateLimit.cost=${rateLimit?.cost} remaining=${rateLimit?.remaining}`);
    for (const node of pullRequests.nodes) {
      if (skipReason(node, { base, appSenderId, actionsAppId, checkName, holdLabels, restarts, adoption, now }) === "") {
        candidates.push(node);
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
    // A failure an outside outage explains is the lost-run reconciler's to
    // re-run, never a model run's to fix.
    let requiredRun;
    try {
      requiredRun = await api.readRequiredRun(node.headRefOid);
    } catch (error) {
      log(`::warning::#${node.number}: could not read its required run's jobs (${error.message}); left for a later run`);
      continue;
    }
    const reason = skipReason({ ...node, requiredRun }, { base, appSenderId, actionsAppId, checkName, holdLabels, restarts, adoption, now });
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
      log(`dispatched fix-ci #${node.number} head ${node.headRefOid} workflow_run_id=${id}`);
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: dispatch failed: ${error.message}`);
    }
  }
  return { dispatched, failed };
}
