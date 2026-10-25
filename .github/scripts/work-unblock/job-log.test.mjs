import assert from "node:assert/strict";
import { test } from "node:test";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { createJobLogReader } from "./job-log.mjs";

// A latch that lets every request through and records its URL.
const openLatch = (seen = []) => ({ guard: (fetchImpl) => async (url, init) => (seen.push(url), fetchImpl(url, init)) });
const reader = (fetchImpl, latch = openLatch()) => createJobLogReader({ token: "t", apiUrl: "https://api.example", fetchImpl, latch });

test("a job's log comes back as text from one fetch, with the token", async () => {
  const seen = [];
  const fetchImpl = async (url, init) => {
    seen.push({ url, auth: init.headers.Authorization, method: init.method });
    return new Response("2026-10-24T19:57:51Z ##[error]denied\n", { status: 200, headers: { "Content-Type": "text/plain" } });
  };
  assert.equal(await reader(fetchImpl)("o/r", 1, { maxBytes: 100 }), "2026-10-24T19:57:51Z ##[error]denied\n");
  assert.deepEqual(seen, [{ url: "https://api.example/repos/o/r/actions/jobs/1/logs", auth: "Bearer t", method: "GET" }]);
});

test("a log over the cap is refused, by its Content-Length or as it streams", async () => {
  const declared = async () => new Response("x".repeat(11), { status: 200, headers: { "Content-Length": "11" } });
  await assert.rejects(reader(declared)("o/r", 1, { maxBytes: 10 }), /over 10 bytes/);
  const streamed = async () =>
    new Response(
      new ReadableStream({
        pull(controller) {
          controller.enqueue(new TextEncoder().encode("x".repeat(6)));
        },
      }),
      { status: 200 },
    );
  await assert.rejects(reader(streamed)("o/r", 1, { maxBytes: 10 }), /over 10 bytes/);
});

test("a log answered 500 is fetched once and raises its status", async () => {
  let fetches = 0;
  const fetchImpl = async () => {
    fetches += 1;
    return new Response("", { status: 500 });
  };
  await assert.rejects(reader(fetchImpl)("o/r", 1, { maxBytes: 10 }), (error) => error instanceof GitHubError && error.status === 500);
  assert.equal(fetches, 1);
});

test("the log read goes through the rate guard's latch", async () => {
  const seen = [];
  const fetchImpl = async () => new Response("log\n", { status: 200 });
  assert.equal(await reader(fetchImpl, openLatch(seen))("o/r", 1, { maxBytes: 10 }), "log\n");
  assert.deepEqual(seen, ["https://api.example/repos/o/r/actions/jobs/1/logs"]);
  const shut = { guard: () => async () => {
    throw new Error("latched");
  } };
  await assert.rejects(reader(fetchImpl, shut)("o/r", 1, { maxBytes: 10 }), /latched/);
});
