import assert from "node:assert/strict";
import { test } from "node:test";

import { budgetedFetch } from "./request-budget.mjs";

// GitHub's answers: a 200 with an ETag, then 304 for a request that names it
// (docs.github.com rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests).
function github(responses) {
  const sent = [];
  const fetch = async (url, init) => {
    sent.push({ url, init });
    const { status, body = "", headers = {} } = responses.shift();
    return new Response(status === 304 ? null : body, { status, headers });
  };
  return { fetch, sent };
}

const rate = (remaining, resource = "core") => ({
  "x-ratelimit-limit": "5000",
  "x-ratelimit-remaining": String(remaining),
  "x-ratelimit-used": String(5000 - remaining),
  "x-ratelimit-reset": "1792378942",
  "x-ratelimit-resource": resource,
});

test("a repeated GET is sent conditionally and a 304 returns the first body", async () => {
  const gh = github([
    { status: 200, body: '{"n":1}', headers: { etag: '"abc"', link: '<u2>; rel="next"', ...rate(4000) } },
    { status: 304, headers: rate(4000) },
  ]);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {} });
  const first = await budget.fetch("https://api.example/repos/o/r/x", { headers: { Authorization: "Bearer t" } });
  assert.deepEqual(await first.json(), { n: 1 });
  const again = await budget.fetch("https://api.example/repos/o/r/x", { headers: { Authorization: "Bearer t" } });
  assert.equal(gh.sent[1].init.headers["If-None-Match"], '"abc"');
  assert.equal(gh.sent[1].init.headers.Authorization, "Bearer t");
  assert.equal(again.status, 200);
  assert.deepEqual(await again.json(), { n: 1 });
  assert.equal(again.headers.get("link"), '<u2>; rel="next"');
  assert.deepEqual(budget.counts, { rest: 1, notModified: 1, graphql: 0 });
});

test("a POST is never conditional, and GraphQL calls are counted apart", async () => {
  const gh = github([
    { status: 200, body: "{}", headers: { etag: '"g"', ...rate(4100, "graphql") } },
    { status: 200, body: "{}", headers: { etag: '"g"', ...rate(4099, "graphql") } },
  ]);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {} });
  await budget.fetch("https://api.example/graphql", { method: "POST", headers: {} });
  await budget.fetch("https://api.example/graphql", { method: "POST", headers: {} });
  assert.equal(gh.sent[1].init.headers["If-None-Match"], undefined);
  assert.deepEqual(budget.counts, { rest: 0, notModified: 0, graphql: 2 });
  assert.equal(
    budget.summary(),
    "api-calls rest=0 not-modified=0 graphql=2 graphql remaining=4099 used=901 limit=5000 reset=2026-10-19T03:02:22Z",
  );
});

// A rate-limited call waits, then is sent once more: retry-after seconds when
// present, else until x-ratelimit-reset when remaining is 0, else one minute
// (docs.github.com rest/using-the-rest-api/best-practices-for-using-the-rest-api#handle-rate-limit-errors-appropriately).
const RESET = 1792378942;
const limited = (overrides = {}) => ({
  status: 403,
  body: '{"message":"API rate limit exceeded for installation."}',
  headers: { ...rate(0), ...overrides },
});
function clock(startSeconds) {
  let at = startSeconds * 1000;
  const slept = [];
  return {
    now: () => at,
    sleep: async (ms) => {
      slept.push(ms);
      at += ms;
    },
    slept,
  };
}

test("a 403 or 429 logs GitHub's message and retry-after", async () => {
  const gh = github([
    { status: 403, body: '{"message":"You have exceeded a secondary rate limit."}', headers: { "retry-after": "60", ...rate(3000) } },
    { status: 200, body: "{}", headers: rate(2999) },
    { status: 429, body: "not json", headers: { ...rate(0), "x-ratelimit-reset": String(RESET + 10) } },
    { status: 200, body: "{}", headers: rate(4999) },
  ]);
  const lines = [];
  const time = clock(RESET);
  const budget = budgetedFetch({ fetch: gh.fetch, log: (line) => lines.push(line), ...time });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/x", { headers: {} })).status, 200);
  assert.equal((await budget.fetch("https://api.example/repos/o/r/y", { headers: {} })).status, 200);
  assert.equal(lines.filter((line) => line.startsWith("::warning::GET returned")).length, 2);
  assert.equal(lines[0], '::warning::GET returned 403: message="You have exceeded a secondary rate limit." retry-after=60 remaining=3000');
  assert.ok(lines.includes('::warning::GET returned 429: message="" retry-after=none remaining=0'));
});

test("a 403 with remaining 0 waits past x-ratelimit-reset and is sent once more", async () => {
  const gh = github([limited({ "x-ratelimit-reset": String(RESET) }), { status: 200, body: '{"ok":true}', headers: rate(4999) }]);
  const time = clock(RESET - 300);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, ...time });
  const response = await budget.fetch("https://api.example/repos/o/r/actions/runs", { headers: {} });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });
  // 300 s to the reset, plus one second so the retry lands after it.
  assert.deepEqual(time.slept, [301_000]);
  assert.equal(gh.sent.length, 2);
  assert.equal(gh.sent[1].url, gh.sent[0].url);
  assert.deepEqual(budget.counts, { rest: 2, notModified: 0, graphql: 0 });
});

test("a 429 with retry-after waits retry-after seconds", async () => {
  const gh = github([
    { status: 429, body: "{}", headers: { ...rate(10), "retry-after": "30" } },
    { status: 200, body: "{}", headers: rate(9) },
  ]);
  const time = clock(RESET - 3000);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, ...time });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/x", { method: "POST", headers: {}, body: "{}" })).status, 200);
  assert.deepEqual(time.slept, [30_000]);
  assert.equal(gh.sent[1].init.body, "{}");
});

test("a secondary limit with no retry-after waits one minute", async () => {
  const gh = github([
    { status: 403, body: '{"message":"You have exceeded a secondary rate limit."}', headers: rate(3000) },
    { status: 200, body: "{}", headers: rate(2999) },
  ]);
  const time = clock(RESET - 3000);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, ...time });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/x", { headers: {} })).status, 200);
  assert.deepEqual(time.slept, [60_000]);
});

test("a reset past the wait cap fails at once and names the reset", async () => {
  const gh = github([limited({ "x-ratelimit-reset": String(RESET) })]);
  const lines = [];
  const time = clock(RESET - 20 * 60);
  const budget = budgetedFetch({ fetch: gh.fetch, log: (line) => lines.push(line), ...time });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/x", { headers: {} })).status, 403);
  assert.deepEqual(time.slept, []);
  assert.equal(gh.sent.length, 1);
  assert.ok(lines.some((line) => line.startsWith("::error::") && line.includes("2026-10-19T03:02:22Z")));
});

test("waits are capped across the whole run, not per call", async () => {
  const gh = github([
    limited({ "retry-after": "200" }),
    { status: 200, body: "{}", headers: rate(4999) },
    limited({ "retry-after": "200" }),
  ]);
  const time = clock(RESET - 3000);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, ...time, maxWaitMs: 360_000 });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/x", { headers: {} })).status, 200);
  assert.equal((await budget.fetch("https://api.example/repos/o/r/y", { headers: {} })).status, 403);
  assert.deepEqual(time.slept, [200_000]);
  assert.equal(gh.sent.length, 3);
});

test("a second rate limit after the wait is returned, with no third request", async () => {
  const gh = github([limited({ "x-ratelimit-reset": String(RESET) }), limited({ "x-ratelimit-reset": String(RESET + 3600) })]);
  const time = clock(RESET - 60);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, ...time });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/x", { headers: {} })).status, 403);
  assert.deepEqual(time.slept, [61_000]);
  assert.equal(gh.sent.length, 2);
});

test("a 200 that spends the last request is not waited on", async () => {
  const gh = github([{ status: 200, body: "{}", headers: rate(0) }]);
  const time = clock(RESET - 3000);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, ...time });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/x", { headers: {} })).status, 200);
  assert.deepEqual(time.slept, []);
});

test("a permission 403 is not waited on", async () => {
  const gh = github([{ status: 403, body: '{"message":"Resource not accessible by integration"}', headers: rate(4000) }]);
  const time = clock(RESET - 3000);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, ...time });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/x", { method: "POST", headers: {} })).status, 403);
  assert.deepEqual(time.slept, []);
  assert.equal(gh.sent.length, 1);
});

// A GET answered 5xx is sent again after a backoff, as createGitHub's are
// (check-trusted-trigger.mjs): run 39788855311 failed the feedback dispatch on
// one 500 from GET /commits/{sha}/pulls.
const PULLS = "https://api.example/repos/o/r/commits/db53ee51744631cd5ee03d76bf87873fe1ce59f9/pulls";

test("a GET answered 500 is sent again after a backoff and the next answer returned", async () => {
  const gh = github([{ status: 500 }, { status: 200, body: '[{"number":7}]', headers: rate(3994) }]);
  const time = clock(RESET - 3000);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, random: () => 0, ...time });
  const response = await budget.fetch(PULLS, { headers: {} });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), [{ number: 7 }]);
  assert.deepEqual(time.slept, [1000]);
  assert.equal(gh.sent.length, 2);
});

test("a GET that keeps answering 503 returns the fourth 503", async () => {
  const gh = github([{ status: 503 }, { status: 503 }, { status: 503 }, { status: 503 }, { status: 200 }]);
  const time = clock(RESET - 3000);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, random: () => 0, ...time });
  assert.equal((await budget.fetch(PULLS, { headers: {} })).status, 503);
  assert.deepEqual(time.slept, [1000, 2000, 4000]);
  assert.equal(gh.sent.length, 4);
});

test("a POST answered 500 is returned at once", async () => {
  const gh = github([{ status: 500 }]);
  const time = clock(RESET - 3000);
  const budget = budgetedFetch({ fetch: gh.fetch, log: () => {}, random: () => 0, ...time });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/dispatches", { method: "POST", headers: {} })).status, 500);
  assert.deepEqual(time.slept, []);
  assert.equal(gh.sent.length, 1);
});

test("each response's rate-limit headers are appended as a reading under API_BUDGET_TOKEN", async () => {
  const { mkdtempSync, readFileSync, rmSync } = await import("node:fs");
  const { join } = await import("node:path");
  const { tmpdir } = await import("node:os");
  const dir = mkdtempSync(join(tmpdir(), "request-budget-"));
  const saved = { token: process.env.API_BUDGET_TOKEN, temp: process.env.RUNNER_TEMP };
  process.env.API_BUDGET_TOKEN = "github-token";
  process.env.RUNNER_TEMP = dir;
  try {
    const gh = github([
      { status: 200, body: "{}", headers: rate(4000) },
      { status: 403, body: '{"message":"Resource not accessible by integration"}', headers: rate(3999) },
    ]);
    const budget = budgetedFetch({ fetch: gh.fetch, log: () => {} });
    await budget.fetch("https://api.example/repos/o/r/a");
    await budget.fetch("https://api.example/repos/o/r/b");
    assert.equal(
      readFileSync(join(dir, "api-budget", "github-token"), "utf8"),
      "200 5000 4000 1000 1792378942 core\n403 5000 3999 1001 1792378942 core\n",
    );
  } finally {
    for (const [key, value] of [["API_BUDGET_TOKEN", saved.token], ["RUNNER_TEMP", saved.temp]]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    rmSync(dir, { recursive: true, force: true });
  }
});
