#!/usr/bin/env node
// GENERATED from lib/publish-gate.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Decide whether a rendered view may be published as a claude.ai Artifact or must
// stay on this machine. An explicit `medium: artifact` from a trusted layer
// publishes. Otherwise the view publishes only when its source repository is
// PUBLIC (or it has no repository source) and nothing in it is shaped like a
// credential. A miss proves nothing; a hit keeps the view local.
//
//   publish-gate.mjs <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> [--explicit] [--subject <word>] < text
// Prints one JSON object. Exit 0 decided, 2 usage.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
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
