#!/usr/bin/env node
// Resolve the two settings of the bundled "Fail a change that loosens a check"
// criterion (skills/quality-gate/context/loosened-check.md):
//
//   loosened_check_verdict   policy floor: fail from any valid layer wins; default fail
//   loosened_check_patterns  union of every valid layer's entries; default none
//
// Usage: loosened-check-settings.mjs [--root <dir>] [--ref <origin/name|40-hex>]
//          [--verdict-option <value>] [--patterns-option <JSON list>]
//
// The repository layer is read only from --ref, through setup-apply.mjs --check
// --ref, never from the working tree, so a change cannot relax the verdict or
// drop a pattern for its own review. Without --ref, or when the ref cannot be
// read, the repository layer is skipped and the output says why. An option
// that is empty or an unrendered ${user_config.<key>} placeholder is unset.
//
// Output, one line each:
//   loosened_check_verdict: <fail|note> (<layers that set it, or default>)
//   loosened_check_patterns: <JSON list> (<layers that added entries, or default>)
// then an INFO or WARN line per skipped or invalid layer. Exit 0 when both keys
// resolved; 2 on a usage error.

import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "../lib/yaml-subset.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const APPLY = join(PLUGIN, "skills", "setup", "scripts", "setup-apply.mjs");
const VERDICTS = ["fail", "note"];

function usage(message) {
  process.stderr.write(`loosened-check-settings: ${message}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = { root: null, ref: null, verdict: null, patterns: null };
  const names = { "--root": "root", "--ref": "ref", "--verdict-option": "verdict", "--patterns-option": "patterns" };
  for (let i = 0; i < argv.length; i++) {
    const name = names[argv[i]];
    if (!name) usage(`unknown argument ${JSON.stringify(argv[i])}`);
    if (i + 1 >= argv.length) usage(`${argv[i]} needs a value`);
    opts[name] = argv[++i];
  }
  return opts;
}

const unset = (raw) => raw === null || raw === "" || raw.startsWith("${user_config.");
const isPatternList = (v) => Array.isArray(v) && v.every((p) => typeof p === "string" && p.length > 0);

/** The user layer: {verdict, patterns} with undefined for unset, and the notes for invalid values. */
function userLayer(opts, notes) {
  const layer = {};
  if (!unset(opts.verdict)) {
    if (VERDICTS.includes(opts.verdict)) layer.verdict = opts.verdict;
    else notes.push(`WARN userConfig loosened_check_verdict=${JSON.stringify(opts.verdict)} is not one of ${VERDICTS.join(", ")}; layer dropped for this key`);
  }
  if (!unset(opts.patterns)) {
    let value;
    try {
      value = JSON.parse(opts.patterns);
    } catch {
      value = undefined;
    }
    if (isPatternList(value)) layer.patterns = value;
    else notes.push("WARN userConfig loosened_check_patterns is not a JSON list of non-empty strings; layer dropped for this key");
  }
  return layer;
}

/** The repository layer as committed at opts.ref: {verdict, patterns} for each key that passed the schema check. */
function repositoryLayer(opts, notes) {
  if (opts.ref === null) {
    notes.push("INFO repository layer skipped: no --ref names the default branch");
    return {};
  }
  const args = [APPLY, "--check", "--ref", opts.ref, ...(opts.root ? ["--root", opts.root] : [])];
  const check = spawnSync(process.execPath, args, { encoding: "utf8" });
  if (check.status === 2 || check.status === null) {
    notes.push(`INFO repository layer skipped: ${opts.ref} could not be read (${(check.stderr || "").trim() || `exit ${check.status}`})`);
    return {};
  }
  const out = check.stdout;
  for (const line of out.split("\n")) if (line.startsWith("WARN ")) notes.push(line);
  const read = out.match(/^INFO read (\S+) at \S+, commit ([0-9a-f]{40})$/m);
  if (!read) {
    notes.push(`INFO repository layer skipped: ${(check.stderr || "").trim() || `the settings file at ${opts.ref} could not be read (exit ${check.status})`}`);
    return {};
  }
  if (/^INFO \S+: absent;/m.test(out)) {
    notes.push(`INFO ${read[1]} is absent at ${opts.ref}, commit ${read[2]}`);
    return {};
  }
  notes.push(`INFO read ${read[1]} at ${opts.ref}, commit ${read[2]}`);
  const passed = (key) => new RegExp(`^PASS ${key}: (?!\\(unset\\)$)`, "m").test(out);
  const layer = {};
  const verdict = out.match(/^PASS loosened_check_verdict: (fail|note)$/m);
  if (verdict) layer.verdict = verdict[1];
  if (passed("loosened_check_patterns")) {
    const root = resolve(opts.root ?? process.cwd());
    const shown = spawnSync("git", ["-C", root, "show", `${read[2]}:${read[1]}`], { cwd: PLUGIN, encoding: "utf8" });
    let value;
    try {
      value = shown.status === 0 ? parse(shown.stdout)?.loosened_check_patterns : undefined;
    } catch {
      value = undefined;
    }
    if (isPatternList(value)) layer.patterns = value;
    else notes.push(`WARN ${read[1]} at ${read[2]}: loosened_check_patterns could not be read as a list; layer dropped for this key`);
  }
  return layer;
}

/** Resolve both keys over the named layers ([name, {verdict, patterns}] in order). */
export function resolveLoosenedCheck(layers) {
  const setVerdict = layers.filter(([, l]) => l.verdict !== undefined);
  const failing = setVerdict.filter(([, l]) => l.verdict === "fail");
  const verdict = setVerdict.length === 0 || failing.length > 0 ? "fail" : "note";
  const verdictFrom = setVerdict.length === 0 ? ["default"] : (failing.length ? failing : setVerdict).map(([n]) => n);
  const patterns = [];
  const patternsFrom = [];
  for (const [name, l] of layers) {
    if (!l.patterns) continue;
    let added = false;
    for (const p of l.patterns) {
      if (!patterns.includes(p)) {
        patterns.push(p);
        added = true;
      }
    }
    if (added) patternsFrom.push(name);
  }
  return { verdict, verdictFrom, patterns, patternsFrom: patternsFrom.length ? patternsFrom : ["default"] };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const opts = parseArgs(process.argv.slice(2));
  const notes = [];
  const layers = [
    ["userConfig", userLayer(opts, notes)],
    ["docs/conventions/review.yaml", repositoryLayer(opts, notes)],
  ];
  const r = resolveLoosenedCheck(layers);
  process.stdout.write(
    `loosened_check_verdict: ${r.verdict} (${r.verdictFrom.join(", ")})\n` +
      `loosened_check_patterns: ${JSON.stringify(r.patterns)} (${r.patternsFrom.join(", ")})\n` +
      notes.map((n) => `${n}\n`).join(""),
  );
}
