// A fetch wrapper the dispatchers' GitHub adapters share. It counts the calls
// a run makes, keeps the x-ratelimit-* headers of the last response per
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
// A rate limit is the rate guard's (rate-guard.mjs, through
// retryServerErrors): its latch stops the pool until the reset, fails the step
// and refuses every later call to that pool before then. Here the call that
// hit it waits out the reset once and is sent once more, as GitHub allows: "you
// should not make another request until after the time specified by the
// x-ratelimit-reset header", and for retry-after "until after that many
// seconds has elapsed"
// (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#handle-rate-limit-errors-appropriately).
// maxWaitMs caps the waits of the whole run, summed, so the job fits its
// timeout: a wait that does not fit is not taken, the response is returned at
// once, and an error line names the reset. A second rate limit after the wait
// is returned as it is, and the latch refuses what follows. Either response it
// gives up on carries rateLimited: true, so a caller can defer its work
// instead of failing. A GET or GraphQL query
// answered 5xx is first sent again by retryServerErrors, so only its last
// answer reaches the above; serverFailure tells a caller it still failed.

import { retryServerErrors } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { rateLimitLatch, resetLabel, SIGNALS } from "../../actions/log-api-budget/rate-guard.mjs";

export function budgetedFetch({
  fetch: rawFetch = globalThis.fetch,
  log = (line) => console.log(line),
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now = () => Date.now(),
  random,
  maxWaitMs = 6 * 60 * 1000,
  latch = rateLimitLatch,
} = {}) {
  const fetch = retryServerErrors(rawFetch, { sleep, random, log, now, latch });
  const seen = new Map();
  const counts = { rest: 0, notModified: 0, graphql: 0 };
  const last = new Map();
  let waited = 0;

  async function wrapped(url, init = {}) {
    const response = await send(url, init);
    const until = latch.until(url);
    if (until === null || !(await refused(response))) {
      return response;
    }
    const wait = Math.max(0, until * 1000 - now()) + 1000;
    if (waited + wait > maxWaitMs) {
      log(
        `::error::rate limited on ${init.method ?? "GET"} ${url}: the limit resets ${resetLabel(until)},` +
          ` past this run's ${Math.round(maxWaitMs / 1000)}s wait budget (${Math.round(waited / 1000)}s already waited)`,
      );
      return Object.assign(response, { rateLimited: true });
    }
    log(`::notice::rate limited; waiting ${Math.ceil(wait / 1000)}s for the reset, then sending once more`);
    waited += wait;
    await sleep(wait);
    const again = await send(url, init);
    return latch.until(url) === null || !(await refused(again)) ? again : Object.assign(again, { rateLimited: true });
  }

  // GitHub refused this request: a rate-limit status, or a GraphQL 200 whose
  // errors name the limit. A 200 that spent the last request is not resent.
  async function refused(response) {
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

  async function send(url, init) {
    const method = init.method ?? "GET";
    const graphql = String(url).endsWith("/graphql");
    const cached = method === "GET" ? seen.get(String(url)) : undefined;
    const headers = cached ? { ...init.headers, "If-None-Match": cached.etag } : init.headers;
    const response = await fetch(url, { ...init, headers });
    const header = (name) => response.headers?.get?.(name) ?? null;
    const resource = header("x-ratelimit-resource");
    if (resource) {
      last.set(resource, ["limit", "remaining", "used", "reset"].map((key) => header(`x-ratelimit-${key}`)));
    }
    if (cached && response.status === 304) {
      counts.notModified += 1;
      return new Response(cached.body, { status: 200, headers: cached.headers });
    }
    counts[graphql ? "graphql" : "rest"] += 1;
    if (response.status === 403 || response.status === 429) {
      let message;
      try {
        message = String(JSON.parse(await response.clone().text()).message ?? "");
      } catch {
        message = "";
      }
      log(
        `::warning::${method} returned ${response.status}: message=${JSON.stringify(message.slice(0, 200))}` +
          ` retry-after=${header("retry-after") ?? "none"} remaining=${header("x-ratelimit-remaining") ?? "none"}`,
      );
    }
    const etag = header("etag");
    if (method === "GET" && response.status === 200 && etag) {
      seen.set(String(url), { etag, body: await response.clone().text(), headers: [...response.headers] });
    }
    return response;
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

  return { fetch: wrapped, counts, summary };
}

// Whether a thrown read error is a GitHub 5xx that outlasted retryServerErrors:
// an outage, so a dispatcher skips that PR for a later run instead of failing.
// A rate limit is never one.
export const serverFailure = (error) => error?.rateLimited !== true && error?.status >= 500;
