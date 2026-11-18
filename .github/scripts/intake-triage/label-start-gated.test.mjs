import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { createRateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { labelStartGated } from "./label-start-gated.mjs";

const API = "https://api.github.com";
const REPO = "melodic-software/claude-code-plugins";
const NOW_S = 1_800_000_000;
const RESET = NOW_S + 1800;

const json = (status, body, remaining = 4000) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "x-ratelimit-limit": "5000", "x-ratelimit-remaining": String(remaining), "x-ratelimit-reset": String(RESET), "x-ratelimit-resource": "core" },
  });

async function run(answers, { stop = "" } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "label-start-gated-"));
  try {
    const stopFile = join(dir, "stop");
    if (stop) writeFileSync(stopFile, stop);
    const failed = [];
    const lines = [];
    const latch = createRateLimitLatch({ now: () => NOW_S * 1000, log: (line) => lines.push(line), fail: () => failed.push(true), stopFile, hold: true, sleep: async () => {} });
    const calls = [];
    const fetchImpl = async (url, init = {}) => {
      const key = `${init.method ?? "GET"} ${url.slice(`${API}/repos/${REPO}`.length)}`;
      calls.push({ key, body: init.body });
      const answer = answers[key];
      assert.ok(answer, `an unexpected call: ${key}`);
      return answer();
    };
    const outcome = await labelStartGated({ api: API, repository: REPO, number: "16908", token: "t", latch, fetchImpl, log: (line) => lines.push(line) });
    assert.deepEqual(failed, [], "a rate limit never fails the step");
    return { outcome, calls, lines };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const unlabeled = {
  "GET /issues/16908": () => json(200, { number: 16908, labels: [] }),
  "GET /labels/needs-triage": () => json(200, { name: "needs-triage" }),
  "POST /issues/16908/labels": () => json(200, [{ name: "needs-triage" }]),
};

test("a start-gate stop on an issue with no label adds needs-triage", async () => {
  const { outcome, calls } = await run(unlabeled);
  assert.equal(outcome, "added");
  const posts = calls.filter((call) => call.key.startsWith("POST "));
  assert.equal(posts.length, 1, "one label write");
  assert.equal(posts[0].key, "POST /issues/16908/labels");
  assert.deepEqual(JSON.parse(posts[0].body), { labels: ["needs-triage"] });
});

test("an issue with any label, routing, status or not, gets no write", async () => {
  for (const labels of [[{ name: "bug" }], [{ name: "needs-human" }], [{ name: "spec-container" }]]) {
    const { outcome, calls } = await run({ ...unlabeled, "GET /issues/16908": () => json(200, { number: 16908, labels }) });
    assert.equal(outcome, "labeled", labels[0].name);
    assert.deepEqual(
      calls.map((call) => call.key),
      ["GET /issues/16908"],
      `${labels[0].name}: only the issue read`,
    );
  }
});

test("an exhausted pool on the issue read skips the write and holds green", async () => {
  const { outcome, calls, lines } = await run({
    ...unlabeled,
    "GET /issues/16908": () => json(403, { message: "API rate limit exceeded" }, 0),
  });
  assert.equal(outcome, "rate-limited");
  assert.deepEqual(
    calls.map((call) => call.key),
    ["GET /issues/16908"],
  );
  assert.ok(!lines.some((line) => line.startsWith("::error")), "no error annotation");
});

test("a pool at 50 of 5000, under github-token's 2% stop-floor, stops the label read and the write without sending them", async () => {
  const { outcome, calls } = await run({ ...unlabeled, "GET /issues/16908": () => json(200, { number: 16908, labels: [] }, 50) });
  assert.equal(outcome, "rate-limited");
  assert.deepEqual(
    calls.map((call) => call.key),
    ["GET /issues/16908"],
  );
});

test("a stop an earlier step recorded sends nothing at all", async () => {
  const { outcome, calls } = await run(unlabeled, { stop: `core ${RESET}\n` });
  assert.equal(outcome, "rate-limited");
  assert.equal(calls.length, 0);
});

test("a label the repository lacks is never created", async () => {
  const { outcome, calls } = await run({ ...unlabeled, "GET /labels/needs-triage": () => json(404, { message: "Not Found" }) });
  assert.equal(outcome, "missing-label");
  assert.equal(calls.filter((call) => call.key.startsWith("POST ")).length, 0);
});
