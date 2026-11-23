import process from "node:process";
import { fileURLToPath } from "node:url";

import { sinkOf, UsageError } from "./pull.mjs";
import { query, readRows } from "./store.mjs";

const DAY = 24 * 60 * 60 * 1000;
export const MIN_DAYS = 7;
export const LIMITS = [
  "A run's start is inferred as its transcript artifact's created_at less its duration_ms, so a run is placed by when its artifact was created, not by when its job started.",
  "A lane leg that uploads no transcript, or whose row has no duration_ms, is not counted.",
];
const USAGE = "usage: overlap.mjs [--sink DIR] [--since YYYY-MM-DD] [--until YYYY-MM-DD]";

export function parseArgs(argv) {
  const flags = {};
  for (let i = 0; i < argv.length; i += 2) {
    const name = /^--(sink|since|until)$/.exec(argv[i])?.[1];
    if (!name || argv[i + 1] === undefined || name in flags) throw new UsageError(USAGE);
    flags[name] = argv[i + 1];
  }
  return flags;
}

export function spanOf(row) {
  const end = Date.parse(row?.created_at ?? "");
  const duration = row?.duration_ms;
  if (Number.isNaN(end) || !Number.isInteger(duration) || duration <= 0) return null;
  return { start: end - duration, end, lane: row.lane ?? "unknown" };
}

export function windowDays(rows) {
  const dates = rows.map((row) => row.date).filter((date) => typeof date === "string").sort();
  if (dates.length === 0) return { first_date: null, last_date: null, days: 0 };
  const [first] = dates;
  const last = dates.at(-1);
  return { first_date: first, last_date: last, days: Math.round((Date.parse(last) - Date.parse(first)) / DAY) + 1 };
}

const hourOf = (ms) => `${new Date(ms).toISOString().slice(0, 13)}:00Z`;

export function peakOverlap(spans) {
  const events = spans.flatMap((span) => [
    { at: span.start, delta: 1, span },
    { at: span.end, delta: -1, span },
  ]);
  events.sort((a, b) => a.at - b.at);
  const running = new Set();
  let peak = 0;
  let peakAt = null;
  let peakLanes = {};
  let occurrences = 0;
  const hours = new Set();
  for (let i = 0; i < events.length; ) {
    const { at } = events[i];
    const before = running.size;
    for (; i < events.length && events[i].at === at; i++) {
      if (events[i].delta < 0) running.delete(events[i].span);
      else running.add(events[i].span);
    }
    if (running.size > peak) {
      peak = running.size;
      peakAt = at;
      peakLanes = {};
      for (const { lane } of running) peakLanes[lane] = (peakLanes[lane] ?? 0) + 1;
      occurrences = 0;
      hours.clear();
    }
    if (running.size === peak && before < peak) {
      occurrences++;
      hours.add(hourOf(at));
    }
  }
  return {
    peak,
    peak_at: peakAt === null ? null : new Date(peakAt).toISOString(),
    peak_hour: peakAt === null ? null : hourOf(peakAt),
    peak_lanes: Object.fromEntries(Object.entries(peakLanes).sort(([a], [b]) => a.localeCompare(b))),
    peak_occurrences: occurrences,
    peak_hours: [...hours].sort(),
  };
}

export function overlapReport(rows, { since, until } = {}) {
  const inWindow = query(rows, { since, until });
  const counted = inWindow.filter((row) => spanOf(row) !== null);
  const window = { since: since ?? null, until: until ?? null, ...windowDays(counted) };
  if (!(window.days >= MIN_DAYS)) return { refused: true, window };
  const spans = counted.map(spanOf);
  return { window, runs: spans.length, uncounted_rows: inWindow.length - spans.length, ...peakOverlap(spans), limits: LIMITS };
}

export function main(argv = process.argv.slice(2), env = process.env, io = { out: (s) => process.stdout.write(s), err: (s) => process.stderr.write(s) }) {
  let report;
  try {
    const flags = parseArgs(argv);
    report = overlapReport(readRows(sinkOf(flags, env)), flags);
  } catch (error) {
    io.err(`${error.message}\n`);
    return 2;
  }
  if (report.refused) {
    const { days, first_date: first, last_date: last } = report.window;
    io.err(`refused: the window holds ${days} day${days === 1 ? "" : "s"} of rows${first ? ` (${first} to ${last})` : ""}; the count needs at least ${MIN_DAYS}\n`);
    return 1;
  }
  io.out(`${JSON.stringify(report)}\n`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = main();
