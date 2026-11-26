import { appendFileSync, mkdirSync, readFileSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";

export const SIGNALS = Object.freeze({
  statuses: Object.freeze([403, 429]),
  message: /rate limit|abuse detection/i,
  secondary: /secondary rate limit|abuse detection/i,
  graphqlErrorType: "RATE_LIMITED",
  fallbackSeconds: 60,
  primaryFallbackSeconds: 3600,
});

const MAX_RESET = 999_999_999_999;

/**
 * The one copy of how long a job may wait out a rate limit before it stops and
 * leaves the run to the lost-run reconciler, in seconds (outage posture
 * element 1, docs/conventions/pr-pipeline/README.md). A workflow cannot import
 * this module, so each literal below is pinned to it by rate-guard.test.mjs:
 * - `step`: one process's waits, summed. The latch's budget for rate-limit
 *   waits and, counted apart, a client's 5xx retries (retryServerErrors), and
 *   the `rate-limit-wait-seconds` default of check-contract and
 *   aggregate-results, which ci-status's report-ci-status composite keeps.
 * - `ciStatusReads`: ci-status's reads, from the job's start: its
 *   GH_READ_JOB_SECONDS less GH_READ_MARGIN_SECONDS.
 * - `rerunCiStatus`: pr-dispatch-feedback.yml's rerun-ci-status find step,
 *   its POLL_LIMIT_SECONDS.
 * - `rerunCiStatusRate`: that step's rate-limit waits, counted with the
 *   poll's, its RATE_WAIT_SECONDS. The job's timeout-minutes holds it, and
 *   the reconciler's PENDING_BACKOFF_MINUTES holds the timeout, so no
 *   recovery waits longer.
 * - `workResolveIssue`: work-resolve-issue's steps after the model ran, whose
 *   failure drops finished work: the `rate-limit-wait-seconds` it passes
 *   pr-run-activity-read.yml and pr-run-activity-write.yml, which caps the
 *   leak scan's wait, and its jobs' API_BUDGET_WAIT_SECONDS. It is
 *   waitBudgetMs's cap.
 * - `mergeGroup`: one merge-group run's waits for a pool's reset, together.
 *   check-plugins' read of the queued pull request waits first, up to all of
 *   it (QUEUED_PR_WAIT_SECONDS), before the bump, fragment, release and
 *   vendor gates refuse and eject the group; ci-status's verdict reader,
 *   whose job needs check-plugins, waits only what that left
 *   (MERGE_GROUP_WAIT_SECONDS less the job's queued-pr-waited output, as
 *   BABYSIT_READ_FLOOR_WAIT_SECONDS) for a reset after a read it did not send
 *   below the read floor, then judges again (owner decision D417), and with
 *   nothing left its refusal stands. Each job's timeout-minutes holds the
 *   whole wait, on top of check-plugins' 9 and ci-status's
 *   GH_READ_JOB_SECONDS. The merge queue's check_response_timeout_minutes,
 *   30 (https://docs.github.com/en/rest/repos/rules#get-rules-for-a-branch),
 *   must hold the wait and the run's work. ci-status starts after the slowest
 *   lane, so a reader's wait adds to the whole run: the longest of 100 recent
 *   merge-group runs took 1,002 s (ci-status from 303 s, for 696 s), so 10
 *   minutes of waiting leaves about 3 to spare.
 */
export const WAIT_BUDGET_SECONDS = Object.freeze({ step: 60, ciStatusReads: 765, rerunCiStatus: 600, rerunCiStatusRate: 720, workResolveIssue: 1200, mergeGroup: 600 });

export const SERVER_RETRY_BUDGET_MS = WAIT_BUDGET_SECONDS.step * 1000;

export function waitBudgetMs(value = process.env.API_BUDGET_WAIT_SECONDS) {
  const seconds = /^\d{1,4}$/.test(String(value ?? "")) ? Number(value) : 0;
  return seconds * 1000 > SERVER_RETRY_BUDGET_MS && seconds <= WAIT_BUDGET_SECONDS.workResolveIssue ? seconds * 1000 : SERVER_RETRY_BUDGET_MS;
}

export const API_POOLS = Object.freeze(["github-token", "lanes-app", "graphql", "owner-token", "content-creation"]);

const DEFAULTS = new URL("./rate-limits.json", import.meta.url);

const SHARES = { plan: 0.7, "writer-pause": 0.4, breaker: 0.2, "read-floor": 0.1, "stop-floor": 0.02 };
export const BUILT_IN_LIMITS = Object.freeze({
  "github-token": { ...SHARES, pace: 0.2, "pace-pr-merge": 0.3, "start-gate": 0.1, "start-project": 0.3, "start-run-minutes": 21, "defer-project": 0.3, "defer-run-minutes": 15, "defer-run-minutes-pr-merge": 6, "defer-run-minutes-review": 8 },
  "lanes-app": SHARES,
  graphql: SHARES,
  "owner-token": SHARES,
  "content-creation": { ...SHARES, "per-minute": 80, "per-hour": 500 },
});

const SHARE = (value) => typeof value === "number" && value >= 0 && value <= 1;
const COUNT = (value) => Number.isInteger(value) && value >= 1;
const FIELDS = { plan: (value) => SHARE(value) && value > 0, "writer-pause": SHARE, breaker: SHARE, "read-floor": SHARE, "stop-floor": SHARE, pace: SHARE, "pace-pr-merge": SHARE, "start-gate": SHARE, "start-project": SHARE, "start-run-minutes": COUNT, "defer-project": SHARE, "defer-run-minutes": COUNT, "defer-run-minutes-pr-merge": COUNT, "defer-run-minutes-review": COUNT };
const CONTENT_FIELDS = { ...FIELDS, "per-minute": COUNT, "per-hour": COUNT };
export const FILE_ONLY_FIELDS = Object.freeze(["pace-pr-merge", "start-gate", "start-project", "start-run-minutes"]);
const REQUIRED = ["plan", "writer-pause", "breaker", "read-floor"];

function readDefaults(path) {
  const defaults = JSON.parse(readFileSync(path, "utf8"));
  const pools = Object.keys(defaults ?? {});
  if (Array.isArray(defaults) || pools.length !== API_POOLS.length || !API_POOLS.every((name) => pools.includes(name))) {
    throw new Error(`${path}: the pools must be ${API_POOLS.join(", ")}`);
  }
  for (const name of API_POOLS) {
    const fields = name === "content-creation" ? CONTENT_FIELDS : FIELDS;
    const entry = defaults[name];
    const bad = [...REQUIRED.filter((field) => !(field in (entry ?? {}))), ...Object.entries(entry ?? {}).filter(([field, value]) => !fields[field]?.(value)).map(([field]) => field)];
    if (typeof entry !== "object" || entry === null || Array.isArray(entry) || bad.length) {
      throw new Error(`${path}: ${name} has a missing or invalid ${bad.join(", ") || "entry"}`);
    }
  }
  return defaults;
}

export function apiLimitsOrBuiltIn({ resolvedPath = process.env.RESOLVED_CONFIG, defaultsPath = DEFAULTS, log = (line) => console.log(line) } = {}) {
  try {
    return apiLimits({ resolvedPath, defaultsPath });
  } catch (error) {
    log(`::warning::rate-limits.json could not be read (${error?.code ?? error?.message}); planning to the built-in defaults, the values that file ships`);
    return apiLimits({ resolvedPath, defaultsPath: null });
  }
}

export function apiLimits({ resolvedPath = process.env.RESOLVED_CONFIG, defaultsPath = DEFAULTS } = {}) {
  const defaults = defaultsPath === null ? BUILT_IN_LIMITS : readDefaults(defaultsPath);
  let set = {};
  if (resolvedPath) {
    try {
      set = JSON.parse(readFileSync(resolvedPath, "utf8"))?.limits?.api ?? {};
    } catch {
      set = {};
    }
  }
  return Object.fromEntries(
    API_POOLS.map((name) => [name, { ...defaults[name], ...(set[name] ?? {}) }]),
  );
}

export function poolOf(url) {
  const path = String(url).replace(/^[a-z]+:\/\/[^/]+/i, "");
  if (/\/graphql(\?|$)/.test(path)) {
    return "graphql";
  }
  if (/^(\/api\/v3)?\/search\/code([/?]|$)/.test(path)) {
    return "code_search";
  }
  return /^(\/api\/v3)?\/search\//.test(path) ? "search" : "core";
}

const CONTENT_PATH =
  /\/repos\/[^/]+\/[^/]+\/(issues|pulls)(\/\d+(\/(comments|labels|reviews|assignees|requested_reviewers))?|\/\d+\/comments\/\d+\/replies|\/comments\/\d+)?\/?(\?|$)/;
export function isContentWrite(url, method = "GET", body) {
  if (!["POST", "PATCH", "PUT"].includes(String(method).toUpperCase())) {
    return false;
  }
  if (poolOf(url) === "graphql") {
    let query = "";
    try {
      query = String(JSON.parse(String(body ?? "")).query ?? "");
    } catch {
      query = "";
    }
    return /^\s*mutation\b/.test(query);
  }
  return CONTENT_PATH.test(String(url).replace(/^[a-z]+:\/\/[^/]+/i, ""));
}

export const entryOf = (pool, token = process.env.API_BUDGET_TOKEN) =>
  pool === "graphql" ? "graphql" : API_POOLS.includes(token) ? token : "github-token";

const READING = { limit: /^\d+$/, remaining: /^\d+$/, used: /^\d+$/, reset: /^\d+$/, resource: /^[a-z_]+$/ };

export function readingLine(status, headers, route = "other") {
  const values = Object.entries(READING).map(([key, re]) => {
    const value = String(headers?.get?.(`x-ratelimit-${key}`) ?? "");
    return re.test(value) ? value : "na";
  });
  return `${status} ${values.join(" ")} ${routeOk(route) ? route : "other"}\n`;
}

export const REST_PATH_WORDS = new Set(
  "api v3 repos orgs users user installation app graphql pulls issues comments reviews requested_reviewers git refs ref heads tags trees blobs commits compare merges merge check-runs check-suites statuses status labels assignees milestones events timeline actions runs jobs attempts artifacts logs rerun rerun-failed-jobs workflows dispatches variables secrets contents branches protection rules rulesets collaborators permission teams members hooks deployments environments releases search code reactions files rate_limit annotations repositories installations access_tokens pending_deployments cancel update-branch dismissals readme matching-refs languages notifications".split(" "),
);
export const PLACEHOLDERS = new Set(["{n}", "{sha}", "{repo}", "{x}"]);
const WORKFLOW_FILE = /^[a-z0-9][a-z0-9_-]*\.ya?ml$/;
export const routeOk = (route) =>
  typeof route === "string" && route.length <= 80 && (route === "graphql" || route === "other" || route.split("/").every((seg, i, all) => REST_PATH_WORDS.has(seg) || PLACEHOLDERS.has(seg) || (all[i - 1] === "workflows" && WORKFLOW_FILE.test(seg))));

const ROUTE_TAIL = /^(contents|ref|refs|matching-refs|readme|compare|trees)$/;
const ROUTE_NAME = /^(labels|branches|tags|users|orgs|teams|members|collaborators|assignees|environments|secrets|variables|workflows|commits|blobs|statuses|releases)$/;
export function routeOf(url) {
  const text = String(url?.url ?? url ?? "");
  const host = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]*)([^?#]*)/i.exec(text);
  if (host && !/^(api|uploads)\.github\.com$/i.test(host[1]) && !/^\/api\//.test(host[2])) {
    return "other";
  }
  const path = text
    .replace(/^[a-z][a-z0-9+.-]*:\/\/[^/?#]*/i, "")
    .replace(/[?#][\s\S]*$/, "")
    .replace(/^\/+/, "")
    .replace(/^api\/(v3\/)?/, "")
    .replace(/\/+$/, "");
  if (path === "graphql") {
    return "graphql";
  }
  if (path === "") {
    return "other";
  }
  const segments = path.split("/");
  const out = [];
  let tail = false;
  let name = false;
  let file = -1;
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i];
    const placeholder = /^[0-9]+$/.test(seg) ? "{n}" : /^[0-9a-f]{7,}$/i.test(seg) ? "{sha}" : null;
    if (name && !tail && segments[i - 1] === "workflows" && WORKFLOW_FILE.test(seg)) {
      file = out.push(seg) - 1;
      name = false;
    } else if (tail || name) {
      out.push(placeholder ?? "{x}");
      name = false;
    } else if (i === 1 && segments[0] === "repos" && segments.length >= 3) {
      out.push("{repo}");
      i++;
    } else if (placeholder) {
      out.push(placeholder);
    } else if (REST_PATH_WORDS.has(seg) && seg !== "api" && seg !== "v3" && seg !== "graphql") {
      out.push(seg);
      tail = ROUTE_TAIL.test(seg);
      name = ROUTE_NAME.test(seg);
    } else {
      out.push("{x}");
    }
  }
  if (file >= 0 && out.join("/").length > 80) {
    out[file] = "{x}";
  }
  const route = out.join("/");
  return route.length > 80 ? "other" : route;
}

export function recordReading({ token = process.env.API_BUDGET_TOKEN, dir = process.env.RUNNER_TEMP, status, headers, route }) {
  if (!dir || !/^[a-z][a-z0-9-]{0,39}$/.test(token ?? "")) {
    return;
  }
  const line = readingLine(status, headers, route);
  try {
    mkdirSync(join(dir, "api-budget"), { recursive: true });
    appendFileSync(join(dir, "api-budget", token), line);
    scriptCalls.count(token, line);
  } catch {
  }
}

export function recordFailure({ method, url, status, dir = process.env.RUNNER_TEMP }) {
  if (!dir) {
    return;
  }
  try {
    const path = new URL(String(url?.url ?? url), "https://api.github.com").pathname;
    const verb = String(method ?? "GET").toUpperCase();
    if (verb === "GET" && status === 404 && /^(\/api\/v3)?\/repos\/[^/]+\/[^/]+\/git\/ref\/tags\/./.test(path)) {
      return;
    }
    mkdirSync(join(dir, "lane-run-report"), { recursive: true });
    appendFileSync(join(dir, "lane-run-report", "api-failures.jsonl"), `${JSON.stringify({ method: String(method ?? "GET").toUpperCase(), path, status })}\n`);
  } catch {
  }
}

export function createScriptCalls() {
  const tokens = { "github-token": 0, "lanes-app": 0 };
  let notModified = 0;
  let graphql = 0;
  return {
    count(token, line) {
      const fields = line.trim().split(" ");
      if (fields[0] === "304") {
        notModified += 1;
      } else {
        tokens[token] = (tokens[token] ?? 0) + 1;
      }
      graphql += fields[5] === "graphql" ? 1 : 0;
    },
    line: (name) =>
      `::notice title=api-calls::script=${name} ${Object.entries(tokens)
        .map(([token, n]) => `${token}=${n}`)
        .join(" ")} not-modified=${notModified} graphql=${graphql}\n`,
  };
}
export const scriptCalls = createScriptCalls();
const SCRIPT = process.env.API_BUDGET_SCRIPT ?? "";
if (/^[a-z][a-z0-9-]{0,39}$/.test(SCRIPT)) {
  process.on("exit", () => {
    try {
      writeSync(1, scriptCalls.line(SCRIPT));
    } catch {
    }
  });
}

const bearerOf = (headers) => {
  const value = typeof headers?.get === "function" ? headers.get("authorization") : Object.entries(headers ?? {}).find(([name]) => name.toLowerCase() === "authorization")?.[1];
  return String(value ?? "").replace(/^(bearer|token)\s+/i, "");
};
export function budgetToken(init, { token, env = process.env } = {}) {
  if (token) {
    return token;
  }
  const own = env.GH_TOKEN || env.GITHUB_TOKEN;
  const bearer = bearerOf(init?.headers);
  return env.API_BUDGET_OVERRIDE_TOKEN && own && bearer && bearer !== own ? env.API_BUDGET_OVERRIDE_TOKEN : env.API_BUDGET_TOKEN;
}

export const COUNTED = Symbol.for("api-budget.counted");
export const countsRequests = (fetchImpl) => Object.assign(fetchImpl, { [COUNTED]: true });
export function countRequests(fetchImpl, { token } = {}) {
  if (fetchImpl?.[COUNTED]) {
    return fetchImpl;
  }
  return countsRequests(async function counted(url, init = {}) {
    const response = await fetchImpl(url, init);
    recordReading({ token: budgetToken(init, { token }), status: response.status, headers: response.headers, route: routeOf(url) });
    if (response.status >= 400) {
      recordFailure({ method: init.method, url, status: response.status });
    }
    return response;
  });
}

export function recordContentWrite({ dir = process.env.RUNNER_TEMP, at }) {
  if (!dir || !Number.isSafeInteger(at)) {
    return;
  }
  try {
    mkdirSync(join(dir, "api-budget"), { recursive: true });
    appendFileSync(join(dir, "api-budget", "content-creation"), `${at}\n`);
  } catch {
  }
}

const headerReader = (headers) => (typeof headers?.get === "function" ? (name) => headers.get(name) : (name) => headers?.[name]);

const intHeader = (get, name) => {
  const value = String(get(name) ?? "");
  return /^\d{1,12}$/.test(value) ? Number(value) : null;
};

const parseBody = (body) => {
  if (typeof body !== "string") {
    return body;
  }
  try {
    return JSON.parse(body);
  } catch {
    return null;
  }
};

export function serverErrorHold({ status, headers, body }) {
  const get = headerReader(headers);
  if (!(status >= 500 && status <= 599) || intHeader(get, "retry-after") === null || intHeader(get, "x-ratelimit-remaining") === 0) {
    return false;
  }
  const parsed = parseBody(body);
  const errors = Array.isArray(parsed?.errors) ? parsed.errors : [];
  const texts = [parsed?.message, ...errors.map((error) => error?.message)].map((text) => String(text ?? ""));
  return !texts.some((text) => SIGNALS.message.test(text)) && !errors.some((error) => error?.type === SIGNALS.graphqlErrorType);
}

export function classify({ url, status, headers, body }, { now = Date.now(), readFloor = null, stopFloor = null, floorGraceMs = 0 } = {}) {
  const get = headerReader(headers);
  const graphqlPool = poolOf(url) === "graphql";
  const parsed = parseBody(body);
  const remaining = intHeader(get, "x-ratelimit-remaining");
  const limit = intHeader(get, "x-ratelimit-limit");
  const reset = intHeader(get, "x-ratelimit-reset");
  const retryAfter = intHeader(get, "retry-after");
  const errors = Array.isArray(parsed?.errors) ? parsed.errors : [];
  const messages = [parsed?.message, ...(graphqlPool ? errors.map((error) => error?.message) : [])].map((text) => String(text ?? ""));
  const flagged = SIGNALS.statuses.includes(status) || graphqlPool;
  const message = flagged && messages.some((text) => SIGNALS.message.test(text));
  const secondary = flagged && messages.some((text) => SIGNALS.secondary.test(text));
  const graphql = errors.some((error) => error?.type === SIGNALS.graphqlErrorType);
  const tooMany = status === 429;
  const floored = stopFloor !== null && limit > 0 && remaining !== null && reset !== null && reset * 1000 > now + floorGraceMs && remaining <= stopFloor * limit;
  const latched = remaining === 0 || floored || retryAfter !== null || message || graphql || tooMany;
  const low = readFloor !== null && limit > 0 && remaining !== null && remaining < readFloor * limit;
  if (!latched) {
    return { latched, low, reset_source: null, reset: null, pool: null };
  }
  const nowSeconds = Math.floor(now / 1000);
  const candidates = [
    retryAfter !== null ? [retryAfter > 0 ? Math.ceil(now / 1000) + retryAfter : nowSeconds, "retry-after"] : null,
    (remaining === 0 || floored) && reset !== null ? [reset, "x-ratelimit-reset"] : null,
  ].filter(Boolean);
  const best = candidates.length ? candidates.reduce((top, next) => (next[0] > top[0] ? next : top)) : null;
  const [at, source] =
    best && best[0] > nowSeconds
      ? best
      : [nowSeconds + (best || secondary ? SIGNALS.fallbackSeconds : SIGNALS.primaryFallbackSeconds), "fallback"];
  const resource = String(get("x-ratelimit-resource") ?? "");
  const every = retryAfter !== null || secondary || ((message || tooMany) && remaining !== 0);
  const pool = every ? "*" : /^[a-z_]+$/.test(resource) ? resource : poolOf(url);
  return { latched, low, reset_source: source, reset: Math.min(at, MAX_RESET), pool };
}

export function headerStop({ url, status, headers }, options) {
  const verdict = classify({ url, status, headers, body: null }, options);
  return verdict.latched && verdict.reset_source !== "fallback" ? { pool: verdict.pool, reset: verdict.reset } : null;
}

export const resetLabel = (seconds) => new Date(seconds * 1000).toISOString().replace(".000Z", "Z");
const poolLabel = (pool) => (pool === "*" ? "API" : `${pool} API`);

export const FALLBACK_NOTE =
  "fallback: GitHub's refusal carried no reset header, so this time is a guess that holds only this job; a re-run works once GitHub's real reset passes";

export class RateLimitStop extends Error {
  constructor(what, pool, reset, serverStatus = null, fallback = false) {
    super(
      serverStatus === null
        ? `${what} was not sent: GitHub's ${poolLabel(pool)} rate limit holds until ${resetLabel(reset)}${fallback ? ` (${FALLBACK_NOTE})` : ""}`
        : `${what} was not sent: GitHub answered HTTP ${serverStatus} with a Retry-After; no call to it before ${resetLabel(reset)}`,
    );
    this.name = "RateLimitStop";
    this.status = 429;
    this.rateLimited = true;
    this.pool = pool;
    this.reset = reset;
  }
}

export const RESEND = Symbol.for("rate-guard.resend");

export async function refusedForLimit(response) {
  if (SIGNALS.statuses.includes(response.status)) {
    return true;
  }
  try {
    const errors = JSON.parse(await response.clone().text())?.errors;
    return Array.isArray(errors) && errors.some((error) => error?.type === SIGNALS.graphqlErrorType);
  } catch {
    return false;
  }
}

let failing = false;
function failProcess() {
  process.exitCode = 1;
  if (!failing) {
    failing = true;
    process.once("exit", () => {
      process.exitCode = 1;
    });
  }
}

const STOP_LINE = /^([a-z_]+|\*) (\d{1,12})$/;
const STOP_FILE = process.env.RUNNER_TEMP ? join(process.env.RUNNER_TEMP, "api-budget", "stop") : null;

function readStops(path, log) {
  const stops = new Map();
  let text = "";
  try {
    text = path ? readFileSync(path, "utf8") : "";
  } catch (error) {
    if (error?.code !== "ENOENT") {
      log(`::error::the rate guard's stop file ${path} cannot be read (${error?.code ?? error?.message}), so every GitHub API pool counts as stopped`);
      stops.set("*", MAX_RESET);
    }
  }
  for (const line of text.split("\n").slice(0, -1)) {
    const [, pool, reset] = STOP_LINE.exec(line) ?? [];
    if (pool) {
      stops.set(pool, Math.max(stops.get(pool) ?? 0, Number(reset)));
    }
  }
  return stops;
}

const CAUSE_LINE = /^([a-z_]+|\*) (\d{1,12}) (limit|server-5\d\d)$/;

function readCauses(path) {
  let text = "";
  try {
    text = path ? readFileSync(path, "utf8") : "";
  } catch {
    text = "";
  }
  return text
    .split("\n")
    .slice(0, -1)
    .map((line) => CAUSE_LINE.exec(line))
    .filter(Boolean)
    .map(([, pool, reset, cause]) => ({ pool, reset: Number(reset), cause }));
}

function readFallbacks(path) {
  let text = "";
  try {
    text = path ? readFileSync(path, "utf8") : "";
  } catch {
    text = "";
  }
  return new Set(text.split("\n").slice(0, -1).filter((line) => STOP_LINE.test(line)));
}

function serverHeld(causes, stops, pools, at) {
  const ending = at === null ? [] : [...new Set(pools)].filter((pool) => stops.get(pool) === at);
  let status = null;
  for (const pool of ending) {
    const own = causes.filter((c) => c.pool === pool && c.reset === at);
    if (!own.length || own.some((c) => c.cause === "limit")) {
      return null;
    }
    status = Number(own.at(-1).cause.slice("server-".length));
  }
  return status;
}

export function createRateLimitLatch({
  now = () => Date.now(),
  log = (line) => console.log(line),
  fail = failProcess,
  limits = () => apiLimitsOrBuiltIn({ log }),
  stopFile = STOP_FILE,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  hold = process.env.API_BUDGET_HOLD === "1",
  budgetMs = waitBudgetMs(),
} = {}) {
  const patient = budgetMs > SERVER_RETRY_BUDGET_MS;
  const stops = readStops(stopFile, log);
  const causeFile = stopFile ? join(dirname(stopFile), "cause") : null;
  const causes = readCauses(causeFile);
  const fallbackFile = stopFile ? join(dirname(stopFile), "fallback") : null;
  const fallbacks = readFallbacks(fallbackFile);
  const low = new Map();
  const warned = new Set();
  let waited = 0;
  let config;
  function margin(pool, key, token) {
    if (config === undefined) {
      try {
        config = limits();
      } catch {
        config = apiLimits({ defaultsPath: null });
        log("::warning::rate guard: rate-limits.json could not be read; the guard plans to its built-in defaults, the values that file ships");
      }
    }
    const value = config?.[entryOf(pool, token)]?.[key];
    return typeof value === "number" ? value : null;
  }

  function until(url) {
    const at = Math.max(stops.get("*") ?? 0, stops.get(poolOf(url)) ?? 0);
    return at * 1000 > now() ? at : null;
  }

  const heldBy = (url, at) => (stops.get(poolOf(url)) === at ? poolOf(url) : "*");

  const serverStatus = (url) => serverHeld(causes, stops, [poolOf(url), "*"], until(url));

  const resetMs = (url) => {
    const at = until(url);
    return at === null ? null : Math.max(0, at * 1000 - now());
  };

  const waits = (url) => {
    const reset = resetMs(url);
    return reset !== null && waited + reset < budgetMs + 1000;
  };

  async function waitOut(url, method, wait = sleep) {
    if (!waits(url)) {
      return;
    }
    const reset = resetMs(url);
    const status = serverStatus(url);
    const reason = status === null ? "GitHub's rate limit to reset" : `GitHub's Retry-After on HTTP ${status} to pass`;
    log(`::notice::${method} ${url} waits ${Math.ceil(reset / 1000) + 1}s for ${reason} at ${resetLabel(until(url))}`);
    waited += reset;
    await wait(reset + 1000);
  }

  function check(url, method = "GET") {
    const at = until(url);
    if (at === null) {
      return;
    }
    const status = serverStatus(url);
    const pool = heldBy(url, at);
    const stop = new RateLimitStop(`${method} ${url}`, pool, at, status, fallbacks.has(`${pool} ${at}`));
    const title = status === null ? "" : " title=GitHub server error";
    if (hold) {
      log(`::notice${title}::${stop.message}; this step holds`);
    } else {
      log(`::error${title}::${stop.message}`);
      fail();
    }
    throw stop;
  }

  async function observe(url, response, method = "GET", token = undefined, resend = false, floorGraceMs = 0) {
    const pool = poolOf(url);
    const classifiesBody = SIGNALS.statuses.includes(response.status) || pool === "graphql";
    const needsBody = classifiesBody || response.status >= 500;
    const stopFloor = margin(pool, "stop-floor", token);
    const options = { now: now(), readFloor: margin(pool, "read-floor", token), stopFloor, floorGraceMs };
    const recorded = new Map();
    const record = ({ pool: held, reset, reset_source }) => {
      const key = `${held} ${reset}`;
      if (!recorded.has(key)) {
        stops.set(held, Math.max(stops.get(held) ?? 0, reset));
        const fallback = reset_source === "fallback";
        if (fallback) {
          fallbacks.add(key);
        }
        let failed = "";
        if (stopFile) {
          try {
            mkdirSync(dirname(stopFile), { recursive: true });
            appendFileSync(stopFile, `${key}\n`);
          } catch (error) {
            failed = `; the stop could not be recorded in the job's stop file (${error?.code ?? error?.message}), so later steps do not see it`;
          }
          if (fallback && !failed) {
            try {
              appendFileSync(fallbackFile, `${key}\n`);
            } catch {
            }
          }
        }
        recorded.set(key, failed);
      }
      return recorded.get(key);
    };
    const early = headerStop({ url, status: response.status, headers: response.headers }, options);
    if (early) {
      record(early);
    }
    const body = needsBody ? await response.clone().text().catch(() => "") : null;
    const verdict = classify({ url, status: response.status, headers: response.headers, body: classifiesBody ? body : null }, options);
    low.set(pool, verdict.low);
    if (verdict.latched) {
      const unrecorded = record(verdict);
      const refused = await refusedForLimit(response);
      const get = headerReader(response.headers);
      const [limit, remaining] = ["limit", "remaining"].map((name) => Number(get(`x-ratelimit-${name}`)));
      const floored = !refused && stopFloor !== null && remaining > 0 && remaining <= stopFloor * limit;
      const server = !floored && serverErrorHold({ status: response.status, headers: response.headers, body });
      const cause = server ? `server-${response.status}` : "limit";
      causes.push({ pool: verdict.pool, reset: verdict.reset, cause });
      if (stopFile && !unrecorded) {
        try {
          appendFileSync(causeFile, `${verdict.pool} ${verdict.reset} ${cause}\n`);
        } catch {
        }
      }
      const resent = !unrecorded && resend && waits(url) && refused;
      const outwaits = patient && !unrecorded && floored && waits(url);
      const holds = resent || outwaits || (hold && !unrecorded);
      const then = resent
        ? "it is sent again after the reset"
        : outwaits
          ? "the next call waits for the reset"
          : `this step ${holds ? "holds" : "fails"}`;
      const what = floored
        ? `left GitHub's ${poolLabel(verdict.pool)} ${remaining} of ${limit} requests, at or under its stop-floor share ${stopFloor} (status ${response.status})`
        : server
          ? `got a GitHub server error, HTTP ${response.status} with a Retry-After`
          : `hit GitHub's ${poolLabel(verdict.pool)} rate limit (status ${response.status})`;
      const level = `${holds ? "::notice" : "::error"}${server ? " title=GitHub server error" : ""}::`;
      log(`${level}${method} ${url} ${what}: no call to it before ${resetLabel(verdict.reset)} (${verdict.reset_source === "fallback" ? FALLBACK_NOTE : verdict.reset_source}); ${then}${unrecorded}`);
      if (!holds) {
        fail();
      }
    } else if (verdict.low && !warned.has(pool)) {
      warned.add(pool);
      const get = headerReader(response.headers);
      const [limit, remaining] = ["limit", "remaining"].map((name) => Number(get(`x-ratelimit-${name}`)));
      log(`::warning::GitHub's ${pool} API has under its read floor left (${remaining} of ${limit}); reads continue`);
    }
    return verdict;
  }

  return {
    until,
    waits,
    check,
    observe,
    reload() {
      for (const [pool, reset] of readStops(stopFile, log)) {
        stops.set(pool, Math.max(stops.get(pool) ?? 0, reset));
      }
      causes.push(...readCauses(causeFile));
      for (const key of readFallbacks(fallbackFile)) {
        fallbacks.add(key);
      }
    },
    serverStatus,
    belowFloor: (url) => low.get(poolOf(url)) === true,
    waitOut,
    guard: (fetchImpl, { token, sleep: wait, floorGraceMs = 0 } = {}) => {
      const send = countRequests(fetchImpl, { token });
      return countsRequests(async function guarded(url, init = {}) {
        const method = String(init.method ?? "GET").toUpperCase();
        for (let again = patient && method === "GET" && init[RESEND] === undefined; ; again = false) {
          await waitOut(url, init.method ?? "GET", wait);
          check(url, init.method);
          if (isContentWrite(url, init.method, init.body)) {
            recordContentWrite({ at: Math.floor(now() / 1000) });
          }
          const response = await send(url, init);
          await observe(url, response, init.method, token, init[RESEND] === true || again, floorGraceMs);
          if (!again || !waits(url) || !(await refusedForLimit(response))) {
            return response;
          }
          await response.body?.cancel().catch(() => {});
        }
      });
    },
  };
}

export const DISPATCH_FLOOR_GRACE_MS = 10 * 60 * 1000;

export const rateLimitLatch = createRateLimitLatch();

export function budgetLatch(token, latch = rateLimitLatch) {
  return { ...latch, guard: (fetchImpl, options = {}) => latch.guard(fetchImpl, { ...options, token }) };
}
