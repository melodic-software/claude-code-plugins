import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { apiLimits, createRateLimitLatch, RateLimitStop, resetLabel } from "../../actions/log-api-budget/rate-guard.mjs";
import { HELD_UNTIL, RATE_LIMITED } from "./label-unblocked.mjs";

const LIB = fileURLToPath(new URL("../../actions/log-api-budget/api-budget.bash", import.meta.url));
const GUARD_LINE = JSON.parse(readFileSync(new URL("../../actions/log-api-budget/rate-guard.vectors.json", import.meta.url), "utf8")).stderr_patterns.guard_line;
const RESET = 4102444800;
const URL_A = "https://api.github.com/repos/o/r/issues/30";

const jobLogLine = (annotation) => {
  const message = /^::error(?: [^:]*)?::(.*)$/.exec(annotation)?.[1];
  assert.ok(message !== undefined, `not an error annotation: ${annotation}`);
  return `2026-10-16T10:02:01.0000000Z ##[error]${message}`;
};

async function latchLines(answer) {
  const dir = mkdtempSync(join(tmpdir(), "stop-lines-"));
  try {
    const lines = [];
    const latch = createRateLimitLatch({ log: (line) => lines.push(line), fail: () => {}, limits: () => apiLimits({ resolvedPath: "" }), stopFile: join(dir, "stop") });
    const [status, headers, body] = answer;
    await latch.guard(async () => new Response(JSON.stringify(body), { status, headers }))(URL_A);
    return lines.filter((line) => line.startsWith("::error"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function bashLines(script) {
  const dir = mkdtempSync(join(tmpdir(), "stop-lines-"));
  try {
    const run = spawnSync("bash", ["-c", `. "${LIB}"\n${script}`], { encoding: "utf8", env: { PATH: process.env.PATH, RUNNER_TEMP: dir, TMPDIR: dir } });
    return run.stderr.split("\n").filter((line) => line.startsWith("::error"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const limitHeaders = (remaining) => ({ "x-ratelimit-limit": "5000", "x-ratelimit-remaining": String(remaining), "x-ratelimit-reset": String(RESET), "x-ratelimit-resource": "core" });

test("label-unblocked.mjs reads the reset, and a server error hold's 5xx, from every stop line rate-guard.mjs and api-budget.bash print", async () => {
  const at = resetLabel(RESET);
  const cases = [
    ["rate-guard.mjs: hit the limit", RATE_LIMITED, (await latchLines([403, limitHeaders(0), { message: "API rate limit exceeded for installation ID 1." }]))[0], at, undefined],
    ["rate-guard.mjs: hit the limit, its reset a fallback", RATE_LIMITED, (await latchLines([403, {}, { message: "API rate limit exceeded for installation ID 1." }]))[0], undefined, undefined],
    ["rate-guard.mjs: the stop floor", RATE_LIMITED, (await latchLines([200, limitHeaders(97), {}]))[0], at, undefined],
    ["rate-guard.mjs: a server error hold", RATE_LIMITED, (await latchLines([503, { "retry-after": String(RESET - Math.ceil(Date.now() / 1000)) }, {}]))[0], undefined, "503"],
    ["RateLimitStop: a rate limit", HELD_UNTIL, `::error::${new RateLimitStop("GET x", "core", RESET).message}`, at, undefined],
    ["RateLimitStop: a fallback rate limit", HELD_UNTIL, `::error::${new RateLimitStop("GET x", "core", RESET, null, true).message}`, at, undefined],
    ["RateLimitStop: a server error hold", HELD_UNTIL, `::error::${new RateLimitStop("GET x", "core", RESET, 503).message}`, at, "503"],
  ];
  for (const [what, stop, status] of [
    ["a rate limit", `api_budget_stop core ${RESET} x-ratelimit-reset "gh api x"`, undefined],
    ["a fallback rate limit", `api_budget_stop '*' ${RESET} fallback "gh api x"`, undefined],
    ["a server error hold", `api_budget_stop core ${RESET} retry-after "gh api x" "" 503`, "503"],
  ]) {
    const lines = bashLines(`${stop} || :\napi_budget_refuse core "gh api y" || :`);
    assert.equal(lines.length, 2, `api-budget.bash, ${what}: ${lines.join("\n")}`);
    cases.push([`api-budget.bash: ${what}`, RATE_LIMITED, lines[0], at, status], [`api-budget.bash: refused on ${what}`, HELD_UNTIL, lines[1], at, status]);
  }
  for (const [name, regex, annotation, reset, status] of cases) {
    assert.ok(annotation, `${name}: the guard printed no error line`);
    const groups = regex.exec(jobLogLine(annotation))?.groups;
    assert.ok(groups, `${name}: not read as a stop: ${annotation}`);
    if (reset !== undefined) assert.equal(groups.reset, reset, name);
    assert.equal(groups.status, status, name);
    const grep = spawnSync("grep", [GUARD_LINE.ignore_case ? "-qiE" : "-qE", GUARD_LINE.pattern], { input: annotation });
    assert.equal(grep.status, 0, `${name}: rate-stop.bash's guard_line pattern misses it, so it would record a second stop`);
  }
});
