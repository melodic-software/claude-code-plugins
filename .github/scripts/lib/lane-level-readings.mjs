#!/usr/bin/env node
// The collect part of collect, decide, publish and read: one window's
// readings for lane-level.mjs's decide(), from the rate-limit readings a job's
// own lanes App calls left in $RUNNER_TEMP/api-budget/lanes-app
// (rate-guard.mjs readingLine: `<status> <limit> <remaining> <used> <reset>
// <resource> <route>`).
//
// A GET /rate_limit reading is left out: it reports a different bucket from
// the one the calls spend. Per pool (core as lanes-app, graphql as graphql)
// the reading is the peak used of any one reset window, with that window's
// limit. A limit signal is a 429, or a 403 with nothing remaining; a
// secondary limit answered 403 with requests left carries no sign in the
// reading line, so it is not seen here.
//
// CLI: `node lane-level-readings.mjs` writes `readings=<json>` to
// GITHUB_OUTPUT from that file, or `readings=` when it holds no reading.
import { appendFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const POOL_OF_RESOURCE = Object.freeze({ core: "lanes-app", graphql: "graphql" });
const NUMBER = /^\d+$/;

// A field the response's headers did not carry (`na`) is null, so a refusal
// with no rate-limit headers still counts as a signal.
const field = (value) => (NUMBER.test(value ?? "") ? Number(value) : null);

function parse(line) {
  const [status, limit, remaining, used, reset, resource, route] = line.trim().split(" ");
  const code = field(status);
  if (route === "rate_limit" || code === null) {
    return null;
  }
  return { status: code, limit: field(limit), remaining: field(remaining), used: field(used), reset: field(reset), resource };
}

const isReading = ({ limit, remaining, used, reset }) => [limit, remaining, used, reset].every((value) => value !== null);

// { at, pools, signals, reset? } for decide(), or null when no line is a
// reading or a limit signal. `at` is epoch seconds.
export function readingsOf(text, { at }) {
  const lines = String(text ?? "").split("\n").map(parse).filter(Boolean);
  const readings = lines.filter(isReading);
  const refused = lines.filter(({ status, remaining }) => status === 429 || (status === 403 && remaining === 0));
  if (readings.length === 0 && refused.length === 0) {
    return null;
  }
  const pools = {};
  for (const { limit, used, resource } of readings) {
    const pool = POOL_OF_RESOURCE[resource];
    if (pool && limit > 0 && used >= (pools[pool]?.used ?? -1)) {
      pools[pool] = { used, limit };
    }
  }
  const resets = refused.map(({ reset }) => reset).filter((reset) => reset !== null);
  return {
    at,
    pools,
    signals: refused.map(({ status }) => String(status)),
    ...(resets.length > 0 ? { reset: Math.max(...resets) } : {}),
  };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  let text = "";
  try {
    text = readFileSync(join(process.env.RUNNER_TEMP ?? "", "api-budget", "lanes-app"), "utf8");
  } catch {
    // No lanes App call this job: no readings.
  }
  const readings = readingsOf(text, { at: Math.floor(Date.now() / 1000) });
  appendFileSync(process.env.GITHUB_OUTPUT, `readings=${readings === null ? "" : JSON.stringify(readings)}\n`);
}
