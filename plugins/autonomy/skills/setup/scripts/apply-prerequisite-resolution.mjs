#!/usr/bin/env node

// Setup-slice apply helper for routine prerequisite resolution.
// Default mode is propose-only (non-interactive): reports reconcile findings,
// prose-context proposals into non-security keys, and org-rung stops.
// `--ratify` writes an additive prerequisite_resolution section after the
// human (or test harness) has accepted the proposal JSON on stdin / --proposal.
// Never writes the security binding.
//
// Usage:
//   node apply-prerequisite-resolution.mjs --repo <dir> --surface <id> [--non-interactive]
//   node apply-prerequisite-resolution.mjs --repo <dir> --ratify --proposal <file>
// Exit 0 = report / write ok; 1 = failure.

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const CHECKER = join(SCRIPT_DIR, "check-prerequisite-resolution.mjs");

function usage(message) {
  if (message) console.error(message);
  console.error(
    "usage: node apply-prerequisite-resolution.mjs --repo <dir> [--surface <id>] [--non-interactive] | --ratify --proposal <file>",
  );
  process.exit(1);
}

function parseArgs(argv) {
  const args = { repo: null, surface: null, nonInteractive: false, ratify: false, proposal: null };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--repo") args.repo = argv[++i];
    else if (arg === "--surface") args.surface = argv[++i];
    else if (arg === "--non-interactive") args.nonInteractive = true;
    else if (arg === "--ratify") args.ratify = true;
    else if (arg === "--proposal") args.proposal = argv[++i];
    else usage(`unknown argument: ${arg}`);
  }
  if (!args.repo) usage("`--repo` is required");
  return args;
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

function runCheck(repo, surface) {
  const args = [CHECKER, "--repo", repo];
  if (surface) args.push("--surface", surface);
  const result = spawnSync(process.execPath, args, {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
    timeout: 60_000,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || `check exit ${result.status}`);
  }
  return JSON.parse(result.stdout);
}

// Every identity row of the check report, paired with the surface report it
// came from, in report order.
function* identityRows(check) {
  for (const report of check.surfaces ?? []) {
    for (const row of report.identities ?? []) {
      yield { report, row };
    }
  }
}

function collectFindings(check) {
  return [...identityRows(check)].flatMap(({ report, row }) =>
    [...(row.findings ?? [])].map((finding) => ({
      surface: report.surface,
      identity: row.identity,
      verdict: row.verdict,
      ...finding,
    })),
  );
}

// Judgment-only heuristics for *proposals* — never runtime authority.
const PROSE_RULES = [
  {
    re: /work-item-tracker|issue tracker|tracker binding/i,
    need: "tracker",
    note: "prose mentions tracker; propose non-security declaration only",
  },
  {
    re: /CI|continuous integration|github actions/i,
    need: "ci_config",
    note: "prose mentions CI; propose non-security declaration only",
  },
];

function proseProposals(repo) {
  return ["CLAUDE.md", "AGENTS.md", "README.md", "README"].flatMap((name) => {
    let body;
    try {
      body = readFileSync(join(repo, name), "utf8");
    } catch {
      return [];
    }
    return PROSE_RULES.filter((rule) => rule.re.test(body)).map((rule) => ({
      source: name,
      kind: "declaration-proposal",
      need: rule.need,
      state: "present",
      rung: "repo-local",
      note: rule.note,
    }));
  });
}

// Identities with connector entitlements at the org rung; current v1 leaves
// are all repo-scoped, so this is empty today.
function orgRungStops(check) {
  return [...identityRows(check)]
    .filter(({ row }) => row.connector_entitlement_rung === "org")
    .map(({ row }) => ({
      identity: row.identity,
      reason: "connector entitlement awaits Org binding layer",
    }));
}

function narrowingAdvice(check) {
  return [...identityRows(check)].map(({ report, row }) => {
    const clears = row.verdict === "supported" || row.verdict === "conditional";
    return {
      identity: row.identity,
      surface: report.surface,
      verdict: row.verdict,
      action: clears ? "may-enable" : "advisory-path",
      note: clears
        ? "narrowing-only: enable in routines.enabled only when verdict clears"
        : "negative/unknown routes to advisory path; do not enable",
    };
  });
}

function writeRatified(repo, proposal) {
  const bindingPath = join(repo, ".claude", "autonomy", "binding.json");
  mkdirSync(dirname(bindingPath), { recursive: true });
  const existing = readJson(bindingPath) ?? { schema_version: "1.0" };
  if (proposal.surfaces) {
    throw new Error(
      "proposal must not carry a surfaces map — reference existing surface ids via surface_refs",
    );
  }
  // Detect-diff-reconcile: keep every existing declaration, even one that
  // contradicts probes (check findings report it); a proposal declaration
  // replaces only the one with its surface, identity and need.
  const prior = existing.prerequisite_resolution;
  const declarations = [...(prior?.declarations ?? [])];
  for (const decl of proposal.declarations ?? []) {
    const idx = declarations.findIndex(
      (d) =>
        d.surface === decl.surface &&
        d.identity === decl.identity &&
        d.need === decl.need,
    );
    if (idx >= 0) declarations[idx] = decl;
    else declarations.push(decl);
  }
  existing.prerequisite_resolution = {
    schema_version: proposal.schema_version ?? "1.0",
    surface_refs: [
      ...new Set([...(prior?.surface_refs ?? []), ...(proposal.surface_refs ?? [])]),
    ],
    declarations,
  };
  if (existing.admission || existing.isolation || existing.executor_class) {
    throw new Error("refusing to write security-binding axes into autonomy binding");
  }
  writeFileSync(bindingPath, `${JSON.stringify(existing, null, 2)}\n`);
  return bindingPath;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    if (!statSync(args.repo).isDirectory()) {
      throw new Error(`--repo ${args.repo} is not a directory`);
    }

    if (args.ratify) {
      if (!args.proposal) usage("`--ratify` requires `--proposal`");
      const proposal = JSON.parse(readFileSync(args.proposal, "utf8"));
      const path = writeRatified(args.repo, proposal);
      process.stdout.write(
        `${JSON.stringify({ action: "ratify", written: path, security_binding_writes: false }, null, 2)}\n`,
      );
      return;
    }

    const check = runCheck(args.repo, args.surface);
    const nonInteractive = args.nonInteractive || !process.stdin.isTTY;
    const report = {
      schema_version: 1,
      action: "apply-propose",
      non_interactive: nonInteractive,
      reconcile_findings: collectFindings(check),
      prose_proposals: proseProposals(args.repo),
      org_rung_stops: orgRungStops(check),
      enablement_advice: narrowingAdvice(check),
      security_binding_writes: false,
      assumptions: nonInteractive
        ? [
            "non-interactive context: skipped ask-and-persist rungs; proposals reported as assumptions",
          ]
        : [],
      note: "Human must ratify via --ratify --proposal; slice never auto-writes org-rung or security axes",
      check,
    };
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } catch (error) {
    console.error(`apply-prerequisite-resolution: ${error.message}`);
    process.exit(1);
  }
}

main();
