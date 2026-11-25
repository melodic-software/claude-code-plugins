#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export const LANE_MARKER = "<!-- claude-lane intake-triage -->";
export const FLAGS = Object.freeze(["intent", "security", "cost", "untrusted"]);
const DIMENSIONS = Object.freeze({ size: "Size", complexity: "Complexity", uncertainty: "Uncertainty" });
const KEYS = ["labels", "comment", "needs_human", ...Object.keys(DIMENSIONS), "flags", "blocked_by"];
const PREFIXES = [...Object.values(DIMENSIONS), "Flags", "Blocked by"];
const MAX_BLOCKED_BY = 20;
const MAX_ISSUE = 999999999;

const isText = (value) => typeof value === "string" && value.trim() !== "";
const unique = (list) => new Set(list).size === list.length;

export function verdictLines(verdict) {
  return [
    ...Object.entries(DIMENSIONS).map(([key, prefix]) => `${prefix}: ${verdict[key]}`),
    `Flags: ${verdict.flags.length === 0 ? "none" : verdict.flags.join(", ")}`,
    `Blocked by: ${verdict.blocked_by.length === 0 ? "none" : verdict.blocked_by.map((n) => `#${n}`).join(", ")}`,
  ];
}

export function checkVerdict(verdict) {
  if (verdict === null || typeof verdict !== "object" || Array.isArray(verdict)) {
    return ["the verdict is not a JSON object"];
  }
  const problems = [];
  const extra = Object.keys(verdict).filter((key) => !KEYS.includes(key));
  if (extra.length > 0) problems.push(`unknown fields: ${extra.join(", ")}`);
  const missing = KEYS.filter((key) => !(key in verdict));
  if (missing.length > 0) return [...problems, `missing fields: ${missing.join(", ")}`];

  if (!Array.isArray(verdict.labels) || !verdict.labels.every(isText) || !unique(verdict.labels)) {
    problems.push("labels is not a list of distinct label names");
  }
  if (typeof verdict.needs_human !== "boolean") problems.push("needs_human is not true or false");
  for (const key of Object.keys(DIMENSIONS)) {
    if (typeof verdict[key] !== "string" || !/^[A-Za-z][A-Za-z0-9-]*$/.test(verdict[key])) {
      problems.push(`${key} is not one option key`);
    }
  }
  if (!Array.isArray(verdict.flags) || !verdict.flags.every((flag) => FLAGS.includes(flag)) || !unique(verdict.flags)) {
    problems.push(`flags is not a list of distinct values from ${FLAGS.join(", ")}`);
  }
  const blocked = verdict.blocked_by;
  if (
    !Array.isArray(blocked) ||
    blocked.length > MAX_BLOCKED_BY ||
    !blocked.every((n) => Number.isSafeInteger(n) && n >= 1 && n <= MAX_ISSUE) ||
    !unique(blocked)
  ) {
    problems.push(`blocked_by is not a list of at most ${MAX_BLOCKED_BY} distinct issue numbers`);
  }
  if (!isText(verdict.comment)) return [...problems, "comment is empty"];
  if (verdict.comment.includes(LANE_MARKER)) problems.push("comment holds the lane marker, which the lane adds");
  if (problems.length > 0) return problems;

  const lines = verdict.comment.split("\n");
  const expected = verdictLines(verdict);
  expected.forEach((line, i) => {
    if (lines[i] !== line) problems.push(`comment line ${i + 1} is not \`${line}\``);
  });
  lines.slice(expected.length).forEach((line, i) => {
    if (PREFIXES.some((prefix) => line.startsWith(`${prefix}: `))) {
      problems.push(`comment line ${i + expected.length + 1} repeats a verdict line`);
    }
  });
  return problems;
}

async function main(argv) {
  const at = argv.indexOf("--verdict");
  if (argv.length !== 2 || at !== 0) {
    console.error("usage: check-ci-verdict.mjs --verdict <path>");
    return 2;
  }
  let verdict;
  try {
    verdict = JSON.parse(await readFile(argv[1], "utf8"));
  } catch (error) {
    console.log(JSON.stringify({ ok: false, problems: [`unreadable verdict file: ${error.message}`] }));
    return 1;
  }
  const problems = checkVerdict(verdict);
  console.log(JSON.stringify({ ok: problems.length === 0, problems }));
  return problems.length === 0 ? 0 : 1;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main(process.argv.slice(2));
}
