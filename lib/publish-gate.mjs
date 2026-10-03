#!/usr/bin/env node
// Decide whether a rendered view may be published as a claude.ai Artifact or must
// stay on this machine. An explicit `medium: artifact` from a trusted layer
// publishes. Otherwise the view publishes only when its source repository is
// PUBLIC (or it has no repository source) and nothing in it is shaped like a
// credential. A miss proves nothing; a hit keeps the view local.
//
//   publish-gate.mjs <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> [--explicit] [--subject <word>] < text
// Prints one JSON object. Exit 0 decided, 2 usage.

import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/** Text shaped like a credential. Conservative: a hit keeps the page local, a miss proves nothing. */
export const SECRET_PATTERNS = Object.freeze([
  ["private key", /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
  ["AWS access key", /\b(?:AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}\b/],
  ["GitHub token", /\b(?:gh[pousr]_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{82})/],
  ["Anthropic key", /\bsk-ant-[A-Za-z0-9_-]{20,}/],
  ["OpenAI key", /\bsk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_-]{20,}/],
  ["Slack token", /\bxox[abposr]-[0-9A-Za-z-]{10,}/],
  ["Stripe key", /\b[sr]k_(?:test|live|prod)_[0-9A-Za-z]{10,}/],
  ["password or secret assignment", /\b(?:password|passwd|pwd|secret|client_secret|api_?key|token)["']?\s*[:=]\s*["'][^"'\s$<>{}]{8,}["']/i],
]);

/** The first credential-shaped pattern in `text`, as [label, 1-based line], or null. Never the match itself. */
export function findSecret(text) {
  const lines = String(text ?? "").split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    for (const [label, re] of SECRET_PATTERNS) if (re.test(lines[i])) return [label, i + 1];
  }
  return null;
}

export const DESTINATION = "a private Artifact on claude.ai";
export const OPT_IN = "set medium: artifact in ~/.claude/rendered-views.md to publish anyway";
export const VISIBILITIES = Object.freeze(["PUBLIC", "PRIVATE", "INTERNAL", "UNKNOWN", "NONE"]);

/**
 * Where an `artifact` view actually goes. `visibility` is the source repository's
 * (`gh repo view --json visibility`), `NONE` when the view draws on no repository,
 * and anything unrecognized is treated as not PUBLIC.
 * @param {{explicit: boolean, visibility: string, text: string, subject?: string}} input
 */
export function publishGate({ explicit, visibility, text, subject = "content" }) {
  if (explicit) return { medium: "artifact", destination: DESTINATION, reason: "a layer sets medium: artifact" };
  if (visibility !== "PUBLIC" && visibility !== "NONE") {
    return { medium: "file", reason: `repository visibility is ${visibility || "unknown"}, not PUBLIC`, opt_in: OPT_IN };
  }
  const secret = findSecret(text);
  if (secret) return { medium: "file", reason: `${subject} line ${secret[1]} looks like a ${secret[0]}`, opt_in: OPT_IN };
  const source = visibility === "NONE" ? "no repository source" : "public repository";
  return { medium: "artifact", destination: DESTINATION, reason: `${source} and nothing credential-shaped in the ${subject}` };
}

// ------------------------------------------------------------ trusted layers

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
 * An overlay applies only untracked, so a pull request cannot ship one. Not
 * gitignored, it warns, or with `requireIgnored` is ignored too.
 */
export function overlayApplies(root, path, warnings, { requireIgnored = false } = {}) {
  // Any tracked case variant counts: on a case-insensitive filesystem it is this file.
  const rel = relative(root, path).split("\\").join("/");
  if (gitOut(root, ["ls-files", "--", `:(icase)${rel}`])) {
    warnings.push(`overlay ${path}: tracked in git, so a pull request could set it; layer ignored`);
    return false;
  }
  const dir = join(root, ".claude");
  // A submodule or tracked file at .claude itself is content a pull request controls.
  const entries = (gitOut(root, ["ls-files", "-s", "-z", "--", ":(icase).claude"]) ?? "").split("\0");
  if (entries.some((e) => e.split("\t")[1]?.toLowerCase() === ".claude") || existsSync(join(dir, ".git"))) {
    warnings.push(`overlay ${path}: .claude is a submodule or tracked entry; layer ignored`);
    return false;
  }
  if (isLink(dir) || isLink(path) || !within(real(path), join(real(root), ".claude"))) {
    warnings.push(`overlay ${path}: .claude or the overlay is a symlink or resolves outside ${dir}; layer ignored`);
    return false;
  }
  if (gitOut(root, ["check-ignore", "-q", "--", path]) === null) {
    warnings.push(`overlay ${path}: not gitignored, so it can reach team history${requireIgnored ? "; layer ignored" : ""}`);
    return !requireIgnored;
  }
  return true;
}

export const MEDIUMS = Object.freeze(["terminal", "file", "artifact"]);
const mediumIn = (text) => /^[ \t]*medium:[ \t]*["']?([a-z]+)["']?[ \t]*$/m.exec(text ?? "")?.[1];
const readText = (p) => (existsSync(p) ? readFileSync(p, "utf8") : null);

/**
 * The medium the user's own layers set, resolved here rather than by the model
 * reading them. The user's argument decides alone. Otherwise any layer setting
 * `terminal` or `file` keeps the view local, and `artifact` counts only from the
 * plugin option, `~/.claude/rendered-views.md`, or an untracked, gitignored
 * `<project>/.claude/rendered-views.local.md`. The team `.claude/rendered-views.md`
 * can arrive in a checked-out branch, so it may keep a view local but never publish it.
 * @returns {{medium: string|null, source: string|null, warnings: string[]}} medium null: no layer decided
 */
export function trustedMedium({ argument = null, option = null, home = homedir(), project = findRoot() } = {}) {
  const warnings = [];
  if (MEDIUMS.includes(argument)) return { medium: argument, source: "the user's argument", warnings };
  const user = join(home, ".claude", "rendered-views.md");
  const layers = [
    ["the plugin option", MEDIUMS.includes(option) ? option : null, true],
    [user, mediumIn(readText(user)), true],
  ];
  const inTree = project && !within(real(home), real(project)) && gitOut(project, ["rev-parse", "--is-inside-work-tree"]) !== null;
  if (inTree) {
    const team = join(project, ".claude", "rendered-views.md");
    if (real(team) !== real(user)) layers.push([team, mediumIn(readText(team)), false]);
    const overlay = join(project, ".claude", "rendered-views.local.md");
    if (real(overlay) !== real(user) && existsSync(overlay) && overlayApplies(project, overlay, warnings, { requireIgnored: true })) {
      layers.push([overlay, mediumIn(readText(overlay)), true]);
    }
  }
  const local = layers.find(([, medium]) => medium === "terminal" || medium === "file");
  if (local) return { medium: local[1], source: local[0], warnings };
  const publish = layers.find(([, medium, trusted]) => medium === "artifact" && trusted);
  return publish ? { medium: "artifact", source: publish[0], warnings } : { medium: null, source: null, warnings };
}

/** CLI: the argument vector after the script path; returns the exit code. */
export function main(argv, input = () => readFileSync(0, "utf8")) {
  const [visibility, ...rest] = argv;
  if (!visibility || visibility.startsWith("--")) return usage();
  let explicit = false;
  let subject = "content";
  for (let i = 0; i < rest.length; i += 1) {
    if (rest[i] === "--explicit") explicit = true;
    else if (rest[i] === "--subject" && /^[a-z]{1,20}$/.test(rest[i + 1] ?? "")) subject = rest[++i];
    else return usage();
  }
  const result = publishGate({ explicit, visibility: visibility.toUpperCase(), text: input(), subject });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return 0;
}

function usage() {
  process.stderr.write("usage: publish-gate.mjs <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> [--explicit] [--subject <word>] < text\n");
  return 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
