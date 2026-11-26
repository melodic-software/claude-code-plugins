import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";

const RETRY_CAPS_MS = [4000, 8000];
const RATE_WAIT_BUDGET_MS = 60_000;
const SECONDARY_WAIT_MS = 60_000;

export async function rateLimitWait(response, now = Date.now) {
  if (response?.status !== 403 && response?.status !== 429) return null;
  const header = (name) => response.headers?.get?.(name) ?? null;
  const retryAfter = header("retry-after");
  if (/^\d+$/.test(retryAfter ?? "")) return Number(retryAfter) * 1000;
  if (header("x-ratelimit-remaining") === "0") {
    const reset = header("x-ratelimit-reset");
    return /^\d+$/.test(reset ?? "") ? Math.max(0, Number(reset) * 1000 - now()) : null;
  }
  if (response.status === 429) return SECONDARY_WAIT_MS;
  let text = "";
  try {
    text = typeof response.clone === "function" ? await response.clone().text() : "";
  } catch {
  }
  return /secondary rate limit/i.test(text) ? SECONDARY_WAIT_MS : null;
}

export const networkError = (error) =>
  error?.name === "TimeoutError" ||
  error?.name === "AbortError" ||
  (error?.name === "TypeError" && error.message === "fetch failed") ||
  typeof error?.cause?.code === "string";

export function isGraphQLRead(url, init = {}) {
  if (init.method !== "POST" || !/\/graphql$/.test(String(url)) || typeof init.body !== "string") {
    return false;
  }
  try {
    const query = JSON.parse(init.body)?.query;
    const text = typeof query === "string" ? query.replace(/#[^\n]*/g, "").trim() : "";
    return /^(query\b|\{)/.test(text) && !/\b(mutation|subscription)\b/.test(query);
  } catch {
    return false;
  }
}

const TAG_REF_PATH = /^(\/api\/v3)?\/repos\/[^/]+\/[^/]+\/git\/ref\/tags\/./;

export function recordFailure({ method, url, status, dir = process.env.RUNNER_TEMP }) {
  if (!dir) return;
  try {
    const path = new URL(String(url?.url ?? url), "https://api.github.com").pathname;
    const verb = String(method ?? "GET").toUpperCase();
    if (verb === "GET" && status === 404 && TAG_REF_PATH.test(path)) return;
    mkdirSync(join(dir, "lane-run-report"), { recursive: true });
    appendFileSync(join(dir, "lane-run-report", "api-failures.jsonl"), `${JSON.stringify({ method: String(method ?? "GET").toUpperCase(), path, status })}\n`);
  } catch {
  }
}

const label = (error) =>
  [error?.name ?? "Error", typeof error?.cause?.code === "string" ? error.cause.code : null].filter(Boolean).join(" ");

export function retryFetch(
  fetchImpl,
  {
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    random = Math.random,
    log = (line) => console.log(line),
    now = Date.now,
    failureDir,
  } = {},
) {
  let rateWaited = 0;
  const counted = Boolean(fetchImpl?.[Symbol.for("api-budget.counted")]);
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
      const limit = error === undefined && resend && !counted && cap !== undefined ? await rateLimitWait(response, now) : null;
      const limited = limit !== null && rateWaited + limit <= RATE_WAIT_BUDGET_MS;
      const failed = error !== undefined ? networkError(error) : response.status >= 500 || limited;
      if (!failed || !resend || cap === undefined) {
        const dir = failureDir ?? process.env.RUNNER_TEMP;
        if (error !== undefined) {
          recordFailure({ method, url, status: 0, dir });
          throw error;
        }
        if (response.status >= 400 && !counted) {
          recordFailure({ method, url, status: response.status, dir });
        }
        return response;
      }
      await response?.body?.cancel().catch(() => {});
      const wait = limited ? limit : Math.round(random() * cap);
      rateWaited += limited ? limit : 0;
      const what = error !== undefined ? `failed (${label(error)})` : `answered ${response.status}${limited ? " on a rate limit" : ""}`;
      log(`::warning::${method} ${url} ${what}; sending it again in ${wait} ms (retry ${attempt + 1} of ${RETRY_CAPS_MS.length})`);
      await sleep(wait);
    }
  };
}

export function retryApi({ fetch, apiUrl, token, sleep }) {
  const send = retryFetch(fetch, { sleep });
  return async (method, path, body, { safeToResend = false, accept } = {}) => {
    const response = await send(`${apiUrl}${path}`, {
      method,
      safeToResend,
      headers: {
        Accept: accept ?? "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (!response.ok) {
      throw Object.assign(new Error(`${method} ${path} answered ${response.status}`), { status: response.status });
    }
    if (accept !== undefined) return response.text();
    return response.status === 204 ? null : response.json();
  };
}
