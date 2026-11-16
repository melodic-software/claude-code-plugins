#!/usr/bin/env node
// Resolve the two settings of the bundled "Fail a change that loosens a check"
// criterion (skills/quality-gate/context/loosened-check.md):
//
//   loosened_check_verdict   policy floor: fail from any valid layer wins; default fail
//   loosened_check_patterns  union of every valid layer's entries; default none
//
// Usage: loosened-check-settings.mjs [--root <dir>] [--ref <origin/name|40-hex>]
//          [--verdict-option <value>] [--patterns-file <path>] [--spec-issue <number>]
//
// The repository layer is read only from --ref, through setup-apply.mjs --check
// --ref, never from the working tree, so a change cannot relax the verdict or
// drop a pattern for its own review. Without --ref the repository layer is
// skipped and the output says why. When the ref cannot be read, the verdict
// resolves fail, the user's patterns still apply, and a WARN line says why. An option
// that is empty or an unrendered ${user_config.<key>} placeholder is unset.
//
// Output, one line each:
//   loosened_check_verdict: <fail|note> (<layers that set it, or default>)
//   loosened_check_patterns: <JSON list> (<layers that added entries, or default>)
// then an INFO or WARN line per skipped or invalid layer. Exit 0 when both keys
// resolved; 2 on a usage error.

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
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
  const names = { "--root": "root", "--ref": "ref", "--verdict-option": "verdict", "--patterns-file": "patternsFile", "--spec-issue": "specIssue" };
  for (let i = 0; i < argv.length; i++) {
    const name = names[argv[i]];
    if (!name) usage(`unknown argument ${JSON.stringify(argv[i])}`);
    if (i + 1 >= argv.length) usage(`${argv[i]} needs a value`);
    opts[name] = argv[++i];
  }
  if (opts.patternsFile !== undefined) {
    try {
      opts.patterns = readFileSync(opts.patternsFile, "utf8").trim();
    } catch (err) {
      usage(`--patterns-file ${JSON.stringify(opts.patternsFile)} could not be read: ${err.code ?? err.message}`);
    }
  }
  if (opts.specIssue !== undefined && !/^[1-9][0-9]{0,9}$/.test(opts.specIssue)) usage("--spec-issue needs an issue number");
  return opts;
}

const TRUSTED_ACTORS = ".github/standards/trusted-actors/trusted-actors.json";
const ACTOR_KEYS = "id,kind,login";
const isObject = (v) => typeof v === "object" && v !== null && !Array.isArray(v);

const MEMBER_ASSOCIATIONS = ["OWNER", "MEMBER", "COLLABORATOR"];

/** The human ids of the trusted-actor list at opts.ref, schema-checked as loadTrustedList does; null when the ref has no list; throws on any other failure. */
function trustedHumans(opts, root) {
  if (opts.ref === null || !/^(origin\/[A-Za-z0-9._/-]+|[0-9a-f]{40})$/.test(opts.ref)) throw new Error("no --ref names the default branch");
  const git = (...args) => spawnSync("git", ["-C", root, ...args], { encoding: "utf8" });
  if (git("rev-parse", "--verify", "--quiet", `${opts.ref}^{commit}`).status !== 0) throw new Error(`${opts.ref} is not readable`);
  if (git("cat-file", "-e", `${opts.ref}:${TRUSTED_ACTORS}`).status !== 0) return null;
  const shown = git("show", `${opts.ref}:${TRUSTED_ACTORS}`);
  if (shown.status !== 0) throw new Error(`${TRUSTED_ACTORS} is not readable at ${opts.ref}`);
  const list = JSON.parse(shown.stdout);
  if (!isObject(list) || Object.keys(list).sort().join() !== "actors,version" || list.version !== 1 || !Array.isArray(list.actors)) {
    throw new Error(`${TRUSTED_ACTORS} at ${opts.ref} does not match its schema`);
  }
  const humans = new Set();
  for (const a of list.actors) {
    if (!isObject(a) || Object.keys(a).sort().join() !== ACTOR_KEYS || !Number.isInteger(a.id) || a.id < 1 || typeof a.login !== "string" || !["human", "bot"].includes(a.kind)) {
      throw new Error(`${TRUSTED_ACTORS} at ${opts.ref} has an entry that does not match its schema`);
    }
    if (a.kind === "human") humans.add(a.id);
  }
  return humans;
}

/** Whether the spec issue's text may give a loosening its reason: [counts, why]. */
function specTrust(opts) {
  if (opts.specIssue === undefined) return [false, "no --spec-issue names the issue"];
  const root = resolve(opts.root ?? process.cwd());
  try {
    const humans = trustedHumans(opts, root);
    const read = spawnSync("gh", ["api", `repos/{owner}/{repo}/issues/${opts.specIssue}`], { cwd: root, encoding: "utf8" });
    if (read.status !== 0) throw new Error(`issue #${opts.specIssue}'s author could not be read`);
    const issue = JSON.parse(read.stdout);
    const user = issue?.user;
    if (!isObject(user) || !Number.isInteger(user.id)) throw new Error(`issue #${opts.specIssue} names no author`);
    const who = `issue #${opts.specIssue} by ${user.login}, id ${user.id}`;
    if (humans === null) {
      const assoc = typeof issue.author_association === "string" ? issue.author_association : "unread";
      const rule = `author_association ${assoc}, no trusted-actor list at ${opts.ref}`;
      const counts = user.type === "User" && MEMBER_ASSOCIATIONS.includes(assoc);
      return [counts, `${who}, ${user.type === "User" ? "" : `type ${user.type}, `}${rule}`];
    }
    if (user.type === "User" && humans.has(user.id)) return [true, `${who}, a trusted person at ${opts.ref}`];
    return [false, `${who}, not a trusted person at ${opts.ref}`];
  } catch (err) {
    return [false, err instanceof SyntaxError ? "a reply could not be parsed" : err.message];
  }
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
  const unreadable = (why) => {
    notes.push(`WARN ${opts.ref} could not be read (${why}): verdict resolves fail, the safe floor, and only the user's patterns apply`);
    return { verdict: "fail", unreadable: true };
  };
  if (check.status === 2 || check.status === null) return unreadable((check.stderr || "").trim() || `exit ${check.status}`);
  const out = check.stdout;
  for (const line of out.split("\n")) if (line.startsWith("WARN ")) notes.push(line);
  const read = out.match(/^INFO read (\S+) at \S+, commit ([0-9a-f]{40})$/m);
  if (!read) return unreadable((check.stderr || "").trim() || `the settings file could not be read, exit ${check.status}`);
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
  const user = userLayer(opts, notes);
  const repo = repositoryLayer(opts, notes);
  const layers = [
    ["userConfig", user],
    [repo.unreadable ? "unreadable default branch" : "docs/conventions/review.yaml", repo],
  ];
  const r = resolveLoosenedCheck(layers);
  const [counts, why] = specTrust(opts);
  process.stdout.write(
    `loosened_check_verdict: ${r.verdict} (${r.verdictFrom.join(", ")})\n` +
      `loosened_check_patterns: ${JSON.stringify(r.patterns)} (${r.patternsFrom.join(", ")})\n` +
      `loosened_check_spec: ${counts ? "counts" : "no reason"} (${why})\n` +
      notes.map((n) => `${n}\n`).join(""),
  );
}
