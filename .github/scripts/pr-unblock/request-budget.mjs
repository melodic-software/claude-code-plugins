// A fetch wrapper the dispatchers' GitHub adapters share. It counts the calls
// a run makes, keeps the x-ratelimit-* headers of the last response per
// resource (the headers are the authoritative reading, per
// https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
// and appends each one for the job-end api-budget notice (api-budget.mjs),
// logs the message and retry-after of a 403 or 429 so a secondary limit can be
// told from a primary one, and repeats a GET of a URL it already read as a
// conditional request: a 304 "does not count against your primary rate limit"
// when the request is authorized
// (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests),
// and the first response's body is returned for it.
//
// A rate-limited 403 or 429 waits, then is sent once more, in the order GitHub
// documents (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#handle-rate-limit-errors-appropriately):
// retry-after seconds when present, else until one second past
// x-ratelimit-reset when remaining is 0, else one minute. It is a rate limit
// when retry-after is present, remaining is 0, or the message names a rate
// limit; "Resource not accessible by integration" and other refusals are not
// waited on. maxWaitMs caps the waits of the whole run, summed, so the job
// fits its timeout: a wait that does not fit is not taken, the response is
// returned at once, and an error line names the reset. A second rate limit
// after the wait is returned as it is. The same policy as ci-workflows'
// pr-require-checks gh-api.sh. A GET answered 5xx is first sent again by
// createGitHub's retryServerErrors, so only its last answer reaches the above.

import { retryServerErrors } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { recordReading } from "../../actions/log-api-budget/api-budget.mjs";

const RATE_LIMIT_MESSAGE = /rate limit/i;

export function budgetedFetch({
  fetch: rawFetch = globalThis.fetch,
  log = (line) => console.log(line),
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now = () => Date.now(),
  random,
  maxWaitMs = 6 * 60 * 1000,
} = {}) {
  const fetch = retryServerErrors(rawFetch, { sleep, random, log, now });
  const seen = new Map();
  const counts = { rest: 0, notModified: 0, graphql: 0 };
  const last = new Map();
  let waited = 0;

  async function wrapped(url, init = {}) {
    const [response, message] = await send(url, init);
    const wait = rateLimitWait(response.headers, message);
    if (wait === null) {
      return response;
    }
    if (waited + wait > maxWaitMs) {
      const reset = Number(response.headers?.get?.("x-ratelimit-reset"));
      const at = reset > 0 ? new Date(reset * 1000).toISOString().replace(".000Z", "Z") : `in ${Math.ceil(wait / 1000)}s`;
      log(
        `::error::rate limited on ${init.method ?? "GET"} ${url}: the limit resets ${at},` +
          ` past this run's ${Math.round(maxWaitMs / 1000)}s wait budget (${Math.round(waited / 1000)}s already waited)`,
      );
      return response;
    }
    log(`::notice::rate limited; waiting ${Math.ceil(wait / 1000)}s, then sending once more`);
    waited += wait;
    await sleep(wait);
    return (await send(url, init))[0];
  }

  function rateLimitWait(headers, message) {
    if (message === null) {
      return null;
    }
    const retryAfter = Number.parseInt(headers?.get?.("retry-after") ?? "", 10);
    if (Number.isSafeInteger(retryAfter) && retryAfter >= 0) {
      return retryAfter * 1000;
    }
    const reset = Number.parseInt(headers?.get?.("x-ratelimit-reset") ?? "", 10);
    if (headers?.get?.("x-ratelimit-remaining") === "0" && Number.isSafeInteger(reset)) {
      return Math.max(0, reset * 1000 - now()) + 1000;
    }
    if (headers?.get?.("x-ratelimit-remaining") === "0" || RATE_LIMIT_MESSAGE.test(message)) {
      return 60 * 1000;
    }
    return null;
  }

  async function send(url, init) {
    const method = init.method ?? "GET";
    const graphql = String(url).endsWith("/graphql");
    const cached = method === "GET" ? seen.get(String(url)) : undefined;
    const headers = cached ? { ...init.headers, "If-None-Match": cached.etag } : init.headers;
    const response = await fetch(url, { ...init, headers });
    const header = (name) => response.headers?.get?.(name) ?? null;
    const resource = header("x-ratelimit-resource");
    recordReading({ status: response.status, headers: response.headers });
    if (resource) {
      last.set(resource, ["limit", "remaining", "used", "reset"].map((key) => header(`x-ratelimit-${key}`)));
    }
    if (cached && response.status === 304) {
      counts.notModified += 1;
      return [new Response(cached.body, { status: 200, headers: cached.headers }), null];
    }
    counts[graphql ? "graphql" : "rest"] += 1;
    // The message of a 403 or 429, null for any other status.
    let message = null;
    if (response.status === 403 || response.status === 429) {
      const text = await response.clone().text();
      try {
        message = String(JSON.parse(text).message ?? "");
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
    return [response, message];
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
