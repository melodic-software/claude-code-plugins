#!/usr/bin/env node
// Decide whether to skip, offer, or build the change digest, and where a built
// page goes. Reads the pull request's facts as `gh pr view --json
// files,additions,deletions,labels` prints them, on stdin. Resolves the
// review-digest cascade surface for the policy and thresholds and the
// rendered-views surface for `medium`. Prints one JSON object. Paths and
// labels from the pull request are compared, never echoed.
//
//   digest-policy.mjs [--event ready|review] [--blast-radius LEVEL]
//                     [--policy off|offer|always] [--requested] < facts.json
// Exit 0 decided, 2 usage or unreadable facts.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, relative, resolve, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";

export const DEFAULTS = Object.freeze({
  digest_policy: "offer",
  max_files: 5,
  max_changed_lines: 200,
  blast_radius: ["HIGH", "CRITICAL"],
  risk_paths: [".github/workflows/**", "**/hooks/**", "**/migrations/**"],
  opt_in_label: "explain-change",
});
export const MEDIUM_DEFAULT = "file";
const POLICIES = ["off", "offer", "always"];
const MEDIUMS = ["terminal", "file", "artifact"];
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

function findRoot() {
  if (process.env.CLAUDE_PROJECT_DIR) return resolve(process.env.CLAUDE_PROJECT_DIR);
  let at = process.cwd();
  for (;;) {
    if (existsSync(join(at, ".git"))) return at;
    const up = dirname(at);
    if (up === at) return null;
    at = up;
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

function git(root, args) {
  try {
    execFileSync("git", ["-C", root, ...args], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
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
    team: teamFiles.map((f) => join(root, f)).filter(notUser),
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
  try {
    const value = JSON.parse(readFileSync(path, "utf8"));
    if (value && typeof value === "object" && !Array.isArray(value)) return value;
    warnings.push(`${label} ${path}: not a JSON object; layer ignored`);
  } catch (error) {
    warnings.push(`${label} ${path}: ${error.message}; layer ignored`);
  }
  return null;
}

function readTeamDigest(docsPath, dotPath, warnings) {
  if (existsSync(docsPath)) {
    const block = configBlock(readFileSync(docsPath, "utf8"));
    if (block.error) {
      warnings.push(`team ${docsPath}: ${block.error}; layer ignored`);
      return null;
    }
    if (!block.none) {
      if (existsSync(dotPath)) warnings.push(`team: both ${docsPath} and ${dotPath} exist; used ${docsPath}`);
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
  if (existsSync(dotPath)) {
    const value = readJsonLayer(dotPath, "team", warnings);
    return value ? { value, path: dotPath } : null;
  }
  return null;
}

/** Per-layer verdicts: team must be tracked, overlay must be ignored. */
function verdict(root, label, path, warnings) {
  if (label === "team" && !git(root, ["ls-files", "--error-unmatch", "--", path])) {
    warnings.push(`team ${path}: not tracked, so teammates never receive it; layer ignored`);
    return false;
  }
  if (label === "overlay" && !git(root, ["check-ignore", "-q", "--", path])) {
    warnings.push(`overlay ${path}: not gitignored, so it can reach team history`);
  }
  return true;
}

/** The review-digest surface, per-key over the shipped defaults. */
export function resolveDigestConfig() {
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
    const [docsPath, dotPath] = [
      join(paths.root, "docs/conventions/review-digest.md"),
      join(paths.root, ".claude/review-digest.json"),
    ];
    const team = paths.team.length ? readTeamDigest(docsPath, dotPath, warnings) : null;
    if (team && verdict(paths.root, "team", team.path, warnings)) {
      layers.push({ label: "team", path: team.path, value: team.value });
    }
    if (paths.overlay && existsSync(paths.overlay)) {
      const value = readJsonLayer(paths.overlay, "overlay", warnings);
      if (value && verdict(paths.root, "overlay", paths.overlay, warnings)) {
        layers.push({ label: "overlay", path: paths.overlay, value });
      }
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
export function resolveMedium(warnings) {
  const paths = layerPaths(findRoot(), "rendered-views.md", [".claude/rendered-views.md"], ".claude/rendered-views.local.md");
  const layers = [["user-global", paths.user], ...paths.team.map((p) => ["team", p]), ["overlay", paths.overlay]];
  let medium = { value: MEDIUM_DEFAULT, source: "default" };
  for (const [label, path] of layers) {
    if (!path || !existsSync(path)) continue;
    if (label !== "user-global" && !verdict(paths.root, label, path, warnings)) continue;
    const match = /^[ \t]*medium:[ \t]*["']?([a-z]+)["']?[ \t]*$/m.exec(readFileSync(path, "utf8"));
    if (!match || match[1] === "auto") continue;
    if (MEDIUMS.includes(match[1])) {
      medium = { value: match[1], source: `${label} ${path}` };
    } else {
      warnings.push(`${label} ${path}: medium ${match[1]} is not one of auto, ${MEDIUMS.join(", ")}; treated as auto`);
    }
  }
  return medium;
}

// ------------------------------------------------------------ decision

/** Glob to RegExp: `**` spans directories, `*` and `?` stay inside one segment. */
export function globRegExp(glob) {
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
  return new RegExp(`^${out}$`);
}

/**
 * @param {{files?: {path?: string, additions?: number, deletions?: number}[], additions?: number, deletions?: number, labels?: {name?: string}[]}} facts
 * @param {{policy: string, event: string, blastRadius: string, requested: boolean}} options
 * @param {Record<string, {value: unknown}>} config
 */
export function decide(facts, options, config) {
  const value = (key) => config[key].value;
  const files = Array.isArray(facts.files) ? facts.files : [];
  const paths = files.map((f) => (f && typeof f.path === "string" ? f.path : "")).filter(Boolean);
  const num = (n) => (Number.isFinite(n) ? n : 0);
  const changed =
    facts.additions !== undefined || facts.deletions !== undefined
      ? num(facts.additions) + num(facts.deletions)
      : files.reduce((sum, f) => sum + num(f?.additions) + num(f?.deletions), 0);
  const labels = (Array.isArray(facts.labels) ? facts.labels : []).map((l) => (typeof l === "string" ? l : l?.name));
  const patterns = value("risk_paths").map(globRegExp);

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

// ------------------------------------------------------------ CLI

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
  const { config, warnings } = resolveDigestConfig();
  const policy = opts.policy ? { value: opts.policy, source: "argument" } : config.digest_policy;
  const result = decide(facts, { ...opts, policy: policy.value }, config);
  const medium = resolveMedium(warnings);
  process.stdout.write(
    `${JSON.stringify({ ...result, policy, event: opts.event, requested: opts.requested, medium, config, warnings }, null, 2)}\n`,
  );
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
