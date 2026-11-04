// Ties the escalation event classes to the guardrails stop rule they route
// under. Reads the "## Escalation" table and its stop rule, then probes
// check-security-binding.mjs: every class the table lists must need its own
// escalation_routes entry, each class must stop for a person only as the
// table says, and the always-stop class must keep its C5 work human at merge.

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
const guardrailsPath = resolve(scriptsDir, "..", "..", "..", "reference", "guardrails.md");
const baseName = "valid.json";
const manifest = JSON.parse(readFileSync(join(scriptsDir, "check-security-binding.fixtures.test.manifest.json"), "utf8"));
const credentialRoots = manifest.fixtures[baseName].credential_roots;

// The route each class's "Stops for a person" cell must state.
const STOP_RULE = "only under the stop rule";
const EXPECTED_STOPS = {
  "gate-failure": STOP_RULE,
  "verification-divergence": STOP_RULE,
  "admission-rejection": STOP_RULE,
  demotion: STOP_RULE,
  "structural-plan-approval": "only when the plan changes intent or the primary design",
  "untrusted-provenance": "always: a kept trust control",
};

// The stop rule's own text for where each routed class goes instead.
const OWNING_ROUTES = {
  "gate-failure": "a failed gate or a dissent to the lane doing the work",
  "verification-divergence": "a failed gate or a dissent to the lane doing the work",
  demotion: "a demotion to its fix issues through intake",
  "admission-rejection": "An audited rejection stays final on the audit trail",
};

function readEscalation() {
  const text = readFileSync(guardrailsPath, "utf8");
  const section = text.split("\n## Escalation\n")[1].split("\n## ")[0];
  const stops = Object.fromEntries(
    section
      .split("\n")
      .filter((line) => line.startsWith("| `"))
      .map((line) => {
        const cells = line.split("|").slice(1, -1).map((cell) => cell.trim());
        return [cells[0].replaceAll("`", ""), cells[2]];
      }),
  );
  const rule = section.split("**Stop rule.**")[1].split("\n\n")[0].replace(/\s+/g, " ");
  return { stops, rule };
}

function runChecker(edit) {
  const dir = mkdtempSync(join(tmpdir(), "escalation-stop-"));
  try {
    const binding = JSON.parse(readFileSync(join(fixturesDir, baseName), "utf8"));
    edit(binding);
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

const { stops, rule } = readEscalation();

test("the escalation table lists exactly the classes this test routes", () => {
  assert.deepEqual(Object.keys(stops).sort(), Object.keys(EXPECTED_STOPS).sort());
});

test("the stop rule names the three reasons and the kept control", () => {
  for (const reason of ["intent or vision changes", "alters intent, vision or the primary design", "HIGH or CRITICAL security or cost"]) {
    assert.ok(rule.includes(reason), `stop rule lacks "${reason}"`);
  }
  assert.ok(rule.includes("`untrusted-provenance`, stops for a person whatever the reason"), rule);
});

test("the base binding passes the checker", () => {
  const result = runChecker(() => {});
  assert.equal(result.status, 0, result.stderr);
});

for (const [eventClass, expected] of Object.entries(EXPECTED_STOPS)) {
  test(`${eventClass}: stops for a person ${expected}`, () => {
    assert.equal(stops[eventClass], expected);
  });

  test(`${eventClass}: the binding must route it`, () => {
    const result = runChecker((binding) => {
      delete binding.escalation_routes[eventClass];
    });
    assert.equal(result.status, 1, result.stderr);
    assert.ok(result.stderr.includes(`escalation_routes.${eventClass}: missing or empty`), result.stderr);
  });

  if (Object.hasOwn(OWNING_ROUTES, eventClass)) {
    test(`${eventClass}: the stop rule sends it to its owning lane`, () => {
      assert.ok(rule.includes(OWNING_ROUTES[eventClass]), `stop rule lacks "${OWNING_ROUTES[eventClass]}"`);
    });
  }
}

test("a bare needs-human route key is rejected: no class routes there by name", () => {
  const result = runChecker((binding) => {
    binding.escalation_routes["needs-human"] = "queue:escalations/needs-human";
  });
  assert.equal(result.status, 1, result.stderr);
  assert.ok(result.stderr.includes('escalation_routes: unknown key "needs-human"'), result.stderr);
});

test("untrusted-provenance still stops for a person: C5 merge stays human", () => {
  const result = runChecker((binding) => {
    binding.merge_policy.C5 = "auto";
  });
  assert.equal(result.status, 1, result.stderr);
  assert.ok(result.stderr.includes('merge_policy.C5: "auto" exceeds the matrix cap'), result.stderr);
  assert.ok(result.stderr.includes("C5 merge is human always"), result.stderr);
});
