// The review-digest cascade concern (docs/conventions/review-digest.md): its defaults, the team
// file read from a pull request's base commit, the layers per key, and the triggers that fire for a
// pull request's facts. Shared by /review:explain-change (whether to offer a digest) and
// /review:reviewer-media (whether a pull request crosses a review-digest trigger).

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join, relative, resolve, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";
import { findRoot, personalOverrideApplies } from "./view-settings.mjs";

export const DEFAULTS = Object.freeze({
  digest_policy: "offer",
  max_files: 5,
  max_changed_lines: 200,
  blast_radius: ["HIGH", "CRITICAL"],
  risk_paths: [".github/workflows/**", "**/hooks/**", "**/migrations/**"],
  opt_in_label: "explain-change",
});
/** The config files themselves: a change to one always fires risk-path, whatever risk_paths says. */
export const CONFIG_PATHS = Object.freeze([
  "docs/conventions/review-digest.yaml",
  ".claude/review-digest.local.json",
  "docs/conventions/rendered-views.yaml",
  "docs/conventions/rendered-views.local.yaml",
  ".gitmodules",
]);
/** The team file, validated by plugins/review/schemas/review-digest.schema.json. */
const TEAM_YAML = "docs/conventions/review-digest.yaml";
const YAML_PARSER = fileURLToPath(new URL("./yaml-subset.awk", import.meta.url));
export const POLICIES = ["off", "offer", "always"];
export const LEVELS = ["LOW", "MEDIUM", "HIGH", "CRITICAL"];

const isCount = (v) => Number.isInteger(v) && v >= 0;
const isStrings = (v) => Array.isArray(v) && v.every((s) => typeof s === "string" && s !== "");
/** risk_paths caps: a layer past either bound is ignored whole, so matching cost stays small. */
export const MAX_RISK_PATHS = 64;
export const MAX_GLOB_LENGTH = 256;
const isGlobs = (v) => isStrings(v) && v.length <= MAX_RISK_PATHS && v.every((s) => s.length <= MAX_GLOB_LENGTH);
const VALID = {
  digest_policy: (v) => POLICIES.includes(v),
  max_files: isCount,
  max_changed_lines: isCount,
  blast_radius: (v) => isStrings(v) && v.every((s) => LEVELS.includes(s)),
  risk_paths: isGlobs,
  opt_in_label: (v) => typeof v === "string",
};

// ------------------------------------------------------------ layers

const real = (p) => {
  try {
    return realpathSync(p);
  } catch {
    return resolve(p);
  }
};
const within = (child, parent) => {
  const rel = relative(parent, child);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
};

/** git's stdout, or null when it fails. */
function gitOut(root, args) {
  try {
    return execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch {
    return null;
  }
}
const git = (root, args) => gitOut(root, args) !== null;
export const isSha = (v) => typeof v === "string" && /^[0-9a-f]{40}$/.test(v);

/**
 * A reader of team files at the pull request's base commit (`baseRefOid`), which
 * names the base repository's commit even for a fork. Without that commit
 * locally, the reader finds nothing and warns, so defaults apply.
 */
export function baseReader(root, baseOid, warnings) {
  if (!isSha(baseOid)) {
    warnings.push("team: no baseRefOid in the facts; team layer ignored");
    return { ref: null, root, read: () => null };
  }
  if (!git(root, ["cat-file", "-e", `${baseOid}^{commit}`])) {
    warnings.push(`team: base commit ${baseOid} is not in this clone; team layer ignored`);
    return { ref: null, root, read: () => null };
  }
  return { ref: baseOid, root, read: (rel) => gitOut(root, ["show", `${baseOid}:${rel}`]) };
}

/** Team and personal override apply only inside a working tree that is not home or above it. */
/** The root a team or personal override layer may come from, or null: never home, above it, or outside a working tree. */
export function projectRootOf(root) {
  return root && !within(real(homedir()), real(root)) && git(root, ["rev-parse", "--is-inside-work-tree"]) ? root : null;
}

function layerPaths(root, userFile, teamFiles, personalOverrideFile) {
  const home = real(homedir());
  const user = join(home, ".claude", userFile);
  if (!projectRootOf(root)) {
    return { user, root: null, team: [], personalOverride: null };
  }
  const notUser = (p) => real(p) !== real(user);
  return {
    user,
    root,
    team: teamFiles.filter((f) => notUser(join(root, f))),
    personalOverride: notUser(join(root, personalOverrideFile)) ? join(root, personalOverrideFile) : null,
  };
}

function readJsonLayer(path, label, warnings) {
  try {
    const value = JSON.parse(readFileSync(path, "utf8"));
    if (value && typeof value === "object" && !Array.isArray(value)) return value;
    warnings.push(`${label} ${path}: not a JSON object; layer ignored`);
  } catch (error) {
    warnings.push(`${label} ${path}: ${error.message}; layer ignored`);
  }
  return null;
}

const COUNT_KEYS = ["max_files", "max_changed_lines"];

/**
 * The team YAML file as a layer object: the records of the shared YAML-subset
 * parser (`lib/yaml-subset.awk`) folded back to keys, lists and, for the count
 * keys, whole numbers. A quoted count reads as a number; the schema, not this
 * reader, is strict about that. A key holding a map reads as an empty object,
 * which no key accepts.
 */
export function parseYamlLayer(text, label, path, warnings) {
  const parsed = spawnSync("awk", ["-f", YAML_PARSER], { input: text, encoding: "utf8", env: { ...process.env, LC_ALL: "C" } });
  if (parsed.error) {
    warnings.push(`${label} ${path}: cannot run awk (${parsed.error.code ?? parsed.error.message}); layer ignored`);
    return null;
  }
  if (parsed.status !== 0) {
    const failure = (parsed.stdout ?? "").split("\n").find((l) => l.startsWith("error\t")) ?? "error\t?\tunreadable";
    const [, line, message] = failure.split("\t");
    warnings.push(`${label} ${path}: line ${line}: ${message}; layer ignored`);
    return null;
  }
  const value = Object.create(null);
  for (const record of parsed.stdout.split("\n").filter(Boolean)) {
    const tab = record.indexOf("\t");
    const [key, ...rest] = record.slice(0, tab).split(".");
    const raw = record.slice(tab + 1);
    if (rest.length === 0) value[key] = COUNT_KEYS.includes(key) && /^(0|[1-9]\d*)$/.test(raw) ? Number(raw) : raw;
    else if (rest.length === 1 && /^\d+$/.test(rest[0])) value[key] = [...(Array.isArray(value[key]) ? value[key] : []), raw];
    else value[key] = {};
  }
  // The parser prints nothing for an empty flow list, which a list key accepts.
  for (const [, key] of text.matchAll(/^([A-Za-z0-9_-]+):[ \t]*\[[ \t]*\][ \t]*(?:#.*)?\r?$/gm)) {
    if (!(key in value)) value[key] = [];
  }
  return value;
}

/** The team layer as the base commit holds it: the YAML file only. */
function readTeamDigest(base, yamlPath, warnings) {
  const yaml = base.read(yamlPath);
  if (yaml === null) {
    if (base.ref && existsSync(join(base.root, yamlPath))) warnings.push(`team ${yamlPath}: not on the base commit ${base.ref}; layer ignored`);
    return null;
  }
  const value = parseYamlLayer(yaml, "team", yamlPath, warnings);
  return value ? { value, path: yamlPath } : null;
}

/** The review-digest surface, per-key over the shipped defaults. */
export function resolveDigestConfig(baseOid) {
  const warnings = [];
  const config = {};
  for (const [key, value] of Object.entries(DEFAULTS)) config[key] = { value, source: "default" };
  const paths = layerPaths(findRoot(), "review-digest.json", [TEAM_YAML], ".claude/review-digest.local.json");
  const layers = [];
  if (existsSync(paths.user)) {
    const value = readJsonLayer(paths.user, "user-global", warnings);
    if (value) layers.push({ label: "user-global", path: paths.user, value });
  }
  if (paths.root) {
    if (paths.team.length) {
      const base = baseReader(paths.root, baseOid, warnings);
      const team = readTeamDigest(base, TEAM_YAML, warnings);
      if (team) layers.push({ label: "team", path: `${base.ref}:${team.path}`, value: team.value });
    }
    if (paths.personalOverride && existsSync(paths.personalOverride) && personalOverrideApplies(paths.root, paths.personalOverride, warnings)) {
      const value = readJsonLayer(paths.personalOverride, "personal-override", warnings);
      if (value) layers.push({ label: "personal-override", path: paths.personalOverride, value });
    }
  }
  for (const layer of layers) {
    for (const [key, value] of Object.entries(layer.value)) {
      if (key === "$schema") continue;
      if (!Object.hasOwn(VALID, key)) {
        warnings.push(`${layer.label} ${layer.path}: unknown key ${key} is inert`);
      } else if (!VALID[key](value)) {
        warnings.push(`${layer.label} ${layer.path}: invalid ${key}; key ignored`);
      } else {
        config[key] = { value, source: `${layer.label} ${layer.path}` };
      }
    }
  }
  return { config, warnings };
}

// ------------------------------------------------------------ decision

/**
 * Glob matcher: `**` spans directories (`**` + `/` also matches no directory),
 * `*` and `?` stay inside one segment, every other character is literal.
 * It runs the glob as a set of positions over the path, one step per character,
 * so a pattern of many stars costs time linear in the path (times the pattern
 * length), never a regex's backtracking.
 * @param {string} glob
 * @param {{nocase?: boolean}} [options]
 * @returns {{test: (path: string) => boolean}}
 */
export function globMatcher(glob, { nocase = false } = {}) {
  const fold = (s) => (nocase ? s.toLowerCase() : s);
  /** @type {{kind: "lit" | "one" | "seg" | "any" | "dirs", ch?: string}[]} */
  const tokens = [];
  // Code points, as test() walks the path: a surrogate half never equals a whole character.
  const chars = [...glob];
  for (let i = 0; i < chars.length; i += 1) {
    const c = chars[i];
    if (c === "*" && chars[i + 1] === "*") {
      const slash = chars[i + 2] === "/";
      tokens.push({ kind: slash ? "dirs" : "any" });
      i += slash ? 2 : 1;
    } else if (c === "*") {
      tokens.push({ kind: "seg" });
    } else if (c === "?") {
      tokens.push({ kind: "one" });
    } else {
      tokens.push({ kind: "lit", ch: fold(c) });
    }
  }
  const end = tokens.length;
  // A state is a token index; `dirs` tokens also have an "inside" state at end + 1 + index,
  // reached once `**/` has consumed a character and left only when it consumes a `/`.
  const inside = (t) => end + 1 + t;
  const close = (states) => {
    const stack = [...states];
    while (stack.length) {
      const s = stack.pop();
      if (s >= end) continue;
      const k = tokens[s].kind;
      if ((k === "seg" || k === "any" || k === "dirs") && !states.has(s + 1)) {
        states.add(s + 1);
        stack.push(s + 1);
      }
    }
    return states;
  };
  return {
    test(path) {
      let states = close(new Set([0]));
      for (const raw of String(path)) {
        const ch = fold(raw);
        const next = new Set();
        for (const s of states) {
          if (s > end) {
            const t = s - end - 1;
            next.add(s);
            if (ch === "/") next.add(t + 1);
            continue;
          }
          if (s === end) continue;
          const tok = tokens[s];
          if (tok.kind === "lit") {
            if (ch === tok.ch) next.add(s + 1);
          } else if (tok.kind === "one") {
            if (ch !== "/") next.add(s + 1);
          } else if (tok.kind === "seg") {
            if (ch !== "/") next.add(s);
          } else if (tok.kind === "any") {
            next.add(s);
          } else {
            next.add(inside(s));
            if (ch === "/") next.add(s + 1);
          }
        }
        if (!next.size) return false;
        states = close(next);
      }
      return states.has(end);
    },
  };
}

/** A changed path as the triggers compare it: forward slashes, no doubled slash, no leading `./`. */
export const normPath = (p) => String(p).replace(/\\/g, "/").replace(/\/{2,}/g, "/").replace(/^(\.\/)+/, "");

/**
 * The review-digest triggers that fire for a set of facts, and the counts they read.
 * @param {{files?: {path?: string, additions?: number, deletions?: number}[], additions?: number, deletions?: number, labels?: ({name?: string}|string)[]}} facts
 * @param {string} blastRadius LOW to CRITICAL, or "" when none was assessed
 * @param {Record<string, {value: unknown}>} config
 */
export function triggers(facts, blastRadius, config) {
  const value = (key) => config[key].value;
  const files = Array.isArray(facts.files) ? facts.files : [];
  const paths = files.map((f) => (f && typeof f.path === "string" ? normPath(f.path) : "")).filter(Boolean);
  const num = (n) => (Number.isFinite(n) ? n : 0);
  const changed =
    facts.additions !== undefined || facts.deletions !== undefined
      ? num(facts.additions) + num(facts.deletions)
      : files.reduce((sum, f) => sum + num(f?.additions) + num(f?.deletions), 0);
  const labels = (Array.isArray(facts.labels) ? facts.labels : []).map((l) => (typeof l === "string" ? l : l?.name));
  // Config paths match in any case: a case-insensitive filesystem reads every variant.
  const patterns = [...CONFIG_PATHS.map((p) => globMatcher(p, { nocase: true })), ...value("risk_paths").map((p) => globMatcher(p))];

  const fired = [];
  if (paths.length > value("max_files")) fired.push("files");
  if (changed > value("max_changed_lines")) fired.push("changed-lines");
  if (value("blast_radius").includes(blastRadius)) fired.push("blast-radius");
  if (paths.some((p) => patterns.some((re) => re.test(p)))) fired.push("risk-path");
  if (value("opt_in_label") !== "" && labels.includes(value("opt_in_label"))) fired.push("label");
  return { triggers: fired, facts: { files: paths.length, changed_lines: changed } };
}

/**
 * The digest decision: skip, offer or build.
 * @param {Parameters<typeof triggers>[0]} facts
 * @param {{policy: string, event: string, blastRadius: string, requested: boolean}} options
 * @param {Record<string, {value: unknown}>} config
 */
export function decide(facts, options, config) {
  const { triggers: fired, facts: counts } = triggers(facts, options.blastRadius, config);
  let action;
  if (options.requested) action = "build";
  else if (options.policy === "off") action = "skip";
  else if (options.policy === "always" && options.event === "ready") action = "build";
  else action = fired.length ? "offer" : "skip";
  return { action, triggers: fired, facts: counts };
}
