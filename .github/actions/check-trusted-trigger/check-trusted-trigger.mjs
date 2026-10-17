// Trigger gate for CI lanes: proceed only for a same-repository PR whose event
// actor and PR author are both on the trusted-actor list, matched by numeric
// id, and whose re-runner is listed by login. A denied id stops the lane even
// when it is listed. A workflow_dispatch sent by github-actions[bot] stands in
// for its sender through a checked dispatcher run, and require-pr false checks
// the actors without a PR. Every failure ends in proceed=false with a
// reason; main never throws.
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";

const ACTOR_KEYS = ["id", "kind", "login"];
const KINDS = new Set(["human", "bot"]);
const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
// Branch names reach later steps; anything beyond these characters stops the
// lane rather than travel on.
const HEAD_REF = /^[A-Za-z0-9._/-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
// github-actions[bot], the sender of every GITHUB_TOKEN workflow dispatch.
const ACTIONS_BOT_ID = 41898282;
const DISPATCHER_EVENTS = new Set(["push", "workflow_dispatch"]);
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
const RECORD_MAX_SLEEPS = 24;

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export class GitHubError extends Error {
  constructor(status, what) {
    super(`${what} failed with status ${status}`);
    this.name = "GitHubError";
    this.status = status;
  }
}

// One function every API read and write goes through; tests replace it.
export function createGitHub({ token, apiUrl = "https://api.github.com", fetchImpl = fetch }) {
  return async function github(method, apiPath, body) {
    const response = await fetchImpl(`${apiUrl}${apiPath}`, {
      method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw new GitHubError(response.status, `${method} ${apiPath}`);
    }
    if (response.status === 204) {
      return null;
    }
    const json = await response.json();
    if (Array.isArray(json?.errors) && json.errors.length > 0) {
      throw new GitHubError(response.status, `${method} ${apiPath} (GraphQL errors)`);
    }
    return json;
  };
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

async function fetchPull(github, repository, number) {
  try {
    return await github("GET", `/repos/${repository}/pulls/${number}`);
  } catch {
    throw new Stop("no-pr");
  }
}

// The PR a workflow_run belongs to. An empty `pull_requests` array is not a
// fork signal, so the PR is always looked up from the run's head SHA.
async function resolveRunPull(github, repository, run) {
  if (!/^[0-9a-f]{40}$/.test(run.head_sha ?? "")) {
    throw new Stop("no-pr");
  }
  let pulls;
  try {
    pulls = await github("GET", `/repos/${repository}/commits/${run.head_sha}/pulls`);
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

// The context gives the re-runner's login only, so it is matched by login.
// A re-run keeps the event, so a stop here could otherwise turn an earlier
// red check on the same SHA neutral: its reason has no skip mapping, and
// an empty login stops too.
function checkRerunnerLogin({ ids, logins }, deniedIds, triggeringActor, pool = ids) {
  const rerunnerId = logins.get(String(triggeringActor).toLowerCase());
  if (rerunnerId === undefined || !pool.has(rerunnerId) || deniedIds.has(rerunnerId)) {
    throw new Stop("untrusted-rerunner");
  }
}

const timeOf = (value) => (typeof value === "string" ? Date.parse(value) : Number.NaN);

async function readOrRefuse(github, apiPath) {
  let body;
  try {
    body = await github("GET", apiPath);
  } catch {
    throw new Stop("untrusted-actor");
  }
  if (!isPlainObject(body)) {
    throw new Stop("untrusted-actor");
  }
  return body;
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
// started by a push or a listed human, its head SHA an ancestor of the branch
// tip, a re-run attempt started by a listed human, its record listing this
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
  // Comparisons with NaN are false, so a missing or unparseable time refuses.
  const trusted =
    own.path === dispatchedWorkflow &&
    own.event === "workflow_dispatch" &&
    dispatcher.repository?.full_name === repository &&
    expectedPath !== "" &&
    dispatcher.path === expectedPath &&
    dispatcher.head_branch === defaultBranch &&
    (viaRun ||
      (DISPATCHER_EVENTS.has(dispatcher.event) &&
        (dispatcher.event === "push" || isListedHuman(dispatcher.actor)))) &&
    SHA.test(dispatcher.head_sha ?? "") &&
    Number.isInteger(attempt) &&
    attempt >= 1 &&
    (attempt === 1 || isListedHuman(dispatcher.triggering_actor)) &&
    started <= created &&
    created <= Math.min(timeOf(dispatcher.updated_at), started + WINDOW_MS);
  if (!trusted) {
    throw new Stop("untrusted-actor");
  }
  // A tag with the branch's name would give a run on that tag the same
  // head_branch, so one must not exist; only a 404 proves that.
  let tagAbsent = false;
  try {
    await github("GET", `/repos/${repository}/git/ref/tags/${defaultBranch}`);
  } catch (error) {
    tagAbsent = error instanceof GitHubError && error.status === 404;
  }
  if (!tagAbsent) {
    throw new Stop("untrusted-actor");
  }
  const tip = await readOrRefuse(github, `/repos/${repository}/git/ref/heads/${defaultBranch}`);
  if (tip.ref !== `refs/heads/${defaultBranch}` || !SHA.test(tip.object?.sha ?? "")) {
    throw new Stop("untrusted-actor");
  }
  const comparison = await readOrRefuse(
    github,
    `/repos/${repository}/compare/${dispatcher.head_sha}...${tip.object.sha}`,
  );
  if (comparison.status !== "ahead" && comparison.status !== "identical") {
    throw new Stop("untrusted-actor");
  }
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

// app-label: the lanes App applying exactly that label to an issue starts the
// lane; the label alone admits the issue. Any other App event stops. The
// re-runner is the App itself or a listed human.
function checkAppLabel({ event, list, deniedIds, triggeringActor, lanesAppId, appLabel }) {
  if (event.action !== "labeled" || event.label?.name !== appLabel) {
    throw new Stop("bot-actor");
  }
  if (!PR_NUMBER.test(String(event.issue?.number ?? ""))) {
    throw new Stop("untrusted-actor");
  }
  console.log(`check-trusted-trigger: ${appLabel} from the lanes App`);
  const rerunnerId = list.logins.get(String(triggeringActor).toLowerCase());
  if (rerunnerId !== lanesAppId && (!list.humans.has(rerunnerId) || deniedIds.has(rerunnerId))) {
    throw new Stop("untrusted-rerunner");
  }
  return { ...stopped("ok"), proceed: "true" };
}

// require-pr: false. A workflow_dispatch or issues event checks its sender
// (on issues, the account that applied the label) and the triggering actor, a
// push only the triggering actor; no PR is read. require-kind human narrows
// both to actors listed as human.
function evaluateActors({ eventName, event, list, deniedIds, triggeringActor, requireKind, lanesAppId, appLabel }) {
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
    return checkAppLabel({ event, list, deniedIds, triggeringActor, lanesAppId, appLabel });
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
  checkRerunnerLogin(list, deniedIds, triggeringActor, pool);
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
  dispatchedWorkflow = "",
  github,
  sleep = defaultSleep,
}) {
  const { ids } = list;
  if (typeof repository !== "string" || !repository.includes("/")) {
    throw new Stop("no-pr");
  }
  if (requireKind !== "" && requireKind !== "human") {
    throw new Stop("no-pr");
  }
  if (requirePr === "false") {
    return evaluateActors({ eventName, event, list, deniedIds, triggeringActor, requireKind, lanesAppId, appLabel });
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
    pull = await fetchPull(github, repository, prNumber);
  } else if (eventName === "workflow_run") {
    const run = event.workflow_run;
    if (run?.head_repository?.full_name !== repository) {
      throw new Stop("fork");
    }
    actors = [event.sender, run.actor, run.triggering_actor];
    pull = await resolveRunPull(github, repository, run);
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
    if (!actors.every((actor) => isListed(ids, actor))) {
      throw new Stop("untrusted-actor");
    }
    checkRerunnerLogin(list, deniedIds, triggeringActor);
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

export async function main({ env = process.env, github, sleep = defaultSleep } = {}) {
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
      github: github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
      sleep,
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
