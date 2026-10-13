#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "./operator-options.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CELLS = ["C2-auto-merge", "C3-auto-merge", "C3-ai-review-blocking"];

const base = realpathSync.native(mkdtempSync(join(tmpdir(), "resolve-promotion-evidence-")));
after(() => rmSync(base, { recursive: true, force: true }));
const checkout = join(base, "checkout");
const ops = join(base, "ops");
mkdirSync(checkout);
mkdirSync(join(ops, "probe"), { recursive: true });
const surfaces = { binding: join(ops, "binding.json"), evidence: join(ops, "evidence.json"), root: join(ops, "probe") };
writeFileSync(surfaces.binding, "{}");
writeFileSync(surfaces.evidence, "[]");

// The helper runs from a copy laid out as a marketplace install, so it finds its user
// settings at <config>/settings.json the way an installed plugin does.
const config = join(base, "config");
const installScripts = join(config, "plugins", "cache", "mkt", "source-control", "9.9.9", "skills", "babysit-loop", "scripts");
mkdirSync(installScripts, { recursive: true });
for (const name of ["resolve-promotion-evidence.mjs", "operator-options.mjs"]) copyFileSync(join(HERE, name), join(installScripts, name));
const HELPER = join(installScripts, "resolve-promotion-evidence.mjs");
const userSettings = join(config, "settings.json");

// The CLI cases read the host's real managed settings; one that configures these options would
// decide the result, so they skip on such a host.
const managedConfigures = managedSettingsFiles().some((file) => {
  try {
    return readFileSync(file, "utf8").includes("promotion_evidence_");
  } catch {
    return false;
  }
});
const cli = { skip: managedConfigures && "host managed settings configure promotion_evidence_* options" };

let stubCount = 0;
// A stub checker that exits 9 unless it got exactly the bootstrap argv, plus `extra`.
function stub(stdout, exitCode = 0, dir = ops, extra = []) {
  stubCount += 1;
  const path = join(dir, `checker-${stubCount}.mjs`);
  const expected = [surfaces.binding, "--evidence", surfaces.evidence, "--probe-evidence-root", surfaces.root, ...extra];
  writeFileSync(
    path,
    `if (JSON.stringify(process.argv.slice(2)) !== ${JSON.stringify(JSON.stringify(expected))}) process.exit(9);
if (["NODE_PATH", "LD_PRELOAD", "GIT_DIR", "CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_BINDING"].some((key) => key in process.env)) process.exit(8);
process.stdout.write(${JSON.stringify(stdout)});
process.exit(${exitCode});
`,
  );
  return path;
}

function writeSettings(options, file = userSettings, id = "source-control@mkt") {
  writeFileSync(file, JSON.stringify({ pluginConfigs: { [id]: { options } } }));
}

function operatorOptions(checker, overrides = {}) {
  return {
    promotion_evidence_binding: surfaces.binding,
    promotion_evidence_root: surfaces.root,
    promotion_evidence_source: surfaces.evidence,
    promotion_evidence_checker: checker,
    ...overrides,
  };
}

function runHelper({ args = {}, env = {} } = {}) {
  const argv = Object.entries({ checkout, ...args }).flatMap(([key, value]) => [`--${key}`, value]);
  const injected = { NODE_PATH: checkout, LD_PRELOAD: checkout, GIT_DIR: checkout, CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_BINDING: checkout };
  const run = spawnSync(process.execPath, [HELPER, ...argv], {
    encoding: "utf8",
    cwd: checkout,
    env: { ...process.env, ...injected, ...env },
  });
  assert.equal(run.status, 0, run.stderr);
  return JSON.parse(run.stdout);
}

// Configures the operator's user settings, then runs the helper.
function runWith(checker, overrides = {}, run = {}) {
  writeSettings(operatorOptions(checker, overrides));
  return runHelper(run);
}

function assertFailClosed(result, reasonPattern) {
  assert.match(result.failClosedReason, reasonPattern);
  for (const cell of CELLS) assert.deepEqual(result.cells[cell], { bound: null, effective: "unpromoted", line: null });
}

const GOOD_OUTPUT = [
  "Security binding OK: binding.json",
  "- some verdict",
  "Effective promotion state (evaluation mode):",
  "- C2-auto-merge: bound promoted -> effective promoted",
  "- C3-auto-merge: bound unpromoted -> effective unpromoted",
  "",
].join("\n");

test("operator settings bootstrap reports the printed cells and leaves an unprinted cell unpromoted", cli, () => {
  const result = runWith(stub(GOOD_OUTPUT));
  assert.equal(result.failClosedReason, null);
  assert.equal(result.source, surfaces.evidence);
  assert.deepEqual(result.options.promotion_evidence_binding, { value: surfaces.binding, scope: "user", file: userSettings });
  assert.deepEqual(result.cells["C2-auto-merge"], {
    bound: "promoted",
    effective: "promoted",
    line: "C2-auto-merge: bound promoted -> effective promoted",
  });
  assert.equal(result.cells["C3-auto-merge"].effective, "unpromoted");
  assert.deepEqual(result.cells["C3-ai-review-blocking"], { bound: null, effective: "unpromoted", line: null });
  // Unset credential roots are not a fail-closed reason: the exact-argv stub saw no flag.
  assert.equal(result.options.promotion_evidence_credential_roots, undefined);
});

const ROOTS = "/home/runner, C:\\Users\\runner\\.aws,/nonexistent-probe-host/creds";

test("set credential roots reach the checker as --credential-roots and are reported in options", cli, () => {
  // The roots name the probe host, so a path absent on this host is still accepted.
  const checker = stub(GOOD_OUTPUT, 0, ops, ["--credential-roots", ROOTS]);
  const result = runWith(checker, { promotion_evidence_credential_roots: ROOTS });
  assert.equal(result.failClosedReason, null);
  assert.equal(result.cells["C2-auto-merge"].effective, "promoted");
  assert.deepEqual(result.options.promotion_evidence_credential_roots, { value: ROOTS, scope: "user", file: userSettings });
});

test("a relative, root, dot-dot, empty or checkout-inside credential root fails closed", cli, () => {
  const checker = stub(GOOD_OUTPUT, 0, ops, ["--credential-roots", "unused"]);
  const worktrees = join(ops, "worktrees");
  const reason = (value, problem) => new RegExp(`promotion_evidence_credential_roots entry ${RegExp.escape(JSON.stringify(value))} ${problem}`);
  const cases = [
    ["home/runner", reason("home/runner", "is not an absolute path")],
    ["//server/share", reason("//server/share", "is not an absolute path")],
    ["/", reason("/", "names a filesystem root")],
    ["/home/runner,C:\\", reason("C:\\", "names a filesystem root")],
    ["/home/runner/../../etc", reason("/home/runner/../../etc", "has a '\\.\\.' segment")],
    ["/home/runner,,/run/secrets", /promotion_evidence_credential_roots has an empty entry/],
    [`/home/runner,${join(checkout, "creds")}`, reason(join(checkout, "creds"), "is inside .*checkout")],
    [checkout, reason(checkout, "is inside .*checkout")],
    [join(worktrees, "w1", ".aws"), reason(join(worktrees, "w1", ".aws"), "is inside .*worktrees")],
  ];
  for (const [value, pattern] of cases) {
    const result = runWith(checker, { promotion_evidence_credential_roots: value }, { args: { "worktree-root": worktrees } });
    assertFailClosed(result, pattern);
  }
});

test("a lane-chosen stub checker or forged binding outside the checkout no longer yields promoted", cli, () => {
  // The operator's checker reports nothing promoted; the lane's stub, kept in a scratch
  // directory outside the checkout and worktrees, would print promoted.
  const operatorChecker = stub(GOOD_OUTPUT.replace("bound promoted -> effective promoted", "bound promoted -> effective unpromoted"));
  writeSettings(operatorOptions(operatorChecker));
  const scratch = mkdtempSync(join(tmpdir(), "lane-scratch-"));
  try {
    const forged = stub(GOOD_OUTPUT, 0, scratch);
    const forgedBinding = join(scratch, "binding.json");
    writeFileSync(forgedBinding, "{}");
    assertFailClosed(runHelper({ args: { checker: forged } }), /usage: .*checker/);
    assertFailClosed(runHelper({ args: { binding: forgedBinding } }), /usage: .*binding/);
    const viaEnv = runHelper({
      env: { CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_CHECKER: forged, CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_BINDING: forgedBinding },
    });
    assert.equal(viaEnv.failClosedReason, null);
    assert.equal(viaEnv.cells["C2-auto-merge"].effective, "unpromoted");
    assert.equal(viaEnv.options.promotion_evidence_checker.value, operatorChecker);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});

test("values offered only by the env mirror, the checkout, or another plugin's entry read as unset", cli, () => {
  const checker = stub(GOOD_OUTPUT);
  writeSettings(operatorOptions(checker), userSettings, "source-control@other-mkt");
  mkdirSync(join(checkout, ".claude"), { recursive: true });
  writeFileSync(join(checkout, ".claude", "settings.json"), JSON.stringify({ pluginConfigs: { "source-control@mkt": { options: operatorOptions(checker) } } }));
  writeFileSync(join(checkout, ".claude", "source-control.md"), `promotion_evidence_checker: ${checker}\n`);
  const result = runHelper({ env: { CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_CHECKER: checker, CLAUDE_CONFIG_DIR: join(checkout, ".claude"), HOME: checkout } });
  assertFailClosed(result, /promotion_evidence_checker not set in managed or user settings/);
  rmSync(join(checkout, ".claude"), { recursive: true, force: true });
});

// A stub checker that records the evidence file it was handed, then prints `stdout`.
function recordingStub(stdout, record) {
  stubCount += 1;
  const path = join(ops, `checker-${stubCount}.mjs`);
  writeFileSync(
    path,
    `import { readFileSync, writeFileSync } from "node:fs";
const [binding, flag, evidence, rootFlag, root] = process.argv.slice(2);
if (binding !== ${JSON.stringify(surfaces.binding)} || flag !== "--evidence" || rootFlag !== "--probe-evidence-root" || root !== ${JSON.stringify(surfaces.root)}) process.exit(9);
writeFileSync(${JSON.stringify(record)}, JSON.stringify({ evidence, events: JSON.parse(readFileSync(evidence, "utf8")) }));
process.stdout.write(${JSON.stringify(stdout)});
`,
  );
  return path;
}

test("--window-start hands the checker a copy with one gate-failure per cell at that instant", cli, () => {
  const record = join(ops, "record.json");
  const prior = { cell: "C2-auto-merge", event: "reverted-merge", at: "2026-10-01T00:00:00Z" };
  writeFileSync(surfaces.evidence, JSON.stringify([prior]));
  try {
    const result = runWith(recordingStub(GOOD_OUTPUT, record), {}, { args: { "window-start": "2026-10-11T07:00:00Z" } });
    assert.equal(result.failClosedReason, null);
    const seen = JSON.parse(readFileSync(record, "utf8"));
    assert.notEqual(seen.evidence, surfaces.evidence);
    assert.deepEqual(seen.events, [prior, ...CELLS.map((cell) => ({ cell, event: "gate-failure", at: "2026-10-11T07:00:00Z" }))]);
    // The copy is gone once the helper exits, and the source is untouched.
    assert.throws(() => readFileSync(seen.evidence));
    assert.deepEqual(JSON.parse(readFileSync(surfaces.evidence, "utf8")), [prior]);
  } finally {
    writeFileSync(surfaces.evidence, "[]");
  }
});

test("a missing, empty or malformed --window-start fails closed", cli, () => {
  const checker = recordingStub(GOOD_OUTPUT, join(ops, "unused.json"));
  for (const bad of ["", "2026-10-11", "2026-10-11T07:00:00", "2026-02-30T07:00:00Z", "2026-10-11T07:00:00.123456Z"]) {
    assertFailClosed(runWith(checker, {}, { args: { "window-start": bad } }), /--window-start .* is not an ISO 8601/);
  }
  writeSettings(operatorOptions(checker));
  const run = spawnSync(process.execPath, [HELPER, "--checkout", checkout, "--window-start"], { encoding: "utf8", cwd: checkout });
  assertFailClosed(JSON.parse(run.stdout), /usage: /);
});

test("--window-start over an unreadable or non-array source fails closed", cli, () => {
  const checker = recordingStub(GOOD_OUTPUT, join(ops, "unused.json"));
  const args = { args: { "window-start": "2026-10-11T07:00:00Z" } };
  try {
    writeFileSync(surfaces.evidence, "{ not json");
    assertFailClosed(runWith(checker, {}, args), /promotion_evidence_source .* cannot be read as JSON/);
    writeFileSync(surfaces.evidence, "{}");
    assertFailClosed(runWith(checker, {}, args), /promotion_evidence_source .* is not a JSON array/);
  } finally {
    writeFileSync(surfaces.evidence, "[]");
  }
});

test("checker exiting 1 fails closed", cli, () => {
  assertFailClosed(runWith(stub(GOOD_OUTPUT, 1)), /checker exited 1/);
});

test("relative path fails closed", cli, () => {
  assertFailClosed(runWith(stub(GOOD_OUTPUT), { promotion_evidence_binding: "ops/binding.json" }), /promotion_evidence_binding .* not an absolute path/);
});

test("a non-string option or an unparsable settings file fails closed", cli, () => {
  assertFailClosed(runWith(stub(GOOD_OUTPUT), { promotion_evidence_root: 7 }), /promotion_evidence_root in .* is not a string/);
  writeFileSync(userSettings, "{ not json");
  assertFailClosed(runHelper(), /not valid JSON/);
});

test("bootstrap path inside the checkout fails closed", cli, () => {
  const inside = join(checkout, "evidence.json");
  writeFileSync(inside, "[]");
  assertFailClosed(runWith(stub(GOOD_OUTPUT), { promotion_evidence_source: inside }), /promotion_evidence_source .* is inside/);
  rmSync(inside);
});

test("probe root that contains the checkout, a worktree root, or links to an ancestor fails closed", cli, () => {
  const checker = stub(GOOD_OUTPUT);
  assertFailClosed(runWith(checker, { promotion_evidence_root: base }), /promotion_evidence_root .* contains .*checkout/);
  assertFailClosed(
    runWith(checker, {}, { args: { "worktree-root": join(surfaces.root, "worktrees") } }),
    /promotion_evidence_root .* contains .*worktrees/,
  );
  const link = join(ops, "link-to-base");
  symlinkSync(base, link);
  assertFailClosed(runWith(checker, { promotion_evidence_root: link }), /promotion_evidence_root .* contains/);
});

test("a nonexistent worktree root under a symlinked parent still bounds the probe root", cli, () => {
  const link = join(ops, "link-to-probe");
  symlinkSync(surfaces.root, link);
  assertFailClosed(
    runWith(stub(GOOD_OUTPUT), {}, { args: { "worktree-root": join(link, "not-yet", "worktrees") } }),
    /promotion_evidence_root .* contains .*worktrees/,
  );
});

test("checker inside the checkout fails closed", cli, () => {
  assertFailClosed(runWith(stub(GOOD_OUTPUT, 0, checkout)), /promotion_evidence_checker .* is inside/);
});

test("missing binding file fails closed", cli, () => {
  assertFailClosed(runWith(stub(GOOD_OUTPUT), { promotion_evidence_binding: join(ops, "absent.json") }), /promotion_evidence_binding .* cannot be resolved/);
});

test("garbled checker output fails closed", cli, () => {
  const garbled = GOOD_OUTPUT.replace("effective promoted", "effective maybe");
  assertFailClosed(runWith(stub(garbled)), /did not parse/);
  assertFailClosed(runWith(stub("Security binding OK: binding.json\n")), /no 'Effective promotion state' block/);
});

test("resolveInstall anchors only the plugins/cache/<marketplace>/<name>/<version> layout", () => {
  assert.deepEqual(resolveInstall("/home/u/.claude/plugins/cache/mkt/source-control/1.2.3"), {
    pluginId: "source-control@mkt",
    name: "source-control",
    userSettings: join("/home/u/.claude", "settings.json"),
  });
  assert.equal(resolveInstall("C:\\Users\\u\\.claude\\plugins\\cache\\mkt\\source-control\\1.2.3").pluginId, "source-control@mkt");
  const checkoutInstall = resolveInstall(join(HERE, "..", "..", ".."));
  assert.deepEqual(checkoutInstall, { pluginId: null, name: "source-control", userSettings: null });
});

test("managed settings win over user settings, later managed files over earlier ones", () => {
  const dir = mkdtempSync(join(base, "scopes-"));
  const user = join(dir, "user.json");
  const primary = join(dir, "managed-settings.json");
  const dropin = join(dir, "10-dropin.json");
  writeSettings({ promotion_evidence_checker: "/user/checker", promotion_evidence_root: "/user/root" }, user);
  writeSettings({ promotion_evidence_checker: "/managed/checker", promotion_evidence_binding: "/managed/binding" }, primary);
  writeSettings({ promotion_evidence_binding: "/dropin/binding" }, dropin);
  const install = { pluginId: "source-control@mkt", name: "source-control", userSettings: user };
  const resolved = readOperatorOptions(install, [primary, dropin, join(dir, "absent.json")]);
  assert.deepEqual(resolved.promotion_evidence_checker, { value: "/managed/checker", scope: "managed", file: primary });
  assert.deepEqual(resolved.promotion_evidence_binding, { value: "/dropin/binding", scope: "managed", file: dropin });
  assert.deepEqual(resolved.promotion_evidence_root, { value: "/user/root", scope: "user", file: user });
  assert.equal(resolved.promotion_evidence_source, undefined);
});

test("a malformed managed entry or a null managed value fails closed instead of letting user settings win", () => {
  const dir = mkdtempSync(join(base, "malformed-"));
  const user = join(dir, "user.json");
  const managed = join(dir, "managed-settings.json");
  writeSettings(operatorOptions("/user/checker"), user);
  const install = { pluginId: "source-control@mkt", name: "source-control", userSettings: user };
  for (const entry of [{ options: "oops" }, { options: [] }, "oops", { options: { promotion_evidence_checker: null } }]) {
    writeFileSync(managed, JSON.stringify({ pluginConfigs: { "source-control@mkt": entry } }));
    assert.throws(() => readOperatorOptions(install, [managed]), OptionsError, JSON.stringify(entry));
  }
  for (const pluginConfigs of ["oops", [], null]) {
    writeFileSync(managed, JSON.stringify({ pluginConfigs }));
    assert.throws(() => readOperatorOptions(install, [managed]), OptionsError, JSON.stringify(pluginConfigs));
  }
  writeFileSync(managed, JSON.stringify({ pluginConfigs: { "source-control@mkt": {} } }));
  assert.equal(readOperatorOptions(install, [managed]).promotion_evidence_checker.value, "/user/checker");
  writeFileSync(managed, JSON.stringify({}));
  assert.equal(readOperatorOptions(install, [managed]).promotion_evidence_checker.value, "/user/checker");
});

test("an unanchored install reads managed settings by manifest name and no user settings", () => {
  const dir = mkdtempSync(join(base, "unanchored-"));
  const managed = join(dir, "managed-settings.json");
  writeSettings({ promotion_evidence_checker: "/managed/checker" }, managed, "source-control@any-mkt");
  const resolved = readOperatorOptions({ pluginId: null, name: "source-control", userSettings: null }, [managed]);
  assert.equal(resolved.promotion_evidence_checker.value, "/managed/checker");
  assert.throws(() => readOperatorOptions({ pluginId: null, name: "source-control", userSettings: null }, [dir]), OptionsError);
});

test("managedSettingsFiles names the fixed system path and nothing on an unknown platform", () => {
  assert.deepEqual(managedSettingsFiles("aix"), []);
  assert.equal(managedSettingsFiles("linux")[0], join("/etc/claude-code", "managed-settings.json"));
});
