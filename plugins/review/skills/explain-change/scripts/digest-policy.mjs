#!/usr/bin/env node
// Decide whether to skip, offer, or build the change digest, and where a built
// page goes. Reads the pull request's facts as `/source-control:pull-request
// view` prints them, on stdin; it uses files, additions, deletions, labels and
// baseRefOid. Resolves
// the review-digest cascade surface for the policy and thresholds and the
// rendered-views surface for `medium`. Team files are read from the base commit,
// never the working tree, so a checked-out pull request cannot configure its
// own digest. Prints one JSON object. Paths and labels from the pull request
// are compared, never echoed.
//
//   digest-policy.mjs [--event ready|review] [--blast-radius LEVEL]
//                     [--policy off|offer|always] [--requested] < facts.json
//   digest-policy.mjs --publish-gate <VISIBILITY>|--facts <facts.json> [--explicit] < diff
// Exit 0 decided, 2 usage or unreadable facts.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join, relative, resolve, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";
import { SECRET_PATTERNS, findRoot, findSecret, overlayApplies, publishGate as sharedGate } from "../../../lib/publish-gate.mjs";

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
  "docs/conventions/review-digest.md",
  ".claude/review-digest.json",
  ".claude/review-digest.local.json",
  ".claude/rendered-views.md",
  ".claude/rendered-views.local.md",
  ".gitmodules",
]);
export const MEDIUM_DEFAULT = "artifact";
const POLICIES = ["off", "offer", "always"];
const MEDIUMS = ["terminal", "file", "artifact", "hosted"];
const LEVELS = ["LOW", "MEDIUM", "HIGH", "CRITICAL"];

const isCount = (v) => Number.isInteger(v) && v >= 0;
const isStrings = (v) => Array.isArray(v) && v.every((s) => typeof s === "string" && s !== "");
const VALID = {
  digest_policy: (v) => POLICIES.includes(v),
  max_files: isCount,
  max_changed_lines: isCount,
  blast_radius: (v) => isStrings(v) && v.every((s) => LEVELS.includes(s)),
  risk_paths: isStrings,
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

/**
 * A reader of team files at the pull request's base commit (`baseRefOid`), which
 * names the base repository's commit even for a fork. Without that commit
 * locally, the reader finds nothing and warns, so defaults apply.
 */
function baseReader(root, baseOid, warnings) {
  if (typeof baseOid !== "string" || !/^[0-9a-f]{40}$/.test(baseOid)) {
    warnings.push("team: no baseRefOid in the facts; team layer ignored");
    return { ref: null, root, read: () => null };
  }
  if (!git(root, ["cat-file", "-e", `${baseOid}^{commit}`])) {
    warnings.push(`team: base commit ${baseOid} is not in this clone; team layer ignored`);
    return { ref: null, root, read: () => null };
  }
  return { ref: baseOid, root, read: (rel) => gitOut(root, ["show", `${baseOid}:${rel}`]) };
}

/** Team and overlay apply only inside a working tree that is not home or above it. */
function layerPaths(root, userFile, teamFiles, overlayFile) {
  const home = real(homedir());
  const user = join(home, ".claude", userFile);
  if (!root || within(home, real(root)) || !git(root, ["rev-parse", "--is-inside-work-tree"])) {
    return { user, root: null, team: [], overlay: null };
  }
  const notUser = (p) => real(p) !== real(user);
  return {
    user,
    root,
    team: teamFiles.filter((f) => notUser(join(root, f))),
    overlay: notUser(join(root, overlayFile)) ? join(root, overlayFile) : null,
  };
}

/** The one ```json config block in a docs convention file, or why there is none. */
export function configBlock(markdown) {
  const lines = markdown.split(/\r?\n/);
  const found = [];
  let fence = null;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (fence) {
      if (fence.config ? line === "```" : new RegExp(`^${fence.mark}${fence.mark[0]}*\\s*$`).test(line)) {
        if (fence.config) found.push({ line: fence.line, body: lines.slice(fence.line, i).join("\n") });
        fence = null;
      }
      continue;
    }
    const open = /^(`{3,}|~{3,})(.*)$/.exec(line);
    if (open) fence = { mark: open[1], line: i + 1, config: line === "```json config" };
  }
  if (found.length > 1) return { error: `two config blocks (lines ${found.map((b) => b.line).join(" and ")})` };
  return found.length ? { body: found[0].body } : { none: true };
}

function readJsonLayer(path, label, warnings) {
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch (error) {
    warnings.push(`${label} ${path}: ${error.message}; layer ignored`);
    return null;
  }
  return parseJsonLayer(text, label, path, warnings);
}

function parseJsonLayer(text, label, path, warnings) {
  try {
    const value = JSON.parse(text);
    if (value && typeof value === "object" && !Array.isArray(value)) return value;
    warnings.push(`${label} ${path}: not a JSON object; layer ignored`);
  } catch (error) {
    warnings.push(`${label} ${path}: ${error.message}; layer ignored`);
  }
  return null;
}

/** The team layer as the base commit holds it: the docs block, else the dot file. */
function readTeamDigest(base, docsPath, dotPath, warnings) {
  const [docs, dot] = [base.read(docsPath), base.read(dotPath)];
  if (docs === null && dot === null && base.ref) {
    for (const p of [docsPath, dotPath]) {
      if (existsSync(join(base.root, p))) warnings.push(`team ${p}: not on the base commit ${base.ref}; layer ignored`);
    }
  }
  if (docs !== null) {
    const block = configBlock(docs);
    if (block.error) {
      warnings.push(`team ${docsPath}: ${block.error}; layer ignored`);
      return null;
    }
    if (!block.none) {
      if (dot !== null) warnings.push(`team: both ${docsPath} and ${dotPath} exist; used ${docsPath}`);
      try {
        const value = JSON.parse(block.body || "{}");
        if (value && typeof value === "object" && !Array.isArray(value)) return { value, path: docsPath };
        warnings.push(`team ${docsPath}: config block is not a JSON object; layer ignored`);
      } catch (error) {
        warnings.push(`team ${docsPath}: ${error.message}; layer ignored`);
      }
      return null;
    }
  }
  if (dot !== null) {
    const value = parseJsonLayer(dot, "team", dotPath, warnings);
    return value ? { value, path: dotPath } : null;
  }
  return null;
}

/** The review-digest surface, per-key over the shipped defaults. */
export function resolveDigestConfig(baseOid) {
  const warnings = [];
  const config = {};
  for (const [key, value] of Object.entries(DEFAULTS)) config[key] = { value, source: "default" };
  const paths = layerPaths(
    findRoot(),
    "review-digest.json",
    ["docs/conventions/review-digest.md", ".claude/review-digest.json"],
    ".claude/review-digest.local.json",
  );
  const layers = [];
  if (existsSync(paths.user)) {
    const value = readJsonLayer(paths.user, "user-global", warnings);
    if (value) layers.push({ label: "user-global", path: paths.user, value });
  }
  if (paths.root) {
    if (paths.team.length) {
      const base = baseReader(paths.root, baseOid, warnings);
      const team = readTeamDigest(base, "docs/conventions/review-digest.md", ".claude/review-digest.json", warnings);
      if (team) layers.push({ label: "team", path: `${base.ref}:${team.path}`, value: team.value });
    }
    if (paths.overlay && existsSync(paths.overlay) && overlayApplies(paths.root, paths.overlay, warnings)) {
      const value = readJsonLayer(paths.overlay, "overlay", warnings);
      if (value) layers.push({ label: "overlay", path: paths.overlay, value });
    }
  }
  for (const layer of layers) {
    for (const [key, value] of Object.entries(layer.value)) {
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

/** The rendered-views `medium` key: the last layer stating a recognized value wins. */
export function resolveMedium(warnings, baseOid) {
  const paths = layerPaths(findRoot(), "rendered-views.md", [".claude/rendered-views.md"], ".claude/rendered-views.local.md");
  // The digest config already warned about a missing base commit.
  const base = paths.root ? baseReader(paths.root, baseOid, []) : null;
  const fromDisk = (p) => (existsSync(p) ? readFileSync(p, "utf8") : null);
  const layers = [
    ["user-global", paths.user, fromDisk(paths.user)],
    ...paths.team.map((p) => ["team", `${base.ref}:${p}`, base.read(p)]),
  ];
  if (paths.overlay && existsSync(paths.overlay) && overlayApplies(paths.root, paths.overlay, warnings)) {
    layers.push(["overlay", paths.overlay, fromDisk(paths.overlay)]);
  }
  let medium = { value: MEDIUM_DEFAULT, source: "default" };
  for (const [label, path, text] of layers) {
    if (text === null) continue;
    const match = /^[ \t]*medium:[ \t]*["']?([a-z]+)["']?[ \t]*$/m.exec(text);
    if (!match || match[1] === "auto") continue;
    if (match[1] === "hosted" && label === "team") {
      // A pull request's base can carry a team file, so it never sends pages off to a shared host.
      warnings.push(`${label} ${path}: medium hosted is honored only from the user-global layer or the overlay; layer ignored`);
    } else if (match[1] === "hosted" && label === "overlay" && !overlayApplies(paths.root, path, [], { requireIgnored: true })) {
      warnings.push(`${label} ${path}: medium hosted is honored from the overlay only once it is gitignored; layer ignored`);
    } else if (MEDIUMS.includes(match[1])) {
      medium = { value: match[1], source: `${label} ${path}` };
    } else {
      warnings.push(`${label} ${path}: medium ${match[1]} is not one of auto, ${MEDIUMS.join(", ")}; treated as auto`);
    }
  }
  return medium;
}

// ------------------------------------------------------------ decision

/** Glob to RegExp: `**` spans directories, `*` and `?` stay inside one segment. */
export function globRegExp(glob, flags = "") {
  let out = "";
  for (let i = 0; i < glob.length; i += 1) {
    const c = glob[i];
    if (c === "*" && glob[i + 1] === "*") {
      const slash = glob[i + 2] === "/";
      out += slash ? "(?:.*/)?" : ".*";
      i += slash ? 2 : 1;
    } else if (c === "*") {
      out += "[^/]*";
    } else if (c === "?") {
      out += "[^/]";
    } else {
      out += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
    }
  }
  return new RegExp(`^${out}$`, flags);
}

/**
 * @param {{files?: {path?: string, additions?: number, deletions?: number}[], additions?: number, deletions?: number, labels?: {name?: string}[]}} facts
 * @param {{policy: string, event: string, blastRadius: string, requested: boolean}} options
 * @param {Record<string, {value: unknown}>} config
 */
export function decide(facts, options, config) {
  const value = (key) => config[key].value;
  const files = Array.isArray(facts.files) ? facts.files : [];
  const paths = files
    .map((f) => (f && typeof f.path === "string" ? f.path.replace(/\\/g, "/").replace(/\/{2,}/g, "/").replace(/^(\.\/)+/, "") : ""))
    .filter(Boolean);
  const num = (n) => (Number.isFinite(n) ? n : 0);
  const changed =
    facts.additions !== undefined || facts.deletions !== undefined
      ? num(facts.additions) + num(facts.deletions)
      : files.reduce((sum, f) => sum + num(f?.additions) + num(f?.deletions), 0);
  const labels = (Array.isArray(facts.labels) ? facts.labels : []).map((l) => (typeof l === "string" ? l : l?.name));
  // Config paths match in any case: a case-insensitive filesystem reads every variant.
  const patterns = [...CONFIG_PATHS.map((p) => globRegExp(p, "i")), ...value("risk_paths").map((p) => globRegExp(p))];

  const triggers = [];
  if (paths.length > value("max_files")) triggers.push("files");
  if (changed > value("max_changed_lines")) triggers.push("changed-lines");
  if (value("blast_radius").includes(options.blastRadius)) triggers.push("blast-radius");
  if (paths.some((p) => patterns.some((re) => re.test(p)))) triggers.push("risk-path");
  if (value("opt_in_label") !== "" && labels.includes(value("opt_in_label"))) triggers.push("label");

  let action;
  if (options.requested) action = "build";
  else if (options.policy === "off") action = "skip";
  else if (options.policy === "always" && options.event === "ready") action = "build";
  else action = triggers.length ? "offer" : "skip";
  return { action, triggers, facts: { files: paths.length, changed_lines: changed } };
}

// ------------------------------------------------------------ publish gate

export { SECRET_PATTERNS, findSecret };

/**
 * Where an `artifact` page actually goes, by the shared publish gate. A pull
 * request always has a repository, so `NONE` counts as not PUBLIC here.
 * @param {{explicit: boolean, visibility: string, diff: string}} input
 */
export function publishGate({ explicit, visibility, diff }) {
  const known = visibility === "NONE" ? "UNKNOWN" : visibility;
  return sharedGate({ explicit, visibility: known, text: diff, subject: "diff" });
}

// ------------------------------------------------------------ CLI

// `--facts <file>` takes the visibility from the saved facts, so no second
// interpreter reads them; a missing, unreadable or empty value gates as UNKNOWN.
function factsVisibility(file) {
  try {
    const value = JSON.parse(readFileSync(file, "utf8"))?.visibility;
    return typeof value === "string" && value ? value : "UNKNOWN";
  } catch {
    return "UNKNOWN";
  }
}

function gateMain(argv) {
  let [visibility, ...rest] = argv;
  if (visibility === "--facts" && rest[0]) [visibility, rest] = [factsVisibility(rest[0]), rest.slice(1)];
  if (!visibility || visibility.startsWith("--") || rest.some((a) => a !== "--explicit")) {
    process.stderr.write("usage: digest-policy.mjs --publish-gate <VISIBILITY>|--facts <facts.json> [--explicit] < diff\n");
    return 2;
  }
  const diff = readFileSync(0, "utf8");
  const result = publishGate({ explicit: rest.includes("--explicit"), visibility: visibility.toUpperCase(), diff });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return 0;
}

function parseArgs(argv) {
  const opts = { policy: null, event: "review", blastRadius: "", requested: false };
  for (let i = 0; i < argv.length; i += 1) {
    const [flag, next] = [argv[i], argv[i + 1]];
    if (flag === "--requested") opts.requested = true;
    else if (flag === "--policy" && POLICIES.includes(next)) [opts.policy, i] = [next, i + 1];
    else if (flag === "--event" && ["ready", "review"].includes(next)) [opts.event, i] = [next, i + 1];
    else if (flag === "--blast-radius" && LEVELS.includes(next?.toUpperCase())) [opts.blastRadius, i] = [next.toUpperCase(), i + 1];
    else return null;
  }
  return opts;
}

function main(argv) {
  if (argv[0] === "--publish-gate") return gateMain(argv.slice(1));
  const opts = parseArgs(argv);
  if (!opts) {
    process.stderr.write(
      "usage: digest-policy.mjs [--event ready|review] [--blast-radius LOW|MEDIUM|HIGH|CRITICAL] [--policy off|offer|always] [--requested] < facts.json\n",
    );
    return 2;
  }
  let facts;
  try {
    facts = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    process.stderr.write(`digest-policy: facts are not JSON (${error.message})\n`);
    return 2;
  }
  if (!facts || typeof facts !== "object" || Array.isArray(facts)) {
    process.stderr.write("digest-policy: facts must be a JSON object\n");
    return 2;
  }
  const { config, warnings } = resolveDigestConfig(facts.baseRefOid);
  const policy = opts.policy ? { value: opts.policy, source: "argument" } : config.digest_policy;
  const result = decide(facts, { ...opts, policy: policy.value }, config);
  const medium = resolveMedium(warnings, facts.baseRefOid);
  process.stdout.write(
    `${JSON.stringify({ ...result, policy, event: opts.event, requested: opts.requested, medium, config, warnings }, null, 2)}\n`,
  );
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
