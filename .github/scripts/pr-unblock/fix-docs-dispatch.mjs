// Starts the pr-refine lane's fix-docs activity once per pull request: for
// each open, ready, same-repository PR into the base that changes a Markdown
// file, carries no hold label (the human-gated one only when a lane escalation
// put it on: gate-source.mjs prHold), and has never had a fix-docs check run under
// either lane fix-docs has run in, by any author except the accounts in
// excludedAuthorIds (refine-event-dispatch.mjs offers only a PR whose event's
// sender is the lanes App or a listed human), and is not a work-resolve-issue PR (the lanes App's, on a
// lane branch, whose one commit is the lane run's) tidied in its own run
// (within the tidy cutoffs). It runs from pr-unblock-dispatch.yml's refine
// job for the one PR whose pull_request_target event started that run
// (refine-event-dispatch.mjs), so the trigger gate and the broker check it as
// they check a resolve-conflicts dispatch.
//
// Once per PR, not after each push. The listing the caller passes (that one
// PR, read by dispatch.mjs's PULL_QUERY) logs its rateLimit.cost; it drops a
// PR whose head already has the check run. For each PR left, lowest number
// first, one more query reads the check runs on its last HISTORY_COMMITS
// commits, and a PR with one on any of them is done for good: its head goes
// into the dispatch record, when the caller keeps one, so a later run skips
// that read. A run older than that window, or a force-push that dropped its
// commit, costs one more run. At most `fix-docs-per-run` dispatches per
// dispatcher run; 0 sends none and makes no GitHub call. Logs carry PR
// numbers, SHAs, run ids and counts only.
//
// A run whose model leg emitted an empty head, or that stopped at its trigger
// gate, posts no check (post-decline: false), so a check run alone would let a
// PR be dispatched every cycle. The newest runs of the workflow, read once
// for the in-flight guard, settle it too: a PR with a completed run titled
// for it is done, and its head goes into the dispatch record, unless each such
// run says nothing about the PR. Those get another dispatch, the PR's next
// event being the probe (outage posture element 3):
//   - one lost run (LOST: cancelled, timed_out or startup_failure);
//   - fewer than maxRunsPerHead runs that went red, or that ended green on a
//     failed or lagging handoff read (heldHandoff) or an unread PR head
//     (heldHead), the one green run whose jobs are read.
//     A red run that posted its check is ended by that check. Red alone names no
//     cause, a read that failed or a broker that refused, so the count is what
//     ends a refusal, and an outage past that many runs still ends the PR.
// The listing cannot tell a run the broker's refusal skipped, a hold skipped or
// a kill switch stopped from one that ran the model, so each that ended green
// ends the PR too. A run older than that listing costs one more run.
//
// A dispatch record the caller keeps also holds the fix-docs runs dispatched
// on each head; refine-event-dispatch.mjs keeps none, so each event's run
// starts from an empty one;
// once `limit-stops-per-head` are kept, each one's status and jobs are read
// through the Actions API, and a head with that many whose broker-allowed job
// succeeded (which no run job can write: handoff-evidence.sh's allowed) goes
// into the dispatch record with one `::warning::`, until a new push. For this
// cap, a run the broker refused, or one a hold skipped, ended with no model
// turn: it does not count and leaves the list once it is done, as a run that
// is gone does.

import { LOST } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { allLaneCommits, laneBranchIssue } from "../work-resolve-issue/report-outcome.mjs";
import { isHandled, markHandled, emptyRecord, sendDispatch } from "./dispatch-record.mjs";
import { prHold, reviewReader } from "./gate-source.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-refine.yml",
  activity: "fix-docs",
  checkName: "pr-refine / fix-docs",
  // fix-docs ran in the pr-unblock lane before; a run there counts as done.
  earlierCheckName: "pr-unblock / fix-docs",
  // Account ids (GET /users/<login>, the same as GraphQL's databaseId):
  // dependabot[bot], whose own rebases a lane commit stops;
  // melodic-release[bot] and melodic-standards-sync[bot], whose PRs
  // carry generated or synced files.
  excludedAuthorIds: Object.freeze([49699333, 337859524, 300666570]),
  // The GitHub Actions app, as in dispatch.mjs: only its runs count.
  actionsAppId: 15368,
  // fix-docs's applies-when labels-absent (docs/conventions/pr-pipeline.yaml).
  holdLabels: Object.freeze(["do-not-merge", "needs-human"]),
  // pr-refine.yml's first fix-docs call's broker-allowed job; the other legs
  // run only after it succeeded.
  allowedJob: "fix-docs / broker-allowed",
  // fix-docs runs with a broker allow one head gets:
  // limits.limit-stops-per-head's default, which refine-event-dispatch.mjs passes resolved.
  maxRunsPerHead: 3,
});

export const HISTORY_COMMITS = 50;
const MAX_PAGES = 20;
// fix-docs's applies-when paths, **/*.md.
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

// A changed path's area under resolve-issue's tidy cutoffs (README,
// Activities, `tidy`): plugins/<name> with .changes/<name>, docs/<dir>, else
// the top-level segment.
const areaOf = (path) => {
  const [top, next] = path.split("/");
  if (next !== undefined && (top === "plugins" || top === ".changes")) {
    return `plugins/${next}`;
  }
  return next !== undefined && top === "docs" ? `docs/${next}` : top;
};

// Whether the PR's change is within resolve-issue's tidy cutoffs, so its run
// tidied it: at most max-files files and max-lines added plus removed lines,
// no path under shared-paths (a directory ends in /), at most max-areas areas.
// No cutoffs, a file list not read whole, or a count not read is not within.
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

// Whether the PR's head is the lane run's own commit, which its tidy saw: the
// PR has one commit, the listed one, and it is the lanes App's API commit
// (report-outcome.mjs allLaneCommits). A listed commit other than the head is
// left to the head check below, which lists the PR as no candidate. The listing's GraphQL fields go
// into the REST shape that helper reads; GitHub records web-flow, whose email
// is noreply@github.com, as the committer of a commit it signs for the API.
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

// Why a listed PR is not a candidate, or "" when it is one.
// The human-gated gateLabel is left to dispatchDocsFixes's prHold read.
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
  // work-resolve-issue tidies its own change in its run when the change is
  // within its tidy cutoffs (its `tidy` key, #8485). Every term: the App's
  // other PRs never tidied, anyone can name a branch, a later push (a
  // person's, fix-ci's, resolve-conflicts') was never tidied, and a lane
  // change over the cutoffs was not tidied. author is a safe integer, so an
  // unset or malformed id skips none.
  if (author === appSenderId && laneBranchIssue(node.headRefName) !== null && laneRunHead(node) && withinTidyCutoffs(node, tidyCutoffs)) {
    return "a work-resolve-issue PR, tidied in its own run";
  }
  if ((node.labels?.nodes ?? []).some((label) => holdLabels.includes(label?.name) && label?.name !== gateLabel)) {
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
  const names = [checkName, earlierCheckName];
  const runs = (commit.statusCheckRollup?.contexts?.nodes ?? []).filter(
    (context) => context?.__typename === "CheckRun" && names.includes(context.name) && context.checkSuite?.app?.databaseId === actionsAppId,
  );
  return runs.length > 0 ? `head already has a ${checkName} check run` : "";
}

// Whether any of the PR's last commits carries a check run of either name; a
// commit whose suites were not listed whole counts as carrying one.
function historyHasRun(pullRequest) {
  return (pullRequest?.commits?.nodes ?? []).some((node) => {
    const suites = node?.commit?.checkSuites;
    return (
      suites?.pageInfo?.hasNextPage === true ||
      (suites?.nodes ?? []).some((suite) => suite?.checkRuns?.totalCount > 0 || suite?.earlierRuns?.totalCount > 0)
    );
  });
}

// Whether a run held on a handoff read (handoff-evidence.sh's hold or lag notice,
// each of which ends the run green): a leg handed off, read from job conclusions as that script
// reads them, its handoff job succeeded, and the next leg never started, which
// pr-refine.yml starts on a handoff that read settled. A scan job skips on the run
// job's handed-off output, which head code can forge, so the handoff job's own
// conclusion is what shows a read ran: a leg with no fallback token has none.
export function heldHandoff(run, activity = DEFAULTS.activity) {
  const jobs = run?.jobs ?? [];
  const conclusion = (name) => jobs.find((job) => job?.name === name)?.conclusion;
  const legs = [activity, `${activity}-subscription`, `${activity}-fallback`];
  return legs.slice(0, -1).some((leg, index) => {
    const scan = conclusion(`${leg} / scan`);
    return (
      conclusion(`${leg} / broker-allowed`) === "success" &&
      conclusion(`${leg} / run`) === "success" &&
      (scan === undefined || scan === "skipped") &&
      conclusion(`${leg}-handoff`) === "success" &&
      !jobs.some((job) => job?.name?.startsWith(`${legs[index + 1]} / `) && job.conclusion !== "skipped")
    );
  });
}

// Whether a run held on an unread PR head: pr-refine.yml's <activity>-head-held
// job, which runs only on fix-docs-head's unread output, succeeded. A green run
// without it, such as one a human-gated hold skipped, still ends the PR.
export function heldHead(run, activity = DEFAULTS.activity) {
  return (run?.jobs ?? []).some((job) => job?.name === `${activity}-head-held` && job.conclusion === "success");
}

// The run-name the workflow gives a dispatch: its file stem, the activity
// and the PR (pr-refine.yml's run-name).
const runTitle = (workflow, activity, number) => `${workflow.replace(/\.ya?ml$/, "")} ${activity} #${number}`;

// Whether the PR's completed runs among the listed ones make it done: any that
// ended the PR, a second lost one, or maxRuns red or held ones. A held run is a
// green one whose jobs show a handoff hold or an unread head.
async function docsRunsEnded(runs, title, readRunJobs, activity, maxRuns) {
  const ended = runs.filter((run) => run.status === "completed" && run.display_title === title);
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

// What a fix-docs run (its status and the REST listing's latest jobs) shows:
// "allowed" when its broker-allowed job succeeded, "done" when it ended
// without that or is gone (null), else "going".
export function docsRunState(run, allowedJob = DEFAULTS.allowedJob) {
  if (run === null) {
    return "done";
  }
  if (run.jobs.some((job) => job?.name === allowedJob && job.conclusion === "success")) {
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
  allowedJob = DEFAULTS.allowedJob,
  maxRunsPerHead = DEFAULTS.maxRunsPerHead,
  gateLabel = null,
  appSenderId,
  // resolve-issue's tidy cutoffs from the base config, null when it does not tidy.
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
  if (candidates.length === 0) {
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
  for (const node of candidates) {
    const title = runTitle(workflow, activity, node.number);
    let runEnded;
    try {
      runEnded = await docsRunsEnded(runs, title, (id) => api.readRunJobs(id), activity, maxRunsPerHead);
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
    const inFlight = runs.find((run) => run.status !== "completed" && run.display_title === title);
    if (inFlight) {
      log(`skip fix-docs #${node.number}: ${workflow} run ${inFlight.id} is not done yet`);
      continue;
    }
    try {
      const { rateLimit, pullRequest } = await api.readDocsFixHistory({ number: node.number, appId: actionsAppId, checkName, earlierCheckName });
      log(`fix-docs history #${node.number}: rateLimit.cost=${rateLimit?.cost} remaining=${rateLimit?.remaining}`);
      if (historyHasRun(pullRequest)) {
        markHandled(record, checkName, node.headRefOid);
        log(`skip fix-docs #${node.number}: an earlier commit already has a ${checkName} check run`);
        continue;
      }
      // Then the human-gated label holds unless a lane escalation put it on;
      // a held PR is not done, so it is not recorded.
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
      // A read that fails, whatever GitHub answered, holds the PR for a later run.
      log(`::warning::#${node.number}: could not read fix-docs history or holds: ${error.message}; skipped, a later run retries`);
      continue;
    }
    // The per-head cap is the loop's hard end, so a head whose runs cannot be
    // read is not dispatched.
    const head = node.headRefOid;
    const kept = record.docsRuns.get(head) ?? [];
    if (kept.length >= maxRunsPerHead) {
      const states = [];
      try {
        for (const id of kept) {
          states.push(docsRunState(await api.readRunJobs(id), allowedJob));
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
    // Every dispatch call counts against the cap: one that failed or returned
    // no usable id may still have started a run.
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
