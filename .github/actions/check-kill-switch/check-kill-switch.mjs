import { randomUUID } from "node:crypto";
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { budgetPolicy, clean, gateDecision, show } from "./budget-policy.mjs";
import { stopRecordLine } from "./stop-record.mjs";

export { budgetStops, deferGate, projectionGate, startGateShare } from "./budget-policy.mjs";

const READ_TIMEOUT_MS = 10_000;

export function checkKillSwitch(value, repoValue) {
  return value === "false" && repoValue === "false"
    ? { proceed: "true", reason: "ok", cause: "ok" }
    : { proceed: "false", reason: "kill-switch", cause: "switch" };
}

const HEADERS = ["limit", "remaining", "reset", "used", "resource"];

export function readingOf(headers, body) {
  const header = Object.fromEntries(HEADERS.map((name) => [name, headers?.get?.(`x-ratelimit-${name}`) ?? null]));
  const fromHeaders = Object.fromEntries(["limit", "remaining", "reset"].map((name) => [name, /^\d+$/.test(header[name] ?? "") ? Number(header[name]) : Number.NaN]));
  const core = body?.resources?.core ?? null;
  const reading = Object.values(fromHeaders).every(Number.isFinite)
    ? { ...fromHeaders, source: "headers" }
    : { limit: Number(core?.limit), remaining: Number(core?.remaining), reset: Number(core?.reset), source: "body" };
  return { reading, header, core };
}

const DEFAULT_WAIT_S = 60;
const whole = (value) => (/^\d+$/.test(value ?? "") ? Number(value) : Number.NaN);

function refusal(response, now, title) {
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
    line: `::warning title=${title}::the GITHUB_TOKEN budget read was refused (HTTP ${status} ${show({ "retry-after": retryAfter, remaining, reset: headerReset })}); the lane stops until ${reset}`,
  };
}

export async function checkBudget({ token, api = "https://api.github.com", share, projection = null, now = Date.now() / 1000, fetchImpl = fetch, title = "start-gate", decide = (reading, at) => gateDecision({ share, projection, title }, reading, at) } = {}) {
  if (!token) {
    return { stop: false, line: `::warning title=${title}::no token to read the GITHUB_TOKEN budget; the lane proceeds` };
  }
  try {
    const response = await fetchImpl(`${api}/rate_limit`, {
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" },
      signal: AbortSignal.timeout(READ_TIMEOUT_MS),
    });
    const refused = refusal(response, now, title);
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
    return decide({ ...reading, header, core }, now);
  } catch (error) {
    return { stop: false, line: `::warning title=${title}::the GITHUB_TOKEN budget was not read (${clean(error?.message ?? error)}); the lane proceeds` };
  }
}

const isoOf = (seconds) => new Date(seconds * 1000).toISOString().replace(".000Z", "Z");

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

async function waitBudget(value, log) {
  if (!value) return 0;
  try {
    const { SERVER_RETRY_BUDGET_MS, waitBudgetMs } = await import("../log-api-budget/rate-guard.mjs");
    const ms = waitBudgetMs(value);
    return ms > SERVER_RETRY_BUDGET_MS ? ms : 0;
  } catch (error) {
    log(`::warning title=start-gate::the wait budget could not be read (${clean(error?.code ?? error?.message)}); a budget stop does not wait`);
    return 0;
  }
}

export async function main(
  env = process.env,
  { fetchImpl = fetch, now = Date.now, log = (line) => console.log(line), rateLimits, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)) } = {},
) {
  const policy = budgetPolicy({ resolvedPath: env.RESOLVED_CONFIG ?? "", defaultsPath: rateLimits, log });
  let result = { ...checkKillSwitch(env.KILL_SWITCH_VALUE, env.REPO_KILL_SWITCH_VALUE), reset: "" };
  if (result.proceed === "true" && env.BUDGET_CHECK === "true") {
    if (await policy.ready("start", { project: env.PROJECT_CHECK === "true" })) {
      const decide = (reading, at) => policy.decide("start", reading, at);
      const read = () => checkBudget({ token: env.BUDGET_TOKEN, api: env.GITHUB_API_URL || undefined, now: now() / 1000, fetchImpl, decide });
      const stoppedAt = Math.floor(now() / 1000);
      let budget = await read();
      log(budget.line);
      const waitMs = budget.stop ? Math.max(0, budget.reset * 1000 - now()) + 1000 : 0;
      if (budget.stop && waitMs <= (await waitBudget(env.WAIT_SECONDS, log))) {
        const seconds = Math.ceil(waitMs / 1000);
        log(`::notice title=start-gate::the GITHUB_TOKEN budget stops this start until ${budget.reset}; it waits ${seconds}s for the reset, then reads the budget once more`);
        await sleep(waitMs);
        budget = await read();
        log(budget.line);
        if (!budget.stop) {
          log(`::notice title=start-gate::started after the reset: the start the budget stopped at ${stoppedAt} goes ahead after a ${seconds}s wait`);
        }
      }
      if (budget.stop) {
        result = { proceed: "false", reason: "kill-switch", cause: "budget", reset: String(budget.reset) };
      }
    }
  }
  if (result.proceed === "true" && env.DEFER_CHECK === "true") {
    if (env.RUN_ATTEMPT !== "1") {
      log(`check-kill-switch: run attempt ${clean(env.RUN_ATTEMPT || "unknown")} is not the first, so it never defers`);
    } else {
      if (await policy.ready("defer", { minutes: env.DEFER_MINUTES ?? "", job: env.DEFER_JOB ?? "" })) {
        const decide = (reading, at) => policy.decide("defer", reading, at);
        const budget = await checkBudget({ token: env.BUDGET_TOKEN, api: env.GITHUB_API_URL || undefined, now: now() / 1000, fetchImpl, title: "defer-gate", decide });
        log(budget.line);
        if (budget.stop) {
          result = { proceed: "false", reason: "kill-switch", cause: "defer", reset: String(budget.reset) };
          const why = budget.why ?? "the budget read was refused";
          log(`::notice title=defer::deferred until the GITHUB_TOKEN window resets at ${budget.reset} (${isoOf(budget.reset)}): ${why}; cause=defer, so a later run after the reset does this work`);
        }
      }
    }
  }
  writeOutputs(result, env.GITHUB_OUTPUT);
  if (result.proceed === "false") {
    try {
      log(stopRecordLine({ pool: result.reset ? "core" : null, cause: result.cause, reset: result.reset ? Number(result.reset) : null }));
    } catch (error) {
      log(`::warning title=stop-record::the stop was not recorded (${clean(error?.message ?? error)}); its outputs stand`);
    }
  }
  log(`check-kill-switch: proceed=${result.proceed} reason=${result.reason} cause=${result.cause}${result.reset ? ` reset=${result.reset}` : ""}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
