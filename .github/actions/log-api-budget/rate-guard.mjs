// The one GitHub API rate guard. createGitHub and retryServerErrors
// (check-trusted-trigger.mjs) send every attempt through a latch, so
// budgetedFetch (request-budget.mjs) and every createGitHub caller share it;
// api-budget.bash's gh wrapper is its shell twin.
//
// GitHub: "Continuing to make requests while you are rate limited may result
// in the banning of your integration"
// (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#exceeding-the-rate-limit).
// So once a response shows a pool exhausted, the latch sends no further call
// to that pool before its reset for the rest of the process, logs an error
// naming the reset, and the process exits red. The stop also goes in the
// job's stop file, so later steps, the gh wrapper's included, keep it. A response under the pool's
// read-floor share of its planned budget left (planOf) logs a warning once;
// belowFloor lets a caller skip a read it can do without. The stop reads only
// the header's remaining and GitHub's refusals, never the plan.
//
// The margins are limits.api in pr-pipeline.yaml, read from resolve-config's
// output (RESOLVED_CONFIG), over the defaults in pr-pipeline.schema.json,
// which this module reads at load: the schema holds the only copy.
// rate-guard.vectors.json pins classify's decisions for every port.

import { appendFileSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";

// GitHub's documented rate-limit signals, same page: a 403 or 429 whose
// message names a rate limit, retry-after, x-ratelimit-remaining 0, and
// "wait for at least one minute" when neither header gives the time. GraphQL
// answers its primary limit with a 200 whose errors carry this type. Any 429
// counts, whatever its headers and message. "abuse detection" is the older
// wording of a secondary limit. A secondary limit with no time waits the
// minute; any other limit with no time, or with a reset already past, could
// hold to its window's end, so it stops for primaryFallbackSeconds, past any
// primary reset (a primary window is one hour).
export const SIGNALS = Object.freeze({
  statuses: Object.freeze([403, 429]),
  message: /rate limit|abuse detection/i,
  secondary: /secondary rate limit|abuse detection/i,
  graphqlErrorType: "RATE_LIMITED",
  fallbackSeconds: 60,
  primaryFallbackSeconds: 3600,
});

const MAX_RESET = 999_999_999_999;

export const API_POOLS = Object.freeze(["github-token", "lanes-app", "graphql", "owner-token", "content-creation"]);

const SCHEMA = new URL("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json", import.meta.url);

const defaultsOf = (properties) =>
  Object.fromEntries(
    Object.entries(properties)
      .filter(([, property]) => "default" in property)
      .map(([key, property]) => [key, property.default]),
  );

// limits.api with every unset field filled from the schema's defaults: the
// pool's $defs entry, then the entry's own default (github-token's
// limit-cap). Throws when the schema cannot be read.
export function apiLimits({ resolvedPath = process.env.RESOLVED_CONFIG, schemaPath = SCHEMA } = {}) {
  const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  const defs = schema.$defs;
  const entries = schema.properties.limits.properties.api.properties;
  const pool = defaultsOf(defs["api-pool"].properties);
  const content = { ...pool, ...defaultsOf(defs["api-content-pool"].properties) };
  let set = {};
  if (resolvedPath) {
    try {
      set = JSON.parse(readFileSync(resolvedPath, "utf8"))?.limits?.api ?? {};
    } catch {
      set = {};
    }
  }
  return Object.fromEntries(
    API_POOLS.map((name) => [name, { ...(name === "content-creation" ? content : pool), ...entries[name]?.default, ...(set[name] ?? {}) }]),
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

export function readingLine(status, headers) {
  const values = Object.entries(READING).map(([key, re]) => {
    const value = String(headers?.get?.(`x-ratelimit-${key}`) ?? "");
    return re.test(value) ? value : "na";
  });
  return `${status} ${values.join(" ")}\n`;
}

export function recordReading({ token = process.env.API_BUDGET_TOKEN, dir = process.env.RUNNER_TEMP, status, headers }) {
  if (!dir || !/^[a-z][a-z0-9-]{0,39}$/.test(token ?? "")) {
    return;
  }
  try {
    mkdirSync(join(dir, "api-budget"), { recursive: true });
    appendFileSync(join(dir, "api-budget", token), readingLine(status, headers));
  } catch {
    // A reading is never worth failing the job.
  }
}

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
// refusals latch.
// headers is a Headers or a plain object of lower-case names; body is the
// parsed body, or its text.
export function classify({ url, status, headers, body }, { now = Date.now(), readFloor = null, limitCap = null } = {}) {
  const get = typeof headers?.get === "function" ? (name) => headers.get(name) : (name) => headers?.[name];
  let parsed = body;
  if (typeof body === "string") {
    try {
      parsed = JSON.parse(body);
    } catch {
      parsed = null;
    }
  }
  const remaining = intHeader(get, "x-ratelimit-remaining");
  const limit = intHeader(get, "x-ratelimit-limit");
  const reset = intHeader(get, "x-ratelimit-reset");
  const retryAfter = intHeader(get, "retry-after");
  const errors = Array.isArray(parsed?.errors) ? parsed.errors : [];
  // GraphQL answers a secondary limit with a 200 or a 403 and an error
  // message (https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api#exceeding-the-rate-limit),
  // so for a GraphQL call any status counts.
  const messages = [parsed?.message, ...(poolOf(url) === "graphql" ? errors.map((error) => error?.message) : [])].map((text) => String(text ?? ""));
  const flagged = SIGNALS.statuses.includes(status) || poolOf(url) === "graphql";
  const message = flagged && messages.some((text) => SIGNALS.message.test(text));
  const secondary = flagged && messages.some((text) => SIGNALS.secondary.test(text));
  const graphql = errors.some((error) => error?.type === SIGNALS.graphqlErrorType);
  const tooMany = status === 429;
  const latched = remaining === 0 || retryAfter !== null || message || graphql || tooMany;
  const plan = limit > 0 && remaining !== null ? planOf({ limit, remaining }, limitCap) : null;
  const low = readFloor !== null && plan !== null && plan.left < readFloor * plan.planned;
  if (!latched) {
    return { latched, low, reset_source: null, reset: null, pool: null };
  }
  const nowSeconds = Math.floor(now / 1000);
  const candidates = [
    retryAfter !== null ? [nowSeconds + retryAfter, "retry-after"] : null,
    remaining === 0 && reset !== null ? [reset, "x-ratelimit-reset"] : null,
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

export const resetLabel = (seconds) => new Date(seconds * 1000).toISOString().replace(".000Z", "Z");
const poolLabel = (pool) => (pool === "*" ? "API" : `${pool} API`);

export class RateLimitStop extends Error {
  constructor(what, pool, reset) {
    super(`${what} was not sent: GitHub's ${poolLabel(pool)} rate limit holds until ${resetLabel(reset)}`);
    this.name = "RateLimitStop";
    this.status = 429;
    // budgetedFetch's mark: a caller that defers its work on a rate limit
    // defers on a refused call too.
    this.rateLimited = true;
    this.pool = pool;
    this.reset = reset;
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

export function createRateLimitLatch({
  now = () => Date.now(),
  log = (line) => console.log(line),
  fail = failProcess,
  limits = () => apiLimits(),
  stopFile = STOP_FILE,
} = {}) {
  const stops = readStops(stopFile, log);
  const low = new Map();
  const warned = new Set();
  let config;
  function margin(pool, key) {
    if (config === undefined) {
      try {
        config = limits();
      } catch {
        config = null;
        log("::warning::rate guard: limits.api and its schema defaults could not be read; the read floor is not checked");
      }
    }
    const value = config?.[entryOf(pool)]?.[key];
    return typeof value === "number" ? value : null;
  }

  // The epoch second the url's pool is stopped until, or null.
  function until(url) {
    const at = Math.max(stops.get("*") ?? 0, stops.get(poolOf(url)) ?? 0);
    return at * 1000 > now() ? at : null;
  }

  function check(url, method = "GET") {
    const at = until(url);
    if (at === null) {
      return;
    }
    const stop = new RateLimitStop(`${method} ${url}`, stops.get(poolOf(url)) === at ? poolOf(url) : "*", at);
    log(`::error::${stop.message}`);
    fail();
    throw stop;
  }

  async function observe(url, response, method = "GET") {
    const pool = poolOf(url);
    const needsBody = SIGNALS.statuses.includes(response.status) || pool === "graphql";
    const body = needsBody ? await response.clone().text().catch(() => "") : null;
    const limitCap = margin(pool, "limit-cap");
    const verdict = classify({ url, status: response.status, headers: response.headers, body }, { now: now(), readFloor: margin(pool, "read-floor"), limitCap });
    low.set(pool, verdict.low);
    if (verdict.latched) {
      stops.set(verdict.pool, Math.max(stops.get(verdict.pool) ?? 0, verdict.reset));
      // The in-process stop holds either way; a later step only sees a
      // recorded one, so a failed write is named.
      let unrecorded = "";
      if (stopFile) {
        try {
          mkdirSync(dirname(stopFile), { recursive: true });
          appendFileSync(stopFile, `${verdict.pool} ${verdict.reset}\n`);
        } catch (error) {
          unrecorded = `; the stop could not be recorded in the job's stop file (${error?.code ?? error?.message}), so later steps do not see it`;
        }
      }
      log(
        `::error::${method} ${url} hit GitHub's ${poolLabel(verdict.pool)} rate limit (status ${response.status}):` +
          ` no call to it before ${resetLabel(verdict.reset)} (${verdict.reset_source}); this step fails${unrecorded}`,
      );
      fail();
    } else if (verdict.low && !warned.has(pool)) {
      warned.add(pool);
      const headers = response.headers;
      const [limit, remaining] = ["limit", "remaining"].map((name) =>
        Number(typeof headers?.get === "function" ? headers.get(`x-ratelimit-${name}`) : headers?.[`x-ratelimit-${name}`]),
      );
      const { planned, left } = planOf({ limit, remaining }, limitCap);
      log(`::warning::GitHub's ${pool} API has under its read floor left (${left} of the planned ${planned}; header remaining ${remaining} of ${limit}); reads continue`);
    }
    return verdict;
  }

  return {
    until,
    check,
    observe,
    belowFloor: (url) => low.get(poolOf(url)) === true,
    // A fetch that checks the latch before each request and reads each answer,
    // keeping its reading under API_BUDGET_TOKEN (recordReading). That one
    // name covers every guarded call in the process, so a step sets it only
    // when all its calls spend one token.
    guard: (fetchImpl) =>
      async function guarded(url, init = {}) {
        check(url, init.method);
        const response = await fetchImpl(url, init);
        recordReading({ status: response.status, headers: response.headers });
        await observe(url, response, init.method);
        return response;
      },
  };
}

// The process-wide latch every helper shares by default.
export const rateLimitLatch = createRateLimitLatch();
