#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export const SCHEMA_PATH = new URL("../schemas/ci-verdict.schema.json", import.meta.url);
export const SCHEMA = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
export const LANE_MARKER = "<!-- claude-lane intake-triage -->";
export const FLAGS = Object.freeze([...SCHEMA.properties.flags.items.enum]);
const DIMENSIONS = Object.freeze({ size: "Size", complexity: "Complexity", uncertainty: "Uncertainty" });
const PREFIXES = [...Object.values(DIMENSIONS), "Flags", "Blocked by"];

const isText = (value) => typeof value === "string" && value.trim() !== "";
const unique = (list) => new Set(list).size === list.length;
const fits = (value, rule) =>
  typeof value === "string" &&
  value.length >= (rule.minLength ?? 0) &&
  value.length <= (rule.maxLength ?? Infinity) &&
  (rule.pattern === undefined || new RegExp(rule.pattern, "u").test(value)) &&
  (rule.enum === undefined || rule.enum.includes(value));

export function verdictLines(verdict) {
  return [
    ...Object.entries(DIMENSIONS).map(([key, prefix]) => `${prefix}: ${verdict[key]}`),
    `Flags: ${verdict.flags.length === 0 ? "none" : verdict.flags.join(", ")}`,
    `Blocked by: ${verdict.blocked_by.length === 0 ? "none" : verdict.blocked_by.map((n) => `#${n}`).join(", ")}`,
  ];
}

export function checkVerdict(verdict, schema = SCHEMA) {
  if (verdict === null || typeof verdict !== "object" || Array.isArray(verdict)) {
    return ["the verdict is not a JSON object"];
  }
  const rules = schema.properties;
  const problems = [];
  const extra = Object.keys(verdict).filter((key) => !Object.hasOwn(rules, key));
  if (extra.length > 0) problems.push(`unknown fields: ${extra.join(", ")}`);
  const missing = schema.required.filter((key) => !(key in verdict));
  if (missing.length > 0) return [...problems, `missing fields: ${missing.join(", ")}`];

  const labels = rules.labels;
  if (
    !Array.isArray(verdict.labels) ||
    verdict.labels.length > labels.maxItems ||
    !verdict.labels.every((label) => isText(label) && fits(label, labels.items)) ||
    !unique(verdict.labels)
  ) {
    problems.push(`labels is not a list of at most ${labels.maxItems} distinct label names`);
  }
  if (typeof verdict.needs_human !== "boolean") problems.push("needs_human is not true or false");
  for (const key of Object.keys(DIMENSIONS)) {
    if (!fits(verdict[key], rules[key])) problems.push(`${key} is not one option key`);
  }
  if ("type" in verdict && !(isText(verdict.type) && fits(verdict.type, rules.type))) {
    problems.push("type is not one Issue Type name");
  }
  const flags = rules.flags;
  if (!Array.isArray(verdict.flags) || !verdict.flags.every((flag) => flags.items.enum.includes(flag)) || !unique(verdict.flags)) {
    problems.push(`flags is not a list of distinct values from ${flags.items.enum.join(", ")}`);
  }
  const blocked = verdict.blocked_by;
  const { maxItems, items } = rules.blocked_by;
  if (
    !Array.isArray(blocked) ||
    blocked.length > maxItems ||
    !blocked.every((n) => Number.isSafeInteger(n) && n >= items.minimum && n <= items.maximum) ||
    !unique(blocked)
  ) {
    problems.push(`blocked_by is not a list of at most ${maxItems} distinct issue numbers`);
  }
  if (!isText(verdict.comment)) return [...problems, "comment is empty"];
  if (verdict.comment.length > rules.comment.maxLength) problems.push(`comment is over ${rules.comment.maxLength} characters`);
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
  const usage = () => {
    console.error("usage: check-ci-verdict.mjs --verdict <path> [--schema <path>]");
    return 2;
  };
  const args = new Map();
  for (let i = 0; i < argv.length; i += 2) {
    if (!["--verdict", "--schema"].includes(argv[i]) || argv[i + 1] === undefined || args.has(argv[i])) return usage();
    args.set(argv[i], argv[i + 1]);
  }
  if (!args.has("--verdict")) return usage();
  let schema = SCHEMA;
  if (args.has("--schema")) {
    try {
      schema = JSON.parse(await readFile(args.get("--schema"), "utf8"));
      if (!schema?.properties || !Array.isArray(schema.required)) throw new Error("not a verdict schema");
    } catch (error) {
      console.error(`unreadable schema file: ${error.message}`);
      return 2;
    }
  }
  let verdict;
  try {
    verdict = JSON.parse(await readFile(args.get("--verdict"), "utf8"));
  } catch (error) {
    console.log(JSON.stringify({ ok: false, problems: [`unreadable verdict file: ${error.message}`] }));
    return 1;
  }
  const problems = checkVerdict(verdict, schema);
  console.log(JSON.stringify({ ok: problems.length === 0, problems }));
  return problems.length === 0 ? 0 : 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main(process.argv.slice(2));
}
