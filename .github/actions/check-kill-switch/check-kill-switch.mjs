// Start gate for CI lanes. Two manual switches, then the GITHUB_TOKEN budget:
//
// - The org switch and the repository switch each proceed only on exactly
//   `false`. `true@<time>` (`true@2026-11-11T18:00:00Z`, UTC, seconds, `Z`)
//   stops until that time and then proceeds; any other value, a malformed time
//   included, stops (fail closed).
// - With both switches proceeding, one GET /rate_limit with the job's token
//   reads the core pool: x-ratelimit-limit, -remaining and -reset when the
//   response carries all three, else the body's resources.core. The lane stops
//   while remaining < limits.api github-token start-gate x limit and the reset
//   is still ahead. A read that fails or cannot be read proceeds with a
//   warning; the rate guard's stop-floor (log-api-budget/rate-guard.mjs) is
//   the backstop. GitHub counts this call against the secondary limit, not the
//   primary one, so it is made once, with no retry.
//
// Every stop is reason=kill-switch; cause says which: switch, expiry (a
// `true@<time>` still ahead), budget, or ok when the lane proceeds.
import { randomUUID } from "node:crypto";
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

// rate-limits.json's github-token start-gate, used when log-api-budget is not
// in the job's checkout (check-kill-switch.test.mjs holds the two equal).
export const START_GATE_SHARE = 0.1;
const READ_TIMEOUT_MS = 10_000;
const TIMED = /^true@(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)$/;

// One switch value at `now` (ms): ok, switch, or expiry while its time is ahead.
export function switchCause(value, now = Date.now()) {
  if (value === "false") {
    return "ok";
  }
  const time = TIMED.exec(value ?? "")?.[1];
  const until = time ? Date.parse(time) : Number.NaN;
  // Date.parse rolls 2026-02-30 over to March; only a real date round-trips.
  if (!Number.isFinite(until) || new Date(until).toISOString() !== time.replace("Z", ".000Z")) {
    return "switch";
  }
  return now < until ? "expiry" : "ok";
}

export function checkKillSwitch(value, repoValue, now = Date.now()) {
  const causes = [switchCause(value, now), switchCause(repoValue, now)];
  const cause = causes.includes("switch") ? "switch" : causes.includes("expiry") ? "expiry" : "ok";
  return cause === "ok" ? { proceed: "true", reason: "ok", cause } : { proceed: "false", reason: "kill-switch", cause };
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

// The budget half of the gate: { stop, line } where line is the run's one
// notice or warning. Never throws.
export async function checkBudget({ token, api = "https://api.github.com", share, now = Date.now() / 1000, fetchImpl = fetch } = {}) {
  if (!token) {
    return { stop: false, line: "::warning title=start-gate::no token to read the GITHUB_TOKEN budget; the lane proceeds" };
  }
  try {
    const response = await fetchImpl(`${api}/rate_limit`, {
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" },
      signal: AbortSignal.timeout(READ_TIMEOUT_MS),
    });
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
      line:
        `::notice title=start-gate::github-token start-gate=${share} decided from ${reading.source}: limit=${reading.limit} remaining=${reading.remaining} reset=${reading.reset} stop=${stop}; ` +
        `body core ${core ? show(coreFields) : "absent"}; headers ${show(header)}`,
    };
  } catch (error) {
    return { stop: false, line: `::warning title=start-gate::the GITHUB_TOKEN budget was not read (${clean(error?.message ?? error)}); the lane proceeds` };
  }
}

// limits.api github-token start-gate, from RESOLVED_CONFIG over rate-limits.json
// (rate-guard.mjs apiLimitsOrBuiltIn), or START_GATE_SHARE when that module is
// not in the job's checkout.
async function startGateShare(resolvedPath, log) {
  try {
    const { apiLimitsOrBuiltIn } = await import(new URL("../log-api-budget/rate-guard.mjs", import.meta.url));
    return apiLimitsOrBuiltIn({ resolvedPath: resolvedPath ?? "", log })["github-token"]["start-gate"] ?? START_GATE_SHARE;
  } catch (error) {
    log(`::warning title=start-gate::rate-guard.mjs could not be loaded (${clean(error?.code ?? error?.message)}); start-gate share ${START_GATE_SHARE}`);
    return START_GATE_SHARE;
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

export async function main(env = process.env, { fetchImpl = fetch, now = Date.now, log = (line) => console.log(line) } = {}) {
  let result = checkKillSwitch(env.KILL_SWITCH_VALUE, env.REPO_KILL_SWITCH_VALUE, now());
  if (result.proceed === "true") {
    const share = await startGateShare(env.RESOLVED_CONFIG, log);
    const budget = await checkBudget({ token: env.BUDGET_TOKEN, api: env.GITHUB_API_URL || undefined, share, now: now() / 1000, fetchImpl });
    log(budget.line);
    if (budget.stop) {
      result = { proceed: "false", reason: "kill-switch", cause: "budget" };
    }
  }
  writeOutputs(result, env.GITHUB_OUTPUT);
  log(`check-kill-switch: proceed=${result.proceed} reason=${result.reason} cause=${result.cause}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
