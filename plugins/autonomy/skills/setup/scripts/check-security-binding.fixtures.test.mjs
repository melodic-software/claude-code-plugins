// Table-driven graded-fixture suite for check-security-binding.mjs. Every
// top-level fixture under evals/fixtures/security-binding/ is graded: the
// co-located manifest pins each fixture's expected checker exit code and the
// substrings the finding (or evaluation-mode verdict) must contain, and this
// runner FAILS if any top-level fixture lacks a manifest (or quarantine) entry
// — so a future ungraded fixture cannot be added silently.
//
// The checker verifies L2/L3 probe evidence only against a protected root, so
// every fixture runs with --probe-evidence-root pointed at the fixtures dir.
// Event-array inputs (evidence-*.json) are not bindings; their entry names the
// valid binding they pair with and grades evaluation mode via --evidence.
//
// Runnable directly (`node check-security-binding.fixtures.test.mjs`) or through
// the co-located .test.sh wrapper that scripts/run-plugin-tests.sh discovers.

import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import process from "node:process";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const checker = join(scriptsDir, "check-security-binding.mjs");
const fixturesDir = resolve(scriptsDir, "..", "evals", "fixtures", "security-binding");
const manifestPath = join(scriptsDir, "check-security-binding.fixtures.test.manifest.json");

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const fixtures = manifest.fixtures ?? {};
const quarantined = manifest.quarantined ?? {};

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

// --- Self-policing: every top-level fixture is graded or quarantined ---------
const topLevelFixtures = readdirSync(fixturesDir, { withFileTypes: true })
  .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
  .map((entry) => entry.name)
  .sort();

for (const name of topLevelFixtures) {
  if (Object.hasOwn(fixtures, name) || Object.hasOwn(quarantined, name)) {
    pass(`covered: ${name}`);
  } else {
    fail(`covered: ${name}`, "top-level fixture has no manifest (or quarantine) entry — add one so it is graded");
  }
}
// Probe transcripts are suite INPUTS (fixtures reference them as probe_evidence
// and the checker reads them through --probe-evidence-root), so the manifest
// enumerates them too — same self-policing in both directions: an unlisted
// on-disk transcript or a listed-but-missing one fails.
const transcriptsDir = join(fixturesDir, "probe-transcripts");
const onDiskTranscripts = readdirSync(transcriptsDir, { withFileTypes: true })
  .filter((entry) => entry.isFile())
  .map((entry) => entry.name)
  .sort();
const listedTranscripts = manifest.probe_transcripts ?? [];
const listedSet = new Set(listedTranscripts);
for (const name of onDiskTranscripts) {
  if (listedSet.has(name)) pass(`transcript-listed: ${name}`);
  else fail(`transcript-listed: ${name}`, "probe transcript on disk but not in the manifest's probe_transcripts list");
}
const onDiskSet = new Set(onDiskTranscripts);
for (const name of listedTranscripts) {
  if (!onDiskSet.has(name)) fail(`transcript-exists: ${name}`, "manifest lists a probe transcript that is not on disk");
}

// Reverse drift: a manifest entry whose fixture (or paired binding/evidence)
// file has been removed.
const present = new Set(topLevelFixtures);
for (const [name, entry] of Object.entries(fixtures)) {
  const referenced = [entry.binding ?? name, entry.evidence].filter(Boolean);
  const missing = referenced.filter((file) => !present.has(file));
  if (missing.length === 0) pass(`manifest-refs-exist: ${name}`);
  else fail(`manifest-refs-exist: ${name}`, `manifest references missing file(s): ${missing.join(", ")}`);
}

// --- Grade each fixture against the checker ----------------------------------
for (const [name, entry] of Object.entries(fixtures)) {
  const bindingFile = entry.binding ?? name;
  const args = [checker, join(fixturesDir, bindingFile), "--probe-evidence-root", fixturesDir];
  if (entry.evidence) args.push("--evidence", join(fixturesDir, entry.evidence));
  if (entry.egress_hosts) args.push("--egress-hosts", entry.egress_hosts);

  const result = spawnSync(process.execPath, args, {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
    timeout: 30_000,
  });
  if (result.error) {
    fail(`grade: ${name}`, `could not launch checker: ${result.error.message}`);
    continue;
  }

  if (result.status !== entry.exit) {
    fail(`grade: ${name}`, `expected exit ${entry.exit}, got ${result.status}\n  stderr: ${result.stderr.trim()}`);
    continue;
  }

  // Findings print to stderr (exit 1); OK verdicts and evaluation-mode lines
  // print to stdout (exit 0) — assert each substring against the right stream.
  const stream = entry.exit === 0 ? result.stdout : result.stderr;
  const missing = (entry.findings_substrings ?? []).filter((sub) => !stream.includes(sub));
  if (missing.length > 0) {
    fail(`grade: ${name}`, `missing expected substring(s): ${JSON.stringify(missing)}\n  actual: ${stream.trim()}`);
    continue;
  }
  pass(`grade: ${name}`);
}

if (failed === 0) {
  process.stdout.write(`\nAll ${cases} checks passed (${Object.keys(fixtures).length} fixtures graded, ${Object.keys(quarantined).length} quarantined).\n`);
  process.exit(0);
}
process.stderr.write(`\n${failed}/${cases} checks failed.\n`);
process.exit(1);
