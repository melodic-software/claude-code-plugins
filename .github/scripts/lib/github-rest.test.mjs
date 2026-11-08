// github-rest.mjs: a GitHub REST client within a call budget, and a
// paginator, over a stubbed fetch.
import assert from "node:assert/strict";
import { test } from "node:test";

import { BudgetSpent, budgetedClient, pages } from "./github-rest.mjs";

const ENV = { GITHUB_API_URL: "https://api.test", GITHUB_TOKEN: "t0ken" };

// A fetch stub answering each request with `answer(url, init)`, recording them.
function stubFetch(t, answer) {
  const requests = [];
  t.mock.method(globalThis, "fetch", async (url, init) => {
    requests.push({ url, init });
    return answer(url, init);
  });
  return requests;
}

test("a call sends the token, API version and JSON body, and answers the JSON", async (t) => {
  const requests = stubFetch(t, () => Response.json({ id: 7 }, { status: 201 }));
  const call = budgetedClient(ENV);
  assert.deepEqual(await call("POST", "/repos/o/r/issues", { title: "x" }), { id: 7 });
  const [{ url, init }] = requests;
  assert.equal(url, "https://api.test/repos/o/r/issues");
  assert.equal(init.method, "POST");
  assert.equal(init.body, '{"title":"x"}');
  assert.deepEqual(init.headers, {
    accept: "application/vnd.github+json",
    authorization: "Bearer t0ken",
    "x-github-api-version": "2022-11-28",
    "content-type": "application/json",
  });
});

test("a call without a body sends no body and no content type", async (t) => {
  const requests = stubFetch(t, () => Response.json({}));
  await budgetedClient(ENV)("GET", "/repos/o/r");
  assert.equal("body" in requests[0].init, false);
  assert.equal("content-type" in requests[0].init.headers, false);
});

test("the API URL defaults to api.github.com", async (t) => {
  const requests = stubFetch(t, () => Response.json({}));
  await budgetedClient({})("GET", "/rate_limit");
  assert.equal(requests[0].url, "https://api.github.com/rate_limit");
});

test("a GET's 404 answers null; a write's 404 throws", async (t) => {
  stubFetch(t, () => new Response("", { status: 404 }));
  const call = budgetedClient(ENV);
  assert.equal(await call("GET", "/repos/o/r/issues/1"), null);
  await assert.rejects(call("PATCH", "/repos/o/r/issues/1", {}), /^Error: PATCH \/repos\/o\/r\/issues\/1: HTTP 404$/);
});

test("a failed call throws its method, path without query, and status", async (t) => {
  stubFetch(t, () => new Response("", { status: 502 }));
  const error = await budgetedClient(ENV)("GET", "/repos/o/r/pulls?state=open").catch((e) => e);
  assert.equal(error.message, "GET /repos/o/r/pulls: HTTP 502");
  assert.equal(error.status, 502);
});

test("a 204 answers null", async (t) => {
  stubFetch(t, () => new Response(null, { status: 204 }));
  assert.equal(await budgetedClient(ENV)("DELETE", "/repos/o/r/git/refs/heads/x"), null);
});

test("a /zip path answers the bytes as a Buffer", async (t) => {
  stubFetch(t, () => new Response(new Uint8Array([80, 75, 3, 4])));
  const bytes = await budgetedClient(ENV)("GET", "/repos/o/r/actions/artifacts/9/zip");
  assert.ok(Buffer.isBuffer(bytes));
  assert.deepEqual([...bytes], [80, 75, 3, 4]);
});

test("the budget refuses the call past it, before pacing or fetching, and counts every call", async (t) => {
  const requests = stubFetch(t, () => Response.json({}));
  let paced = 0;
  const call = budgetedClient(ENV, { budget: 2, pace: async () => (paced += 1) });
  await call("GET", "/a");
  assert.equal(call.remaining(), 1);
  await call("GET", "/b");
  const error = await call("GET", "/c").catch((e) => e);
  assert.ok(error instanceof BudgetSpent);
  assert.equal(error.message, "call budget of 2 spent");
  assert.deepEqual([paced, requests.length, call.used(), call.remaining()], [2, 2, 2, 0]);
});

test("a failed call still spends its share of the budget", async (t) => {
  stubFetch(t, () => new Response("", { status: 500 }));
  const call = budgetedClient(ENV, { budget: 1 });
  await assert.rejects(call("GET", "/a"), /HTTP 500/);
  await assert.rejects(call("GET", "/a"), BudgetSpent);
});

test("each call waits for the pace before it fetches", async (t) => {
  const order = [];
  stubFetch(t, () => {
    order.push("fetch");
    return Response.json({});
  });
  await budgetedClient(ENV, { pace: async () => order.push("pace") })("GET", "/a");
  assert.deepEqual(order, ["pace", "fetch"]);
});

test("fetch is read at call time, so a stub set after the client is built answers", async (t) => {
  const call = budgetedClient(ENV);
  stubFetch(t, () => Response.json({ late: true }));
  assert.deepEqual(await call("GET", "/a"), { late: true });
});

// A call answering `total` numbered items 100 a page, recording each path.
function lister(total, key) {
  const paths = [];
  const call = async (_method, path) => {
    paths.push(path);
    const page = Number(new URL(path, "https://x").searchParams.get("page"));
    const items = Array.from({ length: Math.max(0, Math.min(100, total - (page - 1) * 100)) }, (_, i) => (page - 1) * 100 + i);
    return key ? { [key]: items } : items;
  };
  return { call, paths };
}

test("pages reads until a short page, adding per_page and page to the query", async () => {
  const { call, paths } = lister(250);
  assert.equal((await pages(call, "/repos/o/r/pulls?state=all")).length, 250);
  assert.deepEqual(paths, [1, 2, 3].map((p) => `/repos/o/r/pulls?state=all&per_page=100&page=${p}`));
});

test("pages reads the array a key names in an object answer", async () => {
  const { call, paths } = lister(100, "jobs");
  assert.equal((await pages(call, "/repos/o/r/actions/runs/1/jobs", { key: "jobs" })).length, 100);
  assert.equal(paths[0], "/repos/o/r/actions/runs/1/jobs?per_page=100&page=1");
  assert.equal(paths.length, 2);
});

test("pages takes a null answer as an empty last page", async () => {
  assert.deepEqual(await pages(async () => null, "/x"), []);
});

test("pages throws past its page cap", async () => {
  const { call, paths } = lister(1000);
  await assert.rejects(pages(call, "/repos/o/r/branches?x=1", { max: 3 }), /^Error: \/repos\/o\/r\/branches: more than 3 pages$/);
  assert.equal(paths.length, 3);
});

test("pages caps at 20 pages by default", async () => {
  const { call, paths } = lister(5000);
  await assert.rejects(pages(call, "/x"), /more than 20 pages/);
  assert.equal(paths.length, 20);
});
