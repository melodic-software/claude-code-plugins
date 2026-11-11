import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { budgetStops, checkBudget, checkKillSwitch, main, START_GATE_SHARE, switchCause, writeOutputs } from "./check-kill-switch.mjs";
import { readOutputs } from "./fixtures/read-outputs.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const SCRIPT = fileURLToPath(new URL("./check-kill-switch.mjs", import.meta.url));
const RATE_LIMITS = fileURLToPath(new URL("../log-api-budget/rate-limits.json", import.meta.url));

// 2026-11-11T12:00:00Z.
const NOW_MS = Date.parse("2026-11-11T12:00:00Z");
const NOW_S = NOW_MS / 1000;
const RESET = NOW_S + 1200;

function runCli(env) {
  const dir = tempDir("kill-switch-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    const result = spawnSync(process.execPath, [SCRIPT], {
      env: { PATH: process.env.PATH, GITHUB_OUTPUT: outputPath, ...env },
      encoding: "utf8",
    });
    return { status: result.status, stdout: result.stdout, outputs: readOutputs(readFileSync(outputPath, "utf8")) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// A GET /rate_limit answer in the shape GitHub's REST docs give: a body with
// resources.core, and x-ratelimit-* headers on the response.
function rateLimitResponse({ headers = {}, core = null, status = 200 } = {}) {
  const body = core ? { resources: { core }, rate: core } : {};
  return new Response(JSON.stringify(body), { status, headers });
}

function recordingFetch(answer) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (answer instanceof Error) throw answer;
    return typeof answer === "function" ? answer() : answer;
  };
  return { calls, fetchImpl };
}

const headersOf = (limit, remaining, reset) => ({
  "x-ratelimit-limit": String(limit),
  "x-ratelimit-remaining": String(remaining),
  "x-ratelimit-reset": String(reset),
  "x-ratelimit-used": String(limit - remaining),
  "x-ratelimit-resource": "core",
});

test("proceeds only when the org and the repository switch both read exactly false", () => {
  assert.deepEqual(checkKillSwitch("false", "false", NOW_MS), { proceed: "true", reason: "ok", cause: "ok" });
});

const NOT_FALSE = [
  ["unset", undefined],
  ["empty", ""],
  ["true", "true"],
  ["FALSE in capitals", "FALSE"],
  ["false with whitespace", " false"],
];

for (const [label, value] of NOT_FALSE) {
  test(`stops when the org switch is ${label}, whatever the repository switch`, () => {
    for (const repo of ["false", "true", undefined]) {
      assert.deepEqual(checkKillSwitch(value, repo, NOW_MS), { proceed: "false", reason: "kill-switch", cause: "switch" });
    }
  });

  test(`stops when the repository switch is ${label} and the org switch is false`, () => {
    assert.deepEqual(checkKillSwitch("false", value, NOW_MS), { proceed: "false", reason: "kill-switch", cause: "switch" });
  });
}

test("true@<time> stops until that time and proceeds from it", () => {
  assert.equal(switchCause("true@2026-11-11T12:00:01Z", NOW_MS), "expiry", "one second ahead");
  assert.equal(switchCause("true@2026-11-11T12:00:00Z", NOW_MS), "ok", "at the time");
  assert.equal(switchCause("true@2026-11-11T11:59:59Z", NOW_MS), "ok", "one second past");
  assert.deepEqual(checkKillSwitch("true@2026-11-11T13:00:00Z", "false", NOW_MS), { proceed: "false", reason: "kill-switch", cause: "expiry" });
  assert.deepEqual(checkKillSwitch("false", "true@2026-11-11T13:00:00Z", NOW_MS), { proceed: "false", reason: "kill-switch", cause: "expiry" });
  assert.deepEqual(checkKillSwitch("true@2026-11-11T11:00:00Z", "true@2026-11-10T00:00:00Z", NOW_MS), { proceed: "true", reason: "ok", cause: "ok" });
});

const MALFORMED = [
  ["no Z", "true@2026-11-11T13:00:00"],
  ["an offset", "true@2026-11-11T13:00:00+00:00"],
  ["no seconds", "true@2026-11-11T13:00Z"],
  ["milliseconds", "true@2026-11-11T13:00:00.000Z"],
  ["a day that does not exist", "true@2026-02-30T00:00:00Z"],
  ["hour 24", "true@2026-11-11T24:00:00Z"],
  ["TRUE in capitals", "TRUE@2026-11-11T13:00:00Z"],
  ["false@", "false@2026-11-11T11:00:00Z"],
  ["a past time with trailing text", "true@2026-11-11T11:00:00Z "],
];

for (const [label, value] of MALFORMED) {
  test(`a timed switch with ${label} stops as a plain switch`, () => {
    assert.equal(switchCause(value, NOW_MS), "switch");
  });
}

test("a plain switch wins over a timed one still ahead", () => {
  assert.deepEqual(checkKillSwitch("true", "true@2026-11-11T13:00:00Z", NOW_MS), { proceed: "false", reason: "kill-switch", cause: "switch" });
  assert.deepEqual(checkKillSwitch("true@2026-11-11T13:00:00Z", "", NOW_MS), { proceed: "false", reason: "kill-switch", cause: "switch" });
});

// share 0.1 of a limit of 5000 is 500.
test("the budget stops under the share of the limit while the reset is ahead", () => {
  const at = (remaining, reset = RESET) => budgetStops({ limit: 5000, remaining, reset }, 0.1, NOW_S);
  assert.equal(at(499), true, "499 left, under 500");
  assert.equal(at(0), true, "nothing left");
  assert.equal(at(500), false, "500 left, at the share");
  assert.equal(at(501), false, "501 left");
  assert.equal(at(10, NOW_S), false, "reset now");
  assert.equal(at(10, NOW_S - 1), false, "reset already past");
  assert.equal(budgetStops({ limit: 5000, remaining: 0, reset: RESET }, 0, NOW_S), false, "share 0 is off");
  assert.equal(budgetStops({ limit: Number.NaN, remaining: 0, reset: RESET }, 0.1, NOW_S), false, "no limit");
});

test("the budget read decides from the headers when they carry limit, remaining and reset", async () => {
  // The body has plenty left; the headers, which GitHub says win, do not.
  const answer = rateLimitResponse({ headers: headersOf(5000, 499, RESET), core: { limit: 5000, remaining: 4000, reset: RESET, used: 1000 } });
  const { calls, fetchImpl } = recordingFetch(answer);
  const result = await checkBudget({ token: "t", api: "https://api.example", share: 0.1, now: NOW_S, fetchImpl });
  assert.equal(result.stop, true);
  assert.equal(calls.length, 1, "exactly one call");
  assert.equal(calls[0].url, "https://api.example/rate_limit");
  assert.equal(calls[0].init.headers.Authorization, "Bearer t");
  assert.equal(
    result.line,
    `::notice title=start-gate::github-token start-gate=0.1 decided from headers: limit=5000 remaining=499 reset=${RESET} stop=true; ` +
      `body core limit=5000 remaining=4000 reset=${RESET} used=1000; headers limit=5000 remaining=499 reset=${RESET} used=4501 resource=core`,
  );
});

test("the budget read proceeds at the share and above it", async () => {
  for (const remaining of [500, 501]) {
    const { fetchImpl } = recordingFetch(rateLimitResponse({ headers: headersOf(5000, remaining, RESET) }));
    const result = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
    assert.equal(result.stop, false, `${remaining} left`);
    assert.match(result.line, /^::notice title=start-gate::.* stop=false; body core absent; /);
  }
});

test("the budget read proceeds when the reset is already past", async () => {
  const { fetchImpl } = recordingFetch(rateLimitResponse({ headers: headersOf(5000, 3, NOW_S - 5) }));
  assert.equal((await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl })).stop, false);
});

test("the budget read falls back to the body's resources.core when a header is missing", async () => {
  const headers = headersOf(5000, 4999, RESET);
  delete headers["x-ratelimit-remaining"];
  const { fetchImpl } = recordingFetch(rateLimitResponse({ headers, core: { limit: 1000, remaining: 99, reset: RESET, used: 901 } }));
  const result = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
  assert.equal(result.stop, true, "99 of 1000 is under 100");
  assert.match(result.line, /decided from body: limit=1000 remaining=99 /);
  assert.match(result.line, /headers limit=5000 remaining=na /);
});

const FAILED_READS = [
  ["a 500", () => rateLimitResponse({ status: 500, headers: headersOf(5000, 0, RESET) }), /HTTP 500/],
  ["a 401", () => rateLimitResponse({ status: 401 }), /HTTP 401/],
  ["a network error", new Error("connect ECONNREFUSED"), /connect ECONNREFUSED/],
  ["no headers and no body reading", () => new Response("not json", { status: 200 }), /neither the headers nor the body/],
];

for (const [label, answer, why] of FAILED_READS) {
  test(`a budget read that meets ${label} proceeds with a warning`, async () => {
    const { calls, fetchImpl } = recordingFetch(answer);
    const result = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
    assert.equal(result.stop, false);
    assert.equal(calls.length, 1, "no retry");
    assert.match(result.line, /^::warning title=start-gate::the GITHUB_TOKEN budget was not read \(/);
    assert.match(result.line, why);
    assert.match(result.line, /; the lane proceeds$/);
  });
}

test("with no token the budget is not read and the lane proceeds with a warning", async () => {
  const { calls, fetchImpl } = recordingFetch(rateLimitResponse({ headers: headersOf(5000, 0, RESET) }));
  const result = await checkBudget({ token: "", share: 0.1, now: NOW_S, fetchImpl });
  assert.deepEqual([result.stop, calls.length], [false, 0]);
  assert.match(result.line, /^::warning title=start-gate::no token/);
});

test("a value in the answer cannot start a workflow command", async () => {
  const headers = { ...headersOf(5000, 4000, RESET), "x-ratelimit-resource": "core%0A::error::x" };
  const { fetchImpl } = recordingFetch(rateLimitResponse({ headers }));
  const { line } = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
  assert.equal(line.split("::").length, 3, "the notice's own two :: only");
  assert.match(line, /resource=core 0A  error  x$/);
});

async function runMain(env, answer, { resolved } = {}) {
  const dir = tempDir("kill-switch-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    let config;
    if (resolved) {
      config = path.join(dir, "resolved.json");
      writeFileSync(config, JSON.stringify(resolved));
    }
    const lines = [];
    const { calls, fetchImpl } = recordingFetch(answer);
    await main({ GITHUB_OUTPUT: outputPath, BUDGET_TOKEN: "t", RESOLVED_CONFIG: config, ...env }, { fetchImpl, now: () => NOW_MS, log: (line) => lines.push(line) });
    return { calls, lines, outputs: readOutputs(readFileSync(outputPath, "utf8")) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const OFF = { KILL_SWITCH_VALUE: "false", REPO_KILL_SWITCH_VALUE: "false" };

test("a switch that stops makes no budget call", async () => {
  const { calls, outputs } = await runMain({ KILL_SWITCH_VALUE: "true", REPO_KILL_SWITCH_VALUE: "false" }, rateLimitResponse({ headers: headersOf(5000, 4000, RESET) }));
  assert.equal(calls.length, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "switch" });
});

test("a low budget stops the lane with reason kill-switch and cause budget", async () => {
  const { calls, lines, outputs } = await runMain(OFF, rateLimitResponse({ headers: headersOf(5000, 499, RESET) }));
  assert.equal(calls.length, 1);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "budget" });
  assert.equal(lines.filter((line) => line.startsWith("::notice title=start-gate::")).length, 1, "one notice per run");
});

test("a budget at the default share proceeds", async () => {
  const { outputs } = await runMain(OFF, rateLimitResponse({ headers: headersOf(5000, 500, RESET) }));
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok" });
});

test("limits.api github-token start-gate in the resolved config overrides the default share", async () => {
  // 0.5 of 5000 is 2500.
  const resolved = { limits: { api: { "github-token": { "start-gate": 0.5 } } } };
  assert.equal((await runMain(OFF, rateLimitResponse({ headers: headersOf(5000, 2499, RESET) }), { resolved })).outputs.cause, "budget");
  assert.equal((await runMain(OFF, rateLimitResponse({ headers: headersOf(5000, 2500, RESET) }), { resolved })).outputs.cause, "ok");
  const off = { limits: { api: { "github-token": { "start-gate": 0 } } } };
  assert.equal((await runMain(OFF, rateLimitResponse({ headers: headersOf(5000, 0, RESET) }), { resolved: off })).outputs.cause, "ok", "0 turns it off");
});

test("a failed budget read proceeds", async () => {
  const { outputs, lines } = await runMain(OFF, new Error("socket hang up"));
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok" });
  assert.ok(lines.some((line) => line.startsWith("::warning title=start-gate::the GITHUB_TOKEN budget was not read (socket hang up)")));
});

test("the fallback share is rate-limits.json's github-token start-gate", () => {
  assert.equal(JSON.parse(readFileSync(RATE_LIMITS, "utf8"))["github-token"]["start-gate"], START_GATE_SHARE);
});

test("CLI writes proceed=true when both switches are exactly false, reads no budget without a token, and exits 0", () => {
  const { status, stdout, outputs } = runCli({ KILL_SWITCH_VALUE: "false", REPO_KILL_SWITCH_VALUE: "false" });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok" });
  assert.match(stdout, /::warning title=start-gate::no token/);
});

test("CLI in a checkout without log-api-budget still writes its outputs and warns", () => {
  const dir = tempDir("kill-switch-sparse-");
  try {
    const script = path.join(dir, "check-kill-switch", "check-kill-switch.mjs");
    mkdirSync(path.dirname(script));
    copyFileSync(SCRIPT, script);
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    const result = spawnSync(process.execPath, [script], {
      env: { PATH: process.env.PATH, GITHUB_OUTPUT: outputPath, KILL_SWITCH_VALUE: "false", REPO_KILL_SWITCH_VALUE: "false" },
      encoding: "utf8",
    });
    assert.equal(result.status, 0);
    assert.match(result.stdout, /::warning title=start-gate::rate-guard\.mjs could not be loaded \(ERR_MODULE_NOT_FOUND\); start-gate share 0\.1/);
    assert.deepEqual(readOutputs(readFileSync(outputPath, "utf8")), { proceed: "true", reason: "ok", cause: "ok" });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("CLI writes proceed=false when the repository switch is unset and exits 0", () => {
  const { status, outputs } = runCli({ KILL_SWITCH_VALUE: "false" });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "switch" });
});

test("CLI writes proceed=false when both variables are unset and exits 0", () => {
  const { status, outputs } = runCli({});
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "switch" });
});

test("output values cannot inject a second output line", () => {
  const dir = tempDir("kill-switch-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    writeOutputs({ "head-ref": "a\nproceed=true" }, outputPath);
    assert.deepEqual(readOutputs(readFileSync(outputPath, "utf8")), {
      "head-ref": "a\nproceed=true",
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
