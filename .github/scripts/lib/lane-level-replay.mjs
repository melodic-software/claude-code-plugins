// Replays decide() (lane-level.mjs) hour by hour over the hub's recorded
// history and prints the level it would have chosen, why, and totals. It
// reads only the files it is given and actuates nothing.
//
//   node lane-level-replay.mjs --windows gh-token-windows.jsonl \
//     --app app-quota.jsonl --events events.log [--slots slots.log] \
//     [--concurrency concurrency.jsonl] [--days 14] [--app-limit 5200] \
//     [--end 2026-11-10T22:00:00Z] [--events-end-date 2026-11-10] \
//     [--pools lanes-app,github-token] [--signals app|all] [--actual-level 3] \
//     [--ceiling N] [--clean-windows N] [--quiet]
//
// The rule's limit signals are the lanes App's own; --signals all adds
// breaker trips, to compare against the rule as first drafted.
// --actual-level is the SLOTS the history ran at (3 throughout the default
// window): each hour's
// lanes App spend is scaled by replayed L over it, and 0 replays it as
// recorded.
//
// Readings per UTC hour:
//   lanes-app     app-quota.jsonl: used = --app-limit - the hour's lowest
//                 min_remaining (the file records no limit); a
//                 github-rate-limited deny or a remaining of 0 is a limit signal
//   github-token  gh-token-windows.jsonl: the hour's highest x-ratelimit used
//   signals       with --signals all, events.log BREAKER-TRIP lines too,
//                 holding until the reset named
//   demand        slots.log, the hub's count of work-resolve-issue runs in
//                 progress and waiting; for an hour it lacks, the
//                 concurrency.jsonl repository-wide queued and in-progress runs,
//                 a proxy that counts every workflow, labeled as such
// events.log lines carry HH:MMZ only: dates are counted back from
// --events-end-date (the file's last line), one day per wrap past midnight.

import { readFileSync, statSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { apiLimits } from "../../actions/log-api-budget/rate-guard.mjs";
import { decide, LANE_LEVEL_DEFAULTS } from "./lane-level.mjs";

const HOUR = 3600;
const REPO = "melodic-software/claude-code-plugins";

const hourOf = (epoch) => Math.floor(epoch / HOUR) * HOUR;
const epochOf = (iso) => Math.floor(Date.parse(iso) / 1000);
const isoOf = (epoch) => new Date(epoch * 1000).toISOString().replace(".000Z", "Z");

function jsonl(path) {
  const rows = [];
  for (const line of readFileSync(path, "utf8").split("\n")) {
    if (line.trim() === "") continue;
    try {
      rows.push(JSON.parse(line));
    } catch {
      // A torn line from a concurrent append is skipped.
    }
  }
  return rows;
}

const bucket = (map, hour, init) => {
  if (!map.has(hour)) map.set(hour, init());
  return map.get(hour);
};

// events.log lines dated by counting back from endDate (YYYY-MM-DD, the date
// of the last line): reading backwards, a time later than the line after it
// by more than 12 hours is the day before.
export function datedEvents(text, endDate) {
  const lines = text.split("\n");
  const out = [];
  let day = Date.parse(`${endDate}T00:00:00Z`) / 1000;
  let next = null;
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const m = /^(\d{2}):(\d{2})Z (\S+)(.*)$/.exec(lines[i]);
    if (!m) continue;
    const minutes = Number(m[1]) * 60 + Number(m[2]);
    if (next !== null && minutes - next > 12 * 60) day -= 86400;
    next = minutes;
    out.push({ at: day + minutes * 60, kind: m[3], text: m[4].trim() });
  }
  return out.reverse();
}

// WORKFLOW-MERGE lines carry the merge's ISO time: a line dated before its
// merge, or more than a day after, shows a gap the count above missed.
export function anchorMisses(events) {
  let misses = 0;
  let checked = 0;
  for (const event of events) {
    if (event.kind !== "WORKFLOW-MERGE") continue;
    const when = /\s(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s/.exec(` ${event.text} `)?.[1];
    if (!when) continue;
    checked += 1;
    const lag = event.at - epochOf(when);
    if (lag < -60 || lag > 86400) misses += 1;
  }
  return { checked, misses };
}

// The reset named in a BREAKER-TRIP line, the first HH:MMZ at or after it.
function resetOf(event) {
  const m = /reset=(\d{2}):(\d{2})Z/.exec(event.text);
  if (!m) return undefined;
  let reset = Math.floor(event.at / 86400) * 86400 + (Number(m[1]) * 60 + Number(m[2])) * 60;
  if (reset < event.at) reset += 86400;
  return reset;
}

// One reading per UTC hour, from the parsed inputs.
export function hourlyReadings({ windows = [], app = [], events = [], slots = [], concurrency = [], appLimit, breaker = false }) {
  const hours = new Map();
  const at = (hour) => bucket(hours, hour, () => ({ signals: [], demand: {} }));

  for (const row of windows) {
    if (!Number.isFinite(row.used) || !Number.isFinite(row.limit) || row.limit <= 0) continue;
    const h = at(hourOf(epochOf(row.sampled_at)));
    if (!h.token || row.used / row.limit > h.token.used / h.token.limit) h.token = { used: row.used, limit: row.limit };
  }
  for (const row of app) {
    const hour = epochOf(row.hour);
    if (!Number.isFinite(hour)) continue;
    const h = at(hour);
    if (Number.isFinite(row.min_remaining)) h.appRemaining = Math.min(h.appRemaining ?? Infinity, row.min_remaining);
    h.appLimited = Math.max(h.appLimited ?? 0, row.deny_by_reason?.["github-rate-limited"] ?? 0);
  }
  for (const event of events) {
    if (!breaker || event.kind !== "BREAKER-TRIP") continue;
    const h = at(hourOf(event.at));
    h.signals.push("breaker-trip");
    const reset = resetOf(event);
    if (reset !== undefined) h.reset = Math.max(h.reset ?? 0, reset);
  }
  for (const row of slots) {
    const h = at(hourOf(row.at));
    h.demand.slots = { waiting: Math.max(h.demand.slots?.waiting ?? 0, row.waiting), running: Math.max(h.demand.slots?.running ?? 0, row.running) };
  }
  for (const row of concurrency) {
    const repo = row.repos?.[REPO];
    if (!repo || repo.partial) continue;
    const h = at(hourOf(epochOf(row.ts)));
    const waiting = (repo.queued_runs ?? 0) + (repo.waiting_runs ?? 0);
    const running = repo.in_progress_runs ?? 0;
    h.demand.proxy = { waiting: Math.max(h.demand.proxy?.waiting ?? 0, waiting), running: Math.max(h.demand.proxy?.running ?? 0, running) };
  }

  const out = new Map();
  for (const [hour, h] of hours) {
    const pools = {};
    if (h.appRemaining !== undefined) pools["lanes-app"] = { used: Math.max(0, appLimit - h.appRemaining), limit: appLimit };
    if (h.token) pools["github-token"] = h.token;
    const signals = [...h.signals];
    if (h.appLimited > 0) signals.push("app-rate-limited");
    if (h.appRemaining === 0) signals.push("app-remaining-0");
    const source = h.demand.slots ? "slots" : h.demand.proxy ? "proxy" : "none";
    out.set(hour, {
      readings: { at: hour + HOUR, pools, signals, ...(h.reset ? { reset: h.reset } : {}) },
      demand: h.demand.slots ?? h.demand.proxy ?? null,
      source,
    });
  }
  return out;
}

// slots.log: "<iso> running=N waiting=M" or "<iso> runs_in_progress=N runs_waiting=M".
export function parseSlots(text) {
  const rows = [];
  for (const line of text.split("\n")) {
    const m = /^(\S+Z) (?:running|runs_in_progress)=(\d+) (?:waiting|runs_waiting)=(\d+)/.exec(line);
    if (m) rows.push({ at: epochOf(m[1]), running: Number(m[2]), waiting: Number(m[3]) });
  }
  return rows;
}

const quantile = (sorted, q) => (sorted.length === 0 ? null : sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))]);
const pct = (x) => (x === null || x === undefined ? "-" : `${(x * 100).toFixed(1)}%`);

// The lanes App reading as it would have been at `level` rather than the
// `actual` level it was recorded at, on the fit check's own assumption that
// spend grows with L; a modeled spend past the limit is a limit signal.
export function scaled(readings, level, actual) {
  const app = readings?.pools?.["lanes-app"];
  if (!actual || !app) return readings;
  const used = (app.used * level) / actual;
  const signals = used >= app.limit ? [...readings.signals, "modeled-app-exhausted"] : readings.signals;
  return { ...readings, pools: { ...readings.pools, "lanes-app": { ...app, used: Math.min(used, app.limit) } }, signals };
}

// Runs decide() over [start, end) hour by hour; an hour with no record at
// all passes null readings, which holds. With `actual`, each hour's lanes App
// spend is scaled from the recorded level to the replayed one.
export function replay(byHour, { start, end, config, actual = 0 }) {
  const rows = [];
  let state = null;
  for (let hour = start; hour < end; hour += HOUR) {
    const recorded = byHour.get(hour) ?? { readings: null, demand: null, source: "none" };
    const before = state?.level ?? null;
    const entry = { ...recorded, readings: scaled(recorded.readings, before ?? config["lane-level"].default, actual) };
    state = decide(state, entry.readings, entry.demand, config);
    rows.push({ hour, before, ...state, source: entry.source, readings: entry.readings, demand: entry.demand });
  }
  return rows;
}

export function summarize(rows, config) {
  const levels = {};
  const reasons = {};
  const sources = {};
  const raisedIntoTrip = [];
  const tripsPerDay = {};
  const signalKinds = {};
  const busyShares = [];
  for (const [i, row] of rows.entries()) {
    levels[row.level] = (levels[row.level] ?? 0) + 1;
    reasons[row.reason] = (reasons[row.reason] ?? 0) + 1;
    sources[row.source] = (sources[row.source] ?? 0) + 1;
    for (const kind of new Set(row.readings?.signals ?? [])) signalKinds[kind] = (signalKinds[kind] ?? 0) + 1;
    if (row.readings?.signals?.length) {
      const day = isoOf(row.hour).slice(0, 10);
      tripsPerDay[day] = (tripsPerDay[day] ?? 0) + 1;
    }
    if (row.reason === "step-up" && rows[i + 1]?.readings?.signals?.length) raisedIntoTrip.push(isoOf(rows[i + 1].hour));
    const app = row.readings?.pools?.["lanes-app"];
    if (app && row.demand && (row.demand.waiting > 0 || row.demand.running >= (row.before ?? config["lane-level"].default))) busyShares.push(app.used / app.limit);
  }
  busyShares.sort((a, b) => a - b);
  const stepUps = reasons["step-up"] ?? 0;
  return {
    hours: rows.length,
    levels,
    reasons,
    stepUps,
    stepDowns: rows.filter((r) => r.reason === "step-down" && r.before !== null && r.level < r.before).length,
    raisedIntoTrip,
    signalHoursPerDay: tripsPerDay,
    signalHoursByKind: signalKinds,
    demandSource: sources,
    busyLanesAppShare: { n: busyShares.length, p50: quantile(busyShares, 0.5), p90: quantile(busyShares, 0.9), max: busyShares.at(-1) ?? null },
  };
}

function line(row) {
  const app = row.readings?.pools?.["lanes-app"];
  const token = row.readings?.pools?.["github-token"];
  const d = row.demand ? `w${row.demand.waiting}/r${row.demand.running}(${row.source})` : "demand -";
  const sig = row.readings?.signals?.length ? ` signals=${row.readings.signals.join("+")}` : "";
  return `${isoOf(row.hour)} L=${row.level} ${row.reason} streak=${row.streak} app=${pct(app && app.used / app.limit)} token=${pct(token && token.used / token.limit)} ${d}${sig}`;
}

export function main(argv = process.argv.slice(2), log = (text) => console.log(text)) {
  const { values } = parseArgs({
    args: argv,
    options: {
      windows: { type: "string" },
      app: { type: "string" },
      events: { type: "string" },
      slots: { type: "string" },
      concurrency: { type: "string" },
      days: { type: "string", default: "14" },
      "app-limit": { type: "string", default: "5200" },
      end: { type: "string" },
      "events-end-date": { type: "string" },
      pools: { type: "string" },
      signals: { type: "string", default: "app" },
      "actual-level": { type: "string", default: "3" },
      ceiling: { type: "string" },
      "clean-windows": { type: "string" },
      quiet: { type: "boolean", default: false },
    },
  });
  for (const required of ["windows", "app", "events"]) {
    if (!values[required]) throw new Error(`--${required} is required`);
  }
  const eventsText = readFileSync(values.events, "utf8");
  const endDate = values["events-end-date"] ?? statSync(values.events).mtime.toISOString().slice(0, 10);
  const events = datedEvents(eventsText, endDate);
  const byHour = hourlyReadings({
    windows: jsonl(values.windows),
    app: jsonl(values.app),
    events,
    slots: values.slots ? parseSlots(readFileSync(values.slots, "utf8")) : [],
    concurrency: values.concurrency ? jsonl(values.concurrency) : [],
    appLimit: Number(values["app-limit"]),
    breaker: values.signals === "all",
  });
  const end = values.end ? hourOf(epochOf(values.end)) : hourOf(Math.floor(Date.now() / 1000));
  const start = end - Number(values.days) * 24 * HOUR;
  const laneLevel = {
    ...LANE_LEVEL_DEFAULTS,
    ...(values.pools ? { pools: values.pools.split(",") } : {}),
    ...(values.ceiling ? { ceiling: Number(values.ceiling) } : {}),
    ...(values["clean-windows"] ? { "clean-windows": Number(values["clean-windows"]) } : {}),
  };
  const config = { "lane-level": laneLevel, api: apiLimits({ resolvedPath: "" }) };
  const actual = Number(values["actual-level"]);
  const rows = replay(byHour, { start, end, config, actual });
  if (!values.quiet) {
    for (const row of rows) log(line(row));
  }
  const summary = summarize(rows, config);
  log(JSON.stringify({ from: isoOf(start), to: isoOf(end), appLimit: Number(values["app-limit"]), pools: laneLevel.pools, signals: values.signals, actualLevel: actual, eventsDating: anchorMisses(events), ...summary }, null, 2));
  return summary;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
