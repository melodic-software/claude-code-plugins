import { randomUUID } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { projectedLeft } from "./projection.mjs";

const READ_TIMEOUT_MS = 10_000;
const RATE_LIMITS = new URL("../log-api-budget/rate-limits.json", import.meta.url);

export function checkKillSwitch(value, repoValue) {
  return value === "false" && repoValue === "false"
    ? { proceed: "true", reason: "ok", cause: "ok" }
    : { proceed: "false", reason: "kill-switch", cause: "switch" };
}

export function budgetStops({ limit, remaining, reset } = {}, share, now) {
  return [limit, remaining, reset, share].every(Number.isFinite) && limit > 0 && reset > now && remaining < share * limit;
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

const clean = (text) => String(text).replace(/[\r\n%:]/g, " ");
const show = (fields) => Object.entries(fields ?? {}).map(([name, value]) => `${name}=${clean(value ?? "na")}`).join(" ");

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

const START_LABELS = { share: "start-project", minutes: "start-run-minutes" };

export function projectionStops(reading, { share, minutes, labels = START_LABELS }, now) {
  const left = projectedLeft(reading, now, minutes * 60);
  if (left === null) {
    return { stop: false, left: null, text: `projection unreadable for this reading, so it does not hold the start (${labels.minutes}=${minutes})` };
  }
  const secondsToReset = reading.reset - now;
  if (secondsToReset < minutes * 60) {
    const floor = (share * secondsToReset) / (minutes * 60);
    const stop = left < floor;
    const [resetIn, shown, floorShown] = [Math.round(secondsToReset), Math.round(left * 1000) / 1000, Math.round(floor * 1000) / 1000];
    return {
      stop,
      left: shown,
      why: `the window is projected to have ${shown} of its limit left at its reset in ${resetIn} s, under ${labels.share}=${share} scaled to the ${resetIn} s of the ${minutes} min run before the reset, ${floorShown}`,
      text: `projected left ${shown} of the limit at the reset in ${resetIn} s, inside the run's ${minutes} min (${labels.minutes}=${minutes}), against ${labels.share}=${share} scaled to the ${resetIn} s before the reset, ${floorShown}; stop=${stop}${stop ? `: the window would reach its reset with under that share of the limit left` : ""}`,
    };
  }
  const stop = left < share;
  const shown = Math.round(left * 100) / 100;
  return {
    stop,
    left: shown,
    why: `the window is projected to have ${shown} of its limit left ${minutes} min ahead, under ${labels.share}=${share}`,
    text: `projected left ${shown} of the limit ${minutes} min ahead, against ${labels.share}=${share} (${labels.minutes}=${minutes}) stop=${stop}${stop ? `: the run would end in a window with under its ${labels.share} share of the limit left` : ""}`,
  };
}

export async function checkBudget({ token, api = "https://api.github.com", share, projection = null, now = Date.now() / 1000, fetchImpl = fetch, title = "start-gate" } = {}) {
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
    const low = share !== null && budgetStops(reading, share, now);
    const ahead = !low && projection ? projectionStops(reading, projection, now) : null;
    const stop = low || ahead?.stop === true;
    const coreFields = core && { limit: core.limit, remaining: core.remaining, reset: core.reset, used: core.used };
    return {
      stop,
      reset: reading.reset,
      projected: ahead?.left ?? null,
      why: ahead?.why ?? null,
      line:
        `::notice title=${title}::github-token ${share === null ? "defer" : `start-gate=${share}`} decided from ${reading.source}: limit=${reading.limit} remaining=${reading.remaining} reset=${reading.reset} stop=${stop}; ` +
        `${ahead ? `${ahead.text}; ` : ""}body core ${core ? show(coreFields) : "absent"}; headers ${show(header)}`,
    };
  } catch (error) {
    return { stop: false, line: `::warning title=${title}::the GITHUB_TOKEN budget was not read (${clean(error?.message ?? error)}); the lane proceeds` };
  }
}

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

export function projectionGate(path = RATE_LIMITS, log = (line) => console.log(line)) {
  try {
    const entry = JSON.parse(readFileSync(path, "utf8"))?.["github-token"];
    const share = entry?.["start-project"];
    const minutes = entry?.["start-run-minutes"];
    if (typeof share !== "number" || !(share > 0 && share <= 1)) throw new Error("github-token start-project is not a share over 0 up to 1");
    if (!Number.isInteger(minutes) || minutes < 1) throw new Error("github-token start-run-minutes is not a whole number of minutes");
    return { share, minutes };
  } catch (error) {
    log(`::warning title=start-gate::the projection gate could not be set up (${clean(error?.code ?? error?.message)}); the lane proceeds on the start-gate share alone`);
    return null;
  }
}

const MINUTES = (value) => Number.isInteger(value) && value >= 1;

export async function deferGate({ rateLimits = RATE_LIMITS, resolvedPath = "", minutes = "", job = "", log = (line) => console.log(line) } = {}) {
  try {
    const { apiLimits } = await import("../log-api-budget/rate-guard.mjs");
    const entry = apiLimits({ resolvedPath, defaultsPath: rateLimits })["github-token"];
    const share = entry?.["defer-project"];
    if (share === 0) {
      log("check-kill-switch: github-token defer-project is 0, so deferral is off");
      return null;
    }
    if (typeof share !== "number" || !(share > 0 && share <= 1)) throw new Error("github-token defer-project is not a share from 0 to 1");
    if (job !== "" && !/^[a-z0-9][a-z0-9-]*$/.test(job)) throw new Error("defer-job is not a key suffix of lowercase letters, digits and hyphens");
    const jobKey = `defer-run-minutes-${job}`;
    const key = minutes !== "" ? "defer-minutes" : job !== "" && entry?.[jobKey] !== undefined ? jobKey : "defer-run-minutes";
    const horizon = key === "defer-minutes" ? (/^\d+$/.test(minutes) ? Number(minutes) : Number.NaN) : entry?.[key];
    if (!MINUTES(horizon)) throw new Error(`${key} is not a whole number of minutes`);
    return { share, minutes: horizon, labels: { share: "defer-project", minutes: key } };
  } catch (error) {
    log(`::warning title=defer-gate::the defer gate could not be set up (${clean(error?.code ?? error?.message)}); the job proceeds`);
    return null;
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
  { fetchImpl = fetch, now = Date.now, log = (line) => console.log(line), rateLimits = RATE_LIMITS, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)) } = {},
) {
  let result = { ...checkKillSwitch(env.KILL_SWITCH_VALUE, env.REPO_KILL_SWITCH_VALUE), reset: "" };
  if (result.proceed === "true" && env.BUDGET_CHECK === "true") {
    const share = startGateShare(rateLimits, log);
    if (share) {
      const projection = env.PROJECT_CHECK === "true" ? projectionGate(rateLimits, log) : null;
      const read = () => checkBudget({ token: env.BUDGET_TOKEN, api: env.GITHUB_API_URL || undefined, share, projection, now: now() / 1000, fetchImpl });
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
      const gate = await deferGate({ rateLimits, resolvedPath: env.RESOLVED_CONFIG ?? "", minutes: env.DEFER_MINUTES ?? "", job: env.DEFER_JOB ?? "", log });
      if (gate) {
        const budget = await checkBudget({ token: env.BUDGET_TOKEN, api: env.GITHUB_API_URL || undefined, share: null, projection: gate, now: now() / 1000, fetchImpl, title: "defer-gate" });
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
  log(`check-kill-switch: proceed=${result.proceed} reason=${result.reason} cause=${result.cause}${result.reset ? ` reset=${result.reset}` : ""}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
