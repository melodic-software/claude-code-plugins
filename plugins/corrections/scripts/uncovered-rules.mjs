#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const LANE_AUTHORS = new Set(["github-actions[bot]", "github-actions"]);
const FOOTER = /^`?claude-lane: (claude-review|claude-security-review)`?$/u;
const BLOCK_OPEN = /^\s*<summary>\s*Uncovered rules \(\d{1,3}\)\s*<\/summary>\s*$/u;
const BLOCK_CLOSE = /^\s*<\/details>\s*$/u;
const RULE_LINE = /^\s*(?:[-*+]\s+)?Uncovered rule:\s*(.*\S)\s*$/u;
const UNSAFE = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu;
const MAX_RULE = 300;
const USAGE = "usage: uncovered-rules.mjs [--file <review-comments.jsonl>]";

const lines = (body) => body.split(/\r?\n/u);

export function laneOf(row) {
  if (!row || typeof row.body !== "string" || !LANE_AUTHORS.has(row.author)) return null;
  const last = lines(row.body).filter((line) => line.trim() !== "").at(-1);
  return last?.trim().match(FOOTER)?.[1] ?? null;
}

export function rulesIn(body) {
  const rules = [];
  let open = false;
  for (const line of lines(body)) {
    if (BLOCK_OPEN.test(line)) {
      open = true;
    } else if (open && BLOCK_CLOSE.test(line)) {
      open = false;
    } else if (open) {
      const text = line.match(RULE_LINE)?.[1]?.replace(UNSAFE, "").trim();
      if (text) rules.push([...text].slice(0, MAX_RULE).join(""));
    }
  }
  return rules;
}

export function uncoveredRules(rows) {
  const seen = new Set();
  const out = [];
  for (const row of rows) {
    const lane = laneOf(row);
    if (!lane) continue;
    for (const rule of rulesIn(row.body)) {
      const key = JSON.stringify([row.pr, lane, rule]);
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ pr: row.pr, lane, rule });
    }
  }
  return out;
}

export function parseRows(text) {
  const rows = [];
  let skipped = 0;
  let truncated = false;
  for (const line of text.split(/\r?\n/u)) {
    if (line.trim() === "") continue;
    let row;
    try {
      row = JSON.parse(line);
    } catch {
      skipped += 1;
      continue;
    }
    if (row?.truncated === true) truncated = true;
    else if (row && typeof row === "object" && !Array.isArray(row)) rows.push(row);
    else skipped += 1;
  }
  return { rows, skipped, truncated };
}

function main(argv) {
  if (argv[0] === "--help" || argv[0] === "-h") {
    process.stdout.write(`${USAGE}\n`);
    return 0;
  }
  const fromFile = argv[0] === "--file" && argv.length === 2;
  if (argv.length > 0 && !fromFile) {
    process.stderr.write(`uncovered-rules: unknown arguments: ${argv.join(" ")}; ${USAGE}\n`);
    return 2;
  }
  let text;
  try {
    text = readFileSync(fromFile ? argv[1] : 0, "utf8");
  } catch (error) {
    process.stderr.write(`uncovered-rules: cannot read the input: ${error.code ?? error.message}\n`);
    return 2;
  }
  const { rows, skipped, truncated } = parseRows(text);
  for (const found of uncoveredRules(rows)) process.stdout.write(`${JSON.stringify(found)}\n`);
  if (skipped) process.stderr.write(`uncovered-rules: skipped ${skipped} line(s) that are not a JSON object\n`);
  if (truncated) process.stderr.write("uncovered-rules: the input was truncated; rules past the cap were not read\n");
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) process.exitCode = main(process.argv.slice(2));
