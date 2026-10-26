// Trigger gate for CI lanes: proceed only for a same-repository PR whose event
// actor, PR author and re-runner are all on the trusted-actor list, matched by
// numeric id. A denied id stops the lane even when it is listed. A
// workflow_dispatch sent by github-actions[bot] stands in for its sender
// through a checked dispatcher run, and require-pr false checks the actors
// without a PR. Every failure ends in proceed=false with a
// reason; main never throws.
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { rateLimitLatch } from "../log-api-budget/rate-guard.mjs";

const ACTOR_KEYS = ["id", "kind", "login"];
const KINDS = new Set(["human", "bot"]);
const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
// Branch names reach later steps; anything beyond these characters stops the
// lane rather than travel on.
const HEAD_REF = /^[A-Za-z0-9._/-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const RUN_ATTEMPT = /^[1-9][0-9]{0,4}$/;
// github-actions[bot], the sender of every GITHUB_TOKEN workflow dispatch.
const ACTIONS_BOT_ID = 41898282;
// A workflow_dispatch dispatcher must come from a listed human; push and
// schedule name none.
const DISPATCHER_EVENTS = new Set(["push", "schedule", "workflow_dispatch"]);
// The dispatcher dispatches within seconds of starting; a longer run must not
// keep its window open.
const WINDOW_MS = 10 * 60 * 1000;
// The artifact the dispatcher run uploads after its dispatch loop, named with
// every run id it dispatched.
const RECORD_NAME = /^pr-unblock-dispatched(-[1-9][0-9]{0,14})+$/;
const RECORD_PREFIX = "pr-unblock-dispatched-";
// A workflow_run dispatcher sends one dispatch per run and names its record
// with the upstream run that started it, then the run it dispatched.
const RUN_RECORD_NAME = /^pr-feedback-dispatched-([1-9][0-9]{0,14})-([1-9][0-9]{0,14})$/;
// The record can land after this run's gate starts: re-read every 5 s while
// the dispatcher run is still going, for at most 2 min (judgment).
const RECORD_WAIT_MS = 5000;
// Pages of same-name artifacts read for a reconciler record (judgment).
const RECORD_MAX_PAGES = 10;
// Candidate runs read per check: anyone's run can upload a record of the
// predictable name, so each forged one costs a run read (judgment).
const RECORD_MAX_CANDIDATES = 20;
const RECORD_MAX_SLEEPS = 24;
// The lost-run reconciler re-runs a lane run once, on its first attempt, so
// the attempt it starts is always the second.
const RERUN_ATTEMPT = 2;
const RECONCILER_EVENTS = new Set(["schedule", "workflow_dispatch"]);

// The artifact the reconciler run uploads before it re-runs a lane run: the
// run, the attempt the re-run starts, and the run's head SHA.
export const rerunRecordName = (runId, headSha) => `reconcile-rerun-${runId}-${RERUN_ATTEMPT}-${headSha}`;

// The artifact pr-feedback-dispatch.yml's rerun-ci-status job uploads just
// before it re-runs a ci-status job: the run, the attempt the re-run starts,
// and the run's head SHA.
export const ciStatusRerunRecordName = (runId, attempt, headSha) => `rerun-ci-status-${runId}-${attempt}-${headSha}`;

// Who may record a github-actions[bot] re-run: the run's path, the attempts it
// starts, its record's name, how its run must have started, and what bounds the
// window. The reconciler's window runs from its run's start; rerun-ci-status
// may poll for minutes first, so its window runs from the record's upload.
const reconcilerRecorder = (workflow) => ({
  workflow,
  attempts: (attempt) => attempt === RERUN_ATTEMPT,
  name: (runId, _attempt, headSha) => rerunRecordName(runId, headSha),
  started: (run, isListedHuman) => RECONCILER_EVENTS.has(run.event) && (run.event === "schedule" || isListedHuman(run.actor)),
  fromRecord: false,
});
// A workflow_run run runs the default branch's file, whoever's run started it.
const ciStatusRerunRecorder = (workflow) => ({
  workflow,
  attempts: (attempt) => attempt >= RERUN_ATTEMPT,
  name: ciStatusRerunRecordName,
  started: (run) => run.event === "workflow_run",
  fromRecord: true,
});

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export class GitHubError extends Error {
  constructor(status, what) {
    super(`${what} failed with status ${status}`);
    this.name = "GitHubError";
    this.status = status;
  }
}

// Wraps a fetch so an idempotent request (a GET, or a GraphQL query) has each
// attempt aborted after attemptTimeoutMs, and is sent again after 2 s, 4 s and
// 8 s, each with equal jitter (half fixed, half random), when GitHub answers it
// 5xx, answers a GET 200 with an empty body or with JSON that does not parse,
// or it fails on the network (a timeout, "fetch failed", an error with a cause
// code). The time failed attempts took plus the waits, summed over every call
// through one wrapper, is capped at 60 s: a wait past the cap is not taken,
// though a call's first attempt always goes out. With 20 s attempts, retrying adds at most
// about 80 s to one call, inside the shortest step that runs one (3 minutes,
// pr-merge.yml's gate-check and clear-escalations). The last answer is
// returned, or the last error thrown. Any other request, a mutation among
// them, is sent once and never timed out; a 4xx is the caller's to handle, a
// rate limit is the rate guard's (rate-guard.mjs), whose latch refuses any
// attempt while its pool is stopped, and any other thrown error is raised at
// once. A retry line names an error's name and cause code only: undici puts a
// whole header value, the token included, in some messages. createGitHub and
// budgetedFetch both use it.
const SERVER_RETRY_DELAYS_MS = [2000, 4000, 8000];
const SERVER_RETRY_BUDGET_MS = 60_000;
const ATTEMPT_TIMEOUT_MS = 20_000;
// A GraphQL query: a POST to /graphql whose document starts with `query` or
// `{`, holds no `mutation` or `subscription` word anywhere, and whose request
// names no operationName. A document can hold several operations and the
// request pick one by name, so anything less than all three may run a mutation.
const graphqlQuery = (url, init) => {
  if (!String(url).endsWith("/graphql") || typeof init.body !== "string") {
    return false;
  }
  try {
    const request = JSON.parse(init.body);
    const query = request?.query;
    return (
      typeof query === "string" &&
      request.operationName === undefined &&
      /^\s*(query\b|\{)/.test(query) &&
      !/\b(mutation|subscription)\b/.test(query)
    );
  } catch {
    return false;
  }
};
const networkFailure = (error) =>
  error?.name === "TimeoutError" ||
  error?.name === "AbortError" ||
  (error?.name === "TypeError" && error.message === "fetch failed") ||
  typeof error?.cause?.code === "string";
// An error's name and cause code, never its message.
export const errorLabel = (error) =>
  [error?.name ?? "Error", typeof error?.cause?.code === "string" ? error.cause.code : null].filter(Boolean).join(" ");
// A 200 whose body is empty, or is labeled JSON and does not parse: no REST
// read answers 200 with nothing.
async function brokenBody(response) {
  if (response.status !== 200) {
    return false;
  }
  const text = await response.clone().text();
  if (text === "") {
    return true;
  }
  if (!/json/i.test(response.headers.get("content-type") ?? "")) {
    return false;
  }
  try {
    JSON.parse(text);
    return false;
  } catch {
    return true;
  }
}
export function retryServerErrors(
  fetchImpl,
  {
    sleep = defaultSleep,
    random = Math.random,
    log = (line) => console.log(line),
    now = () => Date.now(),
    attemptTimeoutMs = ATTEMPT_TIMEOUT_MS,
    latch = rateLimitLatch,
  } = {},
) {
  // Every attempt, a retry included, goes through the rate guard's latch.
  fetchImpl = latch.guard(fetchImpl);
  let spent = 0;
  return async function send(url, init = {}) {
    const method = init.method ?? "GET";
    const idempotent = method === "GET" || (method === "POST" && graphqlQuery(url, init));
    for (let attempt = 0; ; attempt += 1) {
      // Only an idempotent request is timed out: a write GitHub accepted slowly
      // must not look failed, so writes keep only the caller's signal.
      const timeout = idempotent ? AbortSignal.timeout(attemptTimeoutMs) : undefined;
      const signal = timeout && init.signal ? AbortSignal.any([init.signal, timeout]) : (timeout ?? init.signal);
      const started = now();
      let response;
      let error;
      let broken = false;
      try {
        response = await fetchImpl(url, { ...init, signal });
        broken = method === "GET" && (await brokenBody(response));
      } catch (thrown) {
        error = thrown;
      }
      const failed = error !== undefined ? networkFailure(error) && !init.signal?.aborted : response.status >= 500 || broken;
      spent += failed ? now() - started : 0;
      const delay = SERVER_RETRY_DELAYS_MS[attempt];
      const wait = delay === undefined ? 0 : Math.round(delay / 2 + (random() * delay) / 2);
      if (!failed || !idempotent || delay === undefined || spent + wait > SERVER_RETRY_BUDGET_MS) {
        if (error !== undefined) {
          throw error;
        }
        return response;
      }
      await response?.body?.cancel().catch(() => {});
      const what =
        error !== undefined
          ? `failed (${errorLabel(error)})`
          : broken
            ? `answered ${response.status} with an empty or unparsable body`
            : `answered ${response.status}`;
      log(`::warning::${method} ${url} ${what}; sending it again in ${wait} ms (retry ${attempt + 1} of ${SERVER_RETRY_DELAYS_MS.length})`);
      spent += wait;
      await sleep(wait);
    }
  };
}

// One function every API read and write goes through; tests replace it.
// keepGraphQLErrors returns a GraphQL answer with its errors for the caller to
// judge, instead of raising on any. A read answered 5xx is sent again
// (retryServerErrors). A call while the rate guard's latch holds its pool
// throws RateLimitStop without a request.
export function createGitHub({
  token,
  apiUrl = "https://api.github.com",
  fetchImpl = fetch,
  onResponse,
  keepGraphQLErrors = false,
  sleep,
  random,
  log,
  now,
  attemptTimeoutMs,
  latch,
}) {
  const send = retryServerErrors(fetchImpl, { sleep, random, log, now, attemptTimeoutMs, latch });
  return async function github(method, apiPath, body, headers = {}, { signal } = {}) {
    const response = await send(`${apiUrl}${apiPath}`, {
      method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        ...headers,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
    onResponse?.(response);
    if (!response.ok) {
      throw new GitHubError(response.status, `${method} ${apiPath}`);
    }
    // A success can carry no body: 204, or the 201 a workflow re-run answers.
    const text = await response.text();
    if (text === "") {
      return null;
    }
    const json = JSON.parse(text);
    if (!keepGraphQLErrors && Array.isArray(json?.errors) && json.errors.length > 0) {
      throw new GitHubError(response.status, `${method} ${apiPath} (GraphQL errors)`);
    }
    return json;
  };
}

// A commit's pull requests through GraphQL, for when GET
// /commits/{sha}/pulls still fails after retryServerErrors (it answered 200
// with an empty body while this query read the PR, 2026-10-22). Both list the
// same set: the PR that merged the commit, plus open ones while it is off the
// default branch. commitPullsFromGraphQL maps the answer to the REST fields
// the lane scripts read; more than 100 PRs or labels is a failed read.
export const COMMIT_PULLS_QUERY = `query($owner: String!, $name: String!, $oid: GitObjectID!) {
  repository(owner: $owner, name: $name) {
    object(oid: $oid) {
      ... on Commit {
        associatedPullRequests(first: 100) {
          pageInfo { hasNextPage }
          nodes {
            number state isDraft headRefName headRefOid baseRefName baseRefOid
            headRepository { nameWithOwner }
            author { __typename login ... on User { databaseId } ... on Bot { databaseId } }
            labels(first: 100) { nodes { name } pageInfo { hasNextPage } }
          }
        }
      }
    }
  }
}`;

export function commitPullsFromGraphQL(data) {
  const list = data?.repository?.object?.associatedPullRequests;
  if (
    !Array.isArray(list?.nodes) ||
    list.pageInfo?.hasNextPage !== false ||
    list.nodes.some((node) => !Array.isArray(node?.labels?.nodes) || node.labels.pageInfo?.hasNextPage !== false)
  ) {
    throw new Error("the commit's pull requests could not be read through GraphQL");
  }
  return list.nodes.map((node) => ({
    number: node.number,
    state: node.state === "OPEN" ? "open" : "closed",
    draft: node.isDraft,
    // REST spells an App's login `app[bot]`; GraphQL spells it `app`.
    user: node.author
      ? {
          id: node.author.databaseId ?? null,
          login: node.author.__typename === "Bot" ? `${node.author.login}[bot]` : node.author.login,
          type: node.author.__typename,
        }
      : null,
    labels: node.labels.nodes.map((label) => ({ name: label.name })),
    head: { sha: node.headRefOid, ref: node.headRefName, repo: node.headRepository ? { full_name: node.headRepository.nameWithOwner } : null },
    base: { ref: node.baseRefName, sha: node.baseRefOid },
  }));
}

// The commit's pull requests: readRest's list, else COMMIT_PULLS_QUERY sent
// through readGraphQL(query, variables), which returns the answer's data.
// Throws when both fail, or at once on an error readRest marks
// `fallback: false` (a list too long to read, which GraphQL cannot read
// either). The query is a read sent as a POST, so readGraphQL gets a signal
// that aborts it after timeoutMs, as a GET attempt is.
export async function commitPulls({
  repository,
  sha,
  readRest,
  readGraphQL,
  log = (line) => console.log(line),
  timeoutMs = ATTEMPT_TIMEOUT_MS,
}) {
  try {
    const pulls = await readRest();
    if (Array.isArray(pulls)) {
      return pulls;
    }
    throw new Error("the answer is not a list");
  } catch (error) {
    if (error?.fallback === false) {
      throw error;
    }
    log(`::warning::the REST read of ${sha}'s pull requests failed (${errorLabel(error)}${Number.isInteger(error?.status) ? ` ${error.status}` : ""}); reading them through GraphQL`);
    const [owner, name] = repository.split("/");
    return commitPullsFromGraphQL(await readGraphQL(COMMIT_PULLS_QUERY, { owner, name, oid: sha }, AbortSignal.timeout(timeoutMs)));
  }
}

// readGraphQL for a createGitHub client.
export const graphQLReader = (github) => async (query, variables, signal) =>
  (await github("POST", "/graphql", { query, variables }, {}, { signal }))?.data;

// Whether a close counts: (a) a listed human made it, matched by id; or (b) a
// merge in this repository closed it: the `closer` GraphQL gives the issue's
// last ClosedEvent is a merged pull request or a commit here, whoever merged
// it. The REST close event carries no link to the pull request, so GraphQL
// is the read. Any
// other close, such as a workflow's GITHUB_TOKEN or an outside author closing
// their own issue, counts for nothing.
const CLOSER_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      timelineItems(itemTypes: CLOSED_EVENT, last: 1) {
        nodes { ... on ClosedEvent { closer {
          __typename
          ... on PullRequest { merged repository { nameWithOwner } }
          ... on Commit { repository { nameWithOwner } }
        } } }
      }
    }
  }
}`;
export async function isTrustedClose(github, repo, closedIssue, humans) {
  const closer = closedIssue?.closed_by;
  if (humans.has(closer?.id)) {
    return true;
  }
  if (closedIssue?.state !== "closed" || !/^[1-9][0-9]{0,9}$/.test(String(closedIssue.number))) {
    return false;
  }
  const [owner, name] = repo.split("/");
  const answer = await github("POST", "/graphql", {
    query: CLOSER_QUERY,
    variables: { owner, name, number: Number(closedIssue.number) },
  });
  const by = answer?.data?.repository?.issue?.timelineItems?.nodes?.at(-1)?.closer;
  const here = String(by?.repository?.nameWithOwner ?? "").toLowerCase() === repo.toLowerCase();
  return here && (by.__typename === "Commit" || (by.__typename === "PullRequest" && by.merged === true));
}

// Reads every page of a list endpoint (100 per page).
export async function paginate(github, apiPath, maxPages = 50) {
  const items = [];
  const separator = apiPath.includes("?") ? "&" : "?";
  for (let page = 1; page <= maxPages; page += 1) {
    const batch = await github("GET", `${apiPath}${separator}per_page=100&page=${page}`);
    items.push(...batch);
    if (batch.length < 100) {
      return items;
    }
  }
  throw new Error(`${apiPath} has more than ${maxPages} pages`);
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// Validates the trusted-actors shape (version 1, no extra keys) and returns
// the listed ids and each lowercased login's id. Throws on any read, parse or
// shape failure.
export function loadTrustedList(listPath) {
  const list = JSON.parse(readFileSync(listPath, "utf8"));
  if (
    !isPlainObject(list) ||
    Object.keys(list).sort().join() !== "actors,version" ||
    list.version !== 1 ||
    !Array.isArray(list.actors)
  ) {
    throw new Error("trusted-actor list does not match its schema");
  }
  const ids = new Set();
  const humans = new Set();
  const logins = new Map();
  for (const actor of list.actors) {
    if (
      !isPlainObject(actor) ||
      Object.keys(actor).sort().join() !== ACTOR_KEYS.join() ||
      !Number.isInteger(actor.id) ||
      actor.id < 1 ||
      typeof actor.login !== "string" ||
      !KINDS.has(actor.kind)
    ) {
      throw new Error("trusted-actor entry does not match its schema");
    }
    ids.add(actor.id);
    if (actor.kind === "human") {
      humans.add(actor.id);
    }
    logins.set(actor.login.toLowerCase(), actor.id);
  }
  return { ids, humans, logins };
}

export const loadTrustedActors = (listPath) => loadTrustedList(listPath).ids;

// Parses a comma- or space-separated list of positive integer ids. Anything
// else throws, so a malformed denial never reads as an empty one.
export function parseDeniedIds(value = "") {
  const tokens = value.split(/[\s,]+/).filter(Boolean);
  if (!tokens.every((token) => /^[1-9][0-9]{0,15}$/.test(token))) {
    throw new Error("denied actor ids must be positive integers");
  }
  return new Set(tokens.map(Number));
}

export const isListed = (ids, user) => Number.isInteger(user?.id) && ids.has(user.id);

class Stop extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

export const REPOSITORY = /^[A-Za-z0-9-]+\/(?!\.\.?$)[A-Za-z0-9_.-]+$/;
// GET /pulls can lag a push by minutes, so the PR is re-read until its head
// matches the branch ref, after each of these waits in turn (60 s in all).
const HEAD_READ_DELAYS_MS = [5000, 10_000, 20_000, 25_000];

// The SHA the PR's head branch points at, or null when it cannot be read.
async function headRefSha(github, pull) {
  const repository = pull.head?.repo?.full_name ?? "";
  const ref = pull.head?.ref;
  if (!REPOSITORY.test(repository) || typeof ref !== "string" || ref === "") {
    return null;
  }
  const encoded = ref.split("/").map(encodeURIComponent).join("/");
  try {
    const sha = (await github("GET", `/repos/${repository}/git/ref/heads/${encoded}`))?.object?.sha;
    return SHA.test(sha ?? "") ? sha : null;
  } catch (error) {
    if (error?.status === 404) {
      return null;
    }
    throw error;
  }
}

// The PR, re-read until its head SHA is the branch ref's. `headConfirmed` is
// false when they never agree, or at once for a PR `confirmable` rejects.
export async function readPull(github, base, prNumber, sleep, confirmable = () => true) {
  for (let read = 0; ; read += 1) {
    const pull = await github("GET", `${base}/pulls/${prNumber}`);
    if (!confirmable(pull)) {
      return { pull, headConfirmed: false };
    }
    const refSha = await headRefSha(github, pull);
    if (refSha !== null && refSha === pull.head?.sha) {
      return { pull, headConfirmed: true };
    }
    if (read === HEAD_READ_DELAYS_MS.length) {
      return { pull, headConfirmed: false };
    }
    await sleep(HEAD_READ_DELAYS_MS[read]);
  }
}

// A dispatched run's PR, its head confirmed against the branch ref; a fork's
// is not waited on, since the fork check stops it.
async function fetchPull(github, repository, number, sleep) {
  const sameRepo = (pull) => pull.head?.repo?.full_name === repository;
  let read;
  try {
    read = await readPull(github, `/repos/${repository}`, number, sleep, sameRepo);
  } catch {
    throw new Stop("no-pr");
  }
  if (!read.headConfirmed && sameRepo(read.pull)) {
    throw new Stop("head-lag");
  }
  return read.pull;
}

// The PR a workflow_run belongs to. An empty `pull_requests` array is not a
// fork signal, so the PR is always looked up from the run's head SHA.
async function resolveRunPull(github, repository, run, attemptTimeoutMs) {
  if (!/^[0-9a-f]{40}$/.test(run.head_sha ?? "")) {
    throw new Stop("no-pr");
  }
  let pulls;
  try {
    pulls = await commitPulls({
      repository,
      sha: run.head_sha,
      readRest: () => github("GET", `/repos/${repository}/commits/${run.head_sha}/pulls`),
      readGraphQL: graphQLReader(github),
      timeoutMs: attemptTimeoutMs,
    });
  } catch {
    throw new Stop("no-pr");
  }
  const matches = pulls.filter(
    (pull) =>
      pull.state === "open" &&
      pull.head?.sha === run.head_sha &&
      pull.head?.repo?.full_name === repository,
  );
  if (matches.length !== 1) {
    throw new Stop("no-pr");
  }
  return matches[0];
}

const timeOf = (value) => (typeof value === "string" ? Date.parse(value) : Number.NaN);

async function readOrRefuse(github, apiPath, reason = "untrusted-actor") {
  let body;
  try {
    body = await github("GET", apiPath);
  } catch {
    throw new Stop(reason);
  }
  if (!isPlainObject(body)) {
    throw new Stop(reason);
  }
  return body;
}

// The account that started this run attempt, read by id from this run's own
// record, since a login can be released and registered by someone else. A
// re-run keeps the event, so a stop here could otherwise turn an earlier red
// check on the same SHA neutral: untrusted-rerunner has no skip mapping, and
// a failed or malformed read stops with it too.
export async function readRerunner(github, repository, runId, runAttempt) {
  const refuse = "untrusted-rerunner";
  if (!RUN_ID.test(runId) || !RUN_ATTEMPT.test(runAttempt)) {
    throw new Stop(refuse);
  }
  const own = await readOrRefuse(github, `/repos/${repository}/actions/runs/${runId}`, refuse);
  if (String(own.id) !== runId || own.run_attempt !== Number(runAttempt) || !Number.isInteger(own.triggering_actor?.id)) {
    throw new Stop(refuse);
  }
  return own.triggering_actor.id;
}

// The re-runner must be in pool and not denied.
async function checkRerunner({ github, repository, runId, runAttempt, pool, deniedIds }) {
  const rerunnerId = await readRerunner(github, repository, runId, runAttempt);
  if (!pool.has(rerunnerId) || deniedIds.has(rerunnerId)) {
    throw new Stop("untrusted-rerunner");
  }
}

// The default branch's tip, read only while no tag shares the branch's name
// (a run on that tag would report the same head_branch; only a 404 proves it
// absent).
export async function readDefaultBranchTip(github, repository, defaultBranch, reason) {
  let tagAbsent = false;
  try {
    await github("GET", `/repos/${repository}/git/ref/tags/${defaultBranch}`);
  } catch (error) {
    tagAbsent = error instanceof GitHubError && error.status === 404;
  }
  if (!tagAbsent) {
    throw new Stop(reason);
  }
  const tip = await readOrRefuse(github, `/repos/${repository}/git/ref/heads/${defaultBranch}`, reason);
  if (tip.ref !== `refs/heads/${defaultBranch}` || !SHA.test(tip.object?.sha ?? "")) {
    throw new Stop(reason);
  }
  return tip.object.sha;
}

// headSha is the tip `tipSha` or behind it.
export async function requireBehindTip(github, repository, headSha, tipSha, reason) {
  const comparison = await readOrRefuse(github, `/repos/${repository}/compare/${headSha}...${tipSha}`, reason);
  if (comparison.status !== "ahead" && comparison.status !== "identical") {
    throw new Stop(reason);
  }
}

// The run at headSha ran the default branch's own code: no tag shares the
// branch's name, and headSha is the branch tip or behind it.
async function requireOnDefaultBranch(github, repository, defaultBranch, headSha, reason) {
  const tip = await readDefaultBranchTip(github, repository, defaultBranch, reason);
  await requireBehindTip(github, repository, headSha, tip, reason);
}

// What a record name says about this run: null when it does not list it,
// otherwise true, or for a workflow_run dispatcher's record the upstream run id.
function readRecordName(name, runId, viaRun) {
  if (typeof name !== "string") {
    return null;
  }
  if (viaRun) {
    const match = RUN_RECORD_NAME.exec(name);
    return match !== null && match[2] === runId ? match[1] : null;
  }
  return RECORD_NAME.test(name) && name.slice(RECORD_PREFIX.length).split("-").includes(runId)
    ? true
    : null;
}

// The dispatcher run's unexpired record of its own that lists this run's id,
// read by readRecordName, or null. A failed or malformed read refuses.
async function findRecord(github, runPath, dispatcherRunId, runId, viaRun) {
  const body = await readOrRefuse(github, `${runPath}/artifacts?per_page=100`);
  if (!Array.isArray(body.artifacts)) {
    throw new Stop("untrusted-actor");
  }
  for (const artifact of body.artifacts) {
    if (
      isPlainObject(artifact) &&
      artifact.expired === false &&
      Number.isSafeInteger(artifact.workflow_run?.id) &&
      String(artifact.workflow_run.id) === dispatcherRunId
    ) {
      const found = readRecordName(artifact.name, runId, viaRun);
      if (found !== null) {
        return found;
      }
    }
  }
  return null;
}

// The dispatcher run records the ids the dispatch API returned to it, so a
// dispatch it did not send is never in its record. Each read takes the
// dispatcher run's status before its artifacts, so an upload landing between
// the two is not refused. While the run is still going, an absent record is
// re-read after RECORD_WAIT_MS, at most RECORD_MAX_SLEEPS times. At the first
// completed status one more read follows the same wait, for any lag between
// the run and its artifact list, and then the gate refuses. That wait counts
// toward the cap, so the whole wait stays within 2 min. Returns what the
// record names (readRecordName).
async function requireRecorded({ github, repository, dispatcherRunId, runId, viaRun, sleep }) {
  const runPath = `/repos/${repository}/actions/runs/${dispatcherRunId}`;
  for (let sleeps = 0; ; sleeps += 1) {
    const { status } = await readOrRefuse(github, runPath);
    const found = await findRecord(github, runPath, dispatcherRunId, runId, viaRun);
    if (found !== null) {
      return found;
    }
    if (sleeps === RECORD_MAX_SLEEPS) {
      throw new Stop("untrusted-actor");
    }
    console.log(
      `check-trusted-trigger: dispatcher record: absent, re-read ${sleeps + 1} (dispatcher run ${dispatcherRunId}, run ${runId})`,
    );
    await sleep(RECORD_WAIT_MS);
    if (status === "completed") {
      const late = await findRecord(github, runPath, dispatcherRunId, runId, viaRun);
      if (late !== null) {
        return late;
      }
      throw new Stop("untrusted-actor");
    }
  }
}

// A dispatch sent by github-actions[bot] names no human, so it is trusted only
// through the dispatcher run it names: that workflow, on the default branch,
// started by a push, a schedule or a listed human, its head SHA an ancestor
// of the branch tip, a re-run attempt started by a listed human, its record listing this
// run, and this run, the dispatched workflow on the default branch, created
// between the dispatcher run's start and the earlier of its last update and
// WINDOW_MS after its start. A dispatcher started by workflow_run must be
// runDispatcherWorkflow instead, and no actor of it is checked: the upstream
// run its record names must be one of runDispatcherUpstreams, run on
// pull_request in this repository, started (and any re-run) by the lanes App
// or a listed human, at the PR's current head or at expectedUpstreamHead
// (upstreamHeadHolds). Returns this run's own record.
async function verifyDispatcher({
  github,
  repository,
  event,
  list,
  deniedIds,
  pull,
  dispatcherRunId,
  dispatcherWorkflow,
  runDispatcherWorkflow,
  runDispatcherUpstreams,
  expectedUpstreamHead,
  lanesAppId,
  dispatchedWorkflow,
  runId,
  sleep,
}) {
  const defaultBranch = event.repository?.default_branch;
  if (
    !RUN_ID.test(dispatcherRunId) ||
    !RUN_ID.test(runId) ||
    dispatchedWorkflow === "" ||
    typeof defaultBranch !== "string" ||
    !HEAD_REF.test(defaultBranch) ||
    event.ref !== `refs/heads/${defaultBranch}`
  ) {
    throw new Stop("untrusted-actor");
  }
  const isListedHuman = (user) =>
    Number.isInteger(user?.id) && list.humans.has(user.id) && !deniedIds.has(user.id);
  const dispatcher = await readOrRefuse(
    github,
    `/repos/${repository}/actions/runs/${dispatcherRunId}`,
  );
  const own = await readOrRefuse(github, `/repos/${repository}/actions/runs/${runId}`);
  const created = timeOf(own.created_at);
  const started = timeOf(dispatcher.run_started_at);
  const attempt = dispatcher.run_attempt;
  // A workflow_run run reports the default branch and its tip as head_branch
  // and head_sha, so the branch and ancestry checks below hold for it too.
  const viaRun = dispatcher.event === "workflow_run";
  const expectedPath = viaRun ? runDispatcherWorkflow : dispatcherWorkflow;
  // Comparisons with NaN are false, so a missing or unparsable time refuses.
  const trusted =
    own.path === dispatchedWorkflow &&
    own.event === "workflow_dispatch" &&
    dispatcher.repository?.full_name === repository &&
    expectedPath !== "" &&
    dispatcher.path === expectedPath &&
    dispatcher.head_branch === defaultBranch &&
    (viaRun ||
      (DISPATCHER_EVENTS.has(dispatcher.event) &&
        (dispatcher.event !== "workflow_dispatch" || isListedHuman(dispatcher.actor)))) &&
    SHA.test(dispatcher.head_sha ?? "") &&
    Number.isInteger(attempt) &&
    attempt >= 1 &&
    (attempt === 1 || isListedHuman(dispatcher.triggering_actor)) &&
    started <= created &&
    created <= Math.min(timeOf(dispatcher.updated_at), started + WINDOW_MS);
  if (!trusted) {
    throw new Stop("untrusted-actor");
  }
  await requireOnDefaultBranch(github, repository, defaultBranch, dispatcher.head_sha, "untrusted-actor");
  if (expectedUpstreamHead !== "" && (!viaRun || !SHA.test(expectedUpstreamHead))) {
    throw new Stop("untrusted-actor");
  }
  const found = await requireRecorded({ github, repository, dispatcherRunId, runId, viaRun, sleep });
  if (viaRun) {
    const upstream = await readOrRefuse(github, `/repos/${repository}/actions/runs/${found}`);
    // The run the review reacted to was started, and any re-run triggered, by
    // the lanes App or a listed human.
    const vouches = (user) =>
      Number.isInteger(user?.id) && (user.id === lanesAppId || isListedHuman(user));
    const reviewed =
      String(upstream.id) === found &&
      runDispatcherUpstreams.includes(upstream.path) &&
      upstream.event === "pull_request" &&
      upstream.repository?.full_name === repository &&
      upstream.head_repository?.full_name === repository &&
      vouches(upstream.actor) &&
      vouches(upstream.triggering_actor) &&
      (await upstreamHeadHolds({ github, repository, upstreamSha: upstream.head_sha, pullSha: pull.head.sha, expectedUpstreamHead, lanesAppId, runCreated: created }));
    if (!reviewed) {
      throw new Stop("untrusted-actor");
    }
  }
  return own;
}

// A job after pr-unblock's model job passes the head that job was gated on:
// the review must be of it, and every commit from it to the PR's current head
// one GitHub signed for the lanes App (author the App, committer web-flow,
// signature valid) during this workflow run. That proves an App-token commit
// made after this run was created, not which lane made it. A human, foreign,
// unsigned, older or truncated range refuses. Without one, the review must be
// of the PR's current head.
//
// web-flow, the committer GitHub records on commits it signs (seen on the
// lanes App's commits of #7493, #7494, #7496, #7520 and #7522).
const WEB_FLOW_ID = 19864447;

async function upstreamHeadHolds({ github, repository, upstreamSha, pullSha, expectedUpstreamHead, lanesAppId, runCreated }) {
  if (expectedUpstreamHead === "") {
    return upstreamSha === pullSha;
  }
  if (upstreamSha !== expectedUpstreamHead) {
    return false;
  }
  if (expectedUpstreamHead === pullSha) {
    return true;
  }
  const range = await readOrRefuse(github, `/repos/${repository}/compare/${expectedUpstreamHead}...${pullSha}`);
  const commits = Array.isArray(range.commits) ? range.commits : [];
  return (
    range.status === "ahead" &&
    commits.length > 0 &&
    range.total_commits === commits.length &&
    commits.every(
      (commit) =>
        Number.isInteger(commit?.author?.id) &&
        commit.author.id === lanesAppId &&
        // GitHub signed it (web-flow): an API commit made with the App's
        // token. A local commit claiming the App as author is committed
        // and signed by whoever pushed it.
        commit.committer?.id === WEB_FLOW_ID &&
        commit?.commit?.verification?.verified === true &&
        commit.commit.verification.reason === "valid" &&
        // Committed during this workflow run, not by an earlier lane.
        timeOf(commit.commit.committer?.date) >= runCreated,
    )
  );
}

// The re-runner of a dispatched run, read by id from this run's own record:
// github-actions[bot] on the first attempt, a listed id on any re-run.
function checkDispatchedRerunner({ ids }, deniedIds, own) {
  const rerunner = own.triggering_actor;
  const trusted =
    Number.isInteger(rerunner?.id) &&
    !deniedIds.has(rerunner.id) &&
    ((rerunner.id === ACTIONS_BOT_ID && own.run_attempt === 1) || ids.has(rerunner.id));
  if (!trusted) {
    throw new Stop("untrusted-rerunner");
  }
}

// A re-run github-actions[bot] started names no human, so it is trusted only
// as the lost-run reconciler's re-run of runId, this run or the upstream run a
// workflow_run event names: its attempt RERUN_ATTEMPT, started by
// github-actions[bot], and an unexpired
// rerunRecordName artifact, created no later than that attempt started, of a
// reconcilerWorkflow run in this repository on the default branch, started by
// its schedule or a listed human's dispatch, any re-run of it by a listed
// human, its head SHA the default branch tip or behind it, and this attempt
// started between that run's start and WINDOW_MS after it. A run id names one
// run and its second attempt starts once, so a record vouches for one attempt.
// The reconciler uploads the record before it re-runs; one more read follows
// RECORD_WAIT_MS for any lag in the artifact list. Every refusal is refuse:
// untrusted-rerunner for this run, as for an unlisted re-runner, and
// untrusted-actor for an upstream run, as for an unlisted actor.
//
// The same check runs for each recorder whose attempts include runAttempt
// (reconcilerRecorder, ciStatusRerunRecorder), reading that attempt and that
// recorder's record name; a rerun-ci-status run must be a workflow_run run,
// and its record uploaded after it started, no later than the attempt started
// and at most WINDOW_MS before it.
async function verifyRecordedRerun({ github, repository, event, list, deniedIds, recorders, runId, runAttempt, sleep, refuse = "untrusted-rerunner" }) {
  const defaultBranch = event.repository?.default_branch;
  const attempt = Number(runAttempt);
  const usable = RUN_ATTEMPT.test(runAttempt) ? recorders.filter((recorder) => recorder.workflow !== "" && recorder.attempts(attempt)) : [];
  if (
    deniedIds.has(ACTIONS_BOT_ID) ||
    !RUN_ID.test(runId) ||
    usable.length === 0 ||
    typeof defaultBranch !== "string" ||
    !HEAD_REF.test(defaultBranch)
  ) {
    throw new Stop(refuse);
  }
  const own = await readOrRefuse(github, `/repos/${repository}/actions/runs/${runId}/attempts/${attempt}`, refuse);
  const ownStarted = timeOf(own.run_started_at);
  if (
    String(own.id) !== runId ||
    own.run_attempt !== attempt ||
    own.triggering_actor?.id !== ACTIONS_BOT_ID ||
    own.repository?.full_name !== repository ||
    !SHA.test(own.head_sha ?? "") ||
    Number.isNaN(ownStarted)
  ) {
    throw new Stop(refuse);
  }
  const isListedHuman = (user) =>
    Number.isInteger(user?.id) && list.humans.has(user.id) && !deniedIds.has(user.id);
  // Anyone's run can upload an artifact of this name, so each candidate's run
  // is read and judged, at most RECORD_MAX_CANDIDATES of them per record name;
  // one that cannot be read does not vouch. A name past its cap returns null:
  // the next recorder's name is still read, and past the last one it refuses.
  const candidates = new Map();
  const vouches = async (artifact, recorder, name) => {
    const recorded = timeOf(artifact?.created_at);
    if (
      !isPlainObject(artifact) ||
      artifact.name !== name ||
      artifact.expired !== false ||
      !Number.isSafeInteger(artifact.workflow_run?.id) ||
      !(recorded <= ownStarted)
    ) {
      return false;
    }
    const count = candidates.get(name) ?? 0;
    if (count >= RECORD_MAX_CANDIDATES) {
      console.log(`check-trusted-trigger: re-run record ${name}: over ${RECORD_MAX_CANDIDATES} candidate runs (run ${runId})`);
      return null;
    }
    candidates.set(name, count + 1);
    let run;
    try {
      run = await readOrRefuse(github, `/repos/${repository}/actions/runs/${artifact.workflow_run.id}`, refuse);
    } catch {
      return false;
    }
    const started = timeOf(run.run_started_at);
    const trusted =
      run.id === artifact.workflow_run.id &&
      run.repository?.full_name === repository &&
      run.path === recorder.workflow &&
      run.head_branch === defaultBranch &&
      recorder.started(run, isListedHuman) &&
      SHA.test(run.head_sha ?? "") &&
      Number.isInteger(run.run_attempt) &&
      run.run_attempt >= 1 &&
      (run.run_attempt === 1 || isListedHuman(run.triggering_actor)) &&
      started <= ownStarted &&
      (recorder.fromRecord ? started <= recorded && ownStarted <= recorded + WINDOW_MS : ownStarted <= started + WINDOW_MS);
    if (!trusted) {
      return false;
    }
    await requireOnDefaultBranch(github, repository, defaultBranch, run.head_sha, refuse);
    return true;
  };
  for (let read = 0; read < 2; read += 1) {
    if (read > 0) {
      console.log(`check-trusted-trigger: re-run record: absent, re-read (run ${runId})`);
      await sleep(RECORD_WAIT_MS);
    }
    for (const [index, recorder] of usable.entries()) {
      const name = recorder.name(runId, attempt, own.head_sha);
      const listingPath = `/repos/${repository}/actions/artifacts?name=${name}&per_page=100`;
      pages: for (let page = 1; page <= RECORD_MAX_PAGES; page += 1) {
        const body = await readOrRefuse(github, `${listingPath}&page=${page}`, refuse);
        if (!Array.isArray(body.artifacts)) {
          throw new Stop(refuse);
        }
        for (const artifact of body.artifacts) {
          const verdict = await vouches(artifact, recorder, name);
          if (verdict === true) {
            return;
          }
          if (verdict === null) {
            if (index === usable.length - 1) {
              throw new Stop(refuse);
            }
            break pages;
          }
        }
        if (body.artifacts.length < 100) {
          break;
        }
      }
    }
  }
  throw new Stop(refuse);
}

// app-label: the lanes App applying exactly that label to an issue starts the
// lane; the label alone admits the issue. Any other App event stops. The
// re-runner is the App itself, listed, or a listed human.
async function checkAppLabel({ github, repository, event, list, deniedIds, lanesAppId, appLabel, runId, runAttempt }) {
  if (event.action !== "labeled" || event.label?.name !== appLabel) {
    throw new Stop("bot-actor");
  }
  if (!PR_NUMBER.test(String(event.issue?.number ?? ""))) {
    throw new Stop("untrusted-actor");
  }
  console.log(`check-trusted-trigger: ${appLabel} from the lanes App`);
  const rerunnerId = await readRerunner(github, repository, runId, runAttempt);
  const isApp = rerunnerId === lanesAppId && list.ids.has(rerunnerId);
  if (!isApp && (!list.humans.has(rerunnerId) || deniedIds.has(rerunnerId))) {
    throw new Stop("untrusted-rerunner");
  }
  return { ...stopped("ok"), proceed: "true" };
}

// require-pr: false. A workflow_dispatch or issues event checks its sender
// (on issues, the account that applied the label) and the triggering actor, a
// push only the triggering actor; no PR is read. require-kind human narrows
// both to actors listed as human.
async function evaluateActors({ github, repository, eventName, event, list, deniedIds, requireKind, lanesAppId, appLabel, runId, runAttempt }) {
  if (eventName !== "workflow_dispatch" && eventName !== "issues" && eventName !== "push") {
    throw new Stop("no-pr");
  }
  if (
    eventName === "issues" &&
    requireKind === "human" &&
    appLabel !== "" &&
    lanesAppId !== null &&
    event.sender?.id === lanesAppId
  ) {
    return checkAppLabel({ github, repository, event, list, deniedIds, lanesAppId, appLabel, runId, runAttempt });
  }
  const pool = requireKind === "human" ? list.humans : list.ids;
  if (eventName !== "push") {
    if (Number.isInteger(event.sender?.id) && deniedIds.has(event.sender.id)) {
      throw new Stop("bot-actor");
    }
    if (!isListed(pool, event.sender)) {
      throw new Stop("untrusted-actor");
    }
  }
  await checkRerunner({ github, repository, runId, runAttempt, pool, deniedIds });
  return { ...stopped("ok"), proceed: "true" };
}

export async function evaluateTrigger({
  eventName,
  event,
  repository,
  list,
  deniedIds = new Set(),
  triggeringActor = "",
  prNumber,
  dispatcherRunId = "",
  dispatcherWorkflow = "",
  runDispatcherWorkflow = "",
  runDispatcherUpstreams = [],
  expectedUpstreamHead = "",
  lanesAppId = null,
  requirePr = "true",
  requireKind = "",
  appLabel = "",
  runId = "",
  runAttempt = "",
  reconcilerWorkflow = "",
  ciStatusRerunWorkflow = "",
  dispatchedWorkflow = "",
  github,
  sleep = defaultSleep,
  attemptTimeoutMs,
}) {
  const { ids } = list;
  if (typeof repository !== "string" || !repository.includes("/")) {
    throw new Stop("no-pr");
  }
  if (requireKind !== "" && requireKind !== "human") {
    throw new Stop("no-pr");
  }
  if (requirePr === "false") {
    return evaluateActors({ github, repository, eventName, event, list, deniedIds, requireKind, lanesAppId, appLabel, runId, runAttempt });
  }
  if (requirePr !== "true") {
    throw new Stop("no-pr");
  }
  let pull;
  let actors = [event.sender];
  if (eventName === "pull_request") {
    pull = event.pull_request;
    if (!isPlainObject(pull)) {
      throw new Stop("no-pr");
    }
  } else if (eventName === "workflow_dispatch") {
    if (!PR_NUMBER.test(prNumber ?? "")) {
      throw new Stop("no-pr");
    }
    pull = await fetchPull(github, repository, prNumber, sleep);
  } else if (eventName === "workflow_run") {
    const run = event.workflow_run;
    if (run?.head_repository?.full_name !== repository) {
      throw new Stop("fork");
    }
    actors = [event.sender, run.actor, run.triggering_actor];
    pull = await resolveRunPull(github, repository, run, attemptTimeoutMs);
  } else {
    throw new Stop("no-pr");
  }
  if (pull.head?.repo?.full_name !== repository) {
    throw new Stop("fork");
  }
  if (
    !HEAD_REF.test(pull.head.ref ?? "") ||
    !SHA.test(pull.head.sha ?? "") ||
    !SHA.test(pull.base?.sha ?? "")
  ) {
    throw new Stop("no-pr");
  }
  // Lanes read the list and scripts from the base, so only the default branch
  // is a trusted one; a payload without it cannot prove the base.
  const defaultBranch = event.repository?.default_branch;
  if (typeof defaultBranch !== "string" || !HEAD_REF.test(defaultBranch) || pull.base.ref !== defaultBranch) {
    throw new Stop("untrusted-base");
  }
  if (actors.some((actor) => Number.isInteger(actor?.id) && deniedIds.has(actor.id))) {
    throw new Stop("bot-actor");
  }
  if (
    eventName === "workflow_dispatch" &&
    event.sender?.id === ACTIONS_BOT_ID &&
    dispatcherRunId !== ""
  ) {
    const own = await verifyDispatcher({
      github,
      repository,
      event,
      list,
      deniedIds,
      pull,
      dispatcherRunId,
      dispatcherWorkflow,
      runDispatcherWorkflow,
      runDispatcherUpstreams,
      expectedUpstreamHead,
      lanesAppId,
      dispatchedWorkflow,
      runId,
      sleep,
    });
    checkDispatchedRerunner(list, deniedIds, own);
  } else if (expectedUpstreamHead !== "") {
    throw new Stop("untrusted-actor");
  } else {
    // A CI run the reconciler or rerun-ci-status re-ran is started by
    // github-actions[bot]; that actor is vouched for only by a record of a
    // recorder whose attempts include it, and every other actor must still be
    // listed.
    const upstream = eventName === "workflow_run" ? event.workflow_run : undefined;
    const recorders = [reconcilerRecorder(reconcilerWorkflow), ciStatusRerunRecorder(ciStatusRerunWorkflow)].filter(
      (recorder) => recorder.workflow !== "",
    );
    const upstreamRerun =
      upstream?.triggering_actor?.id === ACTIONS_BOT_ID &&
      Number.isInteger(upstream.run_attempt) &&
      recorders.some((recorder) => recorder.attempts(upstream.run_attempt));
    const vouched = upstreamRerun ? [event.sender, upstream.actor] : actors;
    if (!vouched.every((actor) => isListed(ids, actor))) {
      throw new Stop("untrusted-actor");
    }
    if (upstreamRerun) {
      await verifyRecordedRerun({
        github,
        repository,
        event,
        list,
        deniedIds,
        recorders,
        runId: String(upstream.id),
        runAttempt: String(upstream.run_attempt),
        sleep,
        refuse: "untrusted-actor",
      });
    }
    if (reconcilerWorkflow !== "" && String(triggeringActor).toLowerCase() === "github-actions[bot]") {
      const reconciler = [reconcilerRecorder(reconcilerWorkflow)];
      await verifyRecordedRerun({ github, repository, event, list, deniedIds, recorders: reconciler, runId, runAttempt, sleep });
    } else {
      await checkRerunner({ github, repository, runId, runAttempt, pool: ids, deniedIds });
    }
  }
  if (!isListed(ids, pull.user)) {
    throw new Stop("untrusted-author");
  }
  return {
    proceed: "true",
    reason: "ok",
    "pr-number": String(pull.number),
    "head-ref": pull.head.ref,
    "head-sha": pull.head.sha,
    "base-sha": pull.base.sha,
  };
}

function stopped(reason) {
  return {
    proceed: "false",
    reason,
    "pr-number": "",
    "head-ref": "",
    "head-sha": "",
    "base-sha": "",
  };
}

export async function main({ env = process.env, github, sleep = defaultSleep, attemptTimeoutMs } = {}) {
  let result;
  try {
    let list;
    let deniedIds;
    try {
      list = loadTrustedList(env.TRUSTED_ACTORS_PATH);
      deniedIds = parseDeniedIds(env.DENIED_ACTOR_IDS);
    } catch {
      throw new Stop("list-unreadable");
    }
    let event;
    try {
      event = JSON.parse(readFileSync(env.EVENT_PATH, "utf8"));
    } catch {
      throw new Stop("no-pr");
    }
    result = await evaluateTrigger({
      eventName: env.EVENT_NAME,
      event,
      repository: env.REPOSITORY,
      list,
      deniedIds,
      triggeringActor: env.TRIGGERING_ACTOR ?? "",
      prNumber: env.PR_NUMBER,
      dispatcherRunId: env.DISPATCHER_RUN_ID ?? "",
      dispatcherWorkflow: env.DISPATCHER_WORKFLOW ?? "",
      runDispatcherWorkflow: env.RUN_DISPATCHER_WORKFLOW ?? "",
      runDispatcherUpstreams: (env.RUN_DISPATCHER_UPSTREAMS ?? "").split(/\s+/).filter(Boolean),
      expectedUpstreamHead: env.EXPECTED_UPSTREAM_HEAD ?? "",
      lanesAppId: /^[1-9][0-9]{0,14}$/.test(env.LANES_APP_ID ?? "") ? Number(env.LANES_APP_ID) : null,
      requirePr: env.REQUIRE_PR ?? "true",
      requireKind: env.REQUIRE_KIND ?? "",
      appLabel: env.APP_LABEL ?? "",
      dispatchedWorkflow: env.DISPATCHED_WORKFLOW ?? "",
      runId: env.GITHUB_RUN_ID ?? "",
      runAttempt: env.GITHUB_RUN_ATTEMPT ?? "",
      reconcilerWorkflow: env.RECONCILER_WORKFLOW ?? "",
      ciStatusRerunWorkflow: env.CI_STATUS_RERUN_WORKFLOW ?? "",
      github: github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
      sleep,
      attemptTimeoutMs,
    });
  } catch (error) {
    if (!(error instanceof Stop)) {
      console.log(`check-trusted-trigger: unexpected ${error?.name ?? "error"}; stopping`);
    }
    result = stopped(error instanceof Stop ? error.reason : "no-pr");
  }
  try {
    writeOutputs(result, env.GITHUB_OUTPUT);
  } catch {
    console.log("check-trusted-trigger: could not write outputs; the lane stays stopped");
  }
  console.log(`check-trusted-trigger: proceed=${result.proceed} reason=${result.reason}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
