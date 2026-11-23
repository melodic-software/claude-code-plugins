
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { createFixtureHarness } from "./fixture-harness.mjs";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const checker = join(scriptsDir, "check-security-binding.mjs");
const fixturesDir = resolve(scriptsDir, "..", "evals", "fixtures", "security-binding");
const manifestPath = join(scriptsDir, "check-security-binding.fixtures.test.manifest.json");

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const fixtures = manifest.fixtures ?? {};
const quarantined = manifest.quarantined ?? {};

const { counts, pass, fail, finish } = createFixtureHarness();

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

const present = new Set(topLevelFixtures);
for (const [name, entry] of Object.entries(fixtures)) {
  const referenced = [entry.binding ?? name, entry.evidence].filter(Boolean);
  const missing = referenced.filter((file) => !present.has(file));
  if (missing.length === 0) pass(`manifest-refs-exist: ${name}`);
  else fail(`manifest-refs-exist: ${name}`, `manifest references missing file(s): ${missing.join(", ")}`);
}

for (const [name, entry] of Object.entries(fixtures)) {
  const bindingFile = entry.binding ?? name;
  const args = [checker, join(fixturesDir, bindingFile), "--probe-evidence-root", fixturesDir];
  if (entry.evidence) args.push("--evidence", join(fixturesDir, entry.evidence));
  if (entry.egress_hosts) args.push("--egress-hosts", entry.egress_hosts);
  if (entry.credential_roots) args.push("--credential-roots", entry.credential_roots);

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

  const stream = entry.exit === 0 ? result.stdout : result.stderr;
  const missing = (entry.findings_substrings ?? []).filter((sub) => !stream.includes(sub));
  if (missing.length > 0) {
    fail(`grade: ${name}`, `missing expected substring(s): ${JSON.stringify(missing)}\n  actual: ${stream.trim()}`);
    continue;
  }
  pass(`grade: ${name}`);

  if (entry.evidence && existsSync(join(fixturesDir, entry.evidence))) {
    const viaStdin = spawnSync(
      process.execPath,
      args.map((arg) => (arg === join(fixturesDir, entry.evidence) ? "-" : arg)),
      { encoding: "utf8", input: readFileSync(join(fixturesDir, entry.evidence), "utf8"), timeout: 30_000 },
    );
    if (viaStdin.status === result.status && viaStdin.stdout === result.stdout && viaStdin.stderr === result.stderr) pass(`stdin: ${name}`);
    else fail(`stdin: ${name}`, `--evidence - printed a different verdict (exit ${viaStdin.status})\n  stdout: ${viaStdin.stdout.trim()}\n  stderr: ${viaStdin.stderr.trim()}`);
  }
}

finish(
  `\nAll ${counts.cases} checks passed (${Object.keys(fixtures).length} fixtures graded, ${Object.keys(quarantined).length} quarantined).\n`,
  `\n${counts.failed}/${counts.cases} checks failed.\n`,
);
