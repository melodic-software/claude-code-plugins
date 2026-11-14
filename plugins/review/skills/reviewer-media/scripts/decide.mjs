#!/usr/bin/env node
// Decide whether a pull request gets reviewer media now: skip, build, or stale (mark posted media
// out of date and build nothing). Reads the pull request's facts as `/source-control:pull-request
// view` prints them, on stdin. Resolves the reviewer-media convention
// (docs/conventions/reviewer-media.md): the team file from the pull request's base commit, never
// the working tree, then an untracked personal override, which can never set a team-only key. The
// thresholds are the review-digest triggers, read by /review:explain-change's own resolver.
//
//   decide.mjs [--requested] [--policy never|on-request|when-selected|always] [--blast-radius LEVEL] < facts.json
// Prints one JSON object. Exit 0 decided, 2 usage or unreadable facts.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readLayers } from "../../../lib/config-cascade.mjs";
import { findRoot, personalOverrideApplies } from "../../../lib/view-settings.mjs";
import { decide as digestDecide, resolveDigestConfig } from "../../explain-change/scripts/digest-policy.mjs";

const PLUGIN = "reviewer-media";
const SCHEMA_PATH = fileURLToPath(new URL("../../../schemas/reviewer-media.schema.json", import.meta.url));
const TEAM_YAML = `docs/conventions/${PLUGIN}.yaml`;
const LOCAL_YAML = `docs/conventions/${PLUGIN}.local.yaml`;
const POLICIES = ["never", "on-request", "when-selected", "always"];
const LEVELS = ["LOW", "MEDIUM", "HIGH", "CRITICAL"];
/** Keys only the team file sets: one runs a command, the other spends money. */
const TEAM_ONLY = ["voice_command", "allow_unattended_paid_voice"];

export const DEFAULTS = Object.freeze({
  policy: "on-request",
  labels: Object.freeze({ requested: "reviewer-media: requested", posted: "reviewer-media: posted", failed: "reviewer-media: failed" }),
  voice_chain: Object.freeze(["edge-tts", "kokoro"]),
  voices: Object.freeze({}),
  voice_command: "",
  allow_unattended_paid_voice: false,
  ui_paths: Object.freeze([]),
  upload_limit_mb: 10,
  artifact_retention_days: 30,
});

const START = "<!-- reviewer-media:start -->";
const END = "<!-- reviewer-media:end -->";
const SHOWN = /^(?:<!-- reviewer-media:posted ([0-9a-f]{40}) -->|Out of date: shows commit ([0-9a-f]{40}))\r?$/;
const isSha = (v) => typeof v === "string" && /^[0-9a-f]{40}$/.test(v);

/** The commit the body's reviewer-media section shows, or null: only lines between the markers count. */
export function sectionShows(body) {
  const lines = String(body ?? "").split("\n").map((l) => l.replace(/\r$/, ""));
  const start = lines.indexOf(START);
  const end = lines.indexOf(END, start + 1);
  if (start < 0 || end < 0) return null;
  for (const line of lines.slice(start + 1, end)) {
    const m = SHOWN.exec(line);
    if (m) return m[1] ?? m[2];
  }
  return null;
}

/**
 * @param {{isDraft?: boolean, isCrossRepository?: boolean, headRefOid?: string, body?: string, labels?: ({name?: string}|string)[], files?: object[]}} facts
 * @param {{requested: boolean, delta: {files: object[], additions?: number, deletions?: number} | null}} options
 * @param {typeof DEFAULTS} config resolved values
 * @param {(facts: object) => string[]} triggersOf the review-digest triggers that fire for a set of facts
 */
export function decide(facts, { requested, delta }, config, triggersOf) {
  const out = (action, reason, extra = {}) => ({ action, reason, triggers: [], shown, ...extra });
  const shown = sectionShows(facts.body);
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
    const triggers = triggersOf(delta);
    return triggers.length ? out("build", "rebuild", { triggers }) : out("stale", "small-delta");
  }
  if (config.policy === "always") return out("build", "always");
  const triggers = triggersOf(facts);
  return triggers.length ? out("build", "selected", { triggers }) : out("skip", "under-thresholds");
}

// ------------------------------------------------------------ layers

function gitOut(root, args) {
  try {
    return execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch {
    return null;
  }
}

const flatten = (object, prefix = "") =>
  Object.entries(object).flatMap(([k, v]) =>
    v && typeof v === "object" && !Array.isArray(v) && k !== "voices" ? flatten(v, `${prefix}${k}.`) : [[`${prefix}${k}`, v]],
  );

/** The convention per key over the defaults: {key: {value, source}} plus warnings. */
export function resolveConfig(root, baseOid) {
  const warnings = [];
  const config = Object.fromEntries(flatten(DEFAULTS).map(([key, value]) => [key, { value, source: "default" }]));
  if (!root || !gitOut(root, ["rev-parse", "--is-inside-work-tree"])) return { config, warnings };
  let team = { path: TEAM_YAML, text: null };
  if (!isSha(baseOid)) warnings.push("team: no baseRefOid in the facts; team layer ignored");
  else if (gitOut(root, ["cat-file", "-e", `${baseOid}^{commit}`]) === null) warnings.push(`team: base commit ${baseOid} is not in this clone; team layer ignored`);
  else team = { path: `${baseOid}:${TEAM_YAML}`, text: gitOut(root, ["show", `${baseOid}:${TEAM_YAML}`]) };
  const schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
  const { layers } = readLayers({ plugin: PLUGIN, projectRoot: root, schema, teamOnly: TEAM_ONLY, team, userHome: root });
  const localPath = join(root, LOCAL_YAML);
  for (const layer of layers) {
    if (layer.name === "local" && (!existsSync(localPath) || !personalOverrideApplies(root, localPath, warnings))) continue;
    warnings.push(...layer.errors);
    const source = layer.name === "team" ? `team ${team.path}` : `personal-override ${LOCAL_YAML}`;
    for (const [key, value] of Object.entries(layer.values)) if (key !== "$schema" && key in config) config[key] = { value, source };
  }
  return { config, warnings };
}

/** {key: {value}} back to the nested shape decide() reads. */
export function valuesOf(config) {
  const values = {};
  for (const [key, { value }] of Object.entries(config)) {
    const parts = key.split(".");
    let at = values;
    for (const part of parts.slice(0, -1)) at = at[part] ??= {};
    at[parts.at(-1)] = value;
  }
  return values;
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
  const opts = { requested: false, policy: null, blastRadius: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const [flag, next] = [argv[i], argv[i + 1]];
    if (flag === "--requested") opts.requested = true;
    else if (flag === "--policy" && POLICIES.includes(next)) [opts.policy, i] = [next, i + 1];
    else if (flag === "--blast-radius" && LEVELS.includes(next?.toUpperCase())) [opts.blastRadius, i] = [next.toUpperCase(), i + 1];
    else return null;
  }
  return opts;
}

function main(argv) {
  const opts = parseArgs(argv);
  if (!opts) {
    process.stderr.write("usage: decide.mjs [--requested] [--policy never|on-request|when-selected|always] [--blast-radius LOW|MEDIUM|HIGH|CRITICAL] < facts.json\n");
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
  const triggersOf = (f) => digestDecide(f, { policy: "offer", event: "review", blastRadius: opts.blastRadius, requested: false }, digest.config).triggers;
  const shown = sectionShows(facts.body);
  const delta = shown && shown !== facts.headRefOid ? deltaOf(root, shown, facts.headRefOid) : null;
  const result = decide(facts, { requested: opts.requested, delta }, valuesOf(config), triggersOf);
  process.stdout.write(`${JSON.stringify({ ...result, head: facts.headRefOid ?? null, config, warnings }, null, 2)}\n`);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
