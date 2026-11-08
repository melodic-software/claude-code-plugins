// A fetch wrapper the dispatchers' GitHub adapters share. It counts each
// request a run sends, keeps the x-ratelimit-* headers of the last response per
// resource (the headers are the authoritative reading, per
// https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api;
// the rate guard under retryServerErrors appends each one for the job-end
// api-budget notice), logs the message and retry-after of a 403 or 429 so a secondary limit can be
// told from a primary one, and repeats a GET of a URL it already read as a
// conditional request: a 304 "does not count against your primary rate limit"
// when the request is authorized
// (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests),
// and the first response's body is returned for it.
//
// A rate limit is the rate guard's (rate-guard.mjs, through retryServerErrors
// with resendLimited): its latch stops the pool until the reset. A read (a GET
// or a GraphQL query, retryServerErrors' graphqlQuery) that hit it is sent
// again once the reset passes, as GitHub allows: "you should not make another
// request until after the time specified by the x-ratelimit-reset header", and
// for retry-after "until after that many seconds has elapsed"
// (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#handle-rate-limit-errors-appropriately).
// That happens inside the read's 3 attempts and only while the resets the latch
// waited out, summed, fit its minute (SERVER_RETRY_BUDGET_MS), and the guard
// fails nothing for a refusal it resends. Any other call is a write the outage
// posture never resends (docs/conventions/pr-pipeline/README.md#outage-posture, element 1). A refusal
// that is not resent carries rateLimited: true, so a caller can defer its work
// instead of failing; the guard fails the step on it unless the step holds
// (API_BUDGET_HOLD=1), and keeps the pool stopped until the reset. A
// GET or GraphQL query answered 5xx is first sent again by retryServerErrors,
// so only its last answer reaches the above; serverFailure tells a caller it
// still failed.

import { graphqlQuery, retryServerErrors } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { countsRequests, rateLimitLatch, refusedForLimit, resetLabel } from "../../actions/log-api-budget/rate-guard.mjs";

export function budgetedFetch({
  fetch: rawFetch = globalThis.fetch,
  log = (line) => console.log(line),
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now = () => Date.now(),
  random,
  latch = rateLimitLatch,
} = {}) {
  const seen = new Map();
  const counts = { rest: 0, notModified: 0, graphql: 0 };
  const last = new Map();

  // One request on the wire, a resend included.
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
  const fetch = retryServerErrors(observed, { sleep, random, log, now, latch, resendLimited: true });

  async function wrapped(url, init = {}) {
    const method = init.method ?? "GET";
    const cached = method === "GET" ? seen.get(String(url)) : undefined;
    const headers = cached ? { ...init.headers, "If-None-Match": cached.etag } : init.headers;
    const response = await fetch(url, { ...init, headers });
    if (cached && response.status === 304) {
      return new Response(cached.body, { status: 200, headers: cached.headers });
    }
    const etag = response.headers?.get?.("etag");
    if (method === "GET" && response.status === 200 && etag) {
      seen.set(String(url), { etag, body: await response.clone().text(), headers: [...response.headers] });
    }
    const until = latch.until(url);
    if (until === null || !(await refusedForLimit(response))) {
      return response;
    }
    if (method !== "GET" && !(method === "POST" && graphqlQuery(url, init))) {
      log(`::error::rate limited on ${method} ${url}: a write is not sent again; the limit resets ${resetLabel(until)}`);
    }
    return Object.assign(response, { rateLimited: true });
  }

  // One line in the pr-merge rate line's shape: counts, then each resource's
  // last header reading.
  function summary() {
    const readings = [...last].map(([resource, [limit, remaining, used, reset]]) => {
      const at = Number(reset) > 0 ? new Date(Number(reset) * 1000).toISOString().replace(".000Z", "Z") : "unknown";
      return `${resource} remaining=${remaining} used=${used} limit=${limit} reset=${at}`;
    });
    return [`api-calls rest=${counts.rest} not-modified=${counts.notModified} graphql=${counts.graphql}`, ...readings].join(" ");
  }

  // retryServerErrors counts each attempt, so a factory handed this fetch
  // counts nothing more (countRequests).
  return { fetch: countsRequests(wrapped), counts, summary };
}

// Whether a thrown read error is a GitHub 5xx that outlasted retryServerErrors:
// an outage, so a dispatcher skips that PR for a later run instead of failing.
// A rate limit is never one.
export const serverFailure = (error) => error?.rateLimited !== true && error?.status >= 500;
