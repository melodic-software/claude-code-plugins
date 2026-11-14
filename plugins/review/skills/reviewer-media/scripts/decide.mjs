#!/usr/bin/env node
// Decide whether a pull request gets reviewer media now: skip, build, or stale (mark posted media
// out of date and build nothing). Reads the pull request's facts as `/source-control:pull-request
// view` prints them, on stdin; `--shown` is the commit its reviewer-media section shows, as
// `/source-control:pull-request media shows` prints it. Resolves the reviewer-media convention
// (docs/conventions/reviewer-media.md): the team file from the pull request's base commit, never
// the working tree, then an untracked personal override, which can never set a team-only key. The
// thresholds are the review-digest triggers (lib/review-digest.mjs).
//
//   decide.mjs [--requested] [--shown <sha>] [--policy <policy>] [--blast-radius <level>] < facts.json
// Prints one JSON object. Exit 0 decided, 2 usage or unreadable facts.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readLayers } from "../../../lib/config-cascade.mjs";
import { LEVELS, baseReader, isSha, projectRootOf, resolveDigestConfig, triggers } from "../../../lib/review-digest.mjs";
import { findRoot, personalOverrideApplies } from "../../../lib/view-settings.mjs";

const PLUGIN = "reviewer-media";
const SCHEMA = JSON.parse(readFileSync(fileURLToPath(new URL("../../../schemas/reviewer-media.schema.json", import.meta.url)), "utf8"));
const TEAM_YAML = `docs/conventions/${PLUGIN}.yaml`;
const LOCAL_YAML = `docs/conventions/${PLUGIN}.local.yaml`;
const POLICIES = SCHEMA.properties.policy.enum;
/** Keys only the team file sets: one runs a command, the other spends money. */
const TEAM_ONLY = ["voice_command", "allow_unattended_paid_voice"];
/** Lists a later layer adds to instead of replacing: a personal override can make the scan stricter, never looser. */
const ADD_ONLY = ["scan.extra_patterns"];

export const DEFAULTS = Object.freeze({
  policy: "on-request",
  labels: Object.freeze({ requested: "reviewer-media: requested", posted: "reviewer-media: posted", failed: "reviewer-media: failed" }),
  voice_chain: Object.freeze(["edge-tts", "kokoro"]),
  voices: Object.freeze({}),
  voice_command: "",
  allow_unattended_paid_voice: false,
  ui_paths: Object.freeze([]),
  scan: Object.freeze({ extra_patterns: Object.freeze([]) }),
  upload_limit_mb: 10,
  artifact_retention_days: 30,
});

/** Every key as config-cascade names it: a schema node with `properties` is a branch, any other a leaf. */
const leavesOf = (node, prefix = []) =>
  Object.entries(node.properties ?? {}).flatMap(([k, child]) => (k === "$schema" ? [] : child.properties ? leavesOf(child, [...prefix, k]) : [[...prefix, k]]));
const LEAVES = leavesOf(SCHEMA);
const at = (object, parts) => parts.reduce((o, k) => o?.[k], object);

/**
 * @param {{isDraft?: boolean, isCrossRepository?: boolean, headRefOid?: string, labels?: ({name?: string}|string)[], files?: object[]}} facts
 * @param {{requested: boolean, shown: string | null, delta: {files: object[]} | null}} options
 * @param {typeof DEFAULTS} config resolved values
 * @param {(facts: object, whole: boolean) => string[]} triggersOf the review-digest triggers that fire for a set
 *   of facts; `whole` is false for the delta since posted media, which an assessment of the whole pull request
 *   (its blast radius) does not describe
 * @param {number[]} badPatterns indexes of scan.extra_patterns that do not compile: a build would fail its scan, so
 *   it skips before claiming the head, and fixing the team file lets the next run build
 */
export function decide(facts, options, config, triggersOf, badPatterns = []) {
  const result = choose(facts, options, config, triggersOf);
  return result.action === "build" && badPatterns.length ? { ...result, action: "skip", reason: "invalid-scan-pattern" } : result;
}

function choose(facts, { requested, shown, delta }, config, triggersOf) {
  const out = (action, reason, fired = []) => ({ action, reason, triggers: fired, shown });
  const labels = (Array.isArray(facts.labels) ? facts.labels : []).map((l) => (typeof l === "string" ? l : l?.name));
  const label = config.labels.requested;
  const asked = requested || (typeof label === "string" && label !== "" && labels.includes(label));

  if (config.policy === "never") return out("skip", "policy-never");
  if (shown && shown === facts.headRefOid) return out("skip", "current");
  if (asked) return out("build", "requested");
  if (facts.isCrossRepository !== false) return out("skip", "fork");
  if (config.policy === "on-request") return out("skip", "not-requested");
  if (facts.isDraft) return out("skip", "draft");
  if (shown) {
    if (!delta) return out("stale", "delta-unknown");
    const fired = triggersOf(delta, false);
    return fired.length ? out("build", "rebuild", fired) : out("stale", "small-delta");
  }
  if (config.policy === "always") return out("build", "always");
  const fired = triggersOf(facts, true);
  return fired.length ? out("build", "selected", fired) : out("skip", "under-thresholds");
}

// ------------------------------------------------------------ layers

function gitOut(root, args) {
  try {
    return execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch {
    return null;
  }
}

/** The convention per dotted key over the defaults: {key: {value, source}} plus warnings. */
export function resolveConfig(root, baseOid) {
  const warnings = [];
  const config = Object.fromEntries(LEAVES.map((parts) => [parts.join("."), { value: at(DEFAULTS, parts), source: "default" }]));
  if (!projectRootOf(root)) return { config, warnings };
  const base = baseReader(root, baseOid, warnings);
  const team = { path: `${base.ref}:${TEAM_YAML}`, text: base.read(TEAM_YAML) };
  const { layers } = readLayers({ plugin: PLUGIN, projectRoot: root, schema: SCHEMA, teamOnly: TEAM_ONLY, team, userHome: homedir() });
  const localPath = join(root, LOCAL_YAML);
  for (const layer of layers) {
    if (layer.name === "local" && (!existsSync(localPath) || !personalOverrideApplies(root, localPath, warnings))) continue;
    warnings.push(...layer.errors);
    const source = layer.name === "team" ? `team ${team.path}` : `personal-override ${LOCAL_YAML}`;
    for (const [key, value] of Object.entries(layer.values)) {
      if (!(key in config)) continue;
      const prior = config[key];
      config[key] =
        ADD_ONLY.includes(key) && prior.source !== "default"
          ? { value: [...new Set([...prior.value, ...value])], source: `${prior.source} + ${source}` }
          : { value, source };
    }
  }
  return { config, warnings };
}

/** {dotted key: {value}} back to the nested shape decide() reads. */
export function valuesOf(config) {
  const values = {};
  for (const [key, { value }] of Object.entries(config)) {
    const parts = key.split(".");
    let node = values;
    for (const part of parts.slice(0, -1)) node = node[part] ??= {};
    node[parts.at(-1)] = value;
  }
  return values;
}

/** Indexes of the patterns Python's re cannot compile (the scans are Python); all of them when python3 cannot run. */
export function invalidPatterns(patterns) {
  if (!patterns.length) return [];
  const check = "import json, re, sys\nbad = []\nfor i, p in enumerate(json.load(sys.stdin)):\n    try: re.compile(p)\n    except re.error: bad.append(i)\nprint(json.dumps(bad))";
  try {
    return JSON.parse(execFileSync("python3", ["-c", check], { input: JSON.stringify(patterns), encoding: "utf8", stdio: ["pipe", "pipe", "ignore"] }));
  } catch {
    return patterns.map((_, i) => i);
  }
}

/** Changed files between the commit the media show and the head, or null when git cannot say. */
function deltaOf(root, from, to) {
  if (!root || !isSha(from) || !isSha(to)) return null;
  const out = gitOut(root, ["diff", "--numstat", "--no-renames", from, to]);
  if (out === null) return null;
  const files = out
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const [add, del, ...path] = line.split("\t");
      return { path: path.join("\t"), additions: Number(add) || 0, deletions: Number(del) || 0 };
    });
  return { files };
}

// ------------------------------------------------------------ CLI

function parseArgs(argv) {
  const opts = { requested: false, shown: null, policy: null, blastRadius: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const [flag, next] = [argv[i], argv[i + 1]];
    if (flag === "--requested") opts.requested = true;
    else if (flag === "--shown" && (next === "" || isSha(next))) [opts.shown, i] = [next || null, i + 1];
    else if (flag === "--policy" && POLICIES.includes(next)) [opts.policy, i] = [next, i + 1];
    else if (flag === "--blast-radius" && LEVELS.includes(next?.toUpperCase())) [opts.blastRadius, i] = [next.toUpperCase(), i + 1];
    else return null;
  }
  return opts;
}

function main(argv) {
  const opts = parseArgs(argv);
  if (!opts) {
    process.stderr.write(`usage: decide.mjs [--requested] [--shown <sha>] [--policy ${POLICIES.join("|")}] [--blast-radius ${LEVELS.join("|")}] < facts.json\n`);
    return 2;
  }
  let facts;
  try {
    facts = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    process.stderr.write(`decide: facts are not JSON (${error.message})\n`);
    return 2;
  }
  if (!facts || typeof facts !== "object" || Array.isArray(facts)) {
    process.stderr.write("decide: facts must be a JSON object\n");
    return 2;
  }
  const root = findRoot();
  const { config, warnings } = resolveConfig(root, facts.baseRefOid);
  if (opts.policy) config.policy = { value: opts.policy, source: "argument" };
  const digest = resolveDigestConfig(facts.baseRefOid);
  warnings.push(...digest.warnings);
  const triggersOf = (f, whole) => triggers(f, whole ? opts.blastRadius : "", digest.config).triggers;
  const delta = opts.shown && opts.shown !== facts.headRefOid ? deltaOf(root, opts.shown, facts.headRefOid) : null;
  const bad = invalidPatterns(config["scan.extra_patterns"].value);
  for (const i of bad) warnings.push(`reviewer-media: scan.extra_patterns[${i}] is not a valid Python regular expression; nothing is built until it is fixed`);
  const result = decide(facts, { requested: opts.requested, shown: opts.shown, delta }, valuesOf(config), triggersOf, bad);
  process.stdout.write(`${JSON.stringify({ ...result, head: facts.headRefOid ?? null, config, warnings }, null, 2)}\n`);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
