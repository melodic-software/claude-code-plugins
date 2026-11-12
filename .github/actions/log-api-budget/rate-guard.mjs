// The one GitHub API rate guard. createGitHub and retryServerErrors
// (check-trusted-trigger.mjs) send every attempt through a latch, so
// budgetedFetch (request-budget.mjs) and every createGitHub caller share it;
// api-budget.bash's gh wrapper is its shell twin.
//
// GitHub: "Continuing to make requests while you are rate limited may result
// in the banning of your integration"
// (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#exceeding-the-rate-limit).
// So once a response shows a pool exhausted, the latch sends no further call
// to that pool before its reset for the rest of the process. A call that meets
// a stop whose reset is within SERVER_RETRY_BUDGET_MS of the process's waits,
// summed, waits for it and goes out, and a refused answer its client will send
// again after that wait (RESEND) fails nothing. Past that budget the call is refused: an
// error names the reset and the process exits red, or, when the step holds
// (API_BUDGET_HOLD=1, outage posture element 2), a notice names it and the
// exit is the caller's. The stop also goes in the
// job's stop file, so later steps, the gh wrapper's included, keep it. A response under the pool's
// read-floor share of its planned budget left (planOf) logs a warning once;
// belowFloor lets a caller skip a read it can do without. The stop reads only
// the header's remaining and limit and GitHub's refusals, never the plan: a
// remaining at or under the pool's stop-floor share of the header's limit
// stops the pool until its reset, as a remaining of 0 does.
//
// The margins are limits.api in pr-pipeline.yaml, read from resolve-config's
// output (RESOLVED_CONFIG), over the defaults in rate-limits.json beside this
// module: that file holds the only copy, and every hold list floors it, so a
// change to a default waits for a person.
// rate-guard.vectors.json pins classify's decisions for every port.

import { appendFileSync, mkdirSync, readFileSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";

// GitHub's documented rate-limit signals, same page: a 403 or 429 whose
// message names a rate limit, retry-after, x-ratelimit-remaining 0, and
// "wait for at least one minute" when neither header gives the time. GraphQL
// answers its primary limit with a 200 whose errors carry this type. Any 429
// counts, whatever its headers and message. "abuse detection" is the older
// wording of a secondary limit. A secondary limit with no time, or a limit
// whose header time is already past, waits the minute; any other limit with
// no time could hold to its window's end, so it stops for
// primaryFallbackSeconds, past any primary reset (a primary window is one
// hour).
export const SIGNALS = Object.freeze({
  statuses: Object.freeze([403, 429]),
  message: /rate limit|abuse detection/i,
  secondary: /secondary rate limit|abuse detection/i,
  graphqlErrorType: "RATE_LIMITED",
  fallbackSeconds: 60,
  primaryFallbackSeconds: 3600,
});

const MAX_RESET = 999_999_999_999;

// The 60 s wait budget: a client's 5xx retries (retryServerErrors) and,
// counted apart, a latch's rate-limit waits.
export const SERVER_RETRY_BUDGET_MS = 60_000;

export const API_POOLS = Object.freeze(["github-token", "lanes-app", "graphql", "owner-token", "content-creation"]);

const DEFAULTS = new URL("./rate-limits.json", import.meta.url);

// The values rate-limits.json ships, which the guard plans to when that file
// cannot be read, so a checkout that misses it still keeps every floor
// (rate-guard.test.mjs holds the two equal).
const SHARES = { plan: 0.7, "writer-pause": 0.4, breaker: 0.2, "read-floor": 0.1, "stop-floor": 0.02 };
export const BUILT_IN_LIMITS = Object.freeze({
  "github-token": { ...SHARES, "limit-cap": 1000, pace: 0.2, "start-gate": 0.1 },
  "lanes-app": SHARES,
  graphql: SHARES,
  "owner-token": SHARES,
  "content-creation": { ...SHARES, "per-minute": 80, "per-hour": 500 },
});

// Each field's check: the shares, then the counts. per-minute and per-hour
// belong to content-creation alone.
const SHARE = (value) => typeof value === "number" && value >= 0 && value <= 1;
const COUNT = (value) => Number.isInteger(value) && value >= 1;
// pace, optional, is pace.mjs's share for timer-driven lanes; stop-floor,
// optional, the share of the header's limit left at which the latch stops;
// start-gate, optional, check-kill-switch's share under which a lane does not
// start, which that gate reads from rate-limits.json alone.
const FIELDS = { plan: (value) => SHARE(value) && value > 0, "writer-pause": SHARE, breaker: SHARE, "read-floor": SHARE, "stop-floor": SHARE, "limit-cap": COUNT, pace: SHARE, "start-gate": SHARE };
const CONTENT_FIELDS = { ...FIELDS, "per-minute": COUNT, "per-hour": COUNT };
// Fields rate-limits.json holds that pr-pipeline.yaml's limits.api cannot set
// (its schema rejects them): their one reader takes the file's value alone.
export const FILE_ONLY_FIELDS = Object.freeze(["start-gate"]);
const REQUIRED = ["plan", "writer-pause", "breaker", "read-floor"];

// rate-limits.json, checked: every pool in API_POOLS and no other, each with
// the four shares, and every field in its range. Throws on anything else.
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

// apiLimits, falling back to BUILT_IN_LIMITS with a warning when
// rate-limits.json cannot be read, so no reader plans to nothing.
export function apiLimitsOrBuiltIn({ resolvedPath = process.env.RESOLVED_CONFIG, defaultsPath = DEFAULTS, log = (line) => console.log(line) } = {}) {
  try {
    return apiLimits({ resolvedPath, defaultsPath });
  } catch (error) {
    log(`::warning::rate-limits.json could not be read (${error?.code ?? error?.message}); planning to the built-in defaults, the values that file ships`);
    return apiLimits({ resolvedPath, defaultsPath: null });
  }
}

// limits.api with every unset field filled from rate-limits.json, or from
// BUILT_IN_LIMITS when defaultsPath is null. Throws when that file cannot be
// read or fails readDefaults' check.
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

// The resource a request spends, as x-ratelimit-resource names it.
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

// A write that creates or changes content GitHub's content-creation limit
// counts (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#about-secondary-rate-limits):
// the issues, pull requests, comments, reviews and labels the lanes write,
// and a GraphQL mutation. GitHub publishes no list of the endpoints it counts.
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

// The limits.api entry a resource's margins come from: graphql its own, any
// other the token's (API_BUDGET_TOKEN, as api-budget.mjs names it).
export const entryOf = (pool, token = process.env.API_BUDGET_TOKEN) =>
  pool === "graphql" ? "graphql" : API_POOLS.includes(token) ? token : "github-token";

// One rate-limit reading, from a response's x-ratelimit-* headers, in
// api-budget.bash's line shape, appended to $RUNNER_TEMP/api-budget/<token>
// for the job-end notice the log-api-budget action writes. `token` names the
// bucket (`github-token`, `lanes-app`); without it or RUNNER_TEMP nothing is
// written. It lives here, not in api-budget.mjs (which re-exports it), so the
// guard below keeps every call's reading without loading another module.
// Never throws.
const READING = { limit: /^\d+$/, remaining: /^\d+$/, used: /^\d+$/, reset: /^\d+$/, resource: /^[a-z_]+$/ };

export function readingLine(status, headers, route = "other") {
  const values = Object.entries(READING).map(([key, re]) => {
    const value = String(headers?.get?.(`x-ratelimit-${key}`) ?? "");
    return re.test(value) ? value : "na";
  });
  return `${status} ${values.join(" ")} ${routeOk(route) ? route : "other"}\n`;
}

// The GitHub REST path words a route, or a lane run report's failure row
// (lane-run-report/post.mjs), may show; any other segment could be a name, a
// path or planted text. api-budget.bash's API_BUDGET_ROUTE carries the same
// list (log-api-budget.test.mjs checks).
export const REST_PATH_WORDS = new Set(
  "api v3 repos orgs users user installation app graphql pulls issues comments reviews requested_reviewers git refs ref heads tags trees blobs commits compare merges merge check-runs check-suites statuses status labels assignees milestones events timeline actions runs jobs attempts artifacts logs rerun rerun-failed-jobs workflows dispatches variables secrets contents branches protection rules rulesets collaborators permission teams members hooks deployments environments releases search code reactions files rate_limit annotations repositories installations access_tokens pending_deployments cancel update-branch dismissals readme matching-refs languages notifications".split(" "),
);
export const PLACEHOLDERS = new Set(["{n}", "{sha}", "{repo}", "{x}"]);
// Whether a route has only path words and placeholders: what each writer and
// the job-end notice keep.
export const routeOk = (route) =>
  typeof route === "string" && route.length <= 80 && (route === "graphql" || route === "other" || route.split("/").every((seg) => REST_PATH_WORDS.has(seg) || PLACEHOLDERS.has(seg)));

// A request's URL as a route that holds no query, name or token, for the
// job-end api-routes notice; api-budget.bash's API_BUDGET_ROUTE is its twin.
// A URL on a host other than api.github.com and uploads.github.com is other,
// unless its path starts with /api/ (GHES); scheme, host, /api/v3,
// query and fragment go; a GraphQL path is graphql; repos/<owner>/<repo> is
// repos/{repo}; a number is {n}; hex of 7 or more characters {sha}; the
// segment after one that names a thing (labels/<name>) and every segment after
// one that starts a path or ref (contents/<path>) is {x} unless a number; a
// REST path word stays; any other segment is {x}.
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
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i];
    const placeholder = /^[0-9]+$/.test(seg) ? "{n}" : /^[0-9a-f]{7,}$/i.test(seg) ? "{sha}" : null;
    if (tail || name) {
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
    // A reading is never worth failing the job.
  }
}

// A 4xx or 5xx answer adds one {method, path, status} line to
// $RUNNER_TEMP/lane-run-report/api-failures.jsonl for the lane run report
// comment (pr-run-activity-read.yml and -write.yml): the URL's path only,
// never its query, headers or body. retry-fetch.mjs records the same way.
export function recordFailure({ method, url, status, dir = process.env.RUNNER_TEMP }) {
  if (!dir) {
    return;
  }
  try {
    const path = new URL(String(url?.url ?? url), "https://api.github.com").pathname;
    mkdirSync(join(dir, "lane-run-report"), { recursive: true });
    appendFileSync(join(dir, "lane-run-report", "api-failures.jsonl"), `${JSON.stringify({ method: String(method ?? "GET").toUpperCase(), path, status })}\n`);
  } catch {
    // A report row is never worth failing the job.
  }
}

// This process's share of the job-end api-calls notice: the readings it
// appended, counted as api_budget_emit_calls counts the file (N its non-304
// lines per token, M its 304s, K its graphql-resource lines). When
// API_BUDGET_SCRIPT names the step, the process ends with
// `::notice title=api-calls::script=<name> github-token=N lanes-app=N
// not-modified=M graphql=K`, so a job's total splits by step. A child
// process's calls (babysit's Python) are its own, not in this line.
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
      // A count is never worth failing the job.
    }
  });
}

// The bucket a request's reading goes under: token when the client pins one;
// else API_BUDGET_OVERRIDE_TOKEN for a request whose bearer is not the
// step's own token (GH_TOKEN, else GITHUB_TOKEN), as babysit_gh.py buckets a
// call carrying its own GH_TOKEN; else API_BUDGET_TOKEN.
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

// A fetch that keeps each answer's rate-limit reading (recordReading) under
// budgetToken's bucket, for the job-end api-calls notice, and changes nothing
// else. Every client factory sends its attempts through one, inside its retry
// layer. A fetch that already counts (marked with countsRequests) comes back
// as it is, so no request is counted twice.
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

// Appends one content-creating write, as its epoch second, to
// $RUNNER_TEMP/api-budget/content-creation, which api-budget.bash's gh wrapper
// also appends to, for the job-end content-creation notice. Without
// RUNNER_TEMP nothing is written. Never throws.
export function recordContentWrite({ dir = process.env.RUNNER_TEMP, at }) {
  if (!dir || !Number.isSafeInteger(at)) {
    return;
  }
  try {
    mkdirSync(join(dir, "api-budget"), { recursive: true });
    appendFileSync(join(dir, "api-budget", "content-creation"), `${at}\n`);
  } catch {
    // A count is never worth failing the job.
  }
}

// A name-to-value reader over a Headers or a plain object of lower-case names.
const headerReader = (headers) => (typeof headers?.get === "function" ? (name) => headers.get(name) : (name) => headers?.[name]);

const intHeader = (get, name) => {
  const value = String(get(name) ?? "");
  return /^\d{1,12}$/.test(value) ? Number(value) : null;
};

// The budget a pool plans to: the header's limit, at most limitCap (null for
// none). used is what the header says this window spent, and left what the
// plan has after it, below zero once used passes the plan.
export function planOf({ limit, remaining }, limitCap = null) {
  const planned = limitCap === null ? limit : Math.min(limit, limitCap);
  const used = limit - remaining;
  return { planned, used, left: planned - used };
}

// One response's decision: latched (exhausted), the reset in epoch seconds
// and where it came from, the pool to stop ("*" for every pool: a secondary
// limit is not per resource), and low (under readFloor of the planned budget
// left, planOf with limitCap). Only the header's remaining and GitHub's
// refusals latch: a remaining of 0, or, with stopFloor, a remaining at or under
// stopFloor of the header's limit whose header reset is still ahead.
// headers is a Headers or a plain object of lower-case names; body is the
// parsed body, or its text.
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

// Whether a response's stop has a Retry-After on a 5xx as its only cause: no
// x-ratelimit-remaining of 0, no message naming a rate limit or abuse
// detection, and no RATE_LIMITED error, whatever the call. GitHub documents
// its rate limits as 403 or 429 answers (REST) and 200 or 403 (GraphQL), so
// such a stop holds as long as classify says but is reported as a server
// error. babysit_gh.py server_error_hold is its twin; rate-guard.vectors.json's
// server_error pins both.
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

export function classify({ url, status, headers, body }, { now = Date.now(), readFloor = null, limitCap = null, stopFloor = null } = {}) {
  const get = headerReader(headers);
  const graphqlPool = poolOf(url) === "graphql";
  const parsed = parseBody(body);
  const remaining = intHeader(get, "x-ratelimit-remaining");
  const limit = intHeader(get, "x-ratelimit-limit");
  const reset = intHeader(get, "x-ratelimit-reset");
  const retryAfter = intHeader(get, "retry-after");
  const errors = Array.isArray(parsed?.errors) ? parsed.errors : [];
  // GraphQL answers a secondary limit with a 200 or a 403 and an error
  // message (https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api#exceeding-the-rate-limit),
  // so for a GraphQL call any status counts.
  const messages = [parsed?.message, ...(graphqlPool ? errors.map((error) => error?.message) : [])].map((text) => String(text ?? ""));
  const flagged = SIGNALS.statuses.includes(status) || graphqlPool;
  const message = flagged && messages.some((text) => SIGNALS.message.test(text));
  const secondary = flagged && messages.some((text) => SIGNALS.secondary.test(text));
  const graphql = errors.some((error) => error?.type === SIGNALS.graphqlErrorType);
  const tooMany = status === 429;
  const floored = stopFloor !== null && limit > 0 && remaining !== null && reset !== null && reset * 1000 > now && remaining <= stopFloor * limit;
  const latched = remaining === 0 || floored || retryAfter !== null || message || graphql || tooMany;
  const plan = limit > 0 && remaining !== null ? planOf({ limit, remaining }, limitCap) : null;
  const low = readFloor !== null && plan !== null && plan.left < readFloor * plan.planned;
  if (!latched) {
    return { latched, low, reset_source: null, reset: null, pool: null };
  }
  const nowSeconds = Math.floor(now / 1000);
  const candidates = [
    retryAfter !== null ? [nowSeconds + retryAfter, "retry-after"] : null,
    (remaining === 0 || floored) && reset !== null ? [reset, "x-ratelimit-reset"] : null,
  ].filter(Boolean);
  const best = candidates.length ? candidates.reduce((top, next) => (next[0] > top[0] ? next : top)) : null;
  // A header time already past would write a stop that lets the next call go.
  const [at, source] =
    best && best[0] > nowSeconds
      ? best
      : [nowSeconds + (best || secondary ? SIGNALS.fallbackSeconds : SIGNALS.primaryFallbackSeconds), "fallback"];
  const resource = String(get("x-ratelimit-resource") ?? "");
  // A secondary limit is not per resource, whatever remaining says.
  const every = retryAfter !== null || secondary || ((message || tooMany) && remaining !== 0);
  const pool = every ? "*" : /^[a-z_]+$/.test(resource) ? resource : poolOf(url);
  // Stop-file readers take at most 12 digits, so a later stop is written at
  // the largest they read.
  return { latched, low, reset_source: source, reset: Math.min(at, MAX_RESET), pool };
}

// The stop an answer's headers set whatever its body says, or null: the
// headers alone latch with a time a header gave (Retry-After, or
// x-ratelimit-reset at remaining 0 or the stop floor). classify takes that
// time from the headers only, and a body only ORs in signals, so with any
// body classify returns the same reset and this pool or `*`, which holds it
// too. With no header time (a 403 or 429 the body decides, a GraphQL
// RATE_LIMITED), the body sets the fallback, so there is none.
export function headerStop({ url, status, headers }, options) {
  const verdict = classify({ url, status, headers, body: null }, options);
  return verdict.latched && verdict.reset_source !== "fallback" ? { pool: verdict.pool, reset: verdict.reset } : null;
}

export const resetLabel = (seconds) => new Date(seconds * 1000).toISOString().replace(".000Z", "Z");
const poolLabel = (pool) => (pool === "*" ? "API" : `${pool} API`);

// serverStatus: the 5xx of a serverErrorHold, the same stop worded as a
// server error.
export class RateLimitStop extends Error {
  constructor(what, pool, reset, serverStatus = null) {
    super(
      serverStatus === null
        ? `${what} was not sent: GitHub's ${poolLabel(pool)} rate limit holds until ${resetLabel(reset)}`
        : `${what} was not sent: GitHub answered HTTP ${serverStatus} with a Retry-After; no call to it before ${resetLabel(reset)}`,
    );
    this.name = "RateLimitStop";
    this.status = 429;
    // budgetedFetch's mark: a caller that defers its work on a rate limit
    // defers on a refused call too.
    this.rateLimited = true;
    this.pool = pool;
    this.reset = reset;
  }
}

// The init key a client sets on a request it will send again after a rate
// limit the latch would wait out (observe's resend).
export const RESEND = Symbol.for("rate-guard.resend");

// GitHub refused the request for a rate limit: a 403 or 429, or an answer
// whose errors name the limit. A 200 that spent the last request stands.
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

// The step fails: an exit listener sets the code last, so a later
// `process.exitCode = await main()` or process.exit(0) cannot clear it.
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

// The job's stop file, which api-budget.bash's gh wrapper shares: lines
// `<pool> <reset epoch>`. A latch starts from the stops an earlier step wrote
// and appends its own, so one stop holds for the whole job. Every port reads
// only whole lines matching STOP_LINE, each ended by \n (rate-guard.vectors.json's
// stop_files), so a fragment a short write left spoils only the line it runs
// into. A file that is missing holds no stop; one that exists but cannot be
// read holds every pool until MAX_RESET (stop_file_errors), with an error.
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
  // Split on \n alone: a multiline $ would also end a line at \r. The last
  // piece has no \n after it, so it is never a line.
  for (const line of text.split("\n").slice(0, -1)) {
    const [, pool, reset] = STOP_LINE.exec(line) ?? [];
    if (pool) {
      stops.set(pool, Math.max(stops.get(pool) ?? 0, Number(reset)));
    }
  }
  return stops;
}

// The job's cause file beside the stop file: one line `<pool> <reset epoch>
// <cause>` per stop a port wrote, cause `limit` or `server-<5xx>` for a
// serverErrorHold. Read by STOP_LINE's rule (rate-guard.vectors.json's
// stop_causes); a missing or unreadable file holds no cause.
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

// The 5xx when every stop of `pools` that ends at `at` has a cause line of its
// own and each is a server error hold, else null: a stop with no cause line (a
// stop an older writer left), or a rate limit among them, reads as a rate
// limit, the safe reading.
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

// hold: a refusal logs a notice and leaves the exit to the caller, which must
// then hold (no write, no merge, green with a notice). A gate that holds green
// would pass what it could not read, so hold is for lanes only.
export function createRateLimitLatch({
  now = () => Date.now(),
  log = (line) => console.log(line),
  fail = failProcess,
  limits = () => apiLimitsOrBuiltIn({ log }),
  stopFile = STOP_FILE,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  hold = process.env.API_BUDGET_HOLD === "1",
} = {}) {
  const stops = readStops(stopFile, log);
  const causeFile = stopFile ? join(dirname(stopFile), "cause") : null;
  const causes = readCauses(causeFile);
  const low = new Map();
  const warned = new Set();
  // The resets waited out, summed; the extra second only lands the call after one.
  let waited = 0;
  let config;
  // A token-pinned guard plans to its own token's entry (entryOf).
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

  // The epoch second the url's pool is stopped until, or null.
  function until(url) {
    const at = Math.max(stops.get("*") ?? 0, stops.get(poolOf(url)) ?? 0);
    return at * 1000 > now() ? at : null;
  }

  // The pool whose stop holds url until `at`: its own, else "*".
  const heldBy = (url, at) => (stops.get(poolOf(url)) === at ? poolOf(url) : "*");

  // The 5xx when url's stop is a server error hold, else null (serverHeld).
  const serverStatus = (url) => serverHeld(causes, stops, [poolOf(url), "*"], until(url));

  const resetMs = (url) => {
    const at = until(url);
    return at === null ? null : Math.max(0, at * 1000 - now());
  };

  // Whether a call to url would wait out its pool's stop rather than be refused.
  const waits = (url) => {
    const reset = resetMs(url);
    return reset !== null && waited + reset <= SERVER_RETRY_BUDGET_MS;
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
    const stop = new RateLimitStop(`${method} ${url}`, heldBy(url, at), at, status);
    const title = status === null ? "" : " title=GitHub server error";
    if (hold) {
      log(`::notice${title}::${stop.message}; this step holds`);
    } else {
      log(`::error${title}::${stop.message}`);
      fail();
    }
    throw stop;
  }

  // resend: the client sends this request again if a rate limit refuses it
  // and the latch would wait (retryServerErrors' resendLimited), so such a
  // refusal fails nothing.
  async function observe(url, response, method = "GET", token = undefined, resend = false) {
    const pool = poolOf(url);
    // classify reads the body of a 403, a 429 and a GraphQL answer; a 5xx's
    // body is read only for serverErrorHold's cause, never for the stop.
    const classifiesBody = SIGNALS.statuses.includes(response.status) || pool === "graphql";
    const needsBody = classifiesBody || response.status >= 500;
    const limitCap = margin(pool, "limit-cap", token);
    const stopFloor = margin(pool, "stop-floor", token);
    const options = { now: now(), readFloor: margin(pool, "read-floor", token), limitCap, stopFloor };
    // The in-process stop holds either way; a later step only sees a
    // recorded one, so a failed write is named. Each distinct stop is set
    // and written once.
    const recorded = new Map();
    const record = ({ pool: held, reset }) => {
      const key = `${held} ${reset}`;
      if (!recorded.has(key)) {
        stops.set(held, Math.max(stops.get(held) ?? 0, reset));
        let failed = "";
        if (stopFile) {
          try {
            mkdirSync(dirname(stopFile), { recursive: true });
            appendFileSync(stopFile, `${key}\n`);
          } catch (error) {
            failed = `; the stop could not be recorded in the job's stop file (${error?.code ?? error?.message}), so later steps do not see it`;
          }
        }
        recorded.set(key, failed);
      }
      return recorded.get(key);
    };
    // A stop every body agrees on is set before any await, so a call in
    // flight beside this one is refused while the body is read.
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
      // Until the cause is in, a refusal reads this stop as a rate limit.
      causes.push({ pool: verdict.pool, reset: verdict.reset, cause });
      if (stopFile && !unrecorded) {
        try {
          appendFileSync(causeFile, `${verdict.pool} ${verdict.reset} ${cause}\n`);
        } catch {
          // Read as a rate limit, the safe reading.
        }
      }
      // A stop later steps cannot see is a fault, not a limit to hold on.
      const resent = !unrecorded && resend && waits(url) && refused;
      const holds = resent || (hold && !unrecorded);
      const then = resent ? "it is sent again after the reset" : `this step ${holds ? "holds" : "fails"}`;
      const what = floored
        ? `left GitHub's ${poolLabel(verdict.pool)} ${remaining} of ${limit} requests, at or under its stop-floor share ${stopFloor} (status ${response.status})`
        : server
          ? `got a GitHub server error, HTTP ${response.status} with a Retry-After`
          : `hit GitHub's ${poolLabel(verdict.pool)} rate limit (status ${response.status})`;
      const level = `${holds ? "::notice" : "::error"}${server ? " title=GitHub server error" : ""}::`;
      log(`${level}${method} ${url} ${what}: no call to it before ${resetLabel(verdict.reset)} (${verdict.reset_source}); ${then}${unrecorded}`);
      if (!holds) {
        fail();
      }
    } else if (verdict.low && !warned.has(pool)) {
      warned.add(pool);
      const get = headerReader(response.headers);
      const [limit, remaining] = ["limit", "remaining"].map((name) => Number(get(`x-ratelimit-${name}`)));
      const { planned, left } = planOf({ limit, remaining }, limitCap);
      log(`::warning::GitHub's ${pool} API has under its read floor left (${left} of the planned ${planned}; header remaining ${remaining} of ${limit}); reads continue`);
    }
    return verdict;
  }

  return {
    until,
    waits,
    check,
    observe,
    // Takes in the stops another process (a reader child) wrote to the job's
    // stop file since this latch started.
    reload() {
      for (const [pool, reset] of readStops(stopFile, log)) {
        stops.set(pool, Math.max(stops.get(pool) ?? 0, reset));
      }
      causes.push(...readCauses(causeFile));
    },
    serverStatus,
    belowFloor: (url) => low.get(poolOf(url)) === true,
    // Waits out url's stop when it fits the budget (with wait, the latch's own
    // sleep when unset), so a caller can wait before it starts its own timers.
    waitOut,
    // A fetch that waits out a stop that fits the budget (with sleep, the
    // latch's own when unset), checks the latch before each request, counts a
    // content-creating write, and reads each answer, keeping its rate-limit
    // reading under token (budgetToken when unset, countRequests), so a
    // second client's readings never mix with the first's.
    guard: (fetchImpl, { token, sleep: wait } = {}) => {
      const send = countRequests(fetchImpl, { token });
      return countsRequests(async function guarded(url, init = {}) {
        await waitOut(url, init.method ?? "GET", wait);
        check(url, init.method);
        if (isContentWrite(url, init.method, init.body)) {
          recordContentWrite({ at: Math.floor(now() / 1000) });
        }
        const response = await send(url, init);
        await observe(url, response, init.method, token, init[RESEND] === true);
        return response;
      });
    },
  };
}

// The process-wide latch every helper shares by default.
export const rateLimitLatch = createRateLimitLatch();

// latch with its guard pinned to token: a client on a second token keeps its
// readings under token and plans to token's limits.api entry (entryOf), not
// API_BUDGET_TOKEN's, while sharing latch's stops.
export function budgetLatch(token, latch = rateLimitLatch) {
  return { ...latch, guard: (fetchImpl, options = {}) => latch.guard(fetchImpl, { ...options, token }) };
}
