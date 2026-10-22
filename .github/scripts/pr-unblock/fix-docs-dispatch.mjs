// Starts the pr-unblock lane's fix-docs activity once per pull request: for
// each open, ready, same-repository PR into the base that a person opened,
// that changes a Markdown file, carries no hold label, and has never had a
// pr-unblock / fix-docs check run. It runs from the same dispatcher run as
// dispatch.mjs (pr-unblock-dispatch.yml), so the trigger gate and the broker
// check it as they check a resolve-conflicts dispatch.
//
// Once per PR, as pr-refine.yml's pull_request trigger ran it when a PR opened
// or turned ready, not after each push. The listing is one GraphQL query per
// page of 50 pull requests, whose rateLimit.cost is logged; it drops a PR
// whose head already has the check run. For each PR left, lowest number
// first, one more query reads the check runs on its last HISTORY_COMMITS
// commits, and a PR with one on any of them is done for good: its head goes
// into the dispatch record so the next run skips that read. A run older than
// that window, or a force-push that dropped its commit, costs one more run.
// At most `fix-docs-per-run` dispatches per dispatcher run. Logs carry PR
// numbers, SHAs, run ids and counts only.

import { isHandled, markHandled, emptyRecord } from "./dispatch-record.mjs";
import { runTitle } from "./feedback-dispatch.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  activity: "fix-docs",
  checkName: "pr-unblock / fix-docs",
  // The GitHub Actions app, as in dispatch.mjs: only its runs count.
  actionsAppId: 15368,
  // fix-docs's applies-when labels-absent (docs/conventions/pr-pipeline.yaml).
  holdLabels: Object.freeze(["do-not-merge", "needs-human"]),
});

export const HISTORY_COMMITS = 50;
const RUN_ID = /^[1-9][0-9]{0,14}$/;
const MAX_PAGES = 20;
// fix-docs's applies-when paths, **/*.md.
const MARKDOWN = /\.md$/;

export const LIST_QUERY = `query($owner: String!, $name: String!, $base: String!, $after: String) {
  rateLimit { cost remaining }
  repository(owner: $owner, name: $name) {
    pullRequests(states: OPEN, baseRefName: $base, first: 50, after: $after) {
      nodes {
        number isDraft isCrossRepository baseRefName headRefOid
        author { __typename login }
        labels(first: 100) { nodes { name } }
        files(first: 100) { nodes { path } pageInfo { hasNextPage } }
        commits(last: 1) {
          nodes {
            commit {
              oid
              statusCheckRollup {
                contexts(first: 100) {
                  nodes {
                    __typename
                    ... on CheckRun { name checkSuite { app { databaseId } } }
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

export const HISTORY_QUERY = `query($owner: String!, $name: String!, $number: Int!, $appId: Int!, $checkName: String!) {
  rateLimit { cost remaining }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      commits(last: ${HISTORY_COMMITS}) {
        nodes {
          commit {
            checkSuites(first: 20, filterBy: { appId: $appId }) {
              nodes { checkRuns(first: 1, filterBy: { checkName: $checkName }) { totalCount } }
              pageInfo { hasNextPage }
            }
          }
        }
      }
    }
  }
}`;

// Why a listed PR is not a candidate, or "" when it is one.
export function skipReason(node, { base, actionsAppId, checkName, holdLabels }) {
  if (node.isDraft !== false || node.isCrossRepository !== false || node.baseRefName !== base) {
    return "not a ready same-repository PR into the base";
  }
  // pr-refine.yml skipped the lanes App's events and every other bot's.
  if (node.author?.__typename !== "User") {
    return "not opened by a person";
  }
  if ((node.labels?.nodes ?? []).some((label) => holdLabels.includes(label?.name))) {
    return "held";
  }
  const paths = (node.files?.nodes ?? []).map((file) => String(file?.path ?? ""));
  // A list cut off at 100 files may hold a Markdown file further on; the lane's
  // own applies-when then decides, before any model turn.
  if (!paths.some((path) => MARKDOWN.test(path)) && !node.files?.pageInfo?.hasNextPage) {
    return "changes no Markdown file";
  }
  const commit = node.commits?.nodes?.[0]?.commit;
  if (!commit || commit.oid !== node.headRefOid || commit.statusCheckRollup?.contexts?.pageInfo?.hasNextPage) {
    return "head commit or its checks not listed whole";
  }
  const runs = (commit.statusCheckRollup?.contexts?.nodes ?? []).filter(
    (context) => context?.__typename === "CheckRun" && context.name === checkName && context.checkSuite?.app?.databaseId === actionsAppId,
  );
  return runs.length > 0 ? `head already has a ${checkName} check run` : "";
}

// Whether any of the PR's last commits carries a check run of checkName; a
// commit whose suites were not listed whole counts as carrying one.
function historyHasRun(pullRequest) {
  return (pullRequest?.commits?.nodes ?? []).some((node) => {
    const suites = node?.commit?.checkSuites;
    return suites?.pageInfo?.hasNextPage === true || (suites?.nodes ?? []).some((suite) => suite?.checkRuns?.totalCount > 0);
  });
}

export async function dispatchDocsFixes({
  api,
  runId,
  log,
  maxDispatch,
  record = emptyRecord(),
  base = DEFAULTS.base,
  workflow = DEFAULTS.workflow,
  activity = DEFAULTS.activity,
  checkName = DEFAULTS.checkName,
  actionsAppId = DEFAULTS.actionsAppId,
  holdLabels = DEFAULTS.holdLabels,
}) {
  const candidates = [];
  let after;
  for (let page = 1; ; page += 1) {
    const { rateLimit, pullRequests } = await api.listDocsFixCandidates({ base, after });
    log(`fix-docs listing page ${page}: rateLimit.cost=${rateLimit?.cost} remaining=${rateLimit?.remaining}`);
    for (const node of pullRequests.nodes) {
      const reason = skipReason(node, { base, actionsAppId, checkName, holdLabels });
      if (reason.startsWith("head already has")) {
        markHandled(record, checkName, node.headRefOid);
      } else if (reason === "" && !isHandled(record, checkName, node.headRefOid)) {
        candidates.push(node);
      }
    }
    if (!pullRequests.pageInfo.hasNextPage) {
      break;
    }
    if (page === MAX_PAGES || pullRequests.pageInfo.endCursor === after) {
      log(`::warning::fix-docs listing stopped after page ${page}; later pull requests wait for a later run`);
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
  let sent = 0;
  for (const node of candidates) {
    if (sent >= maxDispatch) {
      log(`defer fix-docs #${node.number}: ${maxDispatch} fix-docs dispatches this run; left for a later run`);
      continue;
    }
    const inFlight = active.find((run) => run.display_title === runTitle(activity, node.number));
    if (inFlight) {
      log(`skip fix-docs #${node.number}: ${workflow} run ${inFlight.id} is not done yet`);
      continue;
    }
    try {
      const { rateLimit, pullRequest } = await api.readDocsFixHistory({ number: node.number, appId: actionsAppId, checkName });
      log(`fix-docs history #${node.number}: rateLimit.cost=${rateLimit?.cost} remaining=${rateLimit?.remaining}`);
      if (historyHasRun(pullRequest)) {
        markHandled(record, checkName, node.headRefOid);
        log(`skip fix-docs #${node.number}: an earlier commit already has a ${checkName} check run`);
        continue;
      }
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: could not read fix-docs history: ${error.message}`);
      continue;
    }
    // Every dispatch call counts against the cap: one that failed or returned
    // no usable id may still have started a run.
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
      log(`dispatched fix-docs #${node.number} head ${node.headRefOid} workflow_run_id=${id}`);
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: dispatch failed: ${error.message}`);
    }
  }
  return { dispatched, failed };
}
