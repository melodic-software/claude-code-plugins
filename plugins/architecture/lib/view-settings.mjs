#!/usr/bin/env node
// GENERATED from lib/view-settings.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Where a rendered view goes: the one medium resolver every view lane calls. It reads each ADR 0075
// scope's own `medium` value (concern `rendered-views`, home docs/conventions) through the cascade's
// per-layer reader and schema check, and walks them itself, because a filter on the cascade's
// merged output would lose a lower scope's local value under a higher scope's publishing one.
//
// The argument decides alone. Otherwise a terminal or file value from any scope keeps the view
// local, the highest-precedence one naming the scope (personal override, then team, then
// userConfig); a retired file's terminal or file value keeps it local only when no scope sets one,
// naming that file. Else the first publishing value from a trusted scope wins: the personal override
// (only untracked and gitignored), then userConfig. A team file never publishes. With no scope
// deciding, the lane's own default applies (it ships with the installed plugin, which a checked-out
// branch cannot write). An invalid value is ignored without dropping another scope's value; auto is
// unset. The retired files (~/.claude/rendered-views.md, .claude/rendered-views.md,
// .claude/rendered-views.local.md and a fenced config block in docs/conventions/rendered-views.md)
// give a notice, once per plugin per project while unchanged, and never a publishing value. The
// medium then steps down the fallback chain (lib/view-registry.mjs) until reachable.
//
//   view-settings.mjs resolve --lane <id> --option <user_config.medium> [--argument <m>] [--team-ref <ref>]
// Prints the resolution as one JSON line, then the report line and one line per notice. With a
// medium resolved, the JSON adds `page` (the medium shows a page) and `publishes`.
// Exit 0 resolved, 2 usage.

import { execFileSync, spawnSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { configBlockBody, readLayers } from "./config-cascade.mjs";
import { NO_PAGE, NO_PREFERENCE, SCHEMA, fallBack, laneOf, mediumOf, reportLines } from "./view-registry.mjs";

const CONCERN = "rendered-views";
const HOME = "docs/conventions";
const TEAM_FILE = `${HOME}/${CONCERN}.yaml`;
const PERSONAL_FILE = `${HOME}/${CONCERN}.local.yaml`;
const HERE = dirname(fileURLToPath(import.meta.url));

// ------------------------------------------------------------ repository checks

/** The session's project: CLAUDE_PROJECT_DIR, else the nearest directory above the cwd holding `.git`. */
export function findRoot() {
  if (process.env.CLAUDE_PROJECT_DIR) return resolve(process.env.CLAUDE_PROJECT_DIR);
  for (let at = process.cwd(); ; at = dirname(at)) {
    if (existsSync(join(at, ".git"))) return at;
    if (dirname(at) === at) return null;
  }
}

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
const isLink = (p) => {
  try {
    return lstatSync(p).isSymbolicLink();
  } catch {
    return false;
  }
};
function gitOut(root, args) {
  try {
    return execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch {
    return null;
  }
}

/**
 * A personal file applies only untracked, so a pull request cannot ship one. Every directory between
 * the root and the file must be a plain, untracked directory, never a submodule, a tracked file or a
 * symlink. Not gitignored, it warns, or with `requireIgnored` is ignored too.
 */
export function personalOverrideApplies(root, path, warnings, { requireIgnored = false } = {}) {
  // Any tracked case variant counts: on a case-insensitive filesystem it is this file.
  const rel = relative(root, path).split("\\").join("/");
  if (gitOut(root, ["ls-files", "--", `:(icase)${rel}`])) {
    warnings.push(`personal override ${rel}: tracked in git, so a pull request could set it; layer ignored`);
    return false;
  }
  const parts = rel.split("/").slice(0, -1);
  const dirs = parts.map((_, i) => parts.slice(0, i + 1).join("/"));
  for (const dir of dirs) {
    // A submodule or tracked file at the directory itself is content a pull request controls.
    const entries = (gitOut(root, ["ls-files", "-s", "-z", "--", `:(icase)${dir}`]) ?? "").split("\0");
    if (entries.some((e) => e.split("\t")[1]?.toLowerCase() === dir.toLowerCase()) || existsSync(join(root, dir, ".git"))) {
      warnings.push(`personal override ${rel}: ${dir} is a submodule or tracked entry; layer ignored`);
      return false;
    }
    if (isLink(join(root, dir))) {
      warnings.push(`personal override ${rel}: ${dir} is a symlink; layer ignored`);
      return false;
    }
  }
  if (isLink(path) || !within(real(path), join(real(root), ...parts))) {
    warnings.push(`personal override ${rel}: the file is a symlink or resolves outside ${parts.join("/") || "the root"}; layer ignored`);
    return false;
  }
  if (gitOut(root, ["check-ignore", "-q", "--", path]) === null) {
    warnings.push(`personal override ${rel}: not gitignored, so it can reach team history${requireIgnored ? "; layer ignored" : ""}`);
    return !requireIgnored;
  }
  return true;
}

/** Repository scopes apply only inside a working tree that is not the user's home or above it. */
const repoScopes = (root, userHome) => Boolean(root) && !within(real(userHome), real(root)) && gitOut(root, ["rev-parse", "--is-inside-work-tree"]) !== null;

/** A ref name or object id: never an option, never a revision expression. */
const REF = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;

/** The team file as `ref` holds it, for the cascade reader; a ref naming no commit reads nothing. */
function teamAt(root, ref, notices) {
  const sha = REF.test(ref) ? gitOut(root, ["rev-parse", "--verify", "--quiet", `${ref}^{commit}`])?.trim() : null;
  if (!sha) {
    const named = ref ? `team ref ${JSON.stringify(ref)} names no commit here` : "no team ref was given";
    notices.push({ kind: "team-ref", text: `${named}, so ${TEAM_FILE} is not read` });
    return { path: `${ref}:${TEAM_FILE}`, text: null };
  }
  return { path: `${sha.slice(0, 12)}:${TEAM_FILE}`, text: gitOut(root, ["show", `${sha}:${TEAM_FILE}`]) };
}

// ------------------------------------------------------------ retired files

const mediumIn = (text) => /^[ \t]*medium:[ \t]*["']?([a-z]+)["']?[ \t]*$/m.exec(text ?? "")?.[1] ?? null;
/** The medium a retired source sets: for the team .md only its config block counts, not an example fence. */
const retiredMedium = (bytes, kind) => {
  const text = bytes?.toString("utf8") ?? null;
  return mediumIn(kind === "fenced-block" && text !== null ? configBlockBody(text) : text);
};
const readBytes = (p) => {
  try {
    return readFileSync(p);
  } catch {
    return null;
  }
};

/** This project's state key (docs/contracts/plugin-data-report-keying, rule 1), or null when it cannot be derived. */
function stateKey(root) {
  const out = spawnSync("bash", [join(HERE, "state-key.sh"), "--root", root ?? process.cwd()], { encoding: "utf8" });
  const key = out.status === 0 ? out.stdout.trim() : "";
  return /^[a-z0-9][a-z0-9._-]*(\/[a-z0-9][a-z0-9._-]*)+$/.test(key) ? key : null;
}

function writeAtomic(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  const temp = `${path}.${process.pid}.${randomBytes(4).toString("hex")}.tmp`;
  writeFileSync(temp, text);
  renameSync(temp, path);
}

const retiredWhere = (path, root, userHome) => (within(path, join(userHome, ".claude")) ? `~/${relative(userHome, path).split("\\").join("/")}` : relative(root, path).split("\\").join("/"));
const isLocal = (value) => Boolean(mediumOf(value)) && value !== NO_PREFERENCE && !mediumOf(value).publishes;

/** Highest precedence first, mirroring personal override, team, userConfig. */
const RETIRED_LOCAL = [
  ["claude-local", `${CONCERN}.local.md`],
  ["claude-project", `${CONCERN}.md`],
  ["fenced-block", `${CONCERN}.md`],
  ["claude-user", `${CONCERN}.md`],
];
const rank = ({ path, kind }) => RETIRED_LOCAL.findIndex(([k, name]) => k === kind && basename(path) === name);

/** The highest-precedence terminal or file value a retired file sets, or null; read on every call, apart from the shown-once notice state. */
function retiredLocal(legacy) {
  return (
    legacy
      .filter((entry) => rank(entry) >= 0)
      .map((entry) => ({ ...entry, value: retiredMedium(readBytes(entry.path), entry.kind) }))
      .filter(({ value }) => isLocal(value))
      .sort((a, b) => rank(a) - rank(b))[0] ?? null
  );
}

/** One notice per retired file, unless this plugin already showed it for this project with these bytes. */
function retiredNotices(legacy, { plugin, hasMediumOption, root, userHome, dataDir }) {
  const where = (path) => retiredWhere(path, root, userHome);
  const destination = { "claude-user": PERSONAL_FILE, "claude-project": TEAM_FILE, "claude-local": PERSONAL_FILE, "fenced-block": TEAM_FILE };
  const key = dataDir ? stateKey(root) : null;
  const state = key && join(dataDir, "view-settings", key, "retired-notices.json");
  let seen = {};
  try {
    seen = state ? JSON.parse(readFileSync(state, "utf8")) : {};
  } catch {
    seen = {};
  }
  const notices = [];
  let changed = false;
  const order = Object.keys(destination);
  for (const { path, kind } of [...legacy].sort((a, b) => order.indexOf(a.kind) - order.indexOf(b.kind) || a.path.localeCompare(b.path))) {
    const bytes = readBytes(path);
    if (!bytes) continue;
    const shown = where(path);
    const hash = createHash("sha256").update(bytes).digest("hex");
    if (seen[shown] === hash) continue;
    [seen[shown], changed] = [hash, true];
    const value = retiredMedium(bytes, kind);
    const to = destination[kind] ?? TEAM_FILE;
    const caveat = !mediumOf(value)?.publishes
      ? ""
      : to === TEAM_FILE
        ? "; a team file never publishes, so that value would be ignored there"
        : "; it publishes only while that file is untracked and gitignored";
    const status = rank({ path, kind }) >= 0 && isLocal(value) ? "is retired but still keeps the view local" : "is no longer read";
    const perUser = kind === "claude-user" && hasMediumOption ? `; per user, the ${plugin} plugin's medium option also works` : "";
    notices.push({ kind: "retired", path: shown, value, destination: to, text: `${shown} ${status}${value ? ` (it sets medium: ${value})` : ""}; set it in ${to} instead${caveat}${perUser}` });
  }
  if (state && changed) {
    try {
      writeAtomic(state, `${JSON.stringify(seen)}\n`);
    } catch {
      // Unwritable state shows the notice again next time, which is the safe direction.
    }
  }
  return notices;
}

// ------------------------------------------------------------ resolution

/** True when the reader chose a publishing medium (the argument, or a trusted scope), which the publish gate takes as explicit: never the plugin default. */
export const gateExplicit = ({ preferred, decidedBy }) => Boolean(mediumOf(preferred)?.publishes) && ["argument", "userConfig", "personal override"].includes(decidedBy);

/**
 * @param {{lane: string, argument?: string|null, userConfig?: string|null, projectRoot?: string|null, teamRef?: string|null}} request
 * @param {{userHome?: string, dataDir?: string|null, interactive?: boolean}} [options]
 * @returns {{preferred: string|null, medium: string|null, decidedBy: string, notices: {kind: string, text: string}[]}}
 */
export function resolveMedium({ lane, argument = null, userConfig = null, projectRoot = null, teamRef = null }, { userHome = homedir(), dataDir = null, interactive = true } = {}) {
  const laneEntry = laneOf(lane);
  if (!laneEntry) throw new Error(`view-settings: unknown lane ${JSON.stringify(lane)}`);
  const notices = [];
  const root = repoScopes(projectRoot, userHome) ? projectRoot : null;
  const team = root && typeof teamRef === "string" ? teamAt(root, teamRef, notices) : undefined;
  const { layers, legacy } = readLayers({ plugin: CONCERN, projectRoot: root, schema: SCHEMA, userConfig: { medium: userConfig ?? "" }, team, userHome });
  notices.unshift(...retiredNotices(legacy, { plugin: lane.split(":")[0], hasMediumOption: laneEntry.hasMediumOption, root, userHome, dataDir }));
  const finish = (preferred, decidedBy) => {
    if (!preferred) return { preferred: null, medium: null, decidedBy, notices };
    const { medium, fell } = fallBack(preferred, laneEntry, { interactive });
    return { preferred, medium, decidedBy: fell ? `fell back: ${fell}` : decidedBy, notices };
  };
  if (mediumOf(argument)) return finish(argument, "argument");

  const shown = (path) => (path && root && isAbsolute(path) ? relative(root, path).split("\\").join("/") : path);
  for (const layer of layers) {
    const prefix = `${layer.name}${layer.path ? ` (${layer.path})` : ""}: `;
    const where = `${layer.name === "local" ? "personal override" : layer.name}${layer.path ? ` ${shown(layer.path)}` : ""}`;
    for (const error of layer.errors) {
      notices.push({ kind: "invalid", text: `${where}: ${error.startsWith(prefix) ? error.slice(prefix.length) : error}; ignored` });
    }
  }
  const valueOf = (name) => layers.find((l) => l.name === name)?.values.medium;
  const personal = valueOf("local");
  let personalTrusted = false;
  if (personal && mediumOf(personal)?.publishes) {
    const warnings = [];
    personalTrusted = personalOverrideApplies(root, join(root, PERSONAL_FILE), warnings, { requireIgnored: true });
    for (const w of warnings) notices.push({ kind: "ignored", text: w });
  }
  // Highest precedence first (ADR 0075: the personal override, then team, then userConfig).
  const scopes = [
    ["personal override", personal, personalTrusted],
    ["team", valueOf("team"), false],
    ["userConfig", valueOf("userConfig"), true],
  ].filter(([, medium]) => medium && medium !== NO_PREFERENCE);
  const local = scopes.find(([, medium]) => !mediumOf(medium).publishes);
  if (local) return finish(local[1], local[0]);
  const retired = retiredLocal(legacy);
  if (retired) return finish(retired.value, `retired ${retiredWhere(retired.path, root, userHome)}`);
  const teamValue = scopes.find(([name]) => name === "team")?.[1];
  if (teamValue) notices.push({ kind: "ignored", text: `team ${shown(layers.find((l) => l.name === "team").path)} sets medium: ${teamValue}; a team file never publishes, so it is ignored` });
  const trusted = scopes.find(([, , ok]) => ok);
  return trusted ? finish(trusted[1], trusted[0]) : finish(laneEntry.default, "plugin default");
}

// ------------------------------------------------------------ CLI

const USAGE = "usage: view-settings.mjs resolve --lane <id> --option <user_config.medium> [--argument <medium>] [--team-ref <ref>]\n";

/** CLI: the argument vector after the script path; returns the exit code. */
export function main(argv, env = process.env) {
  const [action, ...rest] = argv;
  const request = { lane: null, userConfig: undefined, argument: null, teamRef: null };
  const flags = { "--lane": "lane", "--option": "userConfig", "--argument": "argument", "--team-ref": "teamRef" };
  for (let i = 0; i < rest.length; i += 2) {
    const key = flags[rest[i]];
    if (!key || rest[i + 1] === undefined) return usage();
    request[key] = rest[i + 1];
  }
  if (action !== "resolve" || !laneOf(request.lane) || request.userConfig === undefined) return usage();
  if (request.argument === NO_PREFERENCE) request.argument = null;
  if (request.argument !== null && !mediumOf(request.argument)) return usage();
  const ci = Boolean(env.CI) && env.CI !== "false";
  const resolution = resolveMedium({ ...request, projectRoot: findRoot() }, { dataDir: env.CLAUDE_PLUGIN_DATA || null, interactive: !ci });
  // So a skill can act on the medium without naming its value: does it show a page, does it publish.
  const entry = mediumOf(resolution.medium);
  const shown = entry ? { ...resolution, page: entry.id !== NO_PAGE, publishes: entry.publishes } : resolution;
  process.stdout.write(`${JSON.stringify(shown)}\n${reportLines(resolution).join("\n")}\n`);
  return 0;
}

function usage() {
  process.stderr.write(USAGE);
  return 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
