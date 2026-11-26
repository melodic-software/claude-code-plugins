import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { rateLimitLatch, refusedForLimit, RESEND, SERVER_RETRY_BUDGET_MS } from "../../actions/log-api-budget/rate-guard.mjs";

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** A call GitHub answered non-2xx: `status`, and `detail`, responseDetail's line, apart from the message. */
export class GitHubError extends Error {
  constructor(status, what, detail = "") {
    super(`${what} failed with status ${status}`);
    this.name = "GitHubError";
    this.status = status;
    this.detail = detail;
  }
}

export async function responseDetail(response) {
  const header = (name) => response.headers?.get?.(name) ?? null;
  let text = "";
  try {
    text = await response.clone().text();
  } catch {}
  const fields = [
    `status=${response.status}`,
    ...["remaining", "reset", "resource"].map((key) => `x-ratelimit-${key}=${header(`x-ratelimit-${key}`) ?? "none"}`),
    ...(header("retry-after") === null ? [] : [`retry-after=${header("retry-after")}`]),
    `body=${JSON.stringify(text.slice(0, 200))}`,
  ];
  return fields.join(" ").replaceAll("%", "%25");
}

/** The annotation suffix for a thrown error's responseDetail, or "". */
export const detailSuffix = (error) => (typeof error?.detail === "string" && error.detail ? ` [${error.detail}]` : "");

/**
 * Marks a write that leaves the same state when GitHub applies it twice; the
 * caller says why at the call. retryServerErrors sends it again once,
 * WRITE_RETRY_DELAY_MS later, on a 5xx or a network failure, never times it
 * out, and returns a 403, 429 or any other 4xx at once.
 */
export const RESEND_ONCE = Symbol("resend a write once");
const WRITE_RETRY_DELAY_MS = 3000;
const SERVER_RETRY_DELAYS_MS = [2000, 4000];
const ATTEMPT_TIMEOUT_MS = 20_000;
/**
 * A GraphQL query: a POST to /graphql whose document starts with `query` or
 * `{` past any `#` comments, holds no `mutation` or `subscription` word
 * anywhere in the raw text, and whose request names no operationName.
 */
export const graphqlQuery = (url, init) => {
  if (!String(url).endsWith("/graphql") || typeof init.body !== "string") {
    return false;
  }
  try {
    const request = JSON.parse(init.body);
    const query = request?.query;
    return (
      typeof query === "string" &&
      request.operationName === undefined &&
      /^(query\b|\{)/.test(query.replace(/#[^\n]*/g, "").trim()) &&
      !/\b(mutation|subscription)\b/.test(query)
    );
  } catch {
    return false;
  }
};
export const networkFailure = (error) =>
  error?.name === "TimeoutError" ||
  error?.name === "AbortError" ||
  (error?.name === "TypeError" && error.message === "fetch failed") ||
  typeof error?.cause?.code === "string";
/**
 * A GitHub fault: a 5xx or 429, a call the rate guard refused (RateLimitStop),
 * or a request that got no answer. What the call did is unknown, not wrong, so
 * a lane holds on it. Any other 4xx is not one.
 */
export const isFault = (error) =>
  (error?.name === "GitHubError" && (error.status >= 500 || error.status === 429)) ||
  error?.name === "RateLimitStop" ||
  networkFailure(error);
/** An error's name and cause code, never its message: undici puts a whole header value, the token included, in some messages. */
export const errorLabel = (error) =>
  [error?.name ?? "Error", typeof error?.cause?.code === "string" ? error.cause.code : null].filter(Boolean).join(" ");
async function brokenBody(response) {
  if (response.status !== 200) {
    return false;
  }
  const text = await response.clone().text();
  if (text === "") {
    return true;
  }
  if (!/json/i.test(response.headers.get("content-type") ?? "")) {
    return false;
  }
  try {
    JSON.parse(text);
    return false;
  } catch {
    return true;
  }
}
/**
 * Wraps a fetch so every attempt goes through the rate guard's latch, and an
 * idempotent request (a GET, or a GraphQL query) has each attempt aborted
 * after attemptTimeoutMs and is sent again, at most 3 attempts in all, after a
 * full-jitter wait (a random share of 2 s, then of 4 s), when GitHub answers
 * it 5xx, answers a GET 200 with an empty body or unparsable JSON, or it fails
 * on the network. Failed attempts' time plus the waits, summed over every call
 * through one wrapper, is capped at SERVER_RETRY_BUDGET_MS. The last answer is
 * returned, or the last error thrown. Any other request is sent once and never
 * timed out, unless marked RESEND_ONCE. With resendLimited, an idempotent
 * request a rate limit refused is sent again, inside the same 3 attempts, once
 * the latch waits out the reset.
 */
export function retryServerErrors(
  fetchImpl,
  {
    sleep = defaultSleep,
    random = Math.random,
    log = (line) => console.log(line),
    now = () => Date.now(),
    attemptTimeoutMs = ATTEMPT_TIMEOUT_MS,
    latch = rateLimitLatch,
    resendLimited = false,
    floorGraceMs = 0,
  } = {},
) {
  fetchImpl = latch.guard(fetchImpl, { sleep, floorGraceMs });
  let spent = 0;
  return async function send(url, init = {}) {
    const method = init.method ?? "GET";
    const idempotent = method === "GET" || (method === "POST" && graphqlQuery(url, init));
    for (let attempt = 0; ; attempt += 1) {
      await latch.waitOut(url, method, sleep);
      const timeout = idempotent ? AbortSignal.timeout(attemptTimeoutMs) : undefined;
      const signal = timeout && init.signal ? AbortSignal.any([init.signal, timeout]) : (timeout ?? init.signal);
      const started = now();
      const resend = resendLimited && idempotent && SERVER_RETRY_DELAYS_MS[attempt] !== undefined && spent <= SERVER_RETRY_BUDGET_MS;
      let response;
      let error;
      let broken = false;
      try {
        response = await fetchImpl(url, { ...init, signal, [RESEND]: resend });
        broken = method === "GET" && (await brokenBody(response));
      } catch (thrown) {
        error = thrown;
      }
      const limited = resend && error === undefined && latch.waits(url) && (await refusedForLimit(response));
      const failed = error !== undefined ? networkFailure(error) && !init.signal?.aborted : response.status >= 500 || broken || limited;
      spent += failed && !limited ? now() - started : 0;
      const delay = SERVER_RETRY_DELAYS_MS[attempt];
      const wait = delay === undefined || limited ? 0 : Math.round(random() * delay);
      if (failed && !idempotent && init[RESEND_ONCE] === true && attempt === 0) {
        await response?.body?.cancel().catch(() => {});
        const what = error !== undefined ? `failed (${errorLabel(error)})` : `answered ${response.status}`;
        log(`::warning::${method} ${url} ${what}; sending it again in ${WRITE_RETRY_DELAY_MS} ms (it is safe to send twice; retry 1 of 1)`);
        await sleep(WRITE_RETRY_DELAY_MS);
        continue;
      }
      if (!failed || !idempotent || delay === undefined || spent + wait > SERVER_RETRY_BUDGET_MS) {
        if (error !== undefined) {
          throw error;
        }
        return response;
      }
      await response?.body?.cancel().catch(() => {});
      if (limited) {
        continue;
      }
      const what =
        error !== undefined
          ? `failed (${errorLabel(error)})`
          : broken
            ? `answered ${response.status} with an empty or unparsable body`
            : `answered ${response.status}`;
      log(`::warning::${method} ${url} ${what}; sending it again in ${wait} ms (retry ${attempt + 1} of ${SERVER_RETRY_DELAYS_MS.length})`);
      spent += wait;
      await sleep(wait);
    }
  };
}

/**
 * The GET answers conditionalReads keeps: per key, the URL, its ETag, body and
 * headers. In memory for the process; with `dir`, each entry is also a file
 * there, so a later step of the same job that names the same directory starts
 * with it. Name a directory under RUNNER_TEMP, and only on steps that run
 * before any step that runs pull request or model code: a 304 replays the
 * file as GitHub's answer. A file that cannot be read, or names another URL,
 * counts as absent, and a write that fails keeps the entry in memory only.
 */
export function readStore(dir = "") {
  const kept = new Map();
  const file = (key) => join(dir, `${key}.json`);
  return {
    get(key, url) {
      if (!kept.has(key) && dir) {
        try {
          const entry = JSON.parse(readFileSync(file(key), "utf8"));
          new Headers(entry.headers);
          if (entry.url === url && typeof entry.etag === "string" && typeof entry.body === "string") {
            kept.set(key, entry);
          }
        } catch {}
      }
      return kept.get(key);
    },
    set(key, entry) {
      kept.set(key, entry);
      if (dir) {
        try {
          mkdirSync(dir, { recursive: true });
          const temp = `${file(key)}.${process.pid}.tmp`;
          writeFileSync(temp, JSON.stringify(entry), { mode: 0o600 });
          renameSync(temp, file(key));
        } catch {}
      }
    },
  };
}

const headerOf = (headers, name) =>
  typeof headers?.get === "function" ? (headers.get(name) ?? undefined) : Object.entries(headers ?? {}).find(([key]) => key.toLowerCase() === name)?.[1];
const withHeader = (headers, name, value) => {
  if (typeof headers?.get !== "function") {
    return { ...headers, [name]: value };
  }
  const next = new Headers(headers);
  next.set(name, value);
  return next;
};

/**
 * Wraps a fetch so a GET of a URL whose answer `store` keeps, under the same
 * Authorization header, is sent with that answer's ETag as If-None-Match, and
 * a 304 to it returns the kept body and headers as a 200, with the 304's
 * x-ratelimit-* headers. GitHub answers 304 only while the data has not
 * changed, and a 304 to an authorized request does not count against the
 * primary rate limit
 * (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests).
 * Every other answer is returned as it came. A GET 200 with an ETag and a
 * body retryServerErrors would not resend is kept. A GET that carries its own
 * If-None-Match passes through untouched, so its 304 reaches the caller.
 */
export function conditionalReads(send, store = readStore()) {
  return async function read(url, init = {}) {
    const key =
      (init.method ?? "GET") === "GET" && headerOf(init.headers, "if-none-match") === undefined
        ? createHash("sha256").update(`${headerOf(init.headers, "authorization") ?? ""}\n${url}`).digest("hex")
        : null;
    const kept = key === null ? undefined : store.get(key, String(url));
    const response = await send(url, kept === undefined ? init : { ...init, headers: withHeader(init.headers, "If-None-Match", kept.etag) });
    if (kept !== undefined && response.status === 304) {
      const headers = new Headers(kept.headers);
      response.headers?.forEach?.((value, name) => name.startsWith("x-ratelimit-") && headers.set(name, value));
      return new Response(kept.body, { status: 200, headers });
    }
    const etag = response.headers?.get?.("etag");
    if (key !== null && etag && response.status === 200 && !(await brokenBody(response))) {
      store.set(key, { url: String(url), etag, body: await response.clone().text(), headers: [...response.headers] });
    }
    return response;
  };
}

/** The key createGitHub keeps an answer's ETag under; a 304 to a caller's own If-None-Match still throws GitHubError. */
export const ETAG = Symbol.for("github.etag");

/**
 * One function every API read and write goes through; tests replace it.
 * keepGraphQLErrors returns a GraphQL answer with its errors for the caller to
 * judge, instead of raising on any. Reads retry as retryServerErrors does,
 * with resendLimited. A call while the rate guard's latch holds its pool past
 * the wait budget throws RateLimitStop without a request. Pass
 * `resendOnce: true` only for a write that is safe to send twice
 * (RESEND_ONCE). A success with no body returns null; a list keeps its Link
 * header under Symbol.for("github.link"), and an object its ETag under ETAG.
 * A repeated GET is a conditional read (conditionalReads) on `store`, by
 * default kept for this client, and in the GITHUB_READ_STORE directory too
 * when that is set.
 */
export function createGitHub({
  token,
  apiUrl = "https://api.github.com",
  fetchImpl = fetch,
  onResponse,
  keepGraphQLErrors = false,
  sleep,
  random,
  log,
  now,
  attemptTimeoutMs,
  latch,
  store = readStore(process.env.GITHUB_READ_STORE ?? ""),
}) {
  const send = conditionalReads(retryServerErrors(fetchImpl, { sleep, random, log, now, attemptTimeoutMs, latch, resendLimited: true }), store);
  return async function github(method, apiPath, body, headers = {}, { signal, resendOnce = false } = {}) {
    const response = await send(`${apiUrl}${apiPath}`, {
      [RESEND_ONCE]: resendOnce,
      method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        ...headers,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
    onResponse?.(response);
    if (!response.ok) {
      throw new GitHubError(response.status, `${method} ${apiPath}`, await responseDetail(response));
    }
    const text = await response.text();
    if (text === "") {
      return null;
    }
    const json = JSON.parse(text);
    if (!keepGraphQLErrors && Array.isArray(json?.errors) && json.errors.length > 0) {
      throw new GitHubError(response.status, `${method} ${apiPath} (GraphQL errors)`);
    }
    if (Array.isArray(json)) {
      Object.defineProperty(json, Symbol.for("github.link"), { value: response.headers.get("link") });
    }
    const etag = response.headers.get("etag");
    if (etag && json !== null && typeof json === "object") {
      Object.defineProperty(json, ETAG, { value: etag });
    }
    return json;
  };
}

/**
 * A commit's pull requests through GraphQL, the same set GET
 * /commits/{sha}/pulls lists: the PR that merged the commit, plus open ones
 * while it is off the default branch.
 */
export const COMMIT_PULLS_QUERY = `query($owner: String!, $name: String!, $oid: GitObjectID!) {
  repository(owner: $owner, name: $name) {
    object(oid: $oid) {
      ... on Commit {
        associatedPullRequests(first: 100) {
          pageInfo { hasNextPage }
          nodes {
            number state isDraft mergedAt headRefName headRefOid baseRefName baseRefOid
            headRepository { nameWithOwner }
            author { __typename login ... on User { databaseId } ... on Bot { databaseId } }
            labels(first: 100) { nodes { name } pageInfo { hasNextPage } }
          }
        }
      }
    }
  }
}`;

/**
 * COMMIT_PULLS_QUERY's answer in the REST fields the lane scripts read. More
 * than 100 PRs or labels throws; a list missing from the answer throws an
 * error marked `incomplete`, which a re-read can fix.
 */
export function commitPullsFromGraphQL(data) {
  const list = data?.repository?.object?.associatedPullRequests;
  if (
    !Array.isArray(list?.nodes) ||
    list.pageInfo?.hasNextPage !== false ||
    list.nodes.some((node) => !Array.isArray(node?.labels?.nodes) || node.labels.pageInfo?.hasNextPage !== false)
  ) {
    const pastPage = list?.pageInfo?.hasNextPage === true || (Array.isArray(list?.nodes) && list.nodes.some((node) => node?.labels?.pageInfo?.hasNextPage === true));
    throw Object.assign(new Error("the commit's pull requests could not be read through GraphQL"), pastPage ? {} : { incomplete: true });
  }
  return list.nodes.map((node) => ({
    number: node.number,
    state: node.state === "OPEN" ? "open" : "closed",
    draft: node.isDraft,
    merged_at: node.mergedAt ?? null,
    user: node.author
      ? {
          id: node.author.databaseId ?? null,
          login: node.author.__typename === "Bot" ? `${node.author.login}[bot]` : node.author.login,
          type: node.author.__typename,
        }
      : null,
    labels: node.labels.nodes.map((label) => ({ name: label.name })),
    head: { sha: node.headRefOid, ref: node.headRefName, repo: node.headRepository ? { full_name: node.headRepository.nameWithOwner } : null },
    base: { ref: node.baseRefName, sha: node.baseRefOid },
  }));
}

/**
 * The commit's pull requests: readRest's list, else COMMIT_PULLS_QUERY sent
 * through readGraphQL(query, variables, signal), which returns the answer's
 * data, with a signal that aborts it after timeoutMs. Throws when both fail,
 * or at once on an error readRest marks `fallback: false`.
 */
export async function commitPulls({
  repository,
  sha,
  readRest,
  readGraphQL,
  log = (line) => console.log(line),
  timeoutMs = ATTEMPT_TIMEOUT_MS,
}) {
  try {
    const pulls = await readRest();
    if (Array.isArray(pulls)) {
      return pulls;
    }
    throw new Error("the answer is not a list");
  } catch (error) {
    if (error?.fallback === false) {
      throw error;
    }
    log(`::warning::the REST read of ${sha}'s pull requests failed (${errorLabel(error)}${Number.isInteger(error?.status) ? ` ${error.status}` : ""}); reading them through GraphQL`);
    const [owner, name] = repository.split("/");
    return commitPullsFromGraphQL(await readGraphQL(COMMIT_PULLS_QUERY, { owner, name, oid: sha }, AbortSignal.timeout(timeoutMs)));
  }
}

/** commitPulls' readGraphQL for a createGitHub client. */
export const graphQLReader = (github) => async (query, variables, signal) =>
  (await github("POST", "/graphql", { query, variables }, {}, { signal }))?.data;

/** Every item of a list endpoint, 100 a page; more than maxPages pages throws. */
export async function paginate(github, apiPath, maxPages = 50) {
  const items = [];
  const separator = apiPath.includes("?") ? "&" : "?";
  for (let page = 1; page <= maxPages; page += 1) {
    const batch = await github("GET", `${apiPath}${separator}per_page=100&page=${page}`);
    items.push(...batch);
    if (batch.length < 100) {
      return items;
    }
  }
  throw new Error(`${apiPath} has more than ${maxPages} pages`);
}
