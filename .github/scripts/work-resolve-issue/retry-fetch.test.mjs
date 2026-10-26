import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { isGraphQLRead, retryFetch } from "./retry-fetch.mjs";

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
