#!/usr/bin/env node
import { appendFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const POOL_OF_RESOURCE = Object.freeze({ core: "lanes-app", graphql: "graphql" });
const NUMBER = /^\d+$/;

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
  }
  const readings = readingsOf(text, { at: Math.floor(Date.now() / 1000) });
  appendFileSync(process.env.GITHUB_OUTPUT, `readings=${readings === null ? "" : JSON.stringify(readings)}\n`);
}
