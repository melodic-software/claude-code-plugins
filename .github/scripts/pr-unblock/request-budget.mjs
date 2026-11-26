import { conditionalReads, graphqlQuery, retryServerErrors } from "../lib/github-client.mjs";
import { countsRequests, rateLimitLatch, refusedForLimit, resetLabel } from "../../actions/log-api-budget/rate-guard.mjs";

// A 304 to a conditional request does not count against the primary limit; after a limit, wait for x-ratelimit-reset or retry-after.
// https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api
export function budgetedFetch({
  fetch: rawFetch = globalThis.fetch,
  log = (line) => console.log(line),
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now = () => Date.now(),
  random,
  latch = rateLimitLatch,
  floorGraceMs = 0,
} = {}) {
  const counts = { rest: 0, notModified: 0, graphql: 0 };
  const last = new Map();

  async function observed(url, init) {
    const response = await rawFetch(url, init);
    const header = (name) => response.headers?.get?.(name) ?? null;
    const resource = header("x-ratelimit-resource");
    if (resource) {
      last.set(resource, ["limit", "remaining", "used", "reset"].map((key) => header(`x-ratelimit-${key}`)));
    }
    counts[response.status === 304 ? "notModified" : String(url).endsWith("/graphql") ? "graphql" : "rest"] += 1;
    if (response.status === 403 || response.status === 429) {
      let message;
      try {
        message = String(JSON.parse(await response.clone().text()).message ?? "");
      } catch {
        message = "";
      }
      log(
        `::warning::${init.method ?? "GET"} returned ${response.status}: message=${JSON.stringify(message.slice(0, 200))}` +
          ` retry-after=${header("retry-after") ?? "none"} remaining=${header("x-ratelimit-remaining") ?? "none"}`,
      );
    }
    return response;
  }
  const fetch = conditionalReads(retryServerErrors(observed, { sleep, random, log, now, latch, resendLimited: true, floorGraceMs }));

  async function wrapped(url, init = {}) {
    const method = init.method ?? "GET";
    const response = await fetch(url, init);
    const until = latch.until(url);
    if (until === null || !(await refusedForLimit(response))) {
      return response;
    }
    if (method !== "GET" && !(method === "POST" && graphqlQuery(url, init))) {
      log(`::error::rate limited on ${method} ${url}: a write is not sent again; the limit resets ${resetLabel(until)}`);
    }
    return Object.assign(response, { rateLimited: true });
  }

  function summary() {
    const readings = [...last].map(([resource, [limit, remaining, used, reset]]) => {
      const at = Number(reset) > 0 ? new Date(Number(reset) * 1000).toISOString().replace(".000Z", "Z") : "unknown";
      return `${resource} remaining=${remaining} used=${used} limit=${limit} reset=${at}`;
    });
    return [`api-calls rest=${counts.rest} not-modified=${counts.notModified} graphql=${counts.graphql}`, ...readings].join(" ");
  }

  return { fetch: countsRequests(wrapped), counts, summary };
}

export const serverFailure = (error) => error?.rateLimited !== true && error?.status >= 500;
