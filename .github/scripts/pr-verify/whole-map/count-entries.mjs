#!/usr/bin/env node
/**
 * Lists the entries a /testing:run-e2e map pass drives from a control skill's
 * hub, by the Entries rules of plugins/testing/skills/run-e2e/context/map.md,
 * and prints their counts as one JSON object:
 *
 *   count-entries.mjs --hub <SKILL.md> --unit feature|part [--features <id>[,<id>]...] [--max <n>]
 *
 * listed: entries after the features filter; kept: the first max of them;
 * capped: listed - kept; rows: the entry points of every listed entry, one
 * findings.json pass.entries row each; not_in_map: named ids that match no
 * entry. The hub and feature files are read as data. Exit 2 on a usage error
 * or an unreadable hub.
 */
import { readFileSync, realpathSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

const INDEX = /^- .*\|\s*(features\/|entry points:)/;
const FENCE = /^\s*(```|~~~)/;

function unfenced(text) {
  let fence = false;
  const lines = [];
  for (const line of text.split(/\r?\n/)) {
    if (FENCE.test(line)) fence = !fence;
    else if (!fence) lines.push(line);
  }
  return lines;
}

function section(lines, name) {
  let inside = false;
  const found = [];
  for (const line of lines) {
    if (line.startsWith("## ")) inside = line.slice(3).trim() === name;
    else if (inside && line.trim()) found.push(line.trim());
  }
  return found;
}

/** A Parts line's part: its leading code span, bold id, or word before a `:`, with a trailing `.` or `:` dropped; "" when it names none. */
export function partName(line) {
  const item = /^(?:[-*+]|[0-9]+[.)])\s+(.*)$/.exec(line);
  if (!item) return "";
  const match = /^`([^`\s]+)`/.exec(item[1]) ?? /^\*\*([^*\s]+)\*\*/.exec(item[1]) ?? /^([^`*:\s]+):/.exec(item[1]);
  return match ? match[1].replace(/[.:]$/, "") : "";
}

export function listEntries(hub, unit) {
  const base = realpathSync(path.dirname(hub));
  const read = (file) => {
    if (!/^features\/.+\.md$/.test(file)) return [];
    try {
      const full = realpathSync(path.join(base, file));
      return full.startsWith(`${base}${path.sep}`) ? unfenced(readFileSync(full, "utf8")) : [];
    } catch {
      return [];
    }
  };
  const entries = [];
  const visit = (lines, seen) => {
    for (const line of lines.filter((l) => INDEX.test(l))) {
      const file = line.slice(2).split("|")[1]?.trim() ?? "";
      const text = read(file);
      const subs = section(text, "Sub-features").filter((l) => INDEX.test(l));
      if (subs.length > 0 && !seen.has(file)) {
        visit(subs, new Set([...seen, file]));
        continue;
      }
      const feature = file.replace(/^features\//, "").replace(/(?:\/README)?\.md$/, "");
      const rows = section(text, "Entry points").length;
      const parts = unit === "part" ? section(text, "Parts").map(partName).filter(Boolean) : [];
      if (parts.length === 0) entries.push({ id: feature, feature, part: null, rows });
      for (const part of parts) entries.push({ id: `${feature}/${part}`, feature, part, rows });
    }
  };
  visit(unfenced(readFileSync(hub, "utf8")), new Set());
  return entries;
}

export function countEntries(entries, names, max) {
  const listed = names.length ? entries.filter((e) => names.includes(e.feature) || names.includes(e.id)) : entries;
  const kept = max === undefined ? listed.length : Math.min(max, listed.length);
  return {
    listed: listed.length,
    kept,
    capped: listed.length - kept,
    rows: listed.reduce((sum, e) => sum + e.rows, 0),
    not_in_map: names.filter((name) => !entries.some((e) => e.feature === name || e.id === name)),
  };
}

function main() {
  const fail = (why) => {
    process.stderr.write(`count-entries.mjs: ${why}\n`);
    process.exit(2);
  };
  let values;
  try {
    ({ values } = parseArgs({ options: { hub: { type: "string" }, unit: { type: "string" }, features: { type: "string", default: "" }, max: { type: "string" } } }));
  } catch (error) {
    fail(error.message);
  }
  if (!values.hub || !["feature", "part"].includes(values.unit)) fail("--hub and --unit feature|part are required");
  if (values.max !== undefined && !/^[1-9][0-9]*$/.test(values.max)) fail("--max is not a whole number of 1 or more");
  let entries;
  try {
    entries = listEntries(values.hub, values.unit);
  } catch (error) {
    fail(`cannot read the hub: ${error.message}`);
  }
  const names = values.features.split(",").filter(Boolean);
  process.stdout.write(`${JSON.stringify({ unit: values.unit, ...countEntries(entries, names, values.max && Number(values.max)) })}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) main();
