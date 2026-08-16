#!/usr/bin/env node

// Setup-slice check for routine prerequisite resolution. Invokes the
// deterministic resolver for every scheduling surface recorded in the
// autonomy binding (or a default surface when none are bound). Read-only.
//
// Liveness: engine health-check — runs the resolver end-to-end; non-zero exit
// on internal failure; never a verdict-shaped fallback.
//
// Usage:
//   node check-prerequisite-resolution.mjs [--repo <dir>] [--surface <id>]
// Exit 0 = report emitted; 1 = internal failure.

import { spawnSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const RESOLVER = join(SCRIPT_DIR, "resolve-prerequisites.mjs");

function usage(message) {
  if (message) console.error(message);
  console.error(
    "usage: node check-prerequisite-resolution.mjs [--repo <dir>] [--surface <id>]",
  );
  process.exit(1);
}

function parseArgs(argv) {
  let repo = process.cwd();
  let surface = null;
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
    usage(`unknown argument: ${arg}`);
  }
  return { repo, surface };
}

function loadBinding(repo) {
  try {
    return JSON.parse(
      readFileSync(join(repo, ".claude", "autonomy", "binding.json"), "utf8"),
    );
  } catch {
    return null;
  }
}

function surfaceIds(binding) {
  const ids = new Set();
  if (!binding) return ids;
  for (const key of ["triggers", "routines"]) {
    const map = binding[key]?.surfaces;
    if (map && typeof map === "object") {
      for (const id of Object.keys(map)) ids.add(id);
    }
  }
  const refs = binding.prerequisite_resolution?.surface_refs;
  if (Array.isArray(refs)) {
    for (const id of refs) {
      if (typeof id === "string") ids.add(id);
    }
  }
  return ids;
}

function runResolver(repo, surface) {
  const result = spawnSync(
    process.execPath,
    [RESOLVER, "--repo", repo, "--surface", surface],
    { encoding: "utf8", maxBuffer: 10 * 1024 * 1024, timeout: 60_000 },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `resolver failed for surface ${surface}: ${result.stderr.trim() || `exit ${result.status}`}`,
    );
  }
  return JSON.parse(result.stdout);
}

function main() {
  try {
    const { repo, surface } = parseArgs(process.argv.slice(2));
    if (!statSync(repo).isDirectory()) {
      throw new Error(`--repo ${repo} is not a directory`);
    }

    const binding = loadBinding(repo);
    const surfaces = surface
      ? [surface]
      : [...surfaceIds(binding)];
    if (surfaces.length === 0) surfaces.push("unbound");

    const reports = [];
    for (const id of surfaces.sort()) {
      reports.push(runResolver(repo, id));
    }

    const output = {
      schema_version: 1,
      action: "check",
      repo,
      liveness: {
        taxonomy_row: "engine health-check",
        conformance:
          "invokes resolve-prerequisites.mjs end-to-end; fail-loud on internal failure",
      },
      surfaces: reports,
    };
    process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  } catch (error) {
    console.error(`check-prerequisite-resolution: ${error.message}`);
    process.exit(1);
  }
}

main();
