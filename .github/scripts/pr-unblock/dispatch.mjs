// Starts the pr-unblock lane for each open pull request GitHub reports as
// conflicting, because no pull_request event fires on a conflicting PR.
// Run by .github/workflows/pr-unblock-dispatch.yml on a push to main or its
// half-hourly tick, after the kill switch and, where needed, the
// trusted-trigger gate; this script does no sender check of its own.
//
// It lists open PRs into main, keeps the non-draft, same-repository ones
// whose mergeable state is CONFLICTING (re-querying UNKNOWN a bounded number
// of times), skips a PR whose resolve-conflicts run is still queued or going,
// a held PR (do-not-merge, or the human-gated label unless another lane's
// escalation put it on: gate-source.mjs prHold), or one whose current head
// already carries a pr-unblock check run that handles it (limit-stop.mjs: a
// limit stop, a usage limit or a refused credential, stops counting once its
// limit resets, and the skip names its class and reset; a failed run until
// limit-stops-per-head failures stand on the head, a skip while held once
// the hold is gone, a head-lag stop (the gate's lagging PR read) at once, and a select job's own lane-stopped skip once the base tip
// was committed after it started, since the head then merges another base),
// and dispatches pr-unblock.yml on main for at most maxDispatch of them,
// lowest PR number first, heads retried on a moved base last. Authors are
// left to the lane's own config and gate. Logs carry PR numbers, SHAs and run ids only. The run ids
// it dispatched become the step output run-ids, which the workflow records.
// The same run then starts review-dependency for review-tier Dependabot PRs
// (dependency-dispatch.mjs), fix-ci for lanes App PRs and, with an
// `adoption` section, PRs of the base's trusted actors, whose ci-status or
// pr-test-platforms run failed past the lost-run reconciler's re-run
// (fix-ci-dispatch.mjs), and sync-shared-copies for lanes App PRs pr-merge
// refused as shared-copy-sources-changed at their head
// (dispatchSharedCopies), and their run ids join the same record. It starts
// no fix-docs: a PR's own event does (refine-event-dispatch.mjs).
// resolve-conflicts, review-dependency and fix-ci read the one
// open-PR listing (LIST_QUERY, each page read once a run), and
// resolve-conflicts and fix-ci the one pr-unblock.yml run listing. A read that
// fails, whatever GitHub answered, holds what it was read for: a failed
// listing defers its pass and a failed read for one PR skips that PR, each
// with a warning, and the next run reads it again. fix-ci-dispatch.mjs keeps
// the reads it dispatches past under its caps. The run fails only on a
// dispatch that failed or named no run id, on config it cannot read, or on a
// rate limit, which the rate guard's latch fails. A head whose check
// runs handle it for good is kept in DISPATCH_RECORD (dispatch-record.mjs), which the workflow
// carries to the next run through the Actions cache; the next run skips that
// head's check-run read, and its UNKNOWN re-queries. A head recorded at the
// per-head cap (resolve-conflicts or fix-ci) gets one `::warning::` as it is
// recorded.

import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { testedRun } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { LIMIT_DEFAULTS } from "../work-resolve-issue/limits.mjs";
import { DEPENDABOT_ID, POLICY_PATH } from "./dependency-classify.mjs";
import { dispatchDependencyReviews } from "./dependency-dispatch.mjs";
import { emptyRecord, isHandled, markHandled, pruneRecord, readRecord, RUN_ID, sendDispatch, writeRecord } from "./dispatch-record.mjs";
import { laneReader, withLaneBinding } from "./address-feedback.mjs";
import { prHold, reviewReader } from "./gate-source.mjs";
import { runTitle, shareWorkflowRuns } from "./feedback-dispatch.mjs";
import { adoptableOwnerIds, DEFAULTS as CI_FIX_DEFAULTS, dispatchCiFixes, humanGatedLabel } from "./fix-ci-dispatch.mjs";
import { TRACKER_BINDING_PATH, trackerBindingText } from "../pr-merge/merge-holds.mjs";
import { HISTORY_QUERY as DOCS_FIX_HISTORY_QUERY } from "./fix-docs-dispatch.mjs";
import { anyHandles, cappedAt, headLagStop, laneStop, limitStop, pendingStop, permanentlyHandles, releasedBy, stopRelease } from "./limit-stop.mjs";
import { budgetedFetch } from "./request-budget.mjs";
import { verifyCapReader } from "./verify-cap.mjs";
import { readConfig, readPolicy } from "./review-dependency.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  activity: "resolve-conflicts",
  checkName: "pr-unblock / resolve-conflicts",
  // The push job's check: its lane-stopped skip releases the head for a
  // same-head retry (limit-stop.mjs stopRelease).
  stopCheckName: "pr-unblock / apply-conflict-patch",
  // The GitHub Actions app: only a check run it created counts, so another
  // app cannot suppress a dispatch by posting a run under the same name.
  appId: 15368,
  // Judgment until the lane's measured per-run cost sets it.
  maxDispatch: 3,
  // GitHub gives no timing for computing mergeability; this bounds the wait
  // at about a minute (judgment).
  unknownRetries: 5,
  unknownDelayMs: 10_000,
  // resolve-conflicts's applies-when labels-absent and the human-gated label
  // (docs/conventions/pr-pipeline.yaml), checked before its check runs are read.
  holdLabels: Object.freeze(["do-not-merge", "needs-human"]),
});

const SHA = /^[0-9a-f]{40}$/;

// The check-run handling both dispatchers read a head's runs under.
const handleOptions = (limits) => ({ limits, failuresRetry: true, heldSkipsRelease: true, lagStopsRelease: true });

// prHold's reads of one listed PR.
function holdReads(api, node) {
  return {
    labels: (node.labels?.nodes ?? []).map((label) => label?.name),
    head: node.headRefOid,
    readTimeline: () => api.listTimeline(node.number),
    readReviews: reviewReader(api, node.number),
  };
}

// The in-flight run of `activity` for the PR, logged as a skip, or undefined.
function inFlightRun(log, active, { workflow, activity, node }) {
  const inFlight = active.find((run) => run.display_title === runTitle(activity, node.number));
  if (inFlight) {
    log(`skip #${node.number}: ${workflow} run ${inFlight.id} for ${activity} is not done yet`);
  }
  return inFlight;
}

// The log line that names a head-lag stop on the head as the cause of this
// dispatch (limit-stop.mjs lagStopsRelease).
function lagRefire(log, node, checkName, existing, handled) {
  if (!handled && existing.some(headLagStop)) {
    log(`refire: #${node.number}: head ${node.headRefOid}'s ${checkName} was stopped head-lag; sending it again`);
  }
}

export const TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json";

// A merge commit on a Dependabot head stops Dependabot's own rebases, which
// resolve its conflicts, and breaks the pr-merge Dependabot tier.
function isDependabotHead(node) {
  return String(node.headRefName ?? "").startsWith("dependabot/") && node.author?.databaseId === DEPENDABOT_ID;
}

function inState(node, base, mergeable) {
  return (
    node.isDraft === false &&
    node.isCrossRepository === false &&
    !isDependabotHead(node) &&
    node.baseRefName === base &&
    node.mergeable === mergeable
  );
}

const isCandidate = (node, base) => inState(node, base, "CONFLICTING");
const isPending = (node, base) => inState(node, base, "UNKNOWN");

export async function listAll(api, base) {
  const nodes = [];
  let after;
  for (;;) {
    const page = await api.listOpenPulls({ base, after });
    nodes.push(...page.nodes);
    if (!page.pageInfo.hasNextPage) {
      return nodes;
    }
    after = page.pageInfo.endCursor;
  }
}

export async function dispatchConflicting({
  api,
  runId,
  sleep,
  log,
  base = DEFAULTS.base,
  workflow = DEFAULTS.workflow,
  activity = DEFAULTS.activity,
  checkName = DEFAULTS.checkName,
  stopCheckName = DEFAULTS.stopCheckName,
  appId = DEFAULTS.appId,
  maxDispatch = DEFAULTS.maxDispatch,
  unknownRetries = DEFAULTS.unknownRetries,
  unknownDelayMs = DEFAULTS.unknownDelayMs,
  now = Date.now(),
  limits,
  listed,
  record = emptyRecord(),
  holdLabels = DEFAULTS.holdLabels,
  gateLabel = "needs-human",
  appSenderId,
}) {
  const nodes = listed ?? (await listAll(api, base));
  // The base tip, read once a run and only when a head needs it.
  let tipRead = null;
  const readTip = () => (tipRead ??= api.readBaseTip(base));
  // Heads recorded on a select job's stop under a base that is no longer the
  // tip: read again, after the heads never tried.
  const moved = new Set();
  if (nodes.some((node) => record.bases.has(node.headRefOid))) {
    try {
      const { oid } = await readTip();
      for (const node of nodes) {
        const judged = record.bases.get(node.headRefOid);
        if (judged !== undefined && judged !== oid) {
          moved.add(node.headRefOid);
        }
      }
    } catch (error) {
      log(`::warning::could not read the ${base} tip: ${error.message}; heads recorded on a select job's stop stay skipped, a later run retries`);
    }
  }
  // A recorded head is skipped whatever its mergeable state, so it is neither
  // read nor re-queried.
  const recorded = (node) => {
    if (!isHandled(record, checkName, node.headRefOid) || moved.has(node.headRefOid)) {
      return false;
    }
    log(`skip #${node.number}: head ${node.headRefOid} already has a ${checkName} check run (recorded)`);
    return true;
  };
  const candidates = nodes.filter((node) => isCandidate(node, base) && !recorded(node));
  let pending = nodes.filter((node) => isPending(node, base) && !recorded(node)).map((node) => node.number);

  for (let attempt = 1; pending.length > 0 && attempt <= unknownRetries; attempt += 1) {
    await sleep(unknownDelayMs);
    let reread;
    try {
      reread = await api.getPulls(pending);
    } catch (error) {
      log(`::warning::could not re-query the mergeable state of #${pending.join(", #")}: ${error.message}; skipped, a later run retries`);
      pending = [];
      break;
    }
    candidates.push(...reread.filter((node) => isCandidate(node, base) && !recorded(node)));
    pending = reread.filter((node) => isPending(node, base) && !recorded(node)).map((node) => node.number);
  }
  for (const number of pending) {
    log(
      `skip #${number}: mergeable still UNKNOWN after ${unknownRetries} re-queries; a later run retries`,
    );
  }

  candidates.sort((a, b) => moved.has(a.headRefOid) - moved.has(b.headRefOid) || a.number - b.number);
  const dispatched = [];
  let failed = 0;
  // A dispatched run posts its check run only when it ends, so two main
  // pushes seconds apart would each dispatch one. A run of this activity for
  // the PR that is not done yet holds the dispatch.
  let active = [];
  if (candidates.length > 0) {
    try {
      active = (await api.listWorkflowRuns(workflow)).filter((run) => run.status !== "completed");
    } catch (error) {
      log(`::warning::${workflow} run listing ${error.rateLimited ? "is rate limited" : "could not be read"} (${error.message}); no ${activity} dispatched, a later run retries`);
      return { dispatched, failed };
    }
  }
  // Every dispatch call counts against the cap: one that failed or returned no
  // usable id may still have started a run.
  let sent = 0;
  for (const node of candidates) {
    if (sent >= maxDispatch) {
      log(`defer #${node.number}: ${maxDispatch} dispatches this run; left for a later run`);
      continue;
    }
    if (inFlightRun(log, active, { workflow, activity, node })) {
      continue;
    }
    let handled;
    let waiting = null;
    try {
      const { held, why } = await prHold({ ...holdReads(api, node), holdLabels, gateLabel, activity, appId: appSenderId });
      // Not recorded: the hold can come off with the head unchanged.
      if (held) {
        log(`skip #${node.number}: ${why}`);
        continue;
      }
      let existing = await api.listCheckRuns({ sha: node.headRefOid, checkName, appId });
      const options = handleOptions(limits);
      // A push job that stopped on a reason routed to a failing status
      // releases the head's earlier checks: the next run retries the same
      // head, a fresh model session, until limit-stops-per-head such stops
      // stand on it.
      if (anyHandles(existing, { now, ...options })) {
        const cap = (limits ?? LIMIT_DEFAULTS)["limit-stops-per-head"];
        const { cut, stops } = stopRelease(await api.listCheckRuns({ sha: node.headRefOid, checkName: stopCheckName, appId }), cap);
        existing = releasedBy(existing, cut, limits);
        if (cut === null && stops >= cap) {
          log(`::warning::#${node.number}: head ${node.headRefOid}'s ${stopCheckName} stopped ${stops} time(s), the most one head gets; no ${activity} retry until a new push`);
        }
      }
      // A select job's own stop (escalation-routes.mjs stopSkip) judged the
      // base of its day: one that started before the tip was committed no
      // longer counts. A merge-queue tip committed before it landed can hold
      // such a stop one base longer.
      if (existing.some(laneStop)) {
        const { committedAt } = await readTip();
        existing = existing.filter((run) => !(laneStop(run) && Date.parse(run.started_at ?? "") < committedAt));
      }
      handled = anyHandles(existing, { now, ...options });
      lagRefire(log, node, checkName, existing, handled);
      // Handled only because a limit stop has not reset: the log names it.
      waiting = handled && !anyHandles(existing, { now: Infinity, ...options }) ? pendingStop(existing, { now, limits }) : null;
      if (permanentlyHandles(existing, options)) {
        // Recording it means this warning shows once per head.
        const capped = cappedAt(existing, options);
        if (capped > 0) {
          // The newest finished run's stop class, so a cap a credential outage
          // or a usage limit spent names that cause.
          const newest = existing.filter((run) => run.status === "completed").sort((a, b) => Date.parse(b.completed_at ?? "") - Date.parse(a.completed_at ?? ""))[0];
          const stop = newest ? limitStop(newest, limits) : null;
          log(
            `::warning::#${node.number}: head ${node.headRefOid}'s ${checkName} failed or was skipped while held ${capped} time(s), the most one head gets; no ${activity} until a new push${stop ? `; the last run stopped on class=${stop.failureClass}` : ""}`,
          );
        }
        markHandled(record, checkName, node.headRefOid);
        // Handled only by a select job's stop: kept with the tip it judged,
        // so the next base move reads the head again.
        if (permanentlyHandles(existing.filter((run) => !laneStop(run)), options)) {
          record.bases.delete(node.headRefOid);
        } else {
          record.bases.set(node.headRefOid, (await readTip()).oid);
        }
      }
    } catch (error) {
      log(`::warning::#${node.number}: could not read its holds or check runs for ${node.headRefOid}: ${error.message}; skipped, a later run retries`);
      continue;
    }
    if (waiting) {
      log(
        `::notice::#${node.number}: head ${node.headRefOid}'s ${checkName} stopped on class=${waiting.failureClass}; no ${activity} before ${new Date(waiting.resetsAt).toISOString()}`,
      );
      continue;
    }
    if (handled) {
      log(`skip #${node.number}: head ${node.headRefOid} already has a ${checkName} check run`);
      continue;
    }
    sent += 1;
    const id = await sendDispatch(api, log, { workflow, base, node, inputs: { "pr-number": String(node.number), "dispatcher-run-id": String(runId) } });
    if (id === null) {
      failed += 1;
    } else {
      dispatched.push({ number: node.number, workflowRunId: id });
    }
  }
  return { dispatched, failed };
}

// sync-shared-copies: a lanes App pull request into the base, not a draft,
// carrying the human-gated label that pr-merge's shared-copy-sources-changed
// refusal at its current head put on (gate-source.mjs sharedCopyGate, through
// prHold), gets one pr-unblock.yml dispatch per head. Its
// pr-unblock / sync-shared-copies check runs from the GitHub Actions app
// handle the head as resolve-conflicts's do (limit-stop.mjs, failuresRetry):
// a failed select job's failure retries until limit-stops-per-head failures
// stand on it; a head handled for good is recorded, so the next run reads
// nothing for it. A run of the activity for the PR not done yet holds it.
export const SHARED_COPY_DEFAULTS = Object.freeze({
  activity: "sync-shared-copies",
  checkName: "pr-unblock / sync-shared-copies",
  // Judgment: no model runs, so the cap only spreads the pushes out.
  maxDispatch: 3,
});

export async function dispatchSharedCopies({
  api,
  runId,
  log,
  listed,
  record = emptyRecord(),
  gateLabel,
  appSenderId,
  base = DEFAULTS.base,
  workflow = DEFAULTS.workflow,
  appId = DEFAULTS.appId,
  maxDispatch = SHARED_COPY_DEFAULTS.maxDispatch,
  limits,
  now = Date.now(),
}) {
  const { activity, checkName } = SHARED_COPY_DEFAULTS;
  const dispatched = [];
  let failed = 0;
  if (gateLabel === null || !Number.isSafeInteger(appSenderId)) {
    return { dispatched, failed };
  }
  const candidates = listed
    .filter(
      (node) =>
        node.isDraft === false &&
        node.isCrossRepository === false &&
        node.baseRefName === base &&
        node.author?.databaseId === appSenderId &&
        (node.labels?.nodes ?? []).some((label) => label?.name === gateLabel) &&
        !isHandled(record, checkName, node.headRefOid),
    )
    .sort((a, b) => a.number - b.number);
  let active = null;
  let sent = 0;
  for (const node of candidates) {
    if (sent >= maxDispatch) {
      log(`defer #${node.number}: ${maxDispatch} ${activity} dispatches this run; left for a later run`);
      continue;
    }
    try {
      const { laneEscalated, why } = await prHold({ ...holdReads(api, node), holdLabels: ["do-not-merge"], gateLabel, activity, appId: appSenderId });
      if (!laneEscalated) {
        log(`skip #${node.number}: no shared-copy refusal at head ${node.headRefOid} to answer${why ? ` (${why})` : ""}`);
        continue;
      }
      const existing = await api.listCheckRuns({ sha: node.headRefOid, checkName, appId });
      const options = handleOptions(limits);
      if (permanentlyHandles(existing, options)) {
        const capped = cappedAt(existing, options);
        if (capped > 0) {
          log(`::warning::#${node.number}: head ${node.headRefOid}'s ${checkName} failed or was skipped while held ${capped} time(s), the most one head gets; no ${activity} until a new push`);
        }
        markHandled(record, checkName, node.headRefOid);
      }
      if (anyHandles(existing, { now, ...options })) {
        log(`skip #${node.number}: head ${node.headRefOid} already has a ${checkName} check run`);
        continue;
      }
      active ??= (await api.listWorkflowRuns(workflow)).filter((run) => run.status !== "completed");
      if (inFlightRun(log, active, { workflow, activity, node })) {
        continue;
      }
      lagRefire(log, node, checkName, existing, false);
    } catch (error) {
      log(`::warning::#${node.number}: could not read its refusal, check runs or runs for ${node.headRefOid}: ${error.message}; skipped, a later run retries`);
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

// The Dependabot fields feed dependency-dispatch.mjs's classification.
const PULL_FIELDS =
  "number isDraft isCrossRepository mergeable baseRefName headRefOid headRefName state title body author { login ... on Bot { databaseId } } labels(first: 100) { nodes { name } } changedFiles commits { totalCount }";

const BASE_TIP_QUERY = `query($owner: String!, $name: String!, $base: String!) {
  repository(owner: $owner, name: $name) {
    ref(qualifiedName: $base) { target { oid ... on Commit { committedDate } } }
  }
}`;

// The one open-PR listing resolve-conflicts, review-dependency, fix-ci and
// sync-shared-copies all read: the Dependabot classifier's fields, fix-ci's
// body, update time and head rollup with the base tip's commit time, 50 a
// page, with its rateLimit.cost.
const LIST_NODE_FIELDS = `number isDraft isCrossRepository mergeable baseRefName baseRefOid headRefOid headRefName title body updatedAt changedFiles
        author { __typename ... on Bot { databaseId } ... on User { databaseId } }
        labels(first: 100) { nodes { name } }
        commits(last: 1) {
          totalCount
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
        }`;

export const LIST_QUERY = `query($owner: String!, $name: String!, $base: String!, $after: String) {
  rateLimit { cost remaining }
  repository(owner: $owner, name: $name) {
    ref(qualifiedName: $base) { target { ... on Commit { committedDate } } }
    pullRequests(states: OPEN, baseRefName: $base, first: 50, after: $after) {
      nodes {
        ${LIST_NODE_FIELDS}
      }
      pageInfo { hasNextPage endCursor }
    }
  }
}`;

// One pull request for fix-docs (refine-event-dispatch.mjs): the listing's
// fields plus its open state, files, line counts and head commit's signer,
// which GraphQL merges into the listing's author and commits(last: 1).
export const PULL_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  rateLimit { cost remaining }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      ${LIST_NODE_FIELDS}
      state additions deletions
      author { login }
      files(first: 100) { nodes { path } pageInfo { hasNextPage } }
      commits(last: 1) { nodes { commit { signature { isValid } author { user { login } } committer { email } } } }
    }
  }
}`;

export function createGitHubApi({
  token,
  repository,
  apiUrl,
  graphqlUrl,
  fetch: rawFetch = globalThis.fetch,
}) {
  // Each request's rate-limit reading goes to the job-end api-calls notice.
  const fetch = countRequests(rawFetch);
  const [owner, name] = repository.split("/");
  // Connection: close ends each socket after its answer, so no request goes
  // out on a pooled one that sat idle through dispatchConflicting's waits and
  // that GitHub has since dropped. A read that still fails on the network is
  // sent again (budgetedFetch); a dispatch is not, since it may have started a
  // run. A request's own Connection: close does not keep it off a pooled
  // socket, so every request sends it, as enable-auto-merge.mjs does.
  const headers = {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
    Connection: "close",
  };

  const repoUrl = `${apiUrl}/repos/${owner}/${name}`;

  const httpError = (method, url, response) =>
    Object.assign(new Error(`${method} ${url} returned ${response.status}`), { status: response.status, rateLimited: response.rateLimited === true });

  async function request(url, method = "GET", body) {
    const response = await fetch(url, {
      method,
      headers: body === undefined ? headers : { ...headers, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw httpError(method, url, response);
    }
    return response.status === 204 ? {} : response.json();
  }

  async function paginate(path) {
    const rows = [];
    let url = `${repoUrl}/${path}${path.includes("?") ? "&" : "?"}per_page=100`;
    while (url) {
      const response = await fetch(url, { headers });
      if (!response.ok) {
        throw httpError("GET", url, response);
      }
      rows.push(...(await response.json()));
      url = /<([^>]+)>;\s*rel="next"/.exec(response.headers.get("link") ?? "")?.[1] ?? "";
    }
    return rows;
  }

  async function graphql(query, variables) {
    const result = await request(graphqlUrl, "POST", { query, variables });
    if (result.errors?.length) {
      throw new Error(`GraphQL: ${result.errors.map((error) => error.message).join("; ")}`);
    }
    return result.data;
  }

  // Each LIST_QUERY page is sent once per adapter, however many dispatchers
  // page through it; a failed read is forgotten, so a later one sends it again.
  const pages = new Map();
  function listPage(base, after) {
    const key = JSON.stringify([base, after ?? null]);
    if (!pages.has(key)) {
      pages.set(
        key,
        graphql(LIST_QUERY, { owner, name, base, after: after ?? null }).catch((error) => {
          pages.delete(key);
          throw error;
        }),
      );
    }
    return pages.get(key);
  }

  // A run's latest jobs, which must fit one page.
  async function latestJobs(runId) {
    const jobs = await request(`${repoUrl}/actions/runs/${runId}/jobs?filter=latest&per_page=100`);
    if (!Array.isArray(jobs.jobs) || jobs.total_count > jobs.jobs.length) {
      throw new Error(`run ${runId}'s job listing is not one complete page`);
    }
    return jobs.jobs;
  }

  return {
    async listOpenPulls({ base, after }) {
      return (await listPage(base, after)).repository.pullRequests;
    },
    // The base branch tip and when it was committed.
    async readBaseTip(base) {
      const target = (await graphql(BASE_TIP_QUERY, { owner, name, base })).repository.ref?.target;
      const committedAt = Date.parse(target?.committedDate ?? "");
      if (!SHA.test(target?.oid ?? "") || !Number.isFinite(committedAt)) {
        throw new Error(`the ${base} tip is not a commit`);
      }
      return { oid: target.oid, committedAt };
    },
    // fix-ci-dispatch.mjs's view of the listing, with the page's cost.
    async listCiFixCandidates({ base, after }) {
      const data = await listPage(base, after);
      return { rateLimit: data.rateLimit, pullRequests: data.repository.pullRequests, baseCommittedAt: data.repository.ref?.target?.committedDate };
    },
    // fix-docs-dispatch.mjs's view of one pull request, as a one-page listing
    // (empty unless it is open), and its per-PR check-run history.
    async readDocsFixCandidate(number) {
      if (!Number.isSafeInteger(number) || number < 1) {
        throw new Error(`not a PR number: ${number}`);
      }
      const data = await graphql(PULL_QUERY, { owner, name, number });
      const node = data.repository.pullRequest;
      return { rateLimit: data.rateLimit, pullRequests: { nodes: node?.state === "OPEN" ? [node] : [], pageInfo: { hasNextPage: false } } };
    },
    async readDocsFixHistory({ number, appId, checkName, earlierCheckName }) {
      const data = await graphql(DOCS_FIX_HISTORY_QUERY, { owner, name, number, appId, checkName, earlierCheckName });
      return { rateLimit: data.rateLimit, pullRequest: data.repository.pullRequest };
    },
    async getPulls(numbers) {
      const fields = numbers
        .map((number) => {
          if (!Number.isSafeInteger(number) || number < 1) {
            throw new Error(`not a PR number: ${number}`);
          }
          return `pr${number}: pullRequest(number: ${number}) { ${PULL_FIELDS} }`;
        })
        .join("\n");
      const data = await graphql(
        `query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { ${fields} } }`,
        { owner, name },
      );
      return Object.values(data.repository).filter((node) => node?.state === "OPEN");
    },
    // The REST reads the Dependabot classifier takes: the files listing with
    // patches, the commits, and one commit's files.
    listPullFiles: (number) => paginate(`pulls/${Number(number)}/files`),
    listPullCommits: (number) => paginate(`pulls/${Number(number)}/commits`),
    async getCommit(sha) {
      return request(`${repoUrl}/commits/${encodeURIComponent(sha)}`);
    },
    // A held PR's issue timeline, review comments and reviews (gate-source.mjs
    // reads their REST shape).
    listTimeline: (number) => paginate(`issues/${Number(number)}/timeline`),
    // Written or edited since `since` (GitHub's since query value) when given.
    listReviewComments: (number, since) => paginate(`pulls/${Number(number)}/comments${since === undefined ? "" : `?since=${encodeURIComponent(since)}`}`),
    listReviews: (number) => paginate(`pulls/${Number(number)}/reviews`),
    // Every check run on a commit, skips included, up to 300, as fix-ci-context reads them
    // (address-feedback.mjs listCommitCheckRuns).
    async listCommitCheckRuns(sha) {
      const runs = [];
      for (let page = 1; page <= 3; page += 1) {
        const data = await request(`${repoUrl}/commits/${sha}/check-runs?filter=all&per_page=100&page=${page}`);
        runs.push(...(data.check_runs ?? []));
        if ((data.check_runs ?? []).length < 100) {
          break;
        }
      }
      return runs;
    },
    async listCheckRuns({ sha, checkName, appId }) {
      const query = new URLSearchParams({
        check_name: checkName,
        app_id: String(appId),
        filter: "all",
        per_page: "100",
      });
      return (await request(`${repoUrl}/commits/${sha}/check-runs?${query}`)).check_runs;
    },
    // One check run's annotations: whether a cancelled job passed its time
    // limit (infra-failure.mjs timeLimitNoted).
    async listAnnotations(checkRunId) {
      if (!Number.isSafeInteger(checkRunId) || checkRunId < 1) {
        throw new Error("not a check run id");
      }
      return request(`${repoUrl}/check-runs/${checkRunId}/annotations?per_page=100`);
    },
    // fix-ci-dispatch.mjs's re-run check: the newest pull_request run of the
    // workflow at path (pr-require-checks unless named) on the head that
    // tested it and its latest jobs (infra-failure.mjs testedRun); a null run
    // and no jobs when there is none.
    async readRequiredRun(sha, path = ".github/workflows/pr-require-checks.yml") {
      if (!SHA.test(sha)) {
        throw new Error("not a commit SHA");
      }
      const listing = await request(`${repoUrl}/actions/runs?head_sha=${sha}&event=pull_request&per_page=100`);
      // A fork PR at the same head SHA lists its runs here too; a newer one
      // must not become the tested run or suppress a fix-ci dispatch.
      const runs = (listing.workflow_runs ?? [])
        .filter((run) => run.path === path && run.head_repository?.full_name === repository)
        .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || b.id - a.id);
      const tested = await testedRun(runs, (run) => latestJobs(run.id));
      return { run: tested?.run ?? null, jobs: tested?.jobs ?? [] };
    },
    // One run's status and latest jobs, as fix-docs-dispatch.mjs counts a
    // head's runs; null when the run is gone.
    async readRunJobs(runId) {
      if (!RUN_ID.test(String(runId))) {
        throw new Error("not a run id");
      }
      let run;
      try {
        run = await request(`${repoUrl}/actions/runs/${runId}`);
      } catch (error) {
        if (error.status === 404) {
          return null;
        }
        throw error;
      }
      return { status: run.status, jobs: await latestJobs(runId) };
    },
    // The newest workflow_dispatch runs: a run still queued or going is
    // among them, since a dispatcher waits at most minutes behind it.
    async listWorkflowRuns(workflow) {
      const result = await request(`${repoUrl}/actions/workflows/${workflow}/runs?event=workflow_dispatch&per_page=100`);
      return result.workflow_runs ?? [];
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      const result = await request(`${repoUrl}/actions/workflows/${workflow}/dispatches`, "POST", { ref, inputs, return_run_details: true });
      return { workflowRunId: result.workflow_run_id };
    },
  };
}

// The base checkout's path.
const basePath = (env) => env.BASE_PATH || ".base";

// One reader of the base checkout's resolve-config, called on the base path;
// the workflow installs its dependencies before this runs.
async function fromBase(env, reader) {
  const resolver = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
  return resolver[reader]({ BASE_PATH: basePath(env) });
}

// The base config's resolved limits. A config the resolver refuses throws, so
// nothing is dispatched.
export async function loadBaseLimits(env) {
  return fromBase(env, "limitsFromBase");
}

// The base tracker config's human-gated label, as pr-merge.yml reads it.
export function baseHumanGatedLabel(env) {
  let text = null;
  try {
    text = trackerBindingText(`${basePath(env)}/${TRACKER_BINDING_PATH}`);
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
  return humanGatedLabel(text);
}

// The base config's `adoption` section as set, the same way.
export async function loadBaseAdoption(env) {
  return fromBase(env, "adoptionFromBase");
}

// The base config's merge.refire-skip-branches, the same way: head branches a
// workflow owns and rebuilds, which never get fix-ci.
export async function loadBaseOwnedBranches(env) {
  return fromBase(env, "ownedBranchesFromBase");
}

// The base config's resolve-issue tidy cutoffs, the same way, or null: the
// fix-docs dispatcher skips a lane PR within them, which tidied in its run.
export async function loadBaseTidyCutoffs(env) {
  return fromBase(env, "tidyCutoffsFromBase");
}

// Each run id is also appended to RUN_IDS_FILE as soon as its dispatch
// returns, so a run cancelled mid-step still records what it sent.
export function wrapRunIds(base, env) {
  return {
    ...base,
    async dispatchWorkflow(request) {
      const result = await base.dispatchWorkflow(request);
      if (env.RUN_IDS_FILE && RUN_ID.test(String(result.workflowRunId))) {
        appendFileSync(env.RUN_IDS_FILE, `${result.workflowRunId}\n`);
      }
      return result;
    },
  };
}

// A held PR's timeline, review comments (by their since time) and reviews are
// each read at most once a run, however many dispatchers ask.
export function shareTimeline(base) {
  const shared = (method) => {
    const seen = new Map();
    return (...args) => {
      const key = args.join(" ");
      if (!seen.has(key)) {
        seen.set(key, base[method](...args));
      }
      return seen.get(key);
    };
  };
  return { ...base, listTimeline: shared("listTimeline"), listReviewComments: shared("listReviewComments"), listReviews: shared("listReviews") };
}

// Writes the dispatched run ids, lowest PR first, as the step output run-ids,
// which the workflow records as an artifact on this run.
export async function main(
  env,
  {
    api,
    // The review lanes' run records (address-feedback.mjs laneReader).
    actions,
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    log = (line) => console.log(line),
    loadLimits = loadBaseLimits,
    loadAdoption = loadBaseAdoption,
    loadOwnedBranches = loadBaseOwnedBranches,
    // The gate's reader for fix-ci's FAIL-cap skip (verify-cap.mjs), when the
    // workflow names it in VERIFY_EVIDENCE_SCRIPT.
    verifyCapped = env.VERIFY_EVIDENCE_SCRIPT ? verifyCapReader(env, { log }) : undefined,
    now,
  } = {},
) {
  for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_RUN_ID", "GITHUB_OUTPUT"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const budget = api ? null : budgetedFetch({ log });
  // Every held PR's timeline binds the review lanes' hold comments to their
  // runs (address-feedback.mjs withLaneBinding), read with ARTIFACT_READ_TOKEN.
  const base = withLaneBinding(
    api ??
      createGitHubApi({
        token: env.GITHUB_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
        fetch: budget.fetch,
      }),
    actions ?? laneReader(env, { fetch: budget?.fetch }),
  );
  try {
    return await dispatchAll(env, { client: shareWorkflowRuns(shareTimeline(wrapRunIds(base, env))), sleep, log, loadLimits, loadAdoption, loadOwnedBranches, verifyCapped, now });
  } finally {
    if (budget) {
      log(budget.summary());
    }
  }
}

async function dispatchAll(env, { client, sleep, log, loadLimits, loadAdoption, loadOwnedBranches, verifyCapped, now }) {
  const limits = await loadLimits(env);
  const adoption = await loadAdoption(env);
  const ownedBranches = await loadOwnedBranches(env);
  // Every dispatcher reads this listing's pages, so one that cannot be read
  // holds the whole run: nothing dispatched, nothing recorded.
  let listed;
  try {
    listed = await listAll(client, DEFAULTS.base);
  } catch (error) {
    log(`::warning::the open pull request listing could not be read (${error.message}); nothing dispatched, a later run retries`);
    return 0;
  }
  // The burn-rate pacer paces the next scheduled tick only after a run that
  // listed (pr-unblock-dispatch.yml `Mark this tick's work done`).
  appendFileSync(env.GITHUB_OUTPUT, "listed=true\n");
  const { record, text } = readRecord(env.DISPATCH_RECORD);
  pruneRecord(record, new Set(listed.map((node) => node.headRefOid)));
  // The human-gated label another lane's escalation may leave on for
  // resolve-conflicts, fix-ci and sync-shared-copies; null when unreadable, so it holds.
  const appSenderId = /^[1-9][0-9]*$/.test(env.APP_SENDER_ID ?? "") ? Number(env.APP_SENDER_ID) : undefined;
  let gateLabel = null;
  try {
    gateLabel = baseHumanGatedLabel(env);
  } catch (error) {
    log(`::warning::cannot read the human-gated label from the base tracker binding (${error.message}); it holds every PR it is on`);
  }
  const gate = { gateLabel, appSenderId };
  const conflicts = await dispatchConflicting({ api: client, runId: env.GITHUB_RUN_ID, sleep, log, limits, now, listed, record, ...gate });
  const reviews = await dispatchDependencyReviews({
    api: client,
    runId: env.GITHUB_RUN_ID,
    log,
    limits,
    now,
    listed,
    record,
    config: readConfig(env.DEPENDABOT_CONFIG ?? ".base/.github/dependabot.yml", log),
    policy: readPolicy(env.DEPENDABOT_POLICY ?? `.base/${POLICY_PATH}`, log),
    repository: env.GITHUB_REPOSITORY,
  });
  // A missing lanes App id stops fix-ci alone, as a failure. The tracker's
  // human-gated label is read only when owners are adopted; an unreadable
  // tracker config holds the adopted owner PRs alone, as a failure.
  // With `adoption.idle-hours` set (as pr-merge requires), every account on
  // the base's trusted-actors list is adoptable, by id, but the bot authors
  // fix-ci-dispatch.mjs adoptableOwnerIds leaves out.
  let fixes = { dispatched: [], failed: 1 };
  let ownerIds = [];
  let holdLabels = CI_FIX_DEFAULTS.holdLabels;
  let ownersHeld = "";
  if (adoption["idle-hours"] !== undefined) {
    try {
      ownerIds = adoptableOwnerIds(loadTrustedList(`${basePath(env)}/${TRUSTED_ACTORS_PATH}`).ids);
      holdLabels = [...new Set([...holdLabels, baseHumanGatedLabel(env)])];
    } catch (error) {
      log(`::error::cannot read the base trusted-actors list or the human-gated label from the base tracker binding (${error.message}); no adopted PR gets fix-ci`);
      ownersHeld = "base trusted-actors list or tracker config unreadable";
    }
  }
  if (appSenderId !== undefined) {
    fixes = await dispatchCiFixes({
      api: client,
      record,
      runId: env.GITHUB_RUN_ID,
      log,
      appSenderId,
      maxDispatch: limits["fix-ci-per-run"] ?? 2,
      restarts: limits["fix-ci-restarts"] ?? 1,
      maxRunsPerHead: limits["limit-stops-per-head"] ?? CI_FIX_DEFAULTS.maxRunsPerHead,
      adoption: { ownerIds, idleHours: adoption["idle-hours"], held: ownersHeld },
      ownedBranches,
      holdLabels,
      gateLabel,
      verifyCapped,
      now,
    });
    fixes.failed += ownersHeld === "" ? 0 : 1;
  } else {
    log("::error::APP_SENDER_ID is not the lanes App's user id; no fix-ci dispatched");
  }
  const copies = await dispatchSharedCopies({ api: client, runId: env.GITHUB_RUN_ID, log, listed, record, limits, now, ...gate });
  const dispatched = [...conflicts.dispatched, ...reviews.dispatched, ...fixes.dispatched, ...copies.dispatched];
  const failed = conflicts.failed + reviews.failed + fixes.failed + copies.failed;
  if (dispatched.length > 0) {
    const ids = dispatched.map((run) => run.workflowRunId).join(" ");
    appendFileSync(env.GITHUB_OUTPUT, `run-ids=${ids}\n`);
  }
  if (writeRecord(env.DISPATCH_RECORD, record, text)) {
    appendFileSync(env.GITHUB_OUTPUT, "record-changed=true\n");
  }
  log(`dispatched ${dispatched.length} run(s), ${failed} failure(s)`);
  return failed === 0 ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::pr-unblock dispatch failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
