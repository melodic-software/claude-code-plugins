#!/usr/bin/env node

// Graded-fixture suite for resolve-prerequisites.mjs. Every directory under
// scripts/fixtures/prerequisite-resolution/ must appear in the co-located
// manifest; each fixture is a mini repo tree graded by named assertions.
//
// Also asserts wall-clock-free reproducibility: two consecutive runs on the
// same tree emit byte-identical JSON.

import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import process from "node:process";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const resolver = join(scriptsDir, "resolve-prerequisites.mjs");
const fixturesRoot = resolve(scriptsDir, "fixtures", "prerequisite-resolution");
const manifestPath = join(
  scriptsDir,
  "resolve-prerequisites.fixtures.test.manifest.json",
);

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const fixtures = manifest.fixtures ?? {};

let failed = 0;
let cases = 0;
const pass = (name) => {
  cases += 1;
  process.stdout.write(`PASS: ${name}\n`);
};
const fail = (name, detail) => {
  cases += 1;
  failed += 1;
  process.stderr.write(`FAIL: ${name}\n  detail: ${detail}\n`);
};

function runResolver(repoDir, surface) {
  return spawnSync(
    process.execPath,
    [resolver, "--repo", repoDir, "--surface", surface],
    {
      encoding: "utf8",
      maxBuffer: 10 * 1024 * 1024,
      timeout: 30_000,
    },
  );
}

function parseOut(result) {
  if (result.error) throw new Error(result.error.message);
  if (result.status !== 0) {
    throw new Error(`exit ${result.status}: ${result.stderr.trim()}`);
  }
  return JSON.parse(result.stdout);
}

function byIdentity(output) {
  return new Map(output.identities.map((row) => [row.identity, row]));
}

// --- Self-policing: every fixture directory is graded ----------------------
const onDisk = readdirSync(fixturesRoot, { withFileTypes: true })
  .filter((e) => e.isDirectory())
  .map((e) => e.name)
  .sort();
for (const name of onDisk) {
  if (Object.hasOwn(fixtures, name)) pass(`covered: ${name}`);
  else fail(`covered: ${name}`, "fixture dir has no manifest entry");
}
for (const name of Object.keys(fixtures)) {
  if (onDisk.includes(name)) pass(`manifest-refs-exist: ${name}`);
  else fail(`manifest-refs-exist: ${name}`, "manifest names missing fixture dir");
}

// --- Reproducibility on positive-verdict -----------------------------------
{
  const repo = join(fixturesRoot, "positive-verdict", "repo");
  const a = runResolver(repo, "ci-cron");
  const b = runResolver(repo, "ci-cron");
  if (a.status === 0 && b.status === 0 && a.stdout === b.stdout) {
    pass("reproducibility: byte-identical consecutive runs");
  } else {
    fail(
      "reproducibility: byte-identical consecutive runs",
      `status a=${a.status} b=${b.status}; equal=${a.stdout === b.stdout}`,
    );
  }
}

function assertBareRepo(output) {
  for (const row of output.identities) {
    if (row.verdict === "supported" || row.verdict === "conditional") {
      throw new Error(`${row.identity} verdict ${row.verdict} on bare repo`);
    }
  }
}

function assertFailClosed(output) {
  const row = byIdentity(output).get("issue-triage-sweep");
  if (!row) throw new Error("missing issue-triage-sweep");
  if (row.verdict === "supported" || row.verdict === "conditional") {
    throw new Error(`issue-triage-sweep must not clear; got ${row.verdict}`);
  }
  if (row.verdict !== "unsupported" && row.verdict !== "unknown") {
    throw new Error(`unexpected verdict ${row.verdict}`);
  }
}

function assertDeclaredAbsentNarrows(output) {
  const row = byIdentity(output).get("issue-triage-sweep");
  if (!row) throw new Error("missing issue-triage-sweep");
  if (row.verdict !== "unsupported") {
    throw new Error(`expected unsupported, got ${row.verdict}`);
  }
  const tracker = row.signals.find((s) => s.need === "tracker");
  if (!tracker || tracker.provenance.kind !== "declaration") {
    throw new Error("expected declaration provenance on tracker");
  }
  if (tracker.provenance.probe_result !== "present") {
    throw new Error(
      `probe should have found present; got ${tracker.provenance.probe_result}`,
    );
  }
}

function assertProbeNegativeCaps(output) {
  const row = byIdentity(output).get("issue-triage-sweep");
  if (!row) throw new Error("missing issue-triage-sweep");
  if (row.verdict !== "unsupported") {
    throw new Error(`expected unsupported, got ${row.verdict}`);
  }
  const finding = row.findings.find(
    (f) => f.kind === "declaration-probe-contradiction",
  );
  if (!finding) throw new Error("missing declaration-probe-contradiction finding");
}

function assertProbeCouldNotRun(output) {
  const row = byIdentity(output).get("advisory-cve-triage");
  if (!row) throw new Error("missing advisory-cve-triage");
  if (row.verdict !== "conditional") {
    throw new Error(`expected conditional (declaration stands), got ${row.verdict}`);
  }
  const advisory = row.signals.find((s) => s.need === "advisory_database");
  if (!advisory || advisory.provenance.kind !== "declaration") {
    throw new Error("expected declaration provenance");
  }
  if (!advisory.provenance.unprobeable) {
    throw new Error("expected unprobeable named in provenance");
  }
}

function assertPostureDivergence(output) {
  const map = byIdentity(output);
  const mech = map.get("dependency-update-wave/mechanical");
  const chg = map.get("dependency-update-wave/changelog-informed");
  if (!mech || !chg) throw new Error("missing dependency-update-wave postures");
  if (mech.verdict !== "supported") {
    throw new Error(`mechanical expected supported, got ${mech.verdict}`);
  }
  if (chg.verdict === "supported") {
    throw new Error("changelog-informed must not be supported without upstream");
  }
  if (mech.verdict === chg.verdict) {
    throw new Error(`verdicts should diverge; both ${mech.verdict}`);
  }
}

function assertPositiveVerdict(output) {
  const row = byIdentity(output).get("issue-triage-sweep");
  if (!row) throw new Error("missing issue-triage-sweep");
  if (row.verdict !== "supported") {
    throw new Error(`expected supported, got ${row.verdict}`);
  }
  const tracker = row.signals.find((s) => s.need === "tracker");
  if (!tracker || tracker.result !== "present") {
    throw new Error("expected tracker present with provenance");
  }
  if (!tracker.provenance || !tracker.provenance.kind) {
    throw new Error("missing provenance on positive verdict");
  }
}

const ASSERTIONS = {
  "bare-repo": assertBareRepo,
  "fail-closed": assertFailClosed,
  "declared-absent-narrows": assertDeclaredAbsentNarrows,
  "probe-negative-caps": assertProbeNegativeCaps,
  "probe-could-not-run": assertProbeCouldNotRun,
  "posture-divergence": assertPostureDivergence,
  "positive-verdict": assertPositiveVerdict,
};

for (const [name, entry] of Object.entries(fixtures)) {
  const repo = join(fixturesRoot, name, "repo");
  if (!statSync(repo).isDirectory()) {
    fail(`grade: ${name}`, "missing repo/ directory");
    continue;
  }
  const result = runResolver(repo, entry.surface);
  let output;
  try {
    output = parseOut(result);
  } catch (error) {
    fail(`grade: ${name}`, String(error.message ?? error));
    continue;
  }
  if (!output.liveness || output.liveness.taxonomy_row !== "engine health-check") {
    fail(`grade: ${name}`, "missing liveness taxonomy_row engine health-check");
    continue;
  }
  const assertFn = ASSERTIONS[entry.assert];
  if (!assertFn) {
    fail(`grade: ${name}`, `unknown assert ${entry.assert}`);
    continue;
  }
  try {
    assertFn(output);
    pass(`grade: ${name}`);
  } catch (error) {
    fail(`grade: ${name}`, String(error.message ?? error));
  }
}

if (failed === 0) {
  process.stdout.write(`\nAll ${cases} checks passed.\n`);
  process.exit(0);
}
process.stderr.write(`\n${failed} of ${cases} checks failed.\n`);
process.exit(1);
