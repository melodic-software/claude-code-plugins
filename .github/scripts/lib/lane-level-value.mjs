#!/usr/bin/env node
// The published lane level L and the one reader of it: the read part of
// collect, decide, publish and read (lane-level.mjs decides,
// work-unblock/publish-lane-level.mjs publishes). The level variable's value
// is `<level>@<valid-until>`, valid-until in epoch seconds. Each consumer of
// the issue lane's concurrency (work-resolve-issue.yml's pick-slot and
// label-unblocked.mjs's re-fire room) calls effectiveLevel and nothing else.
//
// An empty, expired or malformed value (one valid past valid-minutes from now
// included) reads as the default; every level is
// clamped to floor and ceiling. With `shadow` set the consumer is handed the
// default, and the level it would have used is only reported.
//
// Settings are limits.lane-level in pr-pipeline.yaml, defaulted from
// LANE_LEVEL_DEFAULTS: floor, ceiling and default as decide() reads them,
// shadow, variable (the level variable's name) and valid-minutes (how long a
// published value holds).
//
// CLI: `node lane-level-value.mjs slots` writes `slots=<level>` to
// GITHUB_OUTPUT and a notice naming the level it would use, from LANE_VARS
// (the workflow's toJSON(vars)) and RESOLVED_CONFIG when that file exists.
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { LANE_LEVEL_DEFAULTS } from "./lane-level.mjs";

// The only names the level may be published under. It cannot name a lanes
// kill switch (CLAUDE_LANES_DISABLED, CLAUDE_LANES_REPO_DISABLED) or any other
// variable; the schema's pattern for limits.lane-level.variable is the same.
export const LEVEL_VARIABLE = /^[A-Z][A-Z0-9_]*_LANE_LEVEL$/;
const VALUE = /^([1-9][0-9]?)@([1-9][0-9]{0,11})$/;

export function levelSettings(laneLevel = {}) {
  return { ...LANE_LEVEL_DEFAULTS, ...laneLevel };
}

export const encodeLevel = (level, validUntil) => `${level}@${validUntil}`;

// { level, validUntil } from a well-formed value, else null.
export function parseLevel(value) {
  const match = VALUE.exec(typeof value === "string" ? value : "");
  return match ? { level: Number(match[1]), validUntil: Number(match[2]) } : null;
}

// { level, published, reason, shadow }: level is what the consumer uses,
// published what the value says once read, clamped and defaulted; reason is
// published, empty, expired or malformed. `now` is epoch milliseconds.
export function effectiveLevel({ value, settings = levelSettings(), now = Date.now() } = {}) {
  const clamp = (level) => Math.min(settings.ceiling, Math.max(settings.floor, level));
  const fallback = clamp(settings.default);
  const parsed = parseLevel(value);
  // The publisher never sets a value valid past valid-minutes from now, so a
  // later one (set by hand) is malformed, not a level that never expires.
  const tooLate = parsed !== null && parsed.validUntil * 1000 > now + settings["valid-minutes"] * 60_000;
  const reason =
    value === undefined || value === null || value === ""
      ? "empty"
      : parsed === null || tooLate
        ? "malformed"
        : parsed.validUntil * 1000 <= now
          ? "expired"
          : "published";
  const published = reason === "published" ? clamp(parsed.level) : fallback;
  return { level: settings.shadow ? fallback : published, published, reason, shadow: settings.shadow === true };
}

// The level variable's value in a workflow's toJSON(vars), or undefined.
export function variableOf(varsJson, settings = levelSettings()) {
  try {
    const vars = JSON.parse(varsJson ?? "");
    return vars !== null && typeof vars === "object" && typeof vars[settings.variable] === "string" ? vars[settings.variable] : undefined;
  } catch {
    return undefined;
  }
}

export const describeLevel = ({ level, published, reason, shadow }) =>
  shadow ? `lane level ${level} (shadow; would use ${published}, ${reason})` : `lane level ${level} (${reason})`;

// The issue lane's level from a job's environment: LANE_VARS and the resolved
// limits leaf, or the defaults.
export function laneLevelFromEnv(laneLevel, env = process.env, now = Date.now()) {
  const settings = levelSettings(laneLevel);
  return effectiveLevel({ value: variableOf(env.LANE_VARS, settings), settings, now });
}

// The limits.lane-level leaf of resolve-config's output file, or {} when it
// cannot be read, so the defaults apply.
export function resolvedLaneLevel(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"))?.limits?.["lane-level"] ?? {};
  } catch {
    return {};
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href && process.argv[2] === "slots") {
  const read = laneLevelFromEnv(process.env.RESOLVED_CONFIG ? resolvedLaneLevel(process.env.RESOLVED_CONFIG) : {});
  console.log(`::notice title=lane-level::${describeLevel(read)}`);
  appendFileSync(process.env.GITHUB_OUTPUT, `slots=${read.level}\n`);
}
