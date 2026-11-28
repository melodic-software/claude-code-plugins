#!/usr/bin/env node
import { readFileSync, realpathSync } from "node:fs";
import process from "node:process";
import { fileURLToPath } from "node:url";

export const DEFAULT_OPEN_CAP = 5;

const isCap = (value) => Number.isSafeInteger(value) && value >= 0;

export function openCap({ team, user, personal, names = { team: "team layer", user: "userConfig", personal: "personal layer" } }) {
  const warnings = [];
  let cap = DEFAULT_OPEN_CAP;
  let source = "default";
  const valid = (value, name) => {
    if (value === undefined) return undefined;
    if (isCap(value)) return value;
    warnings.push(`${name} find_open_item_cap ${JSON.stringify(value)} is not a non-negative integer, so that layer is ignored`);
    return undefined;
  };
  const t = valid(team, names.team);
  if (t !== undefined) [cap, source] = [t, "team"];
  for (const [layer, value] of [["user", user], ["personal", personal]]) {
    const v = valid(value, names[layer] ?? layer);
    if (v === undefined) continue;
    if (v < cap) [cap, source] = [v, layer];
    else if (v > cap) warnings.push(`${names[layer] ?? layer} find_open_item_cap ${v} is above the ${source} cap ${cap}; that layer only lowers it`);
  }
  return { cap, source, warnings };
}

export const titleKey = (title) => title.trim().replace(/\s+/g, " ").toLowerCase();

const isTitles = (value) => Array.isArray(value) && value.every((title) => typeof title === "string");

export function planFiling({ label, labelExists, cap, open, existingTitles, candidates, runCap }) {
  if (typeof labelExists !== "boolean") throw new Error("labelExists must be true or false");
  if (!isCap(cap) || !isCap(open)) throw new Error("cap and open must be non-negative integers");
  if (runCap !== undefined && !isCap(runCap)) throw new Error("runCap, when given, must be a non-negative integer");
  if (!isTitles(candidates) || !isTitles(existingTitles)) throw new Error("candidates and existingTitles must be lists of titles");
  if (!labelExists) {
    return { file: [], skipped: candidates.map((title) => ({ title, why: `label \`${label}\` does not exist and is never created` })), room: 0, stop: "label-missing" };
  }
  let room = Math.max(0, cap - open);
  let budget = runCap === undefined ? Infinity : runCap;
  const seen = new Set(existingTitles.map(titleKey));
  const file = [];
  const skipped = [];
  for (const [index, title] of candidates.entries()) {
    if (room === 0) skipped.push({ title, why: `the open \`${label}\` items reached the cap of ${cap}` });
    else if (budget === 0) skipped.push({ title, why: `the run cap of ${runCap} is spent` });
    else if (seen.has(titleKey(title))) skipped.push({ title, why: `an item with this title already carries \`${label}\`` });
    else {
      file.push(index);
      seen.add(titleKey(title));
      room -= 1;
      budget -= 1;
    }
  }
  return { file, skipped, room, stop: room === 0 ? "open-cap" : null };
}

const isMain = () => {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
};

if (isMain()) {
  try {
    const request = JSON.parse(readFileSync(0, "utf8"));
    for (const layer of ["team", "user", "personal"]) {
      if (request[layer] !== undefined && !isCap(request[layer])) throw new Error(`${layer} must be a non-negative integer when given`);
    }
    const { cap, source, warnings } = openCap({ team: request.team, user: request.user, personal: request.personal });
    process.stdout.write(`${JSON.stringify({ cap, source, warnings, ...planFiling({ ...request, cap }) })}\n`);
  } catch (error) {
    process.stderr.write(`filing-plan: ${error.message}\n`);
    process.exitCode = 2;
  }
}
