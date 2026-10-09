#!/usr/bin/env node
// GENERATED from lib/publish-gate.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Decide whether a rendered view may be published as a claude.ai Artifact or must
// stay on this machine. An explicit `medium: artifact` from a trusted layer
// publishes. Otherwise the view publishes only when its source repository is
// PUBLIC (or it has no repository source) and nothing in it is shaped like a
// credential. A miss proves nothing; a hit keeps the view local.
//
// A `hosted` page goes to a shared page host through `pages-publish`. It runs
// every check whatever the layers say: a credential refuses the host, and a
// repository that is not PUBLIC or a machine path or hostname sends it to the
// private host. The destination is only ever lowered from the one requested.
//
//   publish-gate.mjs <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> [--explicit] [--subject <word>]
//                    [--medium hosted [--visibility public|private]] < text
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
  [
    "R2 key pair",
    /\b[0-9a-f]{32}\b.*\b[0-9a-f]{64}\b|\b[0-9a-f]{64}\b.*\b[0-9a-f]{32}\b|\b(?:access_?key_?id|secret_?access_?key)["']?\s*[:=]\s*["']?[0-9A-Za-z/+]{16,}/i,
  ],
  ["Azure client secret", /(?:^|[^\w~.-])[\w~.]{3}\dQ~[\w~.-]{31,34}(?![\w~.-])/],
  ["Cloudflare API token", /\bcf(?:k|ut|at)_[A-Za-z0-9]{40,}/],
  ["upload token", /\bpgup_[A-Za-z0-9_-]{20,}/],
]);

/** Machine paths and hostnames: a hit sends a hosted page to the private host. Only these shapes are caught. */
export const MACHINE_PATTERNS = Object.freeze([
  ["home path", /\/home\/[a-z_][\w.-]*\/|\/Users\/[^/\s"'<>]+\/|\b[A-Za-z]:\\+Users\\+|\/mnt\/[a-z]\/Users\/|(?<![\w.~-])\/root\//i],
  ["WSL path", /\\\\wsl(?:\$|\.localhost)/i],
  ["scratchpad slug", /(?<![\w-])-home-[a-z_][\w.]*-/i],
  ["fleet hostname", /\bmelo-(?:desk|lap)-\d{3}\b/i],
  ["private hostname", /\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:local|internal|lan)\b(?![.-])/i],
]);

// The builder's page stamp carries a 64-hex digest, which would otherwise pair with any 32-hex token.
const STAMP = /<!-- rv-gen:[\w.-]+ sha256:[0-9a-f]{64} -->/g;

const firstHit = (patterns, text) => {
  const lines = String(text ?? "").split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i].replace(STAMP, "");
    for (const [label, re] of patterns) if (re.test(line)) return [label, i + 1];
  }
  return null;
};

/** The first credential-shaped pattern in `text`, as [label, 1-based line], or null. Never the match itself. */
export const findSecret = (text) => firstHit(SECRET_PATTERNS, text);

/** The first machine path or hostname in `text`, as [label, 1-based line], or null. Never the match itself. */
export const findMachine = (text) => firstHit(MACHINE_PATTERNS, text);

export const DESTINATION = "a private Artifact on claude.ai";
export const OPT_IN = "set medium: artifact in ~/.claude/rendered-views.md to publish anyway";
export const VISIBILITIES = Object.freeze(["PUBLIC", "PRIVATE", "INTERNAL", "UNKNOWN", "NONE"]);

/**
 * Where an `artifact` view actually goes. `visibility` is the source repository's
 * (`gh repo view --json visibility`), `NONE` when the view draws on no repository,
 * and anything unrecognized is treated as not PUBLIC.
 * A `hosted` medium returns `{medium: "hosted", destination: "public"|"private", reason}`,
 * or `medium: "file"` when a credential refuses the host; `explicit` skips nothing there.
 * @param {{explicit: boolean, visibility: string, text: string, subject?: string, medium?: string, requested?: string}} input
 */
export function publishGate({ explicit, visibility, text, subject = "content", medium = "artifact", requested = "public" }) {
  if (medium === "hosted") return hostedGate({ visibility, text, subject, requested });
  if (explicit) return { medium: "artifact", destination: DESTINATION, reason: "a layer sets medium: artifact" };
  if (visibility !== "PUBLIC" && visibility !== "NONE") {
    return { medium: "file", reason: `repository visibility is ${visibility || "unknown"}, not PUBLIC`, opt_in: OPT_IN };
  }
  const secret = findSecret(text);
  if (secret) return { medium: "file", reason: `${subject} line ${secret[1]} looks like a ${secret[0]}`, opt_in: OPT_IN };
  const source = visibility === "NONE" ? "no repository source" : "public repository";
  return { medium: "artifact", destination: DESTINATION, reason: `${source} and nothing credential-shaped in the ${subject}` };
}

function hostedGate({ visibility, text, subject, requested }) {
  const secret = findSecret(text);
  if (secret) return { medium: "file", reason: `${subject} line ${secret[1]} looks like a ${secret[0]}; a hosted page is refused` };
  const to = (destination, reason) => ({ medium: "hosted", destination, reason });
  if (requested !== "public") return to("private", "the private host was requested");
  if (visibility !== "PUBLIC" && visibility !== "NONE") return to("private", `repository visibility is ${visibility || "unknown"}, not PUBLIC`);
  const machine = findMachine(text);
  if (machine) return to("private", `${subject} line ${machine[1]} names a ${machine[0]}`);
  const source = visibility === "NONE" ? "no repository source" : "public repository";
  return to("public", `${source} and nothing credential-, path- or host-shaped in the ${subject}`);
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

export const MEDIUMS = Object.freeze(["terminal", "file", "artifact", "hosted"]);
const PUBLISHING = new Set(["artifact", "hosted"]);
const mediumIn = (text) => /^[ \t]*medium:[ \t]*["']?([a-z]+)["']?[ \t]*$/m.exec(text ?? "")?.[1];
const readText = (p) => (existsSync(p) ? readFileSync(p, "utf8") : null);

/**
 * The medium the user's own layers set, resolved here rather than by the model
 * reading them. The user's argument decides alone. Otherwise any layer setting
 * `terminal` or `file` keeps the view local, and `artifact` or `hosted` counts only from the
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
  const publish = layers.find(([, medium, trusted]) => PUBLISHING.has(medium) && trusted);
  return publish ? { medium: publish[1], source: publish[0], warnings } : { medium: null, source: null, warnings };
}

/** CLI: the argument vector after the script path; returns the exit code. */
export function main(argv, input = () => readFileSync(0, "utf8")) {
  const [visibility, ...rest] = argv;
  if (!visibility || visibility.startsWith("--")) return usage();
  const opts = { explicit: false, subject: "content", medium: "artifact", requested: "public" };
  let requested = false;
  for (let i = 0; i < rest.length; i += 1) {
    const next = rest[i + 1] ?? "";
    if (rest[i] === "--explicit") opts.explicit = true;
    else if (rest[i] === "--subject" && /^[a-z]{1,20}$/.test(next)) opts.subject = rest[++i];
    else if (rest[i] === "--medium" && next === "hosted") opts.medium = rest[++i];
    else if (rest[i] === "--visibility" && ["public", "private"].includes(next)) [opts.requested, requested] = [rest[++i], true];
    else return usage();
  }
  if (requested && opts.medium !== "hosted") return usage();
  const result = publishGate({ ...opts, visibility: visibility.toUpperCase(), text: input() });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return 0;
}

function usage() {
  process.stderr.write(
    "usage: publish-gate.mjs <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> [--explicit] [--subject <word>] [--medium hosted [--visibility public|private]] < text\n",
  );
  return 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
