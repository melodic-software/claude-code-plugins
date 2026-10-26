#!/usr/bin/env node
// Grouped view of the findings buffer, for a person to read instead of raw JSONL.
//   group-findings.mjs [--by <field>[,<field>...]] [--since <UTC ISO-8601>] [--rows]
// Runs tools/findings-buffer/buffer.sh read from the current directory and groups its rows by the
// named top-level fields (default `producer`). It prints the grouping keys, the occurrence rule and
// the totals, then each group: its value for every key, its row count and its occurrence count
// (distinct `source_id`; a row without one is its own occurrence), then each member's obs_id, ts
// and source_id, oldest first; --rows adds the member row itself. Groups come most occurrences
// first, then most rows. With --since, only rows whose ts is at or after it are grouped, since
// buffer.sh read may return older rows.
// Row values are data: control, format and separator characters are printed escaped.
// Exit: 0 ok (no rows prints `no rows`), 2 usage, 1 a row that is not a JSON object or a read that
// does not fit in memory, else buffer.sh read's own exit.
import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const ROOT = resolve(dirname(realpathSync.native(fileURLToPath(import.meta.url))), "..");
const BUFFER = join(ROOT, "tools/findings-buffer/buffer.sh");
const FIELD = /^[A-Za-z0-9_-]{1,64}$/;
const MAX_FIELDS = 8;
const TS = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?Z$/;
const UNSAFE = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu;
const USAGE = "usage: group-findings.mjs [--by <field>[,<field>...]] [--since <UTC ISO-8601>] [--rows]";

const say = (text) => process.stderr.write(`group-findings: ${text}\n`);
const usage = (why) => {
  if (why) say(why);
  say(USAGE);
  process.exit(2);
};
const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

/** JSON text with every control, format (bidirectional and zero-width included) and separator character escaped. */
function show(value) {
  return JSON.stringify(value).replace(UNSAFE, (c) =>
    [...Array(c.length).keys()].map((i) => `\\u${c.charCodeAt(i).toString(16).padStart(4, "0")}`).join(""),
  );
}

/** -1, 0 or 1 comparing two UTC ISO-8601 timestamps that match TS, fraction included. */
function compareTs(a, b) {
  const [, secA, fracA = ""] = TS.exec(a);
  const [, secB, fracB = ""] = TS.exec(b);
  if (secA !== secB) return secA < secB ? -1 : 1;
  const width = Math.max(fracA.length, fracB.length);
  const [x, y] = [fracA.padEnd(width, "0"), fracB.padEnd(width, "0")];
  return x === y ? 0 : x < y ? -1 : 1;
}

let opts;
try {
  ({ values: opts } = parseArgs({ options: { by: { type: "string" }, since: { type: "string" }, rows: { type: "boolean" } } }));
} catch (error) {
  usage(error.message);
}
const keys = (opts.by ?? "producer").split(",");
if (keys.length > MAX_FIELDS) usage(`--by takes at most ${MAX_FIELDS} fields`);
for (const key of keys) {
  if (!FIELD.test(key)) usage(`--by field ${show(key)} is not a top-level field name (letters, digits, _ and -)`);
}
if (new Set(keys).size !== keys.length) usage("--by names a field twice");
if (opts.since !== undefined && !TS.test(opts.since)) usage("--since must be UTC ISO-8601, e.g. 2026-10-21T09:30:00Z");

const read = spawnSync("bash", [BUFFER, "read", ...(opts.since === undefined ? [] : ["--since", opts.since])], {
  encoding: "utf8",
  maxBuffer: 512 * 1024 * 1024,
  stdio: ["ignore", "pipe", "inherit"],
});
if (read.error) {
  say(`buffer.sh read did not complete (${read.error.code ?? read.error.message}); nothing grouped`);
  process.exit(1);
}
if (read.status !== 0) process.exit(read.status ?? 1);

const rows = [];
for (const line of read.stdout.split("\n")) {
  if (!/\S/.test(line)) continue;
  let row;
  try {
    row = JSON.parse(line);
  } catch {
    row = undefined;
  }
  if (row === null || typeof row !== "object" || Array.isArray(row)) {
    say("buffer.sh read returned a line that is not a JSON object; nothing grouped");
    process.exit(1);
  }
  if (opts.since !== undefined && !(typeof row.ts === "string" && TS.test(row.ts) && compareTs(row.ts, opts.since) >= 0)) continue;
  rows.push(row);
}

const hasSource = (row) => row.source_id !== undefined && row.source_id !== null && row.source_id !== "";
const groups = new Map();
for (const [index, row] of rows.entries()) {
  const values = keys.map((key) => (Object.hasOwn(row, key) ? row[key] : undefined));
  const id = JSON.stringify(values.map((v) => (v === undefined ? null : [v])));
  if (!groups.has(id)) groups.set(id, { values, members: [], occurrences: new Set() });
  const group = groups.get(id);
  group.members.push(row);
  group.occurrences.add(hasSource(row) ? `source:${JSON.stringify(row.source_id)}` : `row:${index}`);
}

const label = ({ values }) => keys.map((key, i) => `${key}=${values[i] === undefined ? "(none)" : show(values[i])}`).join(" ");
const sorted = [...groups.values()]
  .map((group) => ({ ...group, label: label(group) }))
  .sort((a, b) => b.occurrences.size - a.occurrences.size || b.members.length - a.members.length || (a.label < b.label ? -1 : a.label > b.label ? 1 : 0));
const tsOf = (row) => (typeof row.ts === "string" && TS.test(row.ts) ? row.ts : null);
const byTs = (a, b) => {
  const [x, y] = [tsOf(a), tsOf(b)];
  if (x === null || y === null) return (x === null) - (y === null);
  return compareTs(x, y);
};

// Written a group at a time, so a large buffer never builds one string of the whole view.
const write = (lines) => process.stdout.write(`${lines.join("\n")}\n`);
write([`grouped by: ${keys.join(", ")}`, "occurrences: distinct source_id in the group; a row without one counts once"]);
if (sorted.length === 0) {
  write(["no rows"]);
} else {
  write([`${plural(sorted.length, "group")}, ${plural(rows.length, "row")}`]);
  for (const group of sorted) {
    const lines = ["", `${group.label}: ${plural(group.members.length, "row")}, ${plural(group.occurrences.size, "occurrence")}`];
    for (const row of group.members.sort(byTs)) {
      lines.push(`  ${show(row.obs_id ?? null)}  ${show(row.ts ?? null)}  source_id=${hasSource(row) ? show(row.source_id) : "(none)"}`);
      if (opts.rows) lines.push(`    ${show(row)}`);
    }
    write(lines);
  }
}
