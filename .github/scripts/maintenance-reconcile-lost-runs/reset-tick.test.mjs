import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { GRACE_SECONDS, main, tickPlan } from "./reset-tick.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const at = (iso) => Date.parse(iso) / 1000;
const RESET = at("2026-11-21T19:55:00Z");
const WINDOW_START = at("2026-11-21T18:55:00Z");

test("a tick up to 30 minutes into the window that began 18:55Z is due, with the pass after 18:56:30Z", () => {
  assert.deepEqual(tickPlan(RESET, at("2026-11-21T19:09:00Z")), { due: true, since: 14 * 60, wait: 0, passAfter: at("2026-11-21T18:56:30Z") });
  assert.equal(tickPlan(RESET, at("2026-11-21T19:25:00Z")).due, true, "30 minutes in");
  assert.deepEqual(tickPlan(RESET, at("2026-11-21T19:25:01Z")), { due: false, since: 30 * 60 + 1 }, "past 30 minutes");
});

test("a tick less than 90 s into the window waits out the rest of the 90 s", () => {
  assert.equal(tickPlan(RESET, at("2026-11-21T18:55:30Z")).wait, 60);
  assert.equal(tickPlan(RESET, at("2026-11-21T18:56:30Z")).wait, 0);
});

test("a reset behind now or more than a window ahead is no reading", () => {
  assert.equal(tickPlan(RESET, at("2026-11-21T19:55:01Z")), null);
  assert.equal(tickPlan(RESET, at("2026-11-21T18:54:59Z")), null);
  assert.equal(tickPlan(Number.NaN, at("2026-11-21T19:09:00Z")), null);
});

test("the longest wait and the slowest measured pass fit check-trusted-trigger's window for a reconciler record", () => {
  const source = readFileSync(new URL("../../actions/check-trusted-trigger/check-trusted-trigger.mjs", import.meta.url), "utf8");
  const [, minutes] = /^const WINDOW_MS = ([0-9]+) \* 60 \* 1000;$/m.exec(source) ?? [];
  assert.ok(minutes, "check-trusted-trigger.mjs WINDOW_MS is read");
  const slowestPassSeconds = 112;
  assert.ok(GRACE_SECONDS + slowestPassSeconds < Number(minutes) * 60, `${GRACE_SECONDS} s + ${slowestPassSeconds} s under ${minutes} minutes`);
});

test("the workflow ticks every 15 minutes, off the hour", () => {
  const text = readFileSync(new URL("../../workflows/maintenance-reconcile-lost-runs.yml", import.meta.url), "utf8");
  assert.match(text, /\n {4}- cron: "4,19,34,49 \* \* \* \*"\n/);
});

const response = ({ status = 200, reset = RESET } = {}) => ({
  ok: status === 200,
  status,
  headers: new Headers({ "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4100", "x-ratelimit-reset": String(reset) }),
  json: async () => ({ resources: { core: { limit: 5000, remaining: 4100, reset } } }),
});

const run = async (env, fetchImpl, now = at("2026-11-21T19:09:00Z")) => {
  const output = join(tempDir("reset-tick-"), "output");
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

test("a due tick reads the reset once and names the window's pass-after", async () => {
  const { output, waits, lines, calls } = await run({ EVENT_NAME: "schedule" }, () => response());
  assert.deepEqual(calls, ["https://api.github.com/rate_limit"]);
  assert.deepEqual(waits, [0]);
  assert.equal(output, `due=true\npost-reset=true\npass-after=${WINDOW_START + 90}\n`);
  assert.deepEqual(lines, [`::notice title=reset-tick::reset=${RESET} now=${at("2026-11-21T19:09:00Z")} since_window_start=840 due=true wait_seconds=0`]);
});

test("a tick past the window's first 30 minutes is not due", async () => {
  const { output, waits } = await run({ EVENT_NAME: "schedule" }, () => response(), at("2026-11-21T19:34:00Z"));
  assert.deepEqual([waits, output], [[], "due=false\npost-reset=false\npass-after=\n"]);
});

test("a dispatched run is due and reads nothing", async () => {
  const { output, calls } = await run({ EVENT_NAME: "workflow_dispatch" }, () => response());
  assert.deepEqual([calls, output], [[], "due=true\npost-reset=false\npass-after=\n"]);
});

test("a failed or unusable read leaves the tick due with no pass-after, and warns", async () => {
  for (const [label, reply] of [
    ["a server error", () => response({ status: 502 })],
    ["a reset behind now", () => response({ reset: at("2026-11-21T19:00:00Z") })],
    ["a transport error", () => Promise.reject(new Error("socket hang up"))],
  ]) {
    const { output, waits, lines } = await run({ EVENT_NAME: "schedule" }, reply);
    assert.deepEqual([waits, output], [[], "due=true\npost-reset=false\npass-after=\n"], label);
    assert.match(lines.at(-1), /^::warning title=reset-tick::the GITHUB_TOKEN reset was not read \(.+\); the pass runs unless one ran in the last hour$/, label);
  }
});
