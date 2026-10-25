// A fetch that sends a request again after a transient failure, for scripts
// that run from a copy of their own directory (collect-base-activity) and so
// cannot import the shared client in actions/check-trusted-trigger.
// apply-patch/, pr-unblock/ and work-resolve-issue/ each hold this same file;
// work-resolve-issue/retry-fetch.test.mjs keeps the copies equal.
//
// A request that fails on the network (undici's "fetch failed", or a cause
// code such as ECONNRESET or UND_ERR_SOCKET) or that GitHub answers 5xx is
// sent again, at most 3 attempts in all, after a full-jitter wait: a random
// share of 4 s, then of 8 s, as enable-auto-merge.mjs's RETRY_CAPS_MS. A GET
// and a GraphQL query are reads and always qualify. Any other write qualifies
// only when the caller passes safeToResend, because it repeats to the same
// state or carries a precondition (an expected head or SHA). A 4xx is
// returned, and any other error raised, at once. A retry line names an
// error's name and cause code, never its message: undici puts a whole header
// value, the token included, in some messages.

const RETRY_CAPS_MS = [4000, 8000];

export const networkError = (error) =>
  error?.name === "TimeoutError" ||
  error?.name === "AbortError" ||
  (error?.name === "TypeError" && error.message === "fetch failed") ||
  typeof error?.cause?.code === "string";

// A POST to /graphql whose query is a query operation (or the `{ ... }`
// shorthand) and names no mutation or subscription anywhere: a read.
// Anything else, a body that does not parse included, is a write.
export function isGraphQLRead(url, init = {}) {
  if (init.method !== "POST" || !/\/graphql$/.test(String(url)) || typeof init.body !== "string") {
    return false;
  }
  try {
    const query = JSON.parse(init.body)?.query;
    const text = typeof query === "string" ? query.replace(/#[^\n]*/g, "").trim() : "";
    return /^(query\b|\{)/.test(text) && !/\b(mutation|subscription)\b/.test(text);
  } catch {
    return false;
  }
}

const label = (error) =>
  [error?.name ?? "Error", typeof error?.cause?.code === "string" ? error.cause.code : null].filter(Boolean).join(" ");

export function retryFetch(
  fetchImpl,
  { sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), random = Math.random, log = (line) => console.log(line) } = {},
) {
  return async function send(url, { safeToResend = false, ...init } = {}) {
    const method = init.method ?? "GET";
    const resend = method === "GET" || safeToResend || isGraphQLRead(url, init);
    for (let attempt = 0; ; attempt += 1) {
      let response;
      let error;
      try {
        response = await fetchImpl(url, init);
      } catch (thrown) {
        error = thrown;
      }
      const cap = RETRY_CAPS_MS[attempt];
      const failed = error !== undefined ? networkError(error) : response.status >= 500;
      if (!failed || !resend || cap === undefined) {
        if (error !== undefined) {
          throw error;
        }
        return response;
      }
      await response?.body?.cancel().catch(() => {});
      const wait = Math.round(random() * cap);
      const what = error !== undefined ? `failed (${label(error)})` : `answered ${response.status}`;
      log(`::warning::${method} ${url} ${what}; sending it again in ${wait} ms (retry ${attempt + 1} of ${RETRY_CAPS_MS.length})`);
      await sleep(wait);
    }
  };
}
