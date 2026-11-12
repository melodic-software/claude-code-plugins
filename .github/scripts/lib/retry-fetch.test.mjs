import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { isGraphQLRead, retryFetch } from "./retry-fetch.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const dropped = () => Object.assign(new TypeError("fetch failed"), { cause: { code: "ECONNRESET", message: "Bearer ghs_secret" } });

function harness(answers, random = () => 1) {
  const sent = [];
  const slept = [];
  const logged = [];
  const fetchImpl = async (url, init) => {
    sent.push({ url, init });
    const answer = answers.shift();
    if (answer instanceof Error) {
      throw answer;
    }
    return new Response("{}", { status: answer });
  };
  const send = retryFetch(fetchImpl, { sleep: async (ms) => slept.push(ms), random, log: (line) => logged.push(line) });
  return { send, sent, slept, logged };
}

test("a GET that lost its socket is sent again and returns the next answer", async () => {
  const h = harness([dropped(), 200]);
  assert.equal((await h.send("https://api/x")).status, 200);
  assert.equal(h.sent.length, 2);
  assert.deepEqual(h.slept, [4000]);
});

test("a GET is sent at most 3 times: the last 5xx is returned, the last network error raised", async () => {
  const fivexx = harness([500, 502, 503, 200]);
  assert.equal((await fivexx.send("https://api/x")).status, 503);
  assert.equal(fivexx.sent.length, 3);
  assert.deepEqual(fivexx.slept, [4000, 8000]);
  const network = harness([dropped(), dropped(), dropped(), 200]);
  await assert.rejects(network.send("https://api/x"), TypeError);
  assert.equal(network.sent.length, 3);
});

test("each wait is a random share of its cap", async () => {
  const h = harness([500, 500, 200], () => 0.5);
  await h.send("https://api/x");
  assert.deepEqual(h.slept, [2000, 4000]);
});

test("a 4xx is returned and an error with no network cause raised, each at once", async () => {
  const h = harness([404, new Error("boom")]);
  assert.equal((await h.send("https://api/x")).status, 404);
  await assert.rejects(h.send("https://api/x"), /boom/);
  assert.equal(h.sent.length, 2);
  assert.deepEqual(h.slept, []);
});

// Outage posture element 1: a rate-limited read waits as long as GitHub asks,
// within the 3 attempts and a 60 s budget per wrapper, and a write is sent once.
function limited(answers, { clock = 0 } = {}) {
  const sent = [];
  const slept = [];
  const fetchImpl = async (url, init) => {
    sent.push(init.method ?? "GET");
    const { status, headers = {}, body = "{}" } = answers.shift();
    return new Response(body, { status, headers });
  };
  const send = retryFetch(fetchImpl, { sleep: async (ms) => slept.push(ms), random: () => 1, log: () => {}, now: () => clock });
  return { send, sent, slept };
}

test("a read refused on a rate limit waits for retry-after, the reset, or 60 s for a secondary limit, then is sent again", async () => {
  const after = limited([{ status: 429, headers: { "retry-after": "7" } }, { status: 200 }]);
  assert.equal((await after.send("https://api/x")).status, 200);
  assert.deepEqual(after.slept, [7000]);
  const reset = limited([{ status: 403, headers: { "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1030" } }, { status: 200 }], { clock: 1_000_000 });
  assert.equal((await reset.send("https://api/x")).status, 200);
  assert.deepEqual(reset.slept, [30_000]);
  const secondary = limited([{ status: 403, body: '{"message":"You have exceeded a secondary rate limit."}' }, { status: 200 }]);
  assert.equal((await secondary.send("https://api/x")).status, 200);
  assert.deepEqual(secondary.slept, [60_000]);
  const bare = limited([{ status: 429 }, { status: 200 }]);
  assert.equal((await bare.send("https://api/x")).status, 200);
  assert.deepEqual(bare.slept, [60_000]);
});

test("a 403 that names no rate limit, and a write refused on one, are returned at once", async () => {
  const h = limited([{ status: 403, body: '{"message":"Resource not accessible by integration"}' }, { status: 429, headers: { "retry-after": "1" } }]);
  assert.equal((await h.send("https://api/x")).status, 403);
  assert.equal((await h.send("https://api/x", { method: "POST", body: "{}" })).status, 429);
  assert.deepEqual(h.sent, ["GET", "POST"]);
  assert.deepEqual(h.slept, []);
});

test("a rate-limit wait past the 60 s budget is not taken: the answer goes back as a failed read", async () => {
  const long = limited([{ status: 429, headers: { "retry-after": "61" } }, { status: 200 }]);
  assert.equal((await long.send("https://api/x")).status, 429);
  assert.deepEqual(long.slept, []);
  // 40 s, then 30 s more would pass 60: the second call returns its 429.
  const spent = limited([{ status: 429, headers: { "retry-after": "40" } }, { status: 200 }, { status: 429, headers: { "retry-after": "30" } }, { status: 200 }]);
  assert.equal((await spent.send("https://api/x")).status, 200);
  assert.equal((await spent.send("https://api/y")).status, 429);
  assert.deepEqual(spent.slept, [40_000]);
  assert.equal(spent.sent.length, 3);
});

// budgetedFetch and the rate guard's latch mark their fetch counted and handle
// a rate limit themselves, so a wait here would stack on theirs.
test("a fetch that already counts its answers is left to the rate guard on a rate limit", async () => {
  const sent = [];
  const slept = [];
  const fetchImpl = async () => {
    sent.push("GET");
    return new Response("{}", { status: 429, headers: { "retry-after": "1" } });
  };
  fetchImpl[Symbol.for("api-budget.counted")] = true;
  const send = retryFetch(fetchImpl, { sleep: async (ms) => slept.push(ms), log: () => {} });
  assert.equal((await send("https://api/x")).status, 429);
  assert.equal(sent.length, 1);
  assert.deepEqual(slept, []);
});

test("a read refused on a rate limit counts against the 3 attempts", async () => {
  const h = limited([{ status: 429, headers: { "retry-after": "1" } }, { status: 502 }, { status: 429, headers: { "retry-after": "1" } }, { status: 200 }]);
  assert.equal((await h.send("https://api/x")).status, 429);
  assert.equal(h.sent.length, 3);
  assert.deepEqual(h.slept, [1000, 8000]);
});

test("a write is sent once unless the caller marks it safeToResend, which never reaches fetch", async () => {
  const h = harness([dropped(), dropped(), 200]);
  await assert.rejects(h.send("https://api/x", { method: "POST", body: "{}" }), TypeError);
  assert.equal(h.sent.length, 1);
  assert.equal((await h.send("https://api/x", { method: "PATCH", body: "{}", safeToResend: true })).status, 200);
  assert.equal(h.sent.length, 3);
  assert.equal("safeToResend" in h.sent[2].init, false);
});

test("a GraphQL query is sent again; a mutation, or a query document holding one, is not", async () => {
  const body = (query) => JSON.stringify({ query });
  const h = harness([dropped(), 200, dropped(), 200, dropped(), dropped()]);
  assert.equal((await h.send("https://api/graphql", { method: "POST", body: body("query($n: Int!) { repository { id } }") })).status, 200);
  assert.equal((await h.send("https://api/graphql", { method: "POST", body: body("# note\n{ viewer { login } }") })).status, 200);
  assert.equal(h.sent.length, 4);
  await assert.rejects(h.send("https://api/graphql", { method: "POST", body: body("mutation { addStar(input: {}) { clientMutationId } }") }), TypeError);
  await assert.rejects(h.send("https://api/graphql", { method: "POST", body: body("query A { x } mutation B { y }") }), TypeError);
  assert.equal(h.sent.length, 6);
});

test("a mutation after a # inside a string is still a write", () => {
  const init = { method: "POST", body: JSON.stringify({ query: 'query A { x(s: "#") } mutation B { y }' }) };
  assert.equal(isGraphQLRead("https://api/graphql", init), false);
});

test("a retry line names the error and its cause code, never its message", async () => {
  const h = harness([dropped(), 200]);
  await h.send("https://api/x");
  assert.equal(h.logged.length, 1);
  assert.match(h.logged[0], /failed \(TypeError ECONNRESET\)/);
  assert.doesNotMatch(h.logged[0], /ghs_secret/);
});

// The lane run report's failure rows: $RUNNER_TEMP/lane-run-report/api-failures.jsonl.
function recorded(answers, { counted = false } = {}) {
  const dir = tempDir("retry-fetch-failures-");
  const fetchImpl = async () => {
    const answer = answers.shift();
    if (answer instanceof Error) throw answer;
    return new Response("{}", { status: answer });
  };
  if (counted) fetchImpl[Symbol.for("api-budget.counted")] = true;
  const send = retryFetch(fetchImpl, { sleep: async () => {}, log: () => {}, failureDir: dir });
  const file = join(dir, "lane-run-report", "api-failures.jsonl");
  const rows = () => (existsSync(file) ? readFileSync(file, "utf8").trim().split("\n").map((line) => JSON.parse(line)) : []);
  return { send, rows };
}

test("a call that still fails is recorded once, by path with no query, and a network error as status 0", async () => {
  const r = recorded([502, 502, 502, 404, dropped(), 200]);
  await r.send("https://api.github.com/repos/o/r/pulls/1?access_token=secret");
  await r.send("https://api.github.com/repos/o/r/git/ref/heads/x", { method: "patch", body: "{}" });
  await assert.rejects(r.send("https://api.github.com/graphql", { method: "POST", body: "{}" }));
  await r.send("https://api.github.com/repos/o/r");
  assert.deepEqual(r.rows(), [
    { method: "GET", path: "/repos/o/r/pulls/1", status: 502 },
    { method: "PATCH", path: "/repos/o/r/git/ref/heads/x", status: 404 },
    { method: "POST", path: "/graphql", status: 0 },
  ]);
});

test("a fetch that already counts its answers leaves the HTTP failures to rate-guard, and nothing is written without RUNNER_TEMP", async () => {
  const r = recorded([500, 500, 500, dropped()], { counted: true });
  await r.send("https://api.github.com/x");
  await assert.rejects(r.send("https://api.github.com/y", { method: "POST" }));
  assert.deepEqual(r.rows(), [{ method: "POST", path: "/y", status: 0 }]);
  const saved = process.env.RUNNER_TEMP;
  delete process.env.RUNNER_TEMP;
  try {
    const send = retryFetch(async () => new Response("{}", { status: 500 }), { sleep: async () => {}, log: () => {} });
    assert.equal((await send("https://api.github.com/z", { method: "POST" })).status, 500);
  } finally {
    if (saved !== undefined) process.env.RUNNER_TEMP = saved;
  }
});
