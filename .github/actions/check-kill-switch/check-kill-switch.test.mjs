// test-scope: .github/workflows/*.yml
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { budgetStops, checkBudget, checkKillSwitch, deferGate, main, projectionGate, startGateShare, writeOutputs } from "./check-kill-switch.mjs";
import { readOutputs } from "./fixtures/read-outputs.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { WAIT_BUDGET_SECONDS } from "../log-api-budget/rate-guard.mjs";

const SCRIPT = fileURLToPath(new URL("./check-kill-switch.mjs", import.meta.url));
const WORKFLOWS = fileURLToPath(new URL("../../workflows/", import.meta.url));

const NOW_MS = Date.parse("2026-11-11T12:00:00Z");
const NOW_S = NOW_MS / 1000;
const RESET = NOW_S + 1200;

function runCli(env, script = SCRIPT) {
  const dir = tempDir("kill-switch-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    const result = spawnSync(process.execPath, [script], {
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
  assert.deepEqual(checkKillSwitch("false", "false"), { proceed: "true", reason: "ok", cause: "ok" });
});

const NOT_FALSE = [
  ["unset", undefined],
  ["empty", ""],
  ["true", "true"],
  ["FALSE in capitals", "FALSE"],
  ["false with whitespace", " false"],
  ["a timed value", "true@2026-11-11T11:00:00Z"],
];

for (const [label, value] of NOT_FALSE) {
  test(`stops when the org switch is ${label}, whatever the repository switch`, () => {
    for (const repo of ["false", "true", undefined]) {
      assert.deepEqual(checkKillSwitch(value, repo), { proceed: "false", reason: "kill-switch", cause: "switch" });
    }
  });

  test(`stops when the repository switch is ${label} and the org switch is false`, () => {
    assert.deepEqual(checkKillSwitch("false", value), { proceed: "false", reason: "kill-switch", cause: "switch" });
  });
}

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
  assert.equal(result.reset, RESET);
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
  const { fetchImpl } = recordingFetch(rateLimitResponse({ headers, core: { limit: 1000, remaining: 99, reset: RESET + 60, used: 901 } }));
  const result = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
  assert.equal(result.stop, true, "99 of 1000 is under 100");
  assert.equal(result.reset, RESET + 60, "the body's reset");
  assert.match(result.line, /decided from body: limit=1000 remaining=99 /);
  assert.match(result.line, /headers limit=5000 remaining=na /);
});

// GitHub answers an exhausted token with 403 or 429, x-ratelimit-remaining 0
// and, for a secondary limit, retry-after in seconds; another call would be
// refused too, so each stops with a reset still ahead.
const REFUSED_READS = [
  ["a 403 with the window's reset", () => rateLimitResponse({ status: 403, headers: headersOf(5000, 0, RESET) }), RESET],
  ["a 429 with retry-after 30", () => rateLimitResponse({ status: 429, headers: { "retry-after": "30" } }), NOW_S + 30],
  ["a bare 403", () => rateLimitResponse({ status: 403 }), NOW_S + 60],
  ["a bare 429", () => rateLimitResponse({ status: 429 }), NOW_S + 60],
  ["a 200 with retry-after 120", () => rateLimitResponse({ headers: { "retry-after": "120" } }), NOW_S + 120],
  ["a 200 with remaining 0 and a reset already past", () => rateLimitResponse({ headers: headersOf(5000, 0, NOW_S - 5) }), NOW_S + 60],
  ["a 500 with remaining 0", () => rateLimitResponse({ status: 500, headers: headersOf(5000, 0, RESET) }), RESET],
];

for (const [label, answer, reset] of REFUSED_READS) {
  test(`a budget read that meets ${label} stops with a future reset and makes no other call`, async () => {
    const { calls, fetchImpl } = recordingFetch(answer);
    const result = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
    assert.equal(result.stop, true);
    assert.equal(result.reset, reset);
    assert.equal(calls.length, 1, "no retry");
    assert.match(result.line, new RegExp(`^::warning title=start-gate::the GITHUB_TOKEN budget read was refused \\(HTTP \\d+ .*\\); the lane stops until ${reset}$`));
  });
}

const FAILED_READS = [
  ["a 500", () => rateLimitResponse({ status: 500 }), /HTTP 500/],
  ["a 503 with headers to spare", () => rateLimitResponse({ status: 503, headers: headersOf(5000, 4000, RESET) }), /HTTP 503/],
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

async function runMain(env, answer, { rateLimits, resolved } = {}) {
  const dir = tempDir("kill-switch-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    let limitsPath;
    if (rateLimits !== undefined) {
      limitsPath = path.join(dir, "rate-limits.json");
      writeFileSync(limitsPath, typeof rateLimits === "string" ? rateLimits : JSON.stringify(rateLimits));
    }
    let resolvedPath;
    if (resolved !== undefined) {
      resolvedPath = path.join(dir, "resolved.json");
      writeFileSync(resolvedPath, JSON.stringify(resolved));
    }
    const lines = [];
    const { calls, fetchImpl } = recordingFetch(answer);
    await main(
      { GITHUB_OUTPUT: outputPath, BUDGET_TOKEN: "t", ...(resolvedPath && { RESOLVED_CONFIG: resolvedPath }), ...env },
      { fetchImpl, now: () => NOW_MS, log: (line) => lines.push(line), ...(limitsPath && { rateLimits: limitsPath }) },
    );
    return { calls, lines, outputs: readOutputs(readFileSync(outputPath, "utf8")) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const OFF = { KILL_SWITCH_VALUE: "false", REPO_KILL_SWITCH_VALUE: "false" };
const START = { ...OFF, BUDGET_CHECK: "true" };
const empty = () => rateLimitResponse({ headers: headersOf(5000, 0, RESET) });

for (const status of [403, 429]) {
  test(`a start gate whose budget read meets a ${status} stops with cause budget after one call`, async () => {
    const { calls, outputs } = await runMain(START, () => rateLimitResponse({ status }));
    assert.equal(calls.length, 1, "no retry");
    assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "budget", reset: String(NOW_S + 60) });
  });
}

test("by default the gate checks the switches only and makes no /rate_limit call", async () => {
  for (const value of [undefined, "", "false", "FALSE", "yes"]) {
    const { calls, lines, outputs } = await runMain({ ...OFF, BUDGET_CHECK: value }, empty);
    assert.equal(calls.length, 0, `BUDGET_CHECK=${JSON.stringify(value)}`);
    assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" }, "an empty pool does not stop it");
    assert.ok(!lines.some((line) => line.includes("start-gate")), "no start-gate notice or warning");
  }
  const { calls, outputs } = await runMain({ KILL_SWITCH_VALUE: "true", REPO_KILL_SWITCH_VALUE: "false" }, empty);
  assert.deepEqual([calls.length, outputs], [0, { proceed: "false", reason: "kill-switch", cause: "switch", reset: "" }]);
});

test("a start gate whose switch stops makes no budget call", async () => {
  const { calls, outputs } = await runMain({ ...START, KILL_SWITCH_VALUE: "true" }, empty);
  assert.equal(calls.length, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "switch", reset: "" });
});

test("a low budget stops a start gate with reason kill-switch, cause budget and the window's reset", async () => {
  const { calls, lines, outputs } = await runMain(START, rateLimitResponse({ headers: headersOf(5000, 499, RESET) }));
  assert.equal(calls.length, 1);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "budget", reset: String(RESET) });
  assert.equal(lines.filter((line) => line.startsWith("::notice title=start-gate::")).length, 1, "one notice per run");
  assert.ok(lines.includes(`check-kill-switch: proceed=false reason=kill-switch cause=budget reset=${RESET}`));
});

test("a start gate at the share proceeds", async () => {
  const { outputs } = await runMain(START, rateLimitResponse({ headers: headersOf(5000, 500, RESET) }));
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
});

test("the share is rate-limits.json's github-token start-gate", async () => {
  const half = { "github-token": { "start-gate": 0.5 } };
  assert.equal((await runMain(START, rateLimitResponse({ headers: headersOf(5000, 2499, RESET) }), { rateLimits: half })).outputs.cause, "budget");
  assert.equal((await runMain(START, rateLimitResponse({ headers: headersOf(5000, 2500, RESET) }), { rateLimits: half })).outputs.cause, "ok");
  const off = await runMain(START, empty, { rateLimits: { "github-token": { "start-gate": 0 } } });
  assert.deepEqual([off.outputs.cause, off.calls.length], ["ok", 0], "0 turns it off: no read");
  assert.equal(startGateShare(fileURLToPath(new URL("../log-api-budget/rate-limits.json", import.meta.url)), () => {}), 0.1, "the shipped value");
});

test("a share that cannot be read makes no call and proceeds with a warning", async () => {
  for (const [label, rateLimits] of [
    ["not JSON", "{"],
    ["no start-gate", { "github-token": {} }],
    ["a share over 1", { "github-token": { "start-gate": 2 } }],
  ]) {
    const { calls, lines, outputs } = await runMain(START, empty, { rateLimits });
    assert.equal(calls.length, 0, label);
    assert.equal(outputs.cause, "ok", label);
    assert.ok(lines.some((line) => line.startsWith("::warning title=start-gate::rate-limits.json gave no start-gate share")), label);
  }
});

const PROJECT = { ...START, PROJECT_CHECK: "true" };
const reading = (remaining, resetIn) => rateLimitResponse({ headers: headersOf(5000, remaining, NOW_S + resetIn) });

test("a window projected to empty before a typical run ends holds the start, with the window's reset", async () => {
  const { lines, outputs } = await runMain(PROJECT, reading(2000, 1800));
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "budget", reset: String(NOW_S + 1800) }, "30 min in, 3000 used: 2000 - 3000 x 1260 / 1800 is under 0");
  const notice = lines.find((line) => line.startsWith("::notice title=start-gate::"));
  assert.match(notice, /stop=true; projected left 0 of the limit 21 min ahead or at the reset, against start-project=0\.3 \(start-run-minutes=21\) stop=true: /);
});

test("tonight's 21:51Z start, 86% left 5 min into the window, holds", async () => {
  const { lines, outputs } = await runMain(PROJECT, reading(4300, 3300));
  assert.equal(outputs.cause, "budget", "4300 - 700 x 1260 / 300 = 1360, 0.27 of 5000, under 0.3");
  assert.ok(lines.some((line) => line.includes("projected left 0.27 of the limit")));
});

test("a quiet window lets the start go", async () => {
  const { lines, outputs } = await runMain(PROJECT, reading(4700, 1800));
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" }, "30 min in, 300 used: 4700 - 300 x 1260 / 1800 = 4490, 0.9 of 5000");
  assert.ok(lines.some((line) => line.includes("projected left 0.9 of the limit") && line.includes("stop=false; body core")));
});

test("the projection stops at the reset when the reset comes before the run's end", async () => {
  const { lines, outputs } = await runMain(PROJECT, reading(2000, 300));
  assert.equal(outputs.cause, "ok", "reset in 300 s: 2000 - 3000 x 300 / 3300 = 1727, 0.35; the full 1260 s would leave 0.17 and hold");
  assert.ok(lines.some((line) => line.includes("projected left 0.35 of the limit")));
});

test("the projection gate adds to the start-gate share and never replaces it", async () => {
  const low = await runMain(PROJECT, reading(499, 30));
  assert.equal(low.outputs.cause, "budget", "499 left stops on the start-gate share");
  assert.ok(!low.lines.some((line) => line.includes("projected left")), "the projection is not consulted after a share stop");
  assert.equal((await runMain(START, reading(2000, 1800))).outputs.cause, "ok", "without PROJECT_CHECK a projected-empty window proceeds");
});

test("a projection gate that cannot be set up proceeds on the start-gate share alone, with a warning", async () => {
  for (const [label, rateLimits] of [
    ["no start-project", { "github-token": { "start-gate": 0.1, plan: 0.7, "start-run-minutes": 21 } }],
    ["no start-run-minutes", { "github-token": { "start-gate": 0.1, "start-project": 0.3 } }],
    ["fractional minutes", { "github-token": { "start-gate": 0.1, "start-project": 0.3, "start-run-minutes": 1.5 } }],
  ]) {
    const { lines, outputs } = await runMain(PROJECT, reading(2000, 1800), { rateLimits });
    assert.equal(outputs.cause, "ok", label);
    assert.ok(lines.some((line) => line.startsWith("::warning title=start-gate::the projection gate could not be set up")), label);
  }
});

test("the shipped projection gate is start-project 0.3 over a 21-minute run", () => {
  const gate = projectionGate(fileURLToPath(new URL("../log-api-budget/rate-limits.json", import.meta.url)), () => {});
  assert.deepEqual([gate.share, gate.minutes], [0.3, 21]);
});

const SHIPPED_LIMITS = fileURLToPath(new URL("../log-api-budget/rate-limits.json", import.meta.url));
const limitsWith = (fields) => {
  const limits = JSON.parse(readFileSync(SHIPPED_LIMITS, "utf8"));
  limits["github-token"] = { ...limits["github-token"], ...fields };
  for (const [key, value] of Object.entries(fields)) if (value === undefined) delete limits["github-token"][key];
  return limits;
};
const DEFER = { ...OFF, DEFER_CHECK: "true", RUN_ATTEMPT: "1" };

test("the shipped defer gate is defer-project 0.3 over a 15-minute horizon", async () => {
  const gate = await deferGate({ rateLimits: SHIPPED_LIMITS, log: () => {} });
  assert.deepEqual([gate.share, gate.minutes], [0.3, 15]);
});

test("a window projected to run short before the job ends defers it, with cause defer, the reset and a notice naming both", async () => {
  const { calls, lines, outputs } = await runMain(DEFER, reading(2000, 1800));
  assert.equal(calls.length, 1, "one budget read");
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "defer", reset: String(NOW_S + 1800) }, "30 min in, 3000 used: 2000 - 3000 x 900 / 1800 is 500, 0.1 of 5000");
  assert.ok(lines.some((line) => line.startsWith("::notice title=defer-gate::github-token defer decided from headers:") && line.includes("projected left 0.1 of the limit 15 min ahead or at the reset, against defer-project=0.3 (defer-run-minutes=15) stop=true")));
  assert.ok(
    lines.includes(
      `::notice title=defer::deferred until the GITHUB_TOKEN window resets at ${NOW_S + 1800} (2026-11-11T12:30:00Z): the window is projected to have 0.1 of its limit left 15 min ahead or at the reset, under defer-project=0.3; cause=defer, so a later run after the reset does this work`,
    ),
  );
  assert.ok(lines.includes(`check-kill-switch: proceed=false reason=kill-switch cause=defer reset=${NOW_S + 1800}`));
  assert.ok(!lines.some((line) => line.includes("start-gate")), "no start-gate label on the defer path");
});

test("a quiet window lets a deferrable job go", async () => {
  const { outputs } = await runMain(DEFER, reading(4700, 1800));
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
});

test("the defer gate reads no start-gate floor: under start-gate but projected above defer-project, it proceeds", async () => {
  const { outputs } = await runMain(DEFER, reading(400, 30), { rateLimits: limitsWith({ "defer-project": 0.05 }) });
  assert.equal(outputs.cause, "ok", "400 left, under start-gate's 500, reset in 30 s: 400 - 4600 x 30 / 3570 = 361, 0.07 of 5000");
  assert.equal((await runMain(START, reading(400, 30))).outputs.cause, "budget", "the start gate stops the same reading");
});

test("a re-run attempt never defers and makes no budget read", async () => {
  for (const attempt of ["2", "3", "", "x", undefined]) {
    const { calls, outputs } = await runMain({ ...DEFER, RUN_ATTEMPT: attempt }, empty);
    assert.deepEqual([calls.length, outputs.cause], [0, "ok"], `RUN_ATTEMPT=${JSON.stringify(attempt)}`);
  }
});

test("defer-project 0 turns deferral off, from rate-limits.json or the resolved config, with no budget read", async () => {
  const fromFile = await runMain(DEFER, empty, { rateLimits: limitsWith({ "defer-project": 0 }) });
  assert.deepEqual([fromFile.calls.length, fromFile.outputs.cause], [0, "ok"]);
  const fromConfig = await runMain(DEFER, empty, { resolved: { limits: { api: { "github-token": { "defer-project": 0 } } } } });
  assert.deepEqual([fromConfig.calls.length, fromConfig.outputs.cause], [0, "ok"]);
});

test("the resolved config overrides the shipped share and horizon", async () => {
  const config = (fields) => ({ limits: { api: { "github-token": fields } } });
  const why = "30 min in, 3000 used, 2000 left: 5 min ahead leaves 2000 - 500 = 1500, 0.3 of 5000";
  assert.equal((await runMain(DEFER, reading(2000, 1800), { resolved: config({ "defer-project": 0.35, "defer-run-minutes": 5 }) })).outputs.cause, "defer", why);
  assert.equal((await runMain(DEFER, reading(2000, 1800), { resolved: config({ "defer-project": 0.25, "defer-run-minutes": 5 }) })).outputs.cause, "ok", why);
});

test("the shipped horizon for defer-job review is 8 minutes", async () => {
  const gate = await deferGate({ rateLimits: SHIPPED_LIMITS, job: "review", log: () => {} });
  assert.deepEqual([gate.minutes, gate.labels.minutes], [8, "defer-run-minutes-review"]);
});

test("the shipped horizon for defer-job pr-merge is 6 minutes, and an unset job key reads defer-run-minutes", async () => {
  assert.equal((await deferGate({ rateLimits: SHIPPED_LIMITS, job: "pr-merge", log: () => {} })).minutes, 6);
  const other = await deferGate({ rateLimits: SHIPPED_LIMITS, job: "pr-verify", log: () => {} });
  assert.deepEqual([other.minutes, other.labels.minutes], [15, "defer-run-minutes"]);
});

test("a conventions override of the job's horizon key changes the projection", async () => {
  const why = "30 min in, 3000 used, 2000 left: 5 min ahead leaves 1500, 0.3 of 5000; 6 min ahead leaves 1400, 0.28";
  const job = { ...DEFER, DEFER_JOB: "pr-merge" };
  const shipped = await runMain(job, reading(2000, 1800), { resolved: { limits: { api: { "github-token": { "defer-project": 0.29 } } } } });
  assert.equal(shipped.outputs.cause, "defer", why);
  assert.ok(shipped.lines.some((line) => line.includes("6 min ahead or at the reset, against defer-project=0.29 (defer-run-minutes-pr-merge=6)")));
  const overridden = await runMain(job, reading(2000, 1800), { resolved: { limits: { api: { "github-token": { "defer-project": 0.29, "defer-run-minutes-pr-merge": 5 } } } } });
  assert.equal(overridden.outputs.cause, "ok", why);
  assert.ok(overridden.lines.some((line) => line.includes("(defer-run-minutes-pr-merge=5)")));
});

test("the gate's defer-minutes input sets the job's horizon over defer-run-minutes", async () => {
  const { lines, outputs } = await runMain({ ...DEFER, DEFER_MINUTES: "5" }, reading(2000, 1800), { resolved: { limits: { api: { "github-token": { "defer-project": 0.35 } } } } });
  assert.equal(outputs.cause, "defer");
  assert.ok(lines.some((line) => line.includes("5 min ahead or at the reset, against defer-project=0.35 (defer-minutes=5)")));
});

test("a defer gate that cannot be set up proceeds with a warning and no budget read", async () => {
  for (const [label, env, options] of [
    ["fractional defer-minutes", { DEFER_MINUTES: "1.5" }, {}],
    ["defer-minutes 0", { DEFER_MINUTES: "0" }, {}],
    ["a defer-job that is no key suffix", { DEFER_JOB: "Pr Merge" }, {}],
    ["a fractional job horizon in the config", { DEFER_JOB: "pr-merge" }, { resolved: { limits: { api: { "github-token": { "defer-run-minutes-pr-merge": 0.5 } } } } }],
    ["a share over 1 in the config", {}, { resolved: { limits: { api: { "github-token": { "defer-project": 2 } } } } }],
    ["a fractional horizon in the config", {}, { resolved: { limits: { api: { "github-token": { "defer-run-minutes": 2.5 } } } } }],
  ]) {
    const { calls, lines, outputs } = await runMain({ ...DEFER, ...env }, empty, options);
    assert.deepEqual([calls.length, outputs.cause], [0, "ok"], label);
    assert.ok(lines.some((line) => line.startsWith("::warning title=defer-gate::the defer gate could not be set up")), label);
  }
});

test("a refused read defers, as a refused start-gate read stops", async () => {
  const { outputs, lines } = await runMain(DEFER, () => rateLimitResponse({ status: 429 }));
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "defer", reset: String(NOW_S + 60) });
  assert.ok(lines.some((line) => line.startsWith("::notice title=defer::deferred until") && line.includes(": the budget read was refused; cause=defer")));
});

test("a failed read on the defer path proceeds", async () => {
  const { outputs } = await runMain(DEFER, new Error("socket hang up"));
  assert.equal(outputs.cause, "ok");
});

test("a switch stop on a defer gate makes no budget read", async () => {
  const { calls, outputs } = await runMain({ ...DEFER, KILL_SWITCH_VALUE: "true" }, empty);
  assert.deepEqual([calls.length, outputs.cause], [0, "switch"]);
});

test("the defer path never waits for the reset", async () => {
  const { sleeps, outputs } = await runWaiting({ ...DEFER, WAIT_SECONDS: "1200" }, [() => reading(500, 100)]);
  assert.deepEqual([sleeps.length, outputs.cause], [0, "defer"], "reset in 100 s: 500 - 4500 x 100 / 3500 = 371, 0.07 of 5000");
});

test("a failed budget read proceeds", async () => {
  const { outputs, lines } = await runMain(START, new Error("socket hang up"));
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
  assert.ok(lines.some((line) => line.startsWith("::warning title=start-gate::the GITHUB_TOKEN budget was not read (socket hang up)")));
});

const GATES = {
  "pr-run-plugin-evals.yml": { "run-eval": "switch", "run-eval-subscription": "switch", "compare-prepare": "switch", "compare-record": "switch" },
  "maintenance-measure-skill-edit-pass.yml": { "run-eval": "switch", "run-eval-subscription": "switch" },
  "intake-reenter.yml": { reenter: "start" },
  "intake-triage.yml": {
    "check-kill-switch": "start",
    "apply-verdict": "switch",
    "refine-select": "start",
    "refine-issue": "switch",
    "refine-issue-subscription": "switch",
    "refine-issue-fallback": "switch",
    "apply-refinement": "switch",
  },
  "maintenance-audit-lane-runs.yml": {
    collect: "start",
    "assess-units": "switch",
    "collect-key-handoffs": "switch",
    "assess-units-subscription": "switch",
    "collect-subscription-handoffs": "switch",
    "assess-units-fallback": "switch",
    file: "switch",
    "triage-sweep": "start",
  },
  "maintenance-delete-stale-branches.yml": { "select-stale-branches": "start", delete: "switch" },
  "maintenance-file-recurring-issues.yml": { "file-recurring-issues": "start" },
  "maintenance-measure-skill-edit.yml": { "check-inputs": "start", "generate-edit": "switch", "push-branch": "switch", publish: "switch" },
  "maintenance-monitor-signals.yml": { monitor: "start" },
  "maintenance-reconcile-lost-runs.yml": { reconcile: "start" },
  "maintenance-tidy-code-upkeep.yml": { "select-areas": "start", "sweep-areas": "switch", "sweep-areas-subscription": "switch", "sweep-areas-fallback": "switch", "push-branches": "switch", publish: "switch" },
  "post-merge-file-demotion-issues.yml": { "report-red-main": "switch" },
  "post-merge-test-mutation.yml": { "check-range": "start" },
  "pr-dispatch-feedback.yml": { "post-verify-notes": "switch", dispatch: "switch", "rerun-ci-status": "switch" },
  "pr-merge.yml": { "dispatch-post-merge-runs": "switch", merge: "switch", "enable-auto-merge": "defer" },
  "pr-rate-merge-risk.yml": { "rate-merge-risk": "switch", "rate-merge-risk-subscription": "switch", "rate-merge-risk-fallback": "switch" },
  "pr-review-hosted.yml": { "check-kill-switch": "defer" },
  "pr-review-main.yml": { "check-trigger": "switch", "collect-trusted-text": "switch", review: "switch", "review-subscription": "switch", "review-fallback": "switch" },
  "pr-review-security-hosted.yml": { "check-kill-switch": "defer" },
  "pr-run-activity-read.yml": { "check-broker": "first-call", run: "switch" },
  "pr-run-activity-write.yml": { run: "switch" },
  "pr-unblock-dispatch.yml": { dispatch: "switch", refine: "switch" },
  "pr-unblock.yml": {
    "resolve-conflicts-select": "switch",
    "sync-shared-copies-select": "switch",
    "fix-test-scope-select": "switch",
    "address-feedback-select": "switch",
    "adjudicate-feedback": "switch",
    "review-dependency-select": "switch",
    "fix-ci-context": "switch",
  },
  "pr-verify.yml": { "check-intent": ["switch", "defer"], "check-intent-subscription": "switch", "check-intent-fallback": "switch" },
  "upstream-apply-changelog.yml": {
    "select-release": "start",
    "apply-changelog": "switch",
    "apply-changelog-subscription": "switch",
    "apply-changelog-fallback": "switch",
    "verify-env-scrub": "switch",
    "verify-env-scrub-subscription": "switch",
    "verify-env-scrub-fallback": "switch",
    "check-claude-function-flags": "switch",
    "check-native-surfaces": "switch",
    "push-native-baseline": "switch",
    "publish-native-baseline": "switch",
    "push-branches": "switch",
    publish: "switch",
  },
  "work-resolve-issue.yml": { "check-admission": "switch", "pick-slot": "switch" },
  "work-unblock.yml": { "label-unblocked": "start", "publish-lane-level": "switch", "sync-status": "switch" },
};

const DEFER_INPUTS = {
  "pr-merge.yml": /^ {10}defer: \$\{\{ inputs\.pr && 'true' \|\| 'false' \}\}$/m,
  "pr-review-hosted.yml": /^ {10}defer: "true"$/m,
  "pr-review-security-hosted.yml": /^ {10}defer: "true"$/m,
  "pr-verify.yml": /^ {10}defer: "true"$/m,
};
const FIRST_CALL = /^ {10}budget: \$\{\{ inputs\.start-gate && \(inputs\.fallback == '' \|\| inputs\.fallback == 'credit-stop' \|\| inputs\.fallback == 'no-key'\) && 'true' \|\| 'false' \}\}$/m;
const FIRST_CALL_PROJECT = /^ {10}project: \$\{\{ inputs\.start-gate && \(inputs\.fallback == '' \|\| inputs\.fallback == 'credit-stop' \|\| inputs\.fallback == 'no-key'\) && 'true' \|\| 'false' \}\}$/m;

const START_CALLS = {
  "work-resolve-issue.yml": ["resolve-issue", "resolve-issue-subscription"],
};

test("only the issue lane's first-call read-runner calls pass start-gate", () => {
  const passing = {};
  for (const file of readdirSync(WORKFLOWS).filter((name) => name.endsWith(".yml"))) {
    const lines = readFileSync(path.join(WORKFLOWS, file), "utf8").split("\n");
    const starting = [];
    let job = null;
    lines.forEach((line, i) => {
      const id = /^ {2}([a-z][a-z0-9-]*):$/.exec(line);
      if (id) job = id[1];
      if (!/^ {4}uses: \.\/\.github\/workflows\/pr-run-activity-read\.yml\b/.test(line)) return;
      const next = lines.findIndex((other, j) => j > i && /^ {2}[a-z]/.test(other));
      if (/^ {6}start-gate: true$/m.test(lines.slice(i, next < 0 ? undefined : next).join("\n"))) starting.push(job);
    });
    if (starting.length) passing[file] = starting;
  }
  assert.deepEqual(passing, START_CALLS);
});

function gatesIn(file) {
  const lines = readFileSync(path.join(WORKFLOWS, file), "utf8").split("\n");
  const jobsAt = lines.indexOf("jobs:");
  const found = [];
  let job = null;
  let index = 0;
  lines.forEach((line, i) => {
    const id = i > jobsAt && /^ {2}([a-z][a-z0-9-]*):$/.exec(line);
    if (id) [job, index] = [id[1], 0];
    if (!/^\s*(?:-\s+)?uses:\s*["']?[^\s"'#]*actions\/check-kill-switch(?:@[^\s"'#]*)?["']?\s*(?:#.*)?$/.test(line)) return;
    const next = lines.findIndex((other, j) => j > i && /^ {6}- |^ {2}[a-z]/.test(other));
    found.push({ job, index, step: lines.slice(i, next < 0 ? undefined : next).join("\n") });
    index += 1;
  });
  return found;
}

const kindsOf = (kind) => (Array.isArray(kind) ? kind : [kind]);
const kindOf = (file, job, index) => {
  const kind = GATES[file]?.[job];
  return Array.isArray(kind) ? kind[index] : kind;
};

test("every gate in the workflows is classified, and only start gates read the budget", () => {
  const seen = new Set();
  for (const file of readdirSync(WORKFLOWS).filter((name) => name.endsWith(".yml"))) {
    for (const { job, index, step } of gatesIn(file)) {
      const kind = kindOf(file, job, index);
      assert.ok(kind, `${file} ${job}: a gate this test does not classify as start or switch`);
      seen.add(`${file} ${job} ${index}`);
      if (kind === "start") {
        assert.match(step, /^ {10}budget: "true"$/m, `${file} ${job} starts new work`);
        assert.doesNotMatch(step, /project:/, `${file} ${job}: the projection gate is the issue lane's alone`);
      } else if (kind === "first-call") {
        assert.match(step, FIRST_CALL, `${file} ${job} starts new work on a starting caller's first call only`);
        assert.match(step, FIRST_CALL_PROJECT, `${file} ${job} projects the window on a starting caller's first call only`);
      } else if (kind === "defer") {
        assert.match(step, DEFER_INPUTS[file], `${file} ${job} defers only the runs a later run recovers`);
        assert.match(step, /^ {10}resolved-config: \$\{\{ runner\.temp \}\}\/defer-config\.json$/m, `${file} ${job} reads the repository's override`);
        assert.match(step, /^ {10}defer-job: [a-z0-9-]+$/m, `${file} ${job} names its horizon key`);
        assert.doesNotMatch(step, /^ {10}defer-minutes:/m, `${file} ${job} reads its horizon from the config`);
        assert.doesNotMatch(step, /budget:|project:/, `${file} ${job} reads no start-gate floor`);
      } else {
        assert.doesNotMatch(step, /budget:|project:|^ {10}defer/m, `${file} ${job} checks the switches only`);
      }
    }
  }
  for (const [file, jobs] of Object.entries(GATES)) {
    for (const [job, kind] of Object.entries(jobs)) {
      kindsOf(kind).forEach((_, index) => assert.ok(seen.has(`${file} ${job} ${index}`), `${file} ${job}: classified gate ${index + 1} has no step`));
    }
  }
});

test("only defer gates defer, and no CI Status or pr-dispatch-feedback gate does", () => {
  const deferring = [];
  for (const file of readdirSync(WORKFLOWS).filter((name) => name.endsWith(".yml"))) {
    for (const { job, step } of gatesIn(file)) {
      if (/^ {10}defer(?:-minutes)?:/m.test(step)) deferring.push(`${file} ${job}`);
    }
  }
  const expected = Object.entries(GATES).flatMap(([file, jobs]) => Object.entries(jobs).filter(([, kind]) => kindsOf(kind).includes("defer")).map(([job]) => `${file} ${job}`));
  assert.deepEqual(deferring.sort(), expected.sort());
  for (const file of ["pr-require-checks.yml", "pr-dispatch-feedback.yml"]) {
    assert.doesNotMatch(readFileSync(path.join(WORKFLOWS, file), "utf8"), /^\s+defer(?:-minutes)?:/m, `${file} is never paced`);
  }
});

function stepsByJob(file) {
  const lines = readFileSync(path.join(WORKFLOWS, file), "utf8").split("\n");
  const jobsAt = lines.indexOf("jobs:");
  const jobs = {};
  let job = null;
  let step = null;
  lines.forEach((line, i) => {
    const id = i > jobsAt && /^ {2}([a-z][a-z0-9-]*):$/.exec(line);
    if (id) {
      job = id[1];
      jobs[job] = [];
      step = null;
    } else if (job && /^ {6}- /.test(line)) {
      step = [line];
      jobs[job].push(step);
    } else if (step && /^ {0,5}\S/.test(line)) {
      step = null;
    } else if (step) {
      step.push(line);
    }
  });
  return Object.fromEntries(Object.entries(jobs).map(([name, steps]) => [name, steps.map((text) => text.join("\n"))]));
}

const KILL_STEP = /^\s*(?:-\s+)?uses:\s*["']?[^\s"'#]*actions\/check-kill-switch\b/m;
const budgetJobs = () =>
  Object.entries(GATES).flatMap(([file, jobs]) =>
    Object.entries(jobs).flatMap(([job, kind]) => {
      const steps = stepsByJob(file)[job];
      const gates = (steps ?? []).flatMap((step, at) => (KILL_STEP.test(step) ? [at] : []));
      return kindsOf(kind)
        .map((each, index) => ({ file, job, cause: each === "defer" ? "defer" : "budget", steps, at: gates[index] ?? gates[0], each }))
        .filter(({ each }) => each === "start" || each === "first-call" || each === "defer");
    }),
  );

test("budget jobs are found", () => {
  const jobs = budgetJobs();
  assert.ok(jobs.length >= 15, `${jobs.length} budget jobs`);
  for (const { file, job, steps } of jobs) {
    assert.ok(steps?.some((step) => KILL_STEP.test(step)), `${file} ${job}: its steps hold the gate`);
  }
});

function splitTop(text, separator) {
  const parts = [""];
  let depth = 0;
  for (let i = 0; i < text.length; i += 1) {
    if (depth === 0 && text.startsWith(separator, i)) {
      parts.push("");
      i += separator.length - 1;
      continue;
    }
    depth += text[i] === "(" ? 1 : text[i] === ")" ? -1 : 0;
    parts[parts.length - 1] += text[i];
  }
  return parts.map((part) => part.trim());
}

// Whether a step `if:` is false on a budget stop: every top-level disjunct
// has a conjunct that needs the gate to proceed, the cause not to be budget,
// or a success or a non-empty output from a step that was skipped.
function falseOnBudget(condition, skipped, cause = "budget", gate = "kill") {
  const falseAtom = (atom) => {
    if (/^\(.*\)$/.test(atom)) return falseOnBudget(atom.slice(1, -1), skipped, cause, gate);
    if (atom === `steps.${gate}.outputs.proceed == 'true'` || atom === `steps.${gate}.outputs.cause != '${cause}'`) return true;
    const ref = /^steps\.([a-z0-9-]+)\.(?:(?:outcome|conclusion) (?:== 'success'|!= 'skipped')|outputs\.[a-z0-9-]+ (?:== '[^']+'|!= ''))$/.exec(atom);
    return Boolean(ref && skipped.has(ref[1]));
  };
  const text = condition.replace(/^\$\{\{|\}\}$/g, "").replace(/\s+/g, " ").trim();
  return text !== "" && splitTop(text, "||").every((disjunct) => splitTop(disjunct, "&&").some(falseAtom));
}

test("a budget stop ends neutral: no step it runs fails the job or writes ::error", () => {
  for (const { file, job, cause, steps, at } of budgetJobs()) {
    const skipped = new Set();
    const gate = /^ {8}id: ([a-z0-9-]+)$/m.exec(steps[at])?.[1];
    assert.ok(gate, `${file} ${job}: its budget gate has a step id`);
    for (const step of steps.slice(at + 1)) {
      const condition = /^ {8}if: (?:>-\n)?([\s\S]*?)\n {8}[a-z-]+:/m.exec(`${step}\n        end:`)?.[1] ?? "";
      if (falseOnBudget(condition, skipped, cause, gate)) {
        const id = /^ {8}id: ([a-z0-9-]+)$/m.exec(step)?.[1];
        if (id) skipped.add(id);
        continue;
      }
      const name = /name: (.*)/.exec(step)?.[1] ?? step.split("\n")[0];
      assert.doesNotMatch(step, /::error|\bexit 1\b/, `${file} ${job} "${name}" runs on a budget stop and fails it`);
    }
  }
});

test("the budget-stop reading of a step condition", () => {
  const skipped = new Set(["broker"]);
  assert.equal(falseOnBudget("steps.kill.outputs.proceed == 'true'", skipped), true);
  assert.equal(falseOnBudget("steps.kill.outputs.cause != 'budget'", skipped), true);
  assert.equal(falseOnBudget("steps.kill.outputs.cause != 'budget'", skipped, "defer"), false, "a defer stop's cause is defer");
  assert.equal(falseOnBudget("steps.kill.outputs.cause != 'defer'", skipped, "defer"), true);
  assert.equal(falseOnBudget("steps.broker.outcome == 'success' && inputs.x != ''", skipped), true, "a skipped step's success");
  assert.equal(falseOnBudget("steps.other.outcome == 'success'", skipped), false, "a step that ran");
  assert.equal(falseOnBudget("always() && steps.broker.outputs.pid != ''", skipped), true, "a skipped step's output is empty");
  assert.equal(falseOnBudget("always() && steps.other.outputs.pid != ''", skipped), false, "a step that ran may set it");
  assert.equal(falseOnBudget("always() && steps.broker.outcome != 'skipped'", skipped), true, "a skipped step's outcome is skipped");
  assert.equal(falseOnBudget("always() && (steps.broker.outcome == 'success' || steps.broker.outputs.done == 'true')", skipped), true, "a parenthesized disjunction of skipped steps");
  assert.equal(falseOnBudget("steps.kill.outputs.proceed != 'true'", skipped), false, "the stop report runs");
  assert.equal(falseOnBudget("always()", skipped), false);
  assert.equal(falseOnBudget("", skipped), false, "no condition runs");
  assert.equal(falseOnBudget("steps.broker.outputs.allowed == 'true' || inputs.force", skipped), false, "one disjunct may hold");
  assert.equal(falseOnBudget("inputs.a == '' && (inputs.b == '' || steps.kill.outputs.proceed == 'true')", skipped), false, "a parenthesized disjunction may hold");
});

test("every budget job checks out log-api-budget beside the gate", () => {
  for (const { file, job, steps } of budgetJobs()) {
    const gate = steps.find((step) => KILL_STEP.test(step));
    const root = /uses:\s*\.\/(.*?)\.github\/actions\/check-kill-switch/.exec(gate)?.[1]?.replace(/\/$/, "") ?? "";
    const checkout = steps.find((step) => /uses: actions\/checkout@/.test(step) && (/^ {10}path: (.*)$/m.exec(step)?.[1]?.trim() ?? "") === root);
    assert.ok(checkout, `${file} ${job}: a checkout at "${root}" holds the gate`);
    const sparse = /^ {10}sparse-checkout: \|\n((?: {12}.*\n?)+)/m.exec(checkout)?.[1];
    if (sparse === undefined) continue;
    const covers = sparse
      .split("\n")
      .map((entry) => entry.trim().replace(/^\//, "").replace(/\/\**$/, ""))
      .some((entry) => entry && ".github/actions/log-api-budget/".startsWith(`${entry}/`));
    assert.ok(covers, `${file} ${job}: its sparse checkout lists .github/actions/log-api-budget/`);
  }
});

async function runWaiting(env, answers) {
  const dir = tempDir("kill-switch-wait-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    let clock = NOW_MS;
    const sleeps = [];
    const lines = [];
    const queue = [...answers];
    const { calls, fetchImpl } = recordingFetch(() => queue.shift()());
    const sleep = async (ms) => {
      sleeps.push(ms);
      clock += ms;
    };
    await main({ GITHUB_OUTPUT: outputPath, BUDGET_TOKEN: "t", ...env }, { fetchImpl, now: () => clock, sleep, log: (line) => lines.push(line) });
    return { calls, lines, sleeps, outputs: readOutputs(readFileSync(outputPath, "utf8")) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const lowUntil = (resetIn) => () => rateLimitResponse({ headers: headersOf(5000, 313, NOW_S + resetIn) });
const freshWindow = () => rateLimitResponse({ headers: headersOf(5000, 5000, NOW_S + 4000) });

test("tonight's refine-select stop, 313 left and the reset 467 s out, waits for the reset and starts once after it", async () => {
  const { calls, lines, sleeps, outputs } = await runWaiting({ ...START, WAIT_SECONDS: String(WAIT_BUDGET_SECONDS.workResolveIssue) }, [lowUntil(467), freshWindow]);
  assert.deepEqual(sleeps, [468_000], "one wait, to a second past the reset");
  assert.equal(calls.length, 2, "one read before the wait and one after it");
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
  assert.ok(lines.includes(`::notice title=start-gate::the GITHUB_TOKEN budget stops this start until ${NOW_S + 467}; it waits 468s for the reset, then reads the budget once more`));
  assert.ok(lines.includes(`::notice title=start-gate::started after the reset: the start the budget stopped at ${NOW_S} goes ahead after a 468s wait`), "the line a before/after count greps");
});

test("a start still under the gate after the reset stops on the second reading, with its reset, and waits no more", async () => {
  const { calls, sleeps, outputs } = await runWaiting({ ...START, WAIT_SECONDS: "1200" }, [lowUntil(100), lowUntil(3700)]);
  assert.deepEqual([sleeps.length, calls.length], [1, 2]);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "budget", reset: String(NOW_S + 3700) });
});

test("a reset past the wait budget stops at once, as before", async () => {
  const { calls, sleeps, outputs } = await runWaiting({ ...START, WAIT_SECONDS: "600" }, [lowUntil(900)]);
  assert.deepEqual([sleeps.length, calls.length], [0, 1]);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "budget", reset: String(NOW_S + 900) });
});

test("a gate with no wait budget never waits, however near the reset", async () => {
  for (const value of [undefined, "", "0", "abc", "1201"]) {
    const { sleeps, outputs } = await runWaiting({ ...START, WAIT_SECONDS: value }, [lowUntil(30)]);
    assert.deepEqual([sleeps.length, outputs.cause], [0, "budget"], `WAIT_SECONDS=${JSON.stringify(value)}`);
  }
});

test("a switch stop never waits", async () => {
  const { calls, sleeps, outputs } = await runWaiting({ ...START, KILL_SWITCH_VALUE: "true", WAIT_SECONDS: "1200" }, []);
  assert.deepEqual([calls.length, sleeps.length, outputs.cause], [0, 0, "switch"]);
});

test("only intake's refine-select waits, for WAIT_BUDGET_SECONDS.workResolveIssue, inside its timeout", () => {
  const waiting = [];
  for (const file of readdirSync(WORKFLOWS).filter((name) => name.endsWith(".yml"))) {
    for (const [job, steps] of Object.entries(stepsByJob(file))) {
      const gate = steps.find((step) => KILL_STEP.test(step) && /^ {10}wait-seconds:/m.test(step));
      if (gate) waiting.push({ file, job, seconds: /^ {10}wait-seconds: "?(\d+)"?$/m.exec(gate)?.[1] });
    }
  }
  assert.deepEqual(waiting, [{ file: "intake-triage.yml", job: "refine-select", seconds: String(WAIT_BUDGET_SECONDS.workResolveIssue) }]);
  const text = readFileSync(path.join(WORKFLOWS, "intake-triage.yml"), "utf8");
  const minutes = Number(/^ {2}refine-select:\n(?: {4}.*\n)*? {4}timeout-minutes: (\d+)$/m.exec(text)?.[1]);
  assert.ok(minutes * 60 >= 600 + WAIT_BUDGET_SECONDS.workResolveIssue, `refine-select's ${minutes} min hold ten minutes of work and the wait`);
});

test("CLI writes proceed=true when both switches are exactly false and exits 0", () => {
  const { status, stdout, outputs } = runCli({ KILL_SWITCH_VALUE: "false", REPO_KILL_SWITCH_VALUE: "false" });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
  assert.doesNotMatch(stdout, /start-gate/);
});

test("CLI start gate without a token reads no budget, warns and proceeds", () => {
  const { status, stdout, outputs } = runCli({ ...START });
  assert.equal(status, 0);
  assert.equal(outputs.cause, "ok");
  assert.match(stdout, /::warning title=start-gate::no token/);
});

test("CLI start gate in a checkout without log-api-budget warns, reads no budget and proceeds", () => {
  const dir = tempDir("kill-switch-sparse-");
  try {
    const script = path.join(dir, "check-kill-switch", "check-kill-switch.mjs");
    mkdirSync(path.dirname(script));
    copyFileSync(SCRIPT, script);
    copyFileSync(fileURLToPath(new URL("./projection.mjs", import.meta.url)), path.join(dir, "check-kill-switch", "projection.mjs"));
    const { status, stdout, outputs } = runCli({ ...START, BUDGET_TOKEN: "t" }, script);
    assert.equal(status, 0);
    assert.match(stdout, /::warning title=start-gate::rate-limits\.json gave no start-gate share \(ENOENT\)/);
    assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
    const deferring = runCli({ ...DEFER, BUDGET_TOKEN: "t" }, script);
    assert.equal(deferring.status, 0);
    assert.match(deferring.stdout, /::warning title=defer-gate::the defer gate could not be set up \(/);
    assert.deepEqual(deferring.outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("CLI writes proceed=false when the repository switch is unset and exits 0", () => {
  const { status, outputs } = runCli({ KILL_SWITCH_VALUE: "false" });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "switch", reset: "" });
});

test("CLI writes proceed=false when both variables are unset and exits 0", () => {
  const { status, outputs } = runCli({});
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "switch", reset: "" });
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
