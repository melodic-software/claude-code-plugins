#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../lib/test-tmp.mjs";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const RESOLVER_DIR = join(REPO, "plugins/source-control/skills/babysit-loop/scripts");
const CHECKER = join(REPO, "plugins/autonomy/skills/setup/scripts/check-security-binding.mjs");
const FIXTURES = join(REPO, "plugins/autonomy/skills/setup/evals/fixtures/security-binding");
const PROMOTED_BINDING = join(FIXTURES, "promoted-c2c3.json");
const TRANSCRIPT_REF = "probe-transcripts/ci-pool-a-l2.json";
// The fixture transcript probes $HOME/.netrc, expanded on the probe host to /home/runner/.netrc.
const CREDENTIAL_ROOTS = "/home/runner";
const CELLS = ["C2-auto-merge", "C3-auto-merge", "C3-ai-review-blocking"];
const IN_EPOCH = "2026-07-10T12:00:00Z";

const base = realpathSync.native(tempDir("promotion-evidence-e2e-"));
after(() => rmSync(base, { recursive: true, force: true }));
const checkout = join(base, "checkout");
const ops = join(base, "ops");
mkdirSync(checkout);
mkdirSync(ops);

const config = join(base, "config");
const install = join(config, "plugins", "cache", "mkt", "source-control", "9.9.9", "skills", "babysit-loop", "scripts");
mkdirSync(install, { recursive: true });
for (const name of ["resolve-promotion-evidence.mjs", "operator-options.mjs"]) copyFileSync(join(RESOLVER_DIR, name), join(install, name));
const RESOLVER = join(install, "resolve-promotion-evidence.mjs");
const userSettings = join(config, "settings.json");

// The resolver refuses a surface or settings file the lane user can write, and every file here
// belongs to whoever runs the suite. Cases run its main() through its test seam instead: a wrapper
// beside it on linux that reports every path administrator-owned (uid 0) and unwritable, so the
// writability test passes and the case reaches the checker.
const SEAM = join(install, "seam.mjs");
writeFileSync(
  SEAM,
  `import { main } from "./resolve-promotion-evidence.mjs";
main({ platform: "linux", uid: 1000, access: () => false, stat: () => ({ uid: 0 }) });
`,
);

const { managedSettingsFiles } = await import(join(RESOLVER_DIR, "operator-options.mjs"));
const managedConfigures = managedSettingsFiles().some((file) => {
  try {
    return readFileSync(file, "utf8").includes("promotion_evidence_");
  } catch {
    return false;
  }
});
const cli = { skip: managedConfigures && "host managed settings configure promotion_evidence_* options" };

let written = 0;
function writeJson(value, name = `file-${++written}.json`, dir = ops) {
  const path = join(dir, name);
  writeFileSync(path, typeof value === "string" ? value : JSON.stringify(value));
  return path;
}
const events = (...list) => writeJson(list);
const EMPTY = join(FIXTURES, "evidence-empty.json");

const BOUND = { promotion_evidence_max_age_hours: "24" };
function published(ageHours = 0, list = []) {
  const dir = join(ops, `published-${++written}`);
  mkdirSync(dir);
  const text = JSON.stringify(list);
  const generatedAt = new Date(Date.now() - ageHours * 3_600_000).toISOString();
  const sha256 = createHash("sha256").update(text).digest("hex");
  writeJson({ generated_at: generatedAt, through: generatedAt, sha256, prev_sha256: null }, "evidence.meta.json", dir);
  return { path: writeJson(text, "evidence.json", dir), generatedAt };
}

function operatorOptions(overrides = {}) {
  const options = {
    promotion_evidence_binding: PROMOTED_BINDING,
    promotion_evidence_root: FIXTURES,
    promotion_evidence_source: EMPTY,
    promotion_evidence_checker: CHECKER,
    promotion_evidence_credential_roots: CREDENTIAL_ROOTS,
    ...overrides,
  };
  for (const key of Object.keys(options)) if (options[key] === undefined) delete options[key];
  return options;
}

const settingsFor = (options) => JSON.stringify({ pluginConfigs: { "source-control@mkt": { options } } });

function runResolver({ args = [], env = {}, helper = SEAM } = {}) {
  const run = spawnSync(process.execPath, [helper, "--checkout", checkout, ...args], {
    encoding: "utf8",
    cwd: checkout,
    env: { ...process.env, ...env },
  });
  assert.equal(run.status, 0, run.stderr);
  return JSON.parse(run.stdout);
}

function resolveWith(overrides = {}, run = {}) {
  writeFileSync(userSettings, settingsFor(operatorOptions(overrides)));
  return runResolver(run);
}

const effective = (result) => Object.fromEntries(CELLS.map((cell) => [cell, result.cells[cell].effective]));
const ALL = (state) => Object.fromEntries(CELLS.map((cell) => [cell, state]));

function assertFailClosed(result, reason) {
  assert.match(result.failClosedReason ?? "", reason);
  assert.deepEqual(effective(result), ALL("unpromoted"));
}

function checkerStderr(binding, probeRoot, credentialRoots = CREDENTIAL_ROOTS) {
  const argv = [CHECKER, binding, "--evidence", EMPTY, "--probe-evidence-root", probeRoot];
  if (credentialRoots !== null) argv.push("--credential-roots", credentialRoots);
  const run = spawnSync(process.execPath, argv, { encoding: "utf8" });
  assert.equal(run.status, 1, run.stdout);
  return run.stderr;
}

describe("promoted", () => {
  test("the operator's real checker over the promoted fixture yields every cell effective promoted", cli, () => {
    const result = resolveWith();
    assert.equal(result.failClosedReason, null);
    assert.deepEqual(effective(result), ALL("promoted"));
    assert.equal(result.cells["C3-auto-merge"].bound, "promoted");
    assert.deepEqual(result.options.promotion_evidence_checker, { value: CHECKER, scope: "user", file: userSettings });
  });

  test("without the seam the same configuration fails closed: the lane user owns the checker", cli, () => {
    const owned = join(ops, "check-security-binding.mjs");
    copyFileSync(CHECKER, owned);
    assertFailClosed(resolveWith({ promotion_evidence_checker: owned }, { helper: RESOLVER }), /^lane-writable:promotion_evidence_checker$/);
  });
});

describe("demoted", () => {
  const expected = {
    "C2-auto-merge": { "C2-auto-merge": "unpromoted", "C3-auto-merge": "unpromoted", "C3-ai-review-blocking": "promoted" },
    "C3-ai-review-blocking": { "C2-auto-merge": "promoted", "C3-auto-merge": "unpromoted", "C3-ai-review-blocking": "unpromoted" },
    "C3-auto-merge": { "C2-auto-merge": "promoted", "C3-auto-merge": "unpromoted", "C3-ai-review-blocking": "promoted" },
  };
  for (const event of ["gate-failure", "reverted-merge", "verification-divergence"]) {
    for (const cell of CELLS) {
      test(`${event} on ${cell} demotes it and its dependents`, cli, () => {
        const result = resolveWith({ promotion_evidence_source: events({ cell, event, at: IN_EPOCH }) });
        assert.equal(result.failClosedReason, null);
        assert.deepEqual(effective(result), expected[cell]);
      });
    }
    test(`${event} on both prerequisites leaves all three cells unpromoted`, cli, () => {
      const source = events({ cell: "C2-auto-merge", event, at: IN_EPOCH }, { cell: "C3-ai-review-blocking", event, at: IN_EPOCH });
      assert.deepEqual(effective(resolveWith({ promotion_evidence_source: source })), ALL("unpromoted"));
    });
  }

  test("the C2 revert fixture cascades to C3 auto-merge", cli, () => {
    const result = resolveWith({ promotion_evidence_source: join(FIXTURES, "evidence-c2-revert-cascades-c3.json") });
    assert.deepEqual(effective(result), expected["C2-auto-merge"]);
    assert.match(result.cells["C3-auto-merge"].line, /prerequisite/);
  });

  test("a contrary event before ratified_at is ignored", cli, () => {
    const result = resolveWith({ promotion_evidence_source: join(FIXTURES, "evidence-stale.json") });
    assert.equal(result.failClosedReason, null);
    assert.deepEqual(effective(result), ALL("promoted"));
    assert.match(result.cells["C2-auto-merge"].line, /pre-epoch contrary event/);
  });

  test("--window-start after ratification restarts the window and demotes every cell", cli, () => {
    const result = resolveWith({ ...BOUND, promotion_evidence_source: published().path }, { args: ["--window-start", "2026-10-11T07:00:00Z"] });
    assert.equal(result.failClosedReason, null);
    assert.deepEqual(effective(result), ALL("unpromoted"));
  });

  test("--window-start before every ratification leaves the cells re-earned from fresh evidence promoted", cli, () => {
    const result = resolveWith({ ...BOUND, promotion_evidence_source: published().path }, { args: ["--window-start", "2026-06-01T00:00:00Z"] });
    assert.equal(result.failClosedReason, null);
    assert.deepEqual(effective(result), ALL("promoted"));
  });

  const escapeRe = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const staleReason = ({ path, generatedAt }) =>
    new RegExp(`^promotion_evidence_source ${escapeRe(path)} is stale: generated_at ${escapeRe(generatedAt)} is older than promotion_evidence_max_age_hours 24$`);

  test("a re-earn read from evidence older than the bound keeps every cell demoted", cli, () => {
    const { path, generatedAt } = published(25);
    const result = resolveWith({ ...BOUND, promotion_evidence_source: path }, { args: ["--window-start", "2026-06-01T00:00:00Z"] });
    assertFailClosed(result, staleReason({ path, generatedAt }));
  });

  const reearnEvents = (since) => CELLS.map((cell) => ({ cell, event: "re-earned", at: "2026-10-20T00:00:00Z", since }));
  const reearned = (since) => published(0, reearnEvents(since)).path;

  test("a re-earn per cell read from evidence older than the bound keeps every cell demoted", cli, () => {
    const stale = published(25, reearnEvents("2026-10-11T07:00:00Z"));
    const result = resolveWith({ ...BOUND, promotion_evidence_source: stale.path }, { args: ["--window-start", "2026-10-11T07:00:00Z"] });
    assertFailClosed(result, staleReason(stale));
  });

  test("without --window-start a re-earn lifting a contrary event in evidence older than the bound fails closed", cli, () => {
    const contrary = { cell: "C2-auto-merge", event: "gate-failure", at: IN_EPOCH, discovered: IN_EPOCH };
    const stale = published(25, [contrary, { cell: "C2-auto-merge", event: "re-earned", at: "2026-10-20T00:00:00Z", since: IN_EPOCH }]);
    assertFailClosed(resolveWith({ ...BOUND, promotion_evidence_source: stale.path }), staleReason(stale));
  });
  test("a re-earn per cell whose since is the --window-start re-promotes every cell", cli, () => {
    const result = resolveWith({ ...BOUND, promotion_evidence_source: reearned("2026-10-11T07:00:00Z") }, { args: ["--window-start", "2026-10-11T07:00:00Z"] });
    assert.equal(result.failClosedReason, null);
    assert.deepEqual(effective(result), ALL("promoted"));
  });

  test("a re-earn whose since precedes the --window-start leaves every cell unpromoted", cli, () => {
    const result = resolveWith({ ...BOUND, promotion_evidence_source: reearned("2026-10-11T06:59:59Z") }, { args: ["--window-start", "2026-10-11T07:00:00Z"] });
    assert.equal(result.failClosedReason, null);
    assert.deepEqual(effective(result), ALL("unpromoted"));
  });
});

describe("forged value", () => {
  test("a lane-chosen checker or binding passed as an argument is a usage error", cli, () => {
    const printed = ["Effective promotion state (evaluation mode):", ...CELLS.map((c) => `- ${c}: bound promoted -> effective promoted`)];
    const stub = writeJson(`console.log(${JSON.stringify(printed.join("\n"))});\n`, "stub-checker.mjs");
    const contrary = events(...CELLS.map((cell) => ({ cell, event: "gate-failure", at: IN_EPOCH })));
    writeFileSync(userSettings, settingsFor(operatorOptions({ promotion_evidence_source: contrary })));
    assertFailClosed(runResolver({ args: ["--checker", stub] }), /^usage: .*checker/);
    assertFailClosed(runResolver({ args: ["--binding", PROMOTED_BINDING] }), /^usage: .*binding/);
  });

  const forged = operatorOptions();
  const channels = {
    "the CLAUDE_PLUGIN_OPTION_* env mirror": () => ({
      env: Object.fromEntries(Object.entries(forged).map(([key, value]) => [`CLAUDE_PLUGIN_OPTION_${key.toUpperCase()}`, value])),
    }),
    "the checkout's .claude/settings.json": () => {
      mkdirSync(join(checkout, ".claude"), { recursive: true });
      writeFileSync(join(checkout, ".claude", "settings.json"), settingsFor(forged));
      return { env: { CLAUDE_CONFIG_DIR: join(checkout, ".claude"), HOME: checkout } };
    },
    "the checkout's .claude/source-control.md": () => {
      mkdirSync(join(checkout, ".claude"), { recursive: true });
      writeFileSync(join(checkout, ".claude", "source-control.md"), `${Object.entries(forged).map(([k, v]) => `${k}: ${v}`).join("\n")}\n`);
      return {};
    },
    "the checkout's docs/conventions/source-control.yaml": () => {
      mkdirSync(join(checkout, "docs", "conventions"), { recursive: true });
      writeFileSync(
        join(checkout, "docs", "conventions", "source-control.yaml"),
        `${Object.entries(forged).map(([k, v]) => `${k}: ${JSON.stringify(v)}`).join("\n")}\n`,
      );
      return {};
    },
  };
  for (const [channel, plant] of Object.entries(channels)) {
    test(`values offered only by ${channel} read as unset`, cli, () => {
      rmSync(userSettings, { force: true });
      try {
        assertFailClosed(runResolver(plant()), /promotion_evidence_checker not set in managed or user settings/);
      } finally {
        rmSync(join(checkout, ".claude"), { recursive: true, force: true });
        rmSync(join(checkout, "docs"), { recursive: true, force: true });
      }
    });
  }

  const probe = join(ops, "probe");
  const outside = join(ops, "outside");
  mkdirSync(join(probe, "probe-transcripts"), { recursive: true });
  mkdirSync(outside);
  copyFileSync(join(FIXTURES, TRANSCRIPT_REF), join(probe, TRANSCRIPT_REF));
  copyFileSync(join(FIXTURES, TRANSCRIPT_REF), join(outside, "ci-pool-a-l2.json"));
  const bindingWithRef = (ref) => {
    const binding = JSON.parse(readFileSync(PROMOTED_BINDING, "utf8"));
    binding.isolation_bindings["ci-pool-a"].L2.probe_evidence = ref;
    return writeJson(binding);
  };

  test("control: the copied probe root alone still yields promoted", cli, () => {
    assert.deepEqual(effective(resolveWith({ promotion_evidence_root: probe })), ALL("promoted"));
  });

  for (const [shape, ref, finding] of [
    ["a '..' ref", "../outside/ci-pool-a-l2.json", /escapes --probe-evidence-root/],
    ["an absolute ref", join(outside, "ci-pool-a-l2.json"), /is an absolute path but --probe-evidence-root/],
  ]) {
    test(`a forged binding whose transcript sits outside the probe root (${shape}) fails closed`, cli, () => {
      const binding = bindingWithRef(ref);
      assertFailClosed(resolveWith({ promotion_evidence_binding: binding, promotion_evidence_root: probe }), /^checker exited 1/);
      assert.match(checkerStderr(binding, probe), finding);
    });
  }

  test("a transcript symlinked out of the probe root fails closed", cli, () => {
    const linked = join(ops, "probe-linked");
    mkdirSync(join(linked, "probe-transcripts"), { recursive: true });
    symlinkSync(join(outside, "ci-pool-a-l2.json"), join(linked, TRANSCRIPT_REF));
    assertFailClosed(resolveWith({ promotion_evidence_root: linked }), /^checker exited 1/);
    assert.match(checkerStderr(PROMOTED_BINDING, linked), /resolves through a link to a real path outside --probe-evidence-root/);
  });

  test("credential roots naming the filesystem root fail closed", cli, () => {
    assertFailClosed(resolveWith({ promotion_evidence_credential_roots: "/" }), /promotion_evidence_credential_roots entry "\/" names a filesystem root/);
  });
});

describe("missing value", () => {
  for (const key of ["promotion_evidence_binding", "promotion_evidence_root", "promotion_evidence_source", "promotion_evidence_checker"]) {
    test(`${key} unset fails closed naming it`, cli, () => {
      assertFailClosed(resolveWith({ [key]: undefined }), new RegExp(`^${key} not set in managed or user settings`));
    });
  }

  test("promotion_evidence_credential_roots unset leaves the filesystem credential probe unproven", cli, () => {
    const result = resolveWith({ promotion_evidence_credential_roots: undefined });
    assertFailClosed(result, /^checker exited 1/);
    assert.equal(result.options.promotion_evidence_credential_roots, undefined);
    assert.match(checkerStderr(PROMOTED_BINDING, FIXTURES, null), /"\$HOME\/\.netrc" — no --credential-roots configured/);
  });

  test("an events file that is not an array fails closed", cli, () => {
    const notArray = writeJson({ cell: "C2-auto-merge", event: "gate-failure", at: IN_EPOCH });
    assertFailClosed(resolveWith({ promotion_evidence_source: notArray }), /^checker line did not parse: - evidence source .* unavailable/);
    assertFailClosed(resolveWith({ promotion_evidence_source: notArray }, { args: ["--window-start", "2026-10-11T07:00:00Z"] }), /is not a JSON array/);
  });
});
