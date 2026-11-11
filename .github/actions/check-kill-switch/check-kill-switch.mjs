// Gate for CI lanes: two manual switches, then, on a gate that starts new
// work, the GITHUB_TOKEN budget.
//
// - The org switch and the repository switch each proceed only on exactly
//   `false`. Unset, empty and every other value stop the lane (fail closed).
// - With BUDGET_CHECK=true (the action's `budget: "true"`, set only on gates
//   that start new work) and both switches proceeding, one GET /rate_limit
//   with the job's token reads the core pool: x-ratelimit-limit, -remaining
//   and -reset when the response carries all three, else the body's
//   resources.core. The lane stops while remaining < start-gate x limit and
//   the reset is still ahead; start-gate is github-token's entry in
//   ../log-api-budget/rate-limits.json. A refused read (403, 429, retry-after
//   or x-ratelimit-remaining 0) stops, since more calls would be refused too.
//   A read that fails otherwise (transport, timeout, 5xx, 401) or cannot be
//   parsed, or a share that cannot be read, proceeds with a warning; the rate guard's
//   stop-floor (log-api-budget/rate-guard.mjs) is the backstop. GitHub counts
//   this call against the secondary limit, not the primary one, so it is made
//   once, with no retry. A gate that finishes or judges existing work leaves
//   the budget off, so a low budget never throws that work away.
//
// Every stop is reason=kill-switch; cause says which: switch, budget, or ok
// when the lane proceeds. A budget stop also writes reset, the epoch second
// the reading's window resets.
import { randomUUID } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

const READ_TIMEOUT_MS = 10_000;
const RATE_LIMITS = new URL("../log-api-budget/rate-limits.json", import.meta.url);

export function checkKillSwitch(value, repoValue) {
  return value === "false" && repoValue === "false"
    ? { proceed: "true", reason: "ok", cause: "ok" }
    : { proceed: "false", reason: "kill-switch", cause: "switch" };
}

// Whether `reading` ({ limit, remaining, reset }, reset in epoch seconds) is
// under `share` of its limit with its reset after `now` (epoch seconds).
// Anything unreadable never stops.
export function budgetStops({ limit, remaining, reset } = {}, share, now) {
  return [limit, remaining, reset, share].every(Number.isFinite) && limit > 0 && reset > now && remaining < share * limit;
}

const HEADERS = ["limit", "remaining", "reset", "used", "resource"];

// The reading from one GET /rate_limit response: its headers when limit,
// remaining and reset all parse, else the body's resources.core.
export function readingOf(headers, body) {
  const header = Object.fromEntries(HEADERS.map((name) => [name, headers?.get?.(`x-ratelimit-${name}`) ?? null]));
  const fromHeaders = Object.fromEntries(["limit", "remaining", "reset"].map((name) => [name, /^\d+$/.test(header[name] ?? "") ? Number(header[name]) : Number.NaN]));
  const core = body?.resources?.core ?? null;
  const reading = Object.values(fromHeaders).every(Number.isFinite)
    ? { ...fromHeaders, source: "headers" }
    : { limit: Number(core?.limit), remaining: Number(core?.remaining), reset: Number(core?.reset), source: "body" };
  return { reading, header, core };
}

// A value from a response, kept to one line with no workflow command in it.
const clean = (text) => String(text).replace(/[\r\n%:]/g, " ");
const show = (fields) => Object.entries(fields ?? {}).map(([name, value]) => `${name}=${clean(value ?? "na")}`).join(" ");

const DEFAULT_WAIT_S = 60;
const whole = (value) => (/^\d+$/.test(value ?? "") ? Number(value) : Number.NaN);

// A response that says the token is already limited (403, 429, retry-after, or
// no requests remaining) stops the lane rather than proceeding into more calls
// that would be refused too. Its reset is always ahead of now: the header's
// reset, else now + retry-after, else now + 60.
function refusal(response, now) {
  const { status, headers } = response;
  const header = (name) => headers?.get?.(name) ?? null;
  const [retryAfter, remaining, headerReset] = [header("retry-after"), header("x-ratelimit-remaining"), header("x-ratelimit-reset")];
  if (status !== 403 && status !== 429 && retryAfter === null && remaining !== "0") {
    return null;
  }
  const wait = Number.isFinite(whole(retryAfter)) ? whole(retryAfter) : DEFAULT_WAIT_S;
  const reset = whole(headerReset) > now ? whole(headerReset) : Math.ceil(now + wait);
  return {
    stop: true,
    reset,
    line: `::warning title=start-gate::the GITHUB_TOKEN budget read was refused (HTTP ${status} ${show({ "retry-after": retryAfter, remaining, reset: headerReset })}); the lane stops until ${reset}`,
  };
}

// The budget half of the gate: { stop, reset, line } where line is the run's
// one notice or warning. Never throws.
export async function checkBudget({ token, api = "https://api.github.com", share, now = Date.now() / 1000, fetchImpl = fetch } = {}) {
  if (!token) {
    return { stop: false, line: "::warning title=start-gate::no token to read the GITHUB_TOKEN budget; the lane proceeds" };
  }
  try {
    const response = await fetchImpl(`${api}/rate_limit`, {
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" },
      signal: AbortSignal.timeout(READ_TIMEOUT_MS),
    });
    const refused = refusal(response, now);
    if (refused) {
      return refused;
    }
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const { reading, header, core } = readingOf(response.headers, await response.json().catch(() => null));
    if (![reading.limit, reading.remaining, reading.reset].every(Number.isFinite)) {
      throw new Error("neither the headers nor the body's resources.core carry limit, remaining and reset");
    }
    const stop = budgetStops(reading, share, now);
    const coreFields = core && { limit: core.limit, remaining: core.remaining, reset: core.reset, used: core.used };
    return {
      stop,
      reset: reading.reset,
      line:
        `::notice title=start-gate::github-token start-gate=${share} decided from ${reading.source}: limit=${reading.limit} remaining=${reading.remaining} reset=${reading.reset} stop=${stop}; ` +
        `body core ${core ? show(coreFields) : "absent"}; headers ${show(header)}`,
    };
  } catch (error) {
    return { stop: false, line: `::warning title=start-gate::the GITHUB_TOKEN budget was not read (${clean(error?.message ?? error)}); the lane proceeds` };
  }
}

// github-token's start-gate share from rate-limits.json, the only copy, or
// null with a warning when it cannot be read.
export function startGateShare(path = RATE_LIMITS, log = (line) => console.log(line)) {
  try {
    const share = JSON.parse(readFileSync(path, "utf8"))?.["github-token"]?.["start-gate"];
    if (typeof share !== "number" || share < 0 || share > 1) {
      throw new Error("github-token start-gate is not a share from 0 to 1");
    }
    return share;
  } catch (error) {
    log(`::warning title=start-gate::rate-limits.json gave no start-gate share (${clean(error?.code ?? error?.message)}); the lane proceeds without a budget read`);
    return null;
  }
}

// Every value is written in the delimited form, so no value can start a
// second output line.
export function writeOutputs(outputs, outputPath = process.env.GITHUB_OUTPUT) {
  if (!outputPath) {
    throw new Error("GITHUB_OUTPUT is not set");
  }
  let text = "";
  for (const [name, value] of Object.entries(outputs)) {
    const delimiter = `ghadelimiter_${randomUUID()}`;
    const body = String(value);
    if (body.includes(delimiter)) {
      throw new Error(`output ${name} contains its delimiter`);
    }
    text += `${name}<<${delimiter}\n${body}\n${delimiter}\n`;
  }
  appendFileSync(outputPath, text);
}

export async function main(env = process.env, { fetchImpl = fetch, now = Date.now, log = (line) => console.log(line), rateLimits = RATE_LIMITS } = {}) {
  let result = { ...checkKillSwitch(env.KILL_SWITCH_VALUE, env.REPO_KILL_SWITCH_VALUE), reset: "" };
  if (result.proceed === "true" && env.BUDGET_CHECK === "true") {
    const share = startGateShare(rateLimits, log);
    if (share) {
      const budget = await checkBudget({ token: env.BUDGET_TOKEN, api: env.GITHUB_API_URL || undefined, share, now: now() / 1000, fetchImpl });
      log(budget.line);
      if (budget.stop) {
        result = { proceed: "false", reason: "kill-switch", cause: "budget", reset: String(budget.reset) };
      }
    }
  }
  writeOutputs(result, env.GITHUB_OUTPUT);
  log(`check-kill-switch: proceed=${result.proceed} reason=${result.reason} cause=${result.cause}${result.reset ? ` reset=${result.reset}` : ""}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
