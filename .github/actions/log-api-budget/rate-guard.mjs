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
// read-floor share left logs a warning once; belowFloor lets a caller skip a
// read it can do without.
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
// answers its primary limit with a 200 whose errors carry this type.
export const SIGNALS = Object.freeze({
  statuses: Object.freeze([403, 429]),
  message: /rate limit/i,
  graphqlErrorType: "RATE_LIMITED",
  fallbackSeconds: 60,
});

export const API_POOLS = Object.freeze(["github-token", "lanes-app", "graphql", "owner-token", "content-creation"]);

const SCHEMA = new URL("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json", import.meta.url);

const defaultsOf = (properties) =>
  Object.fromEntries(
    Object.entries(properties)
      .filter(([, property]) => "default" in property)
      .map(([key, property]) => [key, property.default]),
  );

// limits.api with every unset field filled from the schema's defaults. Throws
// when the schema cannot be read.
export function apiLimits({ resolvedPath = process.env.RESOLVED_CONFIG, schemaPath = SCHEMA } = {}) {
  const defs = JSON.parse(readFileSync(schemaPath, "utf8")).$defs;
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
    API_POOLS.map((name) => [name, { ...(name === "content-creation" ? content : pool), ...(set[name] ?? {}) }]),
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

const intHeader = (get, name) => {
  const value = String(get(name) ?? "");
  return /^\d{1,12}$/.test(value) ? Number(value) : null;
};

// One response's decision: latched (exhausted), the reset in epoch seconds
// and where it came from, the pool to stop ("*" for every pool: a secondary
// limit is not per resource), and low (under readFloor of the limit left).
// headers is a Headers or a plain object of lower-case names; body is the
// parsed body, or its text.
export function classify({ url, status, headers, body }, { now = Date.now(), readFloor = null } = {}) {
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
  const messages = [parsed?.message, ...(poolOf(url) === "graphql" ? errors.map((error) => error?.message) : [])];
  const message =
    (SIGNALS.statuses.includes(status) || poolOf(url) === "graphql") && messages.some((text) => SIGNALS.message.test(String(text ?? "")));
  const graphql = errors.some((error) => error?.type === SIGNALS.graphqlErrorType);
  const latched = remaining === 0 || retryAfter !== null || message || graphql;
  const low = readFloor !== null && limit > 0 && remaining !== null && remaining < readFloor * limit;
  if (!latched) {
    return { latched, low, reset_source: null, reset: null, pool: null };
  }
  const nowSeconds = Math.floor(now / 1000);
  const candidates = [
    retryAfter !== null ? [nowSeconds + retryAfter, "retry-after"] : null,
    remaining === 0 && reset !== null ? [reset, "x-ratelimit-reset"] : null,
  ].filter(Boolean);
  const [at, source] = candidates.length
    ? candidates.reduce((best, next) => (next[0] > best[0] ? next : best))
    : [nowSeconds + SIGNALS.fallbackSeconds, "fallback"];
  const resource = String(get("x-ratelimit-resource") ?? "");
  const every = retryAfter !== null || (message && remaining !== 0);
  const pool = every ? "*" : /^[a-z_]+$/.test(resource) ? resource : poolOf(url);
  return { latched, low, reset_source: source, reset: at, pool };
}

export const resetLabel = (seconds) => new Date(seconds * 1000).toISOString().replace(".000Z", "Z");
const poolLabel = (pool) => (pool === "*" ? "API" : `${pool} API`);

export class RateLimitStop extends Error {
  constructor(what, pool, reset) {
    super(`${what} was not sent: GitHub's ${poolLabel(pool)} rate limit holds until ${resetLabel(reset)}`);
    this.name = "RateLimitStop";
    this.status = 429;
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
// and appends its own, so one stop holds for the whole job.
const STOP_FILE = process.env.RUNNER_TEMP ? join(process.env.RUNNER_TEMP, "api-budget", "stop") : null;

function readStops(path) {
  const stops = new Map();
  let text = "";
  try {
    text = path ? readFileSync(path, "utf8") : "";
  } catch {
    text = "";
  }
  for (const [, pool, reset] of text.matchAll(/^([a-z_]+|\*) (\d{1,12})$/gm)) {
    stops.set(pool, Math.max(stops.get(pool) ?? 0, Number(reset)));
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
  const stops = readStops(stopFile);
  const low = new Map();
  const warned = new Set();
  let config;
  function readFloor(pool) {
    if (config === undefined) {
      try {
        config = limits();
      } catch {
        config = null;
        log("::warning::rate guard: limits.api and its schema defaults could not be read; the read floor is not checked");
      }
    }
    const value = config?.[entryOf(pool)]?.["read-floor"];
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
    const verdict = classify({ url, status: response.status, headers: response.headers, body }, { now: now(), readFloor: readFloor(pool) });
    low.set(pool, verdict.low);
    if (verdict.latched) {
      stops.set(verdict.pool, Math.max(stops.get(verdict.pool) ?? 0, verdict.reset));
      if (stopFile) {
        try {
          mkdirSync(dirname(stopFile), { recursive: true });
          appendFileSync(stopFile, `${verdict.pool} ${verdict.reset}\n`);
        } catch {
          // The in-process stop still holds.
        }
      }
      log(
        `::error::${method} ${url} hit GitHub's ${poolLabel(verdict.pool)} rate limit (status ${response.status}):` +
          ` no call to it before ${resetLabel(verdict.reset)} (${verdict.reset_source}); this step fails`,
      );
      fail();
    } else if (verdict.low && !warned.has(pool)) {
      warned.add(pool);
      log(`::warning::GitHub's ${pool} API has under its read floor left (remaining ${response.headers?.get?.("x-ratelimit-remaining")} of ${response.headers?.get?.("x-ratelimit-limit")}); non-essential reads stop`);
    }
    return verdict;
  }

  return {
    until,
    check,
    observe,
    belowFloor: (url) => low.get(poolOf(url)) === true,
    // A fetch that checks the latch before each request and reads each answer.
    guard: (fetchImpl) =>
      async function guarded(url, init = {}) {
        check(url, init.method);
        const response = await fetchImpl(url, init);
        await observe(url, response, init.method);
        return response;
      },
  };
}

// The process-wide latch every helper shares by default.
export const rateLimitLatch = createRateLimitLatch();
