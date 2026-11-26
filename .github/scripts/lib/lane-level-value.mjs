#!/usr/bin/env node
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { LANE_LEVEL_DEFAULTS } from "./lane-level.mjs";

export const LEVEL_VARIABLE = /^[A-Z][A-Z0-9_]*_LANE_LEVEL$/;
const VALUE = /^([1-9][0-9]?)@([1-9][0-9]{0,11})$/;

export function levelSettings(laneLevel = {}) {
  return { ...LANE_LEVEL_DEFAULTS, ...laneLevel };
}

export const encodeLevel = (level, validUntil) => `${level}@${validUntil}`;

export function parseLevel(value) {
  const match = VALUE.exec(typeof value === "string" ? value : "");
  return match ? { level: Number(match[1]), validUntil: Number(match[2]) } : null;
}

export function effectiveLevel({ value, settings = levelSettings(), now = Date.now() } = {}) {
  const clamp = (level) => Math.min(settings.ceiling, Math.max(settings.floor, level));
  const fallback = clamp(settings.default);
  const parsed = parseLevel(value);
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

export function laneLevelFromEnv(laneLevel, env = process.env, now = Date.now()) {
  const settings = levelSettings(laneLevel);
  return effectiveLevel({ value: variableOf(env.LANE_VARS, settings), settings, now });
}

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
