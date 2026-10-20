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

test("a 403 or 429 logs GitHub's message and retry-after", async () => {
  const gh = github([
    { status: 403, body: '{"message":"You have exceeded a secondary rate limit."}', headers: { "retry-after": "60", ...rate(3000) } },
    { status: 429, body: "not json", headers: rate(0) },
  ]);
  const lines = [];
  const budget = budgetedFetch({ fetch: gh.fetch, log: (line) => lines.push(line) });
  assert.equal((await budget.fetch("https://api.example/repos/o/r/x", { headers: {} })).status, 403);
  await budget.fetch("https://api.example/repos/o/r/y", { headers: {} });
  assert.deepEqual(lines, [
    '::warning::GET returned 403: message="You have exceeded a secondary rate limit." retry-after=60 remaining=3000',
    '::warning::GET returned 429: message="" retry-after=none remaining=0',
  ]);
});
