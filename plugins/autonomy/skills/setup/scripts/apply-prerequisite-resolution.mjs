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

import { readFileSync, writeFileSync, mkdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
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
  let repo = null;
  let surface = null;
  let nonInteractive = false;
  let ratify = false;
  let proposal = null;
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--repo") {
      repo = argv[++i];
      continue;
    }
    if (arg === "--surface") {
      surface = argv[++i];
      continue;
    }
    if (arg === "--non-interactive") {
      nonInteractive = true;
      continue;
    }
    if (arg === "--ratify") {
      ratify = true;
      continue;
    }
    if (arg === "--proposal") {
      proposal = argv[++i];
      continue;
    }
    usage(`unknown argument: ${arg}`);
  }
  if (!repo) usage("`--repo` is required");
  return { repo, surface, nonInteractive, ratify, proposal };
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

function collectFindings(check) {
  const findings = [];
  for (const report of check.surfaces ?? []) {
    for (const row of report.identities ?? []) {
      for (const finding of row.findings ?? []) {
        findings.push({
          surface: report.surface,
          identity: row.identity,
          verdict: row.verdict,
          ...finding,
        });
      }
    }
  }
  return findings;
}

function proseProposals(repo) {
  const proposals = [];
  const files = ["CLAUDE.md", "AGENTS.md", "README.md", "README"];
  for (const name of files) {
    const path = join(repo, name);
    let body;
    try {
      body = readFileSync(path, "utf8");
    } catch {
      continue;
    }
    // Judgment-only heuristics for *proposals* — never runtime authority.
    if (/work-item-tracker|issue tracker|tracker binding/i.test(body)) {
      proposals.push({
        source: name,
        kind: "declaration-proposal",
        need: "tracker",
        state: "present",
        rung: "repo-local",
        note: "prose mentions tracker; propose non-security declaration only",
      });
    }
    if (/CI|continuous integration|github actions/i.test(body)) {
      proposals.push({
        source: name,
        kind: "declaration-proposal",
        need: "ci_config",
        state: "present",
        rung: "repo-local",
        note: "prose mentions CI; propose non-security declaration only",
      });
    }
  }
  return proposals;
}

function orgRungStops(check) {
  const stops = [];
  for (const report of check.surfaces ?? []) {
    for (const row of report.identities ?? []) {
      if (row.connector_entitlement_rung === "org") {
        stops.push({
          identity: row.identity,
          reason: "connector entitlement awaits Org binding layer",
        });
      }
      // Emission-backed: identities with non-empty connector entitlements would
      // appear here; current v1 leaves are all repo-scoped (none).
    }
  }
  return stops;
}

function narrowingAdvice(check) {
  const advice = [];
  for (const report of check.surfaces ?? []) {
    for (const row of report.identities ?? []) {
      if (row.verdict === "supported" || row.verdict === "conditional") {
        advice.push({
          identity: row.identity,
          surface: report.surface,
          verdict: row.verdict,
          action: "may-enable",
          note: "narrowing-only: enable in routines.enabled only when verdict clears",
        });
      } else {
        advice.push({
          identity: row.identity,
          surface: report.surface,
          verdict: row.verdict,
          action: "advisory-path",
          note: "negative/unknown routes to advisory path; do not enable",
        });
      }
    }
  }
  return advice;
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
  const section = {
    schema_version: proposal.schema_version ?? "1.0",
    surface_refs: proposal.surface_refs ?? [],
    declarations: proposal.declarations ?? [],
  };
  // Detect-diff-reconcile: never silently drop existing declarations that
  // contradict probes — keep them and rely on check findings.
  const prior = existing.prerequisite_resolution?.declarations ?? [];
  const merged = [...prior];
  for (const decl of section.declarations) {
    const idx = merged.findIndex(
      (d) =>
        d.surface === decl.surface &&
        d.identity === decl.identity &&
        d.need === decl.need,
    );
    if (idx >= 0) {
      // Do not overwrite a declaration that would hide a contradiction —
      // ratify replaces only when explicitly included in the proposal.
      merged[idx] = decl;
    } else {
      merged.push(decl);
    }
  }
  existing.prerequisite_resolution = {
    schema_version: section.schema_version,
    surface_refs: [
      ...new Set([
        ...(existing.prerequisite_resolution?.surface_refs ?? []),
        ...section.surface_refs,
      ]),
    ],
    declarations: merged,
  };
  // Refuse security keys.
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
    const findings = collectFindings(check);
    const proposals = proseProposals(args.repo);
    const orgStops = orgRungStops(check);
    const enablement = narrowingAdvice(check);
    const nonInteractive = args.nonInteractive || !process.stdin.isTTY;

    const report = {
      schema_version: 1,
      action: "apply-propose",
      non_interactive: nonInteractive,
      reconcile_findings: findings,
      prose_proposals: proposals,
      org_rung_stops: orgStops,
      enablement_advice: enablement,
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
