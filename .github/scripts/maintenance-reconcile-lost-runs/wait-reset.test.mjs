import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { main, resetWait } from "./wait-reset.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const at = (iso) => Date.parse(iso) / 1000;
const RESET = at("2026-11-21T19:55:00Z");

test("a tick 42 minutes before the reset waits until 90 s past it", () => {
  assert.equal(resetWait(RESET, at("2026-11-21T19:13:00Z")), 42 * 60 + 90);
});

test("a tick in a window that began at most 11 minutes ago runs at once, or once 90 s into it", () => {
  assert.equal(resetWait(RESET, at("2026-11-21T19:05:00Z")), 0, "10 minutes into the window that began 18:55Z");
  assert.equal(resetWait(RESET, at("2026-11-21T19:06:00Z")), 0, "11 minutes in, the last minute that runs at once");
  assert.equal(resetWait(RESET, at("2026-11-21T18:55:30Z")), 60, "30 s in: 60 s more to 90 s past 18:55Z");
  assert.equal(resetWait(RESET, at("2026-11-21T19:06:01Z")), 48 * 60 + 59 + 90, "past 11 minutes, it waits for 19:55Z");
});

test("a reset behind now or more than a window ahead is no reading", () => {
  assert.equal(resetWait(RESET, at("2026-11-21T19:55:01Z")), null);
  assert.equal(resetWait(RESET, at("2026-11-21T18:54:59Z")), null);
  assert.equal(resetWait(Number.NaN, at("2026-11-21T19:13:00Z")), null);
});

const response = ({ status = 200, reset = RESET } = {}) => ({
  ok: status === 200,
  status,
  headers: new Headers({ "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4100", "x-ratelimit-reset": String(reset) }),
  json: async () => ({ resources: { core: { limit: 5000, remaining: 4100, reset } } }),
});

const run = async (env, fetchImpl, now = at("2026-11-21T19:13:00Z")) => {
  const output = join(tempDir("wait-reset-"), "output");
  const waits = [];
  const lines = [];
  const calls = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    await main({ GITHUB_TOKEN: "t", GITHUB_OUTPUT: output, ...env }, { fetchImpl: async (url) => (calls.push(url), fetchImpl()), now: () => now, wait: async (s) => waits.push(s) });
  } finally {
    console.log = log;
  }
  return { output: readFileSync(output, "utf8"), waits, lines, calls };
};

test("a scheduled tick reads the reset once, waits, and marks the pass post-reset", async () => {
  const { output, waits, lines, calls } = await run({ EVENT_NAME: "schedule" }, () => response());
  assert.deepEqual(calls, ["https://api.github.com/rate_limit"]);
  assert.deepEqual(waits, [2610]);
  assert.equal(output, "post-reset=true\n");
  assert.deepEqual(lines, [`::notice title=reset-wait::reset=${RESET} (2026-11-21T19:55:00.000Z) now=${at("2026-11-21T19:13:00Z")} wait_seconds=2610`]);
});

test("a dispatched run waits for nothing and reads nothing", async () => {
  const { output, waits, calls } = await run({ EVENT_NAME: "workflow_dispatch" }, () => response());
  assert.deepEqual([calls, waits, output], [[], [], "post-reset=false\n"]);
});

test("a failed or unusable read waits for nothing, warns, and leaves the tick paced as before", async () => {
  for (const [label, reply] of [
    ["a server error", () => response({ status: 502 })],
    ["a reset behind now", () => response({ reset: at("2026-11-21T19:00:00Z") })],
    ["a transport error", () => Promise.reject(new Error("socket hang up"))],
  ]) {
    const { output, waits, lines } = await run({ EVENT_NAME: "schedule" }, reply);
    assert.deepEqual([waits, output], [[], "post-reset=false\n"], label);
    assert.match(lines[0], /^::warning title=reset-wait::the GITHUB_TOKEN reset was not read \(.+\); the pass runs now, paced as before$/, label);
  }
});
