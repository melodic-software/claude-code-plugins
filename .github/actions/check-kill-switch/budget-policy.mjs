import { readFileSync } from "node:fs";

import { projectedLeft } from "./projection.mjs";

const RATE_LIMITS = new URL("../log-api-budget/rate-limits.json", import.meta.url);
const RATE_GUARD = "../log-api-budget/rate-guard.mjs";
const print = (line) => console.log(line);

export const clean = (text) => String(text).replace(/[\r\n%:]/g, " ");
export const show = (fields) => Object.entries(fields ?? {}).map(([name, value]) => `${name}=${clean(value ?? "na")}`).join(" ");

export function budgetStops({ limit, remaining, reset } = {}, share, now) {
  return [limit, remaining, reset, share].every(Number.isFinite) && limit > 0 && reset > now && remaining < share * limit;
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

export function gateDecision({ share = null, projection = null, title = "start-gate" }, { header, core, ...reading }, now) {
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
}

export function startGateShare(path = RATE_LIMITS, log = print) {
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

export function projectionGate(path = RATE_LIMITS, log = print) {
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

export async function deferGate({ rateLimits = RATE_LIMITS, resolvedPath = "", minutes = "", job = "", log = print } = {}) {
  try {
    const { apiLimits } = await import(RATE_GUARD);
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

export function paceShare(limits, file) {
  const own = limits?.[`pace-${String(file ?? "").replace(/\.ya?ml$/, "")}`];
  return limits?.pace > 0 && typeof own === "number" ? own : limits?.pace;
}

export function paceDecision(reading, share, now) {
  const projected = share > 0 ? projectedLeft(reading, now) : null;
  return projected === null ? { paced: false, projected: null } : { paced: projected < share, projected: Math.round(projected * 100) / 100 };
}

async function paceLimits(resolvedPath, defaultsPath, log) {
  const { apiLimits, apiLimitsOrBuiltIn, FILE_ONLY_FIELDS } = await import(RATE_GUARD);
  let builtIn = false;
  const warn = (line) => {
    builtIn = true;
    log(line);
  };
  const merged = apiLimitsOrBuiltIn({ resolvedPath, defaultsPath, log: warn })["github-token"];
  const file = apiLimits({ resolvedPath: "", defaultsPath: builtIn ? null : defaultsPath })["github-token"];
  return { ...merged, ...Object.fromEntries(FILE_ONLY_FIELDS.map((field) => [field, file[field]])) };
}

export function budgetPolicy({ resolvedPath, defaultsPath = RATE_LIMITS, log = print } = {}) {
  const setups = new Map();
  const load = {
    start: async ({ project = false } = {}) => {
      const share = startGateShare(defaultsPath, log);
      return share ? { share, projection: project ? projectionGate(defaultsPath, log) : null, title: "start-gate" } : null;
    },
    defer: async ({ job = "", minutes = "" } = {}) => {
      const gate = await deferGate({ rateLimits: defaultsPath, resolvedPath: resolvedPath ?? "", minutes, job, log });
      return gate && { share: null, projection: gate, title: "defer-gate" };
    },
    pace: async () => ({ limits: await paceLimits(resolvedPath, defaultsPath, log) }),
  };
  return {
    async ready(kind, options) {
      if (!setups.has(kind)) setups.set(kind, await load[kind](options));
      return setups.get(kind) !== null;
    },
    decide(kind, reading, now, { workflow } = {}) {
      const setup = setups.get(kind);
      if (kind !== "pace") return gateDecision(setup, reading, now);
      const share = paceShare(setup.limits, workflow);
      const { paced, projected } = paceDecision(reading, share, now);
      return { stop: paced, reset: reading.reset, projected, why: null, line: null, share };
    },
  };
}
