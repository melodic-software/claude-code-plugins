// Trigger gate for CI lanes: proceed only for a same-repository PR whose event
// actor and PR author are both on the trusted-actor list, matched by numeric
// id, and whose re-runner, when given, is listed by login. A denied id stops
// the lane even when it is listed. Every failure ends in proceed=false with a
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
    logins.set(actor.login.toLowerCase(), actor.id);
  }
  return { ids, logins };
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

export async function evaluateTrigger({
  eventName,
  event,
  repository,
  list,
  deniedIds = new Set(),
  triggeringActor = "",
  prNumber,
  github,
}) {
  const { ids, logins } = list;
  if (typeof repository !== "string" || !repository.includes("/")) {
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
    !/^[0-9a-f]{40}$/.test(pull.head.sha ?? "") ||
    !/^[0-9a-f]{40}$/.test(pull.base?.sha ?? "")
  ) {
    throw new Stop("no-pr");
  }
  // The context gives the re-runner's login only, so it is matched by login.
  const rerunnerId = triggeringActor === "" ? undefined : logins.get(triggeringActor.toLowerCase());
  if (
    actors.some((actor) => Number.isInteger(actor?.id) && deniedIds.has(actor.id)) ||
    (rerunnerId !== undefined && deniedIds.has(rerunnerId))
  ) {
    throw new Stop("bot-actor");
  }
  if (!actors.every((actor) => isListed(ids, actor))) {
    throw new Stop("untrusted-actor");
  }
  if (triggeringActor !== "" && rerunnerId === undefined) {
    throw new Stop("untrusted-actor");
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

export async function main({ env = process.env, github } = {}) {
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
      github: github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
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
