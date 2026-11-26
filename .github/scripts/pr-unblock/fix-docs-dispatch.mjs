import { DISPATCH_HOLDS } from "../lib/lane-vocabulary.mjs";
import { isPrRefineTitle } from "../lib/run-title.mjs";
import { LOST } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { allLaneCommits, laneBranchIssue } from "../work-resolve-issue/report-outcome.mjs";
import { isHandled, markHandled, emptyRecord, sendDispatch } from "./dispatch-record.mjs";
import { prHold, reviewReader } from "./gate-source.mjs";

const ALLOW_JOBS = ["broker-allowed", "record-broker-allow"];

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-refine.yml",
  activity: "fix-docs",
  checkName: "pr-refine / fix-docs",
  earlierCheckName: "pr-unblock / fix-docs",
  excludedAuthorIds: Object.freeze([49699333, 337859524, 300666570]),
  actionsAppId: 15368,
  holdLabels: DISPATCH_HOLDS,
  allowedJobs: Object.freeze(ALLOW_JOBS.map((id) => `fix-docs / ${id}`)),
  maxRunsPerHead: 3,
});

export const HISTORY_COMMITS = 50;
const MAX_PAGES = 20;
const MARKDOWN = /\.md$/;

export const HISTORY_QUERY = `query($owner: String!, $name: String!, $number: Int!, $appId: Int!, $checkName: String!, $earlierCheckName: String!) {
  rateLimit { cost remaining }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      commits(last: ${HISTORY_COMMITS}) {
        nodes {
          commit {
            checkSuites(first: 20, filterBy: { appId: $appId }) {
              nodes {
                checkRuns(first: 1, filterBy: { checkName: $checkName }) { totalCount }
                earlierRuns: checkRuns(first: 1, filterBy: { checkName: $earlierCheckName }) { totalCount }
              }
              pageInfo { hasNextPage }
            }
          }
        }
      }
    }
  }
}`;

const areaOf = (path) => {
  const [top, next] = path.split("/");
  if (next !== undefined && (top === "plugins" || top === ".changes")) {
    return `plugins/${next}`;
  }
  return next !== undefined && top === "docs" ? `docs/${next}` : top;
};

export function withinTidyCutoffs(node, cutoffs) {
  if (cutoffs === null || node.files?.pageInfo?.hasNextPage !== false) {
    return false;
  }
  if (!(node.changedFiles <= cutoffs["max-files"]) || !(node.additions + node.deletions <= cutoffs["max-lines"])) {
    return false;
  }
  const paths = (node.files.nodes ?? []).map((file) => String(file?.path ?? ""));
  const shared = cutoffs["shared-paths"] ?? [];
  if (paths.some((path) => shared.some((entry) => (entry.endsWith("/") ? path.startsWith(entry) : path === entry)))) {
    return false;
  }
  return new Set(paths.map(areaOf)).size <= cutoffs["max-areas"];
}

function laneRunHead(node) {
  const commit = node.commits?.nodes?.[0]?.commit;
  if (node.commits?.totalCount !== 1 || !commit) {
    return false;
  }
  const rest = {
    commit: { verification: { verified: commit.signature?.isValid === true } },
    author: { login: commit.author?.user?.login },
    committer: { login: commit.committer?.email === "noreply@github.com" ? "web-flow" : undefined },
  };
  return allLaneCommits([rest], `${node.author.login}[bot]`);
}

export function skipReason(node, { base, actionsAppId, checkName, earlierCheckName, excludedAuthorIds, holdLabels, gateLabel = null, appSenderId, tidyCutoffs = null }) {
  if (node.isDraft !== false || node.isCrossRepository !== false || node.baseRefName !== base) {
    return "not a ready same-repository PR into the base";
  }
  const author = node.author?.databaseId;
  if (!Number.isSafeInteger(author)) {
    return "author has no account id";
  }
  if (excludedAuthorIds.includes(author)) {
    return "opened by an excluded account";
  }
  if (author === appSenderId && laneBranchIssue(node.headRefName) !== null && laneRunHead(node) && withinTidyCutoffs(node, tidyCutoffs)) {
    return "a work-resolve-issue PR, tidied in its own run";
  }
  if ((node.labels?.nodes ?? []).some((label) => holdLabels.includes(label?.name) && label?.name !== gateLabel)) {
    return "held";
  }
  const paths = (node.files?.nodes ?? []).map((file) => String(file?.path ?? ""));
  if (!paths.some((path) => MARKDOWN.test(path)) && !node.files?.pageInfo?.hasNextPage) {
    return "changes no Markdown file";
  }
  const commit = node.commits?.nodes?.[0]?.commit;
  if (!commit || commit.oid !== node.headRefOid || commit.statusCheckRollup?.contexts?.pageInfo?.hasNextPage) {
    return "head commit or its checks not listed whole";
  }
  const names = [checkName, earlierCheckName];
  const runs = (commit.statusCheckRollup?.contexts?.nodes ?? []).filter(
    (context) => context?.__typename === "CheckRun" && names.includes(context.name) && context.checkSuite?.app?.databaseId === actionsAppId,
  );
  return runs.length > 0 ? `head already has a ${checkName} check run` : "";
}

function historyHasRun(pullRequest) {
  return (pullRequest?.commits?.nodes ?? []).some((node) => {
    const suites = node?.commit?.checkSuites;
    return (
      suites?.pageInfo?.hasNextPage === true ||
      (suites?.nodes ?? []).some((suite) => suite?.checkRuns?.totalCount > 0 || suite?.earlierRuns?.totalCount > 0)
    );
  });
}

const titled = (id) => id.replace(/[a-z0-9]+/g, (word) => word[0].toUpperCase() + word.slice(1)).replaceAll("-", " ");
const NAMINGS = [titled, (id) => id];
const isJob = (job, id) => NAMINGS.some((named) => job?.name === named(id));

export function heldHandoff(run, activity = DEFAULTS.activity) {
  const jobs = run?.jobs ?? [];
  return NAMINGS.some((named) => {
    const conclusion = (id) => jobs.find((job) => job?.name === named(id))?.conclusion;
    const legs = [activity, `${activity}-subscription`, `${activity}-fallback`];
    return legs.slice(0, -1).some((leg, index) => {
      const scan = conclusion(`${leg} / scan`);
      return (
        ALLOW_JOBS.some((id) => conclusion(`${leg} / ${id}`) === "success") &&
        conclusion(`${leg} / run`) === "success" &&
        (scan === undefined || scan === "skipped") &&
        conclusion(`${leg}-handoff`) === "success" &&
        !jobs.some((job) => job?.name?.startsWith(`${named(legs[index + 1])} / `) && job.conclusion !== "skipped")
      );
    });
  });
}

export function heldHead(run, activity = DEFAULTS.activity) {
  return (run?.jobs ?? []).some((job) => isJob(job, `${activity}-head-held`) && job.conclusion === "success");
}

async function docsRunsEnded(runs, titled, readRunJobs, activity, maxRuns) {
  const ended = runs.filter((run) => run.status === "completed" && titled(run));
  const lost = ended.filter((run) => LOST.has(run.conclusion)).length;
  let again = ended.filter((run) => run.conclusion === "failure").length;
  for (const run of ended) {
    if (LOST.has(run.conclusion) || run.conclusion === "failure") {
      continue;
    }
    if (run.conclusion !== "success") {
      return true;
    }
    const jobs = await readRunJobs(run.id);
    if (!heldHandoff(jobs, activity) && !heldHead(jobs, activity)) {
      return true;
    }
    again += 1;
  }
  return lost > 1 || again >= maxRuns;
}

export function docsRunState(run, allowedJobs = DEFAULTS.allowedJobs) {
  if (run === null) {
    return "done";
  }
  if (run.jobs.some((job) => allowedJobs.some((id) => isJob(job, id)) && job.conclusion === "success")) {
    return "allowed";
  }
  return run.status === "completed" ? "done" : "going";
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
  earlierCheckName = DEFAULTS.earlierCheckName,
  excludedAuthorIds = DEFAULTS.excludedAuthorIds,
  actionsAppId = DEFAULTS.actionsAppId,
  holdLabels = DEFAULTS.holdLabels,
  allowedJobs = DEFAULTS.allowedJobs,
  maxRunsPerHead = DEFAULTS.maxRunsPerHead,
  gateLabel = null,
  appSenderId,
  tidyCutoffs = null,
}) {
  if (maxDispatch === 0) {
    log("fix-docs is off (fix-docs-per-run: 0)");
    return { dispatched: [], failed: 0 };
  }
  const candidates = [];
  let after;
  for (let page = 1; ; page += 1) {
    const { rateLimit, pullRequests } = await api.listDocsFixCandidates({ base, after });
    log(`fix-docs listing page ${page}: rateLimit.cost=${rateLimit?.cost} remaining=${rateLimit?.remaining}`);
    for (const node of pullRequests.nodes) {
      const reason = skipReason(node, { base, actionsAppId, checkName, earlierCheckName, excludedAuthorIds, holdLabels, gateLabel, appSenderId, tidyCutoffs });
      if (reason.startsWith("head already has") || (reason === "" && isHandled(record, earlierCheckName, node.headRefOid))) {
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
  const unsettled = [];
  for (const node of candidates) {
    try {
      const { rateLimit, pullRequest } = await api.readDocsFixHistory({ number: node.number, appId: actionsAppId, checkName, earlierCheckName });
      log(`fix-docs history #${node.number}: rateLimit.cost=${rateLimit?.cost} remaining=${rateLimit?.remaining}`);
      if (historyHasRun(pullRequest)) {
        markHandled(record, checkName, node.headRefOid);
        log(`skip fix-docs #${node.number}: an earlier commit already has a ${checkName} check run`);
        continue;
      }
    } catch (error) {
      log(`::warning::#${node.number}: could not read fix-docs history or holds: ${error.message}; skipped, a later run retries`);
      continue;
    }
    unsettled.push(node);
  }
  if (unsettled.length === 0) {
    return { dispatched, failed };
  }
  let runs;
  try {
    runs = await api.listWorkflowRuns(workflow);
  } catch (error) {
    log(`::warning::${workflow} run listing ${error.rateLimited ? "is rate limited" : "could not be read"} (${error.message}); no fix-docs dispatched, a later run retries`);
    return { dispatched, failed };
  }
  let sent = 0;
  for (const node of unsettled) {
    const titled = (run) => isPrRefineTitle(run.display_title, activity, node.number);
    let runEnded;
    try {
      runEnded = await docsRunsEnded(runs, titled, (id) => api.readLatestJobs(id), activity, maxRunsPerHead);
    } catch (error) {
      log(`::warning::#${node.number}: a ${workflow} run's jobs ${error.rateLimited ? "are rate limited" : "could not be read"} (${error.message}); no fix-docs dispatched, a later run retries`);
      continue;
    }
    if (runEnded) {
      markHandled(record, checkName, node.headRefOid);
      record.docsRuns.delete(node.headRefOid);
      log(`skip fix-docs #${node.number}: a ${workflow} run for it already ended`);
      continue;
    }
    if (sent >= maxDispatch) {
      log(`defer fix-docs #${node.number}: ${maxDispatch} fix-docs dispatches this run; left for a later run`);
      continue;
    }
    const inFlight = runs.find((run) => run.status !== "completed" && titled(run));
    if (inFlight) {
      log(`skip fix-docs #${node.number}: ${workflow} run ${inFlight.id} is not done yet`);
      continue;
    }
    try {
      const { held, why } = await prHold({
        labels: (node.labels?.nodes ?? []).map((label) => label?.name),
        holdLabels,
        gateLabel,
        head: node.headRefOid,
        activity,
        appId: appSenderId,
        readTimeline: () => api.listTimeline(node.number),
        readReviews: reviewReader(api, node.number),
      });
      if (held) {
        log(`skip fix-docs #${node.number}: ${why}`);
        continue;
      }
    } catch (error) {
      log(`::warning::#${node.number}: could not read fix-docs history or holds: ${error.message}; skipped, a later run retries`);
      continue;
    }
    const head = node.headRefOid;
    const kept = record.docsRuns.get(head) ?? [];
    if (kept.length >= maxRunsPerHead) {
      const states = [];
      try {
        for (const id of kept) {
          states.push(docsRunState(await api.readRunJobs(id), allowedJobs));
        }
      } catch (error) {
        if (error.rateLimited) {
          log(`::warning::#${node.number}: its fix-docs run read is rate limited (${error.message}); no fix-docs dispatched, a later run retries`);
        } else {
          log(`::warning::#${node.number}: could not read its fix-docs runs: ${error.message}; skipped, a later run retries`);
        }
        continue;
      }
      const allowed = states.filter((state) => state === "allowed").length;
      if (allowed >= maxRunsPerHead) {
        log(`::warning::#${node.number}: head ${head}'s fix-docs ran ${allowed} time(s) with no ${checkName} check run, the most one head gets; no fix-docs until a new push`);
        markHandled(record, checkName, head);
        record.docsRuns.delete(head);
        continue;
      }
      record.docsRuns.set(head, kept.filter((_, index) => states[index] !== "done"));
    }
    sent += 1;
    const id = await sendDispatch(api, log, {
      workflow,
      base,
      node,
      label: "fix-docs ",
      inputs: { "pr-number": String(node.number), activity, "dispatcher-run-id": String(runId) },
    });
    if (id === null) {
      failed += 1;
      continue;
    }
    dispatched.push({ number: node.number, workflowRunId: id });
    record.docsRuns.set(head, [...(record.docsRuns.get(head) ?? []), id]);
  }
  return { dispatched, failed };
}
