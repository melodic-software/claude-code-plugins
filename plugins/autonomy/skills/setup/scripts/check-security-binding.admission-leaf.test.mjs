// Ties the validator's admission defaults to the admission-policy leaf they
// encode. Reads the leaf's "Shipped defaults" table and its no-match default,
// then probes check-security-binding.mjs with one unjustified
// autonomous-eligible rule per cell: the checker must reject the rule exactly
// where the leaf ships a less permissive disposition for that cell.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const checker = join(scriptsDir, "check-security-binding.mjs");
const fixturesDir = resolve(scriptsDir, "..", "evals", "fixtures", "security-binding");
const leafPath = resolve(scriptsDir, "..", "..", "..", "reference", "guardrails", "admission-policy.md");
const baseName = "admission-c3-autonomous-no-justification-valid.json";
const manifest = JSON.parse(readFileSync(join(scriptsDir, "check-security-binding.fixtures.test.manifest.json"), "utf8"));
const credentialRoots = manifest.fixtures[baseName].credential_roots;

const PERMISSIVENESS = { "audited-rejection": 0, "human-gated": 1, "autonomous-eligible": 2 };
const WORK_CLASSES = ["C1", "C2", "C3", "C4", "C5"];
const SURFACES = ["tracker-vcs-event", "temporal", "agent-internal", "channel-feed"];

const unquote = (cell) => cell.replaceAll("`", "").replaceAll('"', "").trim();

function readLeaf() {
  const text = readFileSync(leafPath, "utf8");
  const section = text.split("## Shipped defaults")[1].split("\n## ")[0];
  const rows = section
    .split("\n")
    .filter((line) => line.startsWith("|") && !line.startsWith("|---") && !line.includes("Surface class"))
    .map((line) => {
      const [surface, provenance, workClass, disposition] = line.split("|").slice(1, 5).map(unquote);
      return { surface, provenance, workClass, disposition };
    });
  const fallback = section.match(/Default disposition where no rule matches[^`]*`([a-z-]+)`/)[1];
  return { rows, fallback };
}

// The leaf's disposition for one cell: the most specific shipped row that
// matches, else the no-match default.
function leafDisposition({ rows, fallback }, surface, workClass) {
  const matching = rows.filter(
    (row) => (row.surface === "*" || row.surface === surface) && (row.workClass === "*" || row.workClass === workClass),
  );
  if (matching.length === 0) return fallback;
  return matching.reduce((a, b) => (PERMISSIVENESS[a.disposition] <= PERMISSIVENESS[b.disposition] ? a : b)).disposition;
}

function runChecker(rule) {
  const dir = mkdtempSync(join(tmpdir(), "admission-leaf-"));
  try {
    const binding = JSON.parse(readFileSync(join(fixturesDir, baseName), "utf8"));
    binding.admission.rules = [rule];
    const file = join(dir, "binding.json");
    writeFileSync(file, JSON.stringify(binding));
    return spawnSync(
      process.execPath,
      [checker, file, "--probe-evidence-root", fixturesDir, "--credential-roots", credentialRoots],
      { encoding: "utf8" },
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const leaf = readLeaf();

test("the leaf ships rows and a no-match default", () => {
  assert.ok(leaf.rows.length > 0);
  assert.ok(Object.hasOwn(PERMISSIVENESS, leaf.fallback));
});

for (const surface of SURFACES) {
  for (const workClass of WORK_CLASSES) {
    const expected = leafDisposition(leaf, surface, workClass);
    const rejects = PERMISSIVENESS[expected] < PERMISSIVENESS["autonomous-eligible"];
    test(`{${surface}, *, ${workClass}} autonomous-eligible: leaf ships ${expected}`, () => {
      const result = runChecker({
        signal_class: surface,
        provenance: "*",
        work_class: workClass,
        disposition: "autonomous-eligible",
      });
      const flagged = result.stderr.includes('admission.rules[0]: disposition "autonomous-eligible" is more permissive');
      assert.equal(flagged, rejects, result.stderr);
      if (!rejects) assert.equal(result.status, 0, result.stderr);
    });
  }
}
