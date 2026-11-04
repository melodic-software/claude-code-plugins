// The read-floor gate's rules (check-read-floor.mjs): skip while the
// GITHUB_TOKEN pool is under read-floor of its planned budget, the header's
// limit at most limit-cap; run at or above it; skip when the pool cannot be
// read. Expected values are worked by hand from limit, remaining and the
// rate-limits.json defaults (read-floor 0.1, limit-cap 1000).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { floorDecision, main } from "./check-read-floor.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const DEFAULTS = { "read-floor": 0.1, "limit-cap": 1000 };

test("under the read floor skips; at or above it runs", () => {
  // 1,000 planned: 99 left is under the 100 floor, 100 is at it.
  assert.deepEqual(floorDecision({ limit: 1000, remaining: 99 }, DEFAULTS), { skip: true, reason: "below-floor", left: 99, planned: 1000 });
  assert.deepEqual(floorDecision({ limit: 1000, remaining: 100 }, DEFAULTS), { skip: false, reason: "ok", left: 100, planned: 1000 });
  assert.equal(floorDecision({ limit: 1000, remaining: 0 }, DEFAULTS).skip, true);
});

test("a header limit over limit-cap plans to the cap", () => {
  // 15,000 limit, capped at 1,000: 900 used leaves 100, 901 used leaves 99.
  assert.equal(floorDecision({ limit: 15000, remaining: 14100 }, DEFAULTS).skip, false);
  assert.deepEqual(floorDecision({ limit: 15000, remaining: 14099 }, DEFAULTS), { skip: true, reason: "below-floor", left: 99, planned: 1000 });
});

test("a reading it cannot take skips", () => {
  for (const reading of [{}, { limit: 0, remaining: 0 }, { limit: 1000, remaining: Number.NaN }, { limit: 1000, remaining: 1001 }, { limit: 1000, remaining: -1 }]) {
    assert.deepEqual(floorDecision(reading, DEFAULTS), { skip: true, reason: "unreadable", left: null, planned: null }, JSON.stringify(reading));
  }
  assert.equal(floorDecision({ limit: 1000, remaining: 900 }, {}).skip, true, "no read-floor margin");
});

const answer = (headers, status = 200) => async () => new Response("{}", { status, headers });
const pool = (remaining, limit = 1000) => answer({ "x-ratelimit-limit": String(limit), "x-ratelimit-remaining": String(remaining), "x-ratelimit-resource": "core" });
const run = async (env, fetchImpl) => {
  const dir = tempDir("read-floor-");
  const output = join(dir, "output");
  writeFileSync(output, "");
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    await main({ GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: output, RUNNER_TEMP: dir, ...env }, { fetchImpl });
  } finally {
    console.log = log;
  }
  return { output: readFileSync(output, "utf8"), lines };
};

test("main reads the pool once and writes skip and reason, with a notice", async () => {
  let calls = 0;
  const below = async (...args) => {
    calls += 1;
    return pool(50)(...args);
  };
  const low = await run({}, below);
  assert.equal(calls, 1);
  assert.equal(low.output, "skip=true\nreason=below-floor\n");
  assert.deepEqual(low.lines, ["::notice title=api-read-floor::github-token left=50 of planned 1000, read-floor=0.1 skip=true reason=below-floor; this run skips its work"]);
  const high = await run({}, pool(900));
  assert.equal(high.output, "skip=false\nreason=ok\n");
  assert.match(high.lines[0], /skip=false reason=ok; the run proceeds$/);
});

test("an answer with no headers, a refused or failed answer, or a failed read skips", async () => {
  assert.equal((await run({}, answer({}))).output, "skip=true\nreason=unreadable\n", "no headers");
  assert.equal((await run({}, answer({ "x-ratelimit-limit": "1000", "x-ratelimit-remaining": "na" }))).output, "skip=true\nreason=unreadable\n");
  // An exhausted pool's refusal carries remaining 0; any refusal skips.
  assert.equal((await run({}, answer({ "x-ratelimit-limit": "1000", "x-ratelimit-remaining": "900" }, 403))).output, "skip=true\nreason=unreadable\n");
  assert.equal((await run({}, answer({}, 502))).output, "skip=true\nreason=unreadable\n");
  const failed = await run({}, async () => {
    throw new Error("down");
  });
  assert.equal(failed.output, "skip=true\nreason=unreadable\n");
  assert.match(failed.lines.join("\n"), /::warning::/);
});

// The action's first step hands the base checkout's limits.api to the gate,
// in resolve-config's output shape; the action sits three levels under it.
const ACTION = readFileSync(new URL("./action.yml", import.meta.url), "utf8");
const READ_RUN = /- name: Read the API margins from the base config\n(?: {6}.*\n)*? {6}run: \|\n((?: {8}.*\n)+)/.exec(ACTION)[1].replace(/^ {8}/gm, "");

const readConfig = (yaml) => {
  const dir = tempDir("read-floor-config-");
  const actionPath = join(dir, ".base/.github/actions/check-read-floor");
  mkdirSync(actionPath, { recursive: true });
  mkdirSync(join(dir, ".base/docs/conventions"), { recursive: true });
  if (yaml !== null) writeFileSync(join(dir, ".base/docs/conventions/pr-pipeline.yaml"), yaml);
  const result = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", READ_RUN], { env: { PATH: process.env.PATH, RUNNER_TEMP: dir, GITHUB_ACTION_PATH: actionPath }, encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  return join(dir, "read-floor-config.json");
};

test("limits.api github-token read-floor in the base config moves the floor", async () => {
  const resolved = readConfig("limits:\n  api:\n    github-token:\n      read-floor: 0.3\n");
  assert.equal((await run({ RESOLVED_CONFIG: resolved }, pool(250))).output, "skip=true\nreason=below-floor\n");
  assert.equal((await run({ RESOLVED_CONFIG: resolved }, pool(300))).output, "skip=false\nreason=ok\n");
});

test("a base config that cannot be read leaves rate-limits.json's floor", async () => {
  const resolved = readConfig(null);
  assert.equal((await run({ RESOLVED_CONFIG: resolved }, pool(99))).output, "skip=true\nreason=below-floor\n");
  assert.equal((await run({ RESOLVED_CONFIG: resolved }, pool(100))).output, "skip=false\nreason=ok\n");
});

test("the CLI writes skip=true when it cannot run its read", () => {
  const dir = tempDir("read-floor-cli-");
  const output = join(dir, "output");
  writeFileSync(output, "");
  // An API URL no fetch can reach, so the read throws.
  const result = spawnSync(process.execPath, [fileURLToPath(new URL("./check-read-floor.mjs", import.meta.url))], {
    env: { PATH: process.env.PATH, GITHUB_OUTPUT: output, GITHUB_REPOSITORY: "o/r", GITHUB_TOKEN: "t", GITHUB_API_URL: "http://127.0.0.1:9" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(output, "utf8"), "skip=true\nreason=unreadable\n");
});
