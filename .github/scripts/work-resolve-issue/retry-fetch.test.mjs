import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { isGraphQLRead, retryFetch } from "./retry-fetch.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

// Each script directory that runs from a copy of itself holds its own copy.
test("apply-patch and pr-unblock hold the same retry-fetch.mjs as this directory", () => {
  const own = readFileSync(new URL("./retry-fetch.mjs", import.meta.url), "utf8");
  for (const copy of ["../apply-patch/retry-fetch.mjs", "../pr-unblock/retry-fetch.mjs"]) {
    assert.equal(readFileSync(new URL(copy, import.meta.url), "utf8"), own, copy);
  }
});

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
