#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "./operator-options.mjs";
import { FULL, GATE, github, LANE, MECHANICAL, pr, REPO, shaOf, wfRun } from "./fixtures/publish-promotion-evidence/github-fake.mjs";
import { collect } from "./publish-promotion-evidence.mjs";
import { laneWritable } from "./resolve-promotion-evidence.mjs";

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
for (const name of ["resolve-promotion-evidence.mjs", "operator-options.mjs", "publish-promotion-evidence.mjs"]) copyFileSync(join(HERE, name), join(installScripts, name));
const HELPER = join(installScripts, "resolve-promotion-evidence.mjs");
const userSettings = join(config, "settings.json");

// The test seam: a wrapper beside the installed helper that runs its main() with an injected
// platform and owner test, so a case does not depend on who owns the temp files. A path listed in
// `owned` is the lane user's (uid 1000), everything else an administrator's (uid 0), and access()
// grants nothing.
let seamCount = 0;
// A path listed in `denied` throws EACCES from stat().
function seam({ platform = "linux", owned = [], denied = [] } = {}) {
  seamCount += 1;
  const path = join(installScripts, `seam-${seamCount}.mjs`);
  writeFileSync(
    path,
    `import { main } from "./resolve-promotion-evidence.mjs";
const owned = ${JSON.stringify(owned)};
const denied = ${JSON.stringify(denied)};
function stat(p) {
  if (denied.includes(p)) throw Object.assign(new Error("denied"), { code: "EACCES" });
  return { uid: owned.includes(p) ? 1000 : 0 };
}
main({ platform: ${JSON.stringify(platform)}, uid: 1000, access: () => false, stat });
`,
  );
  return path;
}
// Every surface and settings file administrator-owned, so the writability check passes.
const ADMIN = seam();

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

function runHelper({ args = {}, env = {}, helper = ADMIN } = {}) {
  const argv = Object.entries({ checkout, ...args }).flatMap(([key, value]) => [`--${key}`, value]);
  const injected = { NODE_PATH: checkout, LD_PRELOAD: checkout, GIT_DIR: checkout, CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_BINDING: checkout };
  const run = spawnSync(process.execPath, [helper, ...argv], {
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
const escapeRe = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

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
  const reason = (value, problem) => new RegExp(`promotion_evidence_credential_roots entry ${escapeRe(JSON.stringify(value))} ${problem}`);
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
  const run = spawnSync(process.execPath, [ADMIN, "--checkout", checkout, "--window-start"], { encoding: "utf8", cwd: checkout });
  assertFailClosed(JSON.parse(run.stdout), /usage: /);
});

// --- Inline mode: the publisher's GitHub reads fed straight to the checker ---

const FAKE = join(HERE, "fixtures", "publish-promotion-evidence", "github-fake.mjs");
const NOW = "2026-10-05T00:00:00Z";
const daysBefore = (at, days) => new Date(Date.parse(at) - days * 86_400_000).toISOString();

// A checker that demotes each cell some event in its --evidence names, so the verdict shows which
// events reached it, whether read from a file or from stdin.
const ECHO = join(ops, "echo-checker.mjs");
writeFileSync(
  ECHO,
  `import { readFileSync } from "node:fs";
const args = process.argv.slice(2);
const source = args[args.indexOf("--evidence") + 1];
const events = JSON.parse(readFileSync(source === "-" ? 0 : source, "utf8"));
const lines = ["Security binding OK", "Effective promotion state (evaluation mode):"];
for (const cell of ${JSON.stringify(CELLS)}) {
  const hits = events.filter((e) => e.cell === cell).map((e) => e.event + " at " + e.at);
  lines.push("- " + cell + ": bound promoted -> effective " + (hits.length ? "unpromoted (" + hits.join("; ") + ")" : "promoted"));
}
process.stdout.write(lines.join("\\n") + "\\n");
`,
);

function bindingFile(ratifiedAt, name = `binding-${++stubCount}.json`) {
  const path = join(ops, name);
  const promotion_state = Object.fromEntries(CELLS.map((cell) => [cell, ratifiedAt === undefined ? { state: "promoted" } : { state: "promoted", ratified_at: ratifiedAt }]));
  writeFileSync(path, JSON.stringify({ promotion_state }));
  return path;
}

// Runs inline mode from the install copy through a wrapper that injects the clock and
// the `gh` seam: the recorded GitHub over `fixture`, or a `gh api` that fails with `failWith`.
function runInline({ binding, fixture = {}, failWith = null, now = NOW, extra = [], ghRepo = REPO }) {
  seamCount += 1;
  const wrapper = join(installScripts, `inline-seam-${seamCount}.mjs`);
  writeFileSync(
    wrapper,
    `import { inline } from "./resolve-promotion-evidence.mjs";
import { github } from ${JSON.stringify(FAKE)};
import { ghFailure } from ${JSON.stringify(join(HERE, "publish-promotion-evidence.mjs"))};
const failWith = ${JSON.stringify(failWith)};
const gh = failWith === null ? github(${JSON.stringify(fixture)}) : (path, graphql) => ghFailure(path, graphql, "", failWith);
await inline({ argv: process.argv.slice(2), gh, now: Date.parse(${JSON.stringify(now)}) });
`,
  );
  const argv = ["--repo", REPO, "--binding", binding, "--checker", ECHO, "--probe-evidence-root", surfaces.root, "--lane-login", LANE, ...GATE.flatMap((g) => ["--gate-check", g]), ...extra];
  const run = spawnSync(process.execPath, [wrapper, ...argv], { encoding: "utf8", cwd: checkout, env: { ...process.env, GITHUB_REPOSITORY: ghRepo } });
  assert.equal(run.status, 0, run.stderr);
  return JSON.parse(run.stdout);
}

// One autonomous C2 merge, then a red scheduled full run on a later commit containing it: the
// publisher's post-merge gate counts that as a gate-failure on C2-auto-merge only.
const TIP = shaOf(0xa001);
const RED_C2 = {
  pulls: [pr(1301, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })],
  history: [shaOf(1301), TIP],
  workflowRuns: { [FULL]: [wfRun(1, "schedule", TIP, "2026-09-03T00:00:00Z", { conclusion: "failure" })] },
};

test("inline mode prints the verdict file mode prints for the publisher's events over the same recorded GitHub", cli, () => {
  const binding = bindingFile("2026-08-01T00:00:00Z");
  const evidenceFile = join(ops, "published.json");
  const published = collect({ repo: REPO, since: "2026-08-01T00:00:00Z", through: NOW, laneLogins: [LANE], gateChecks: GATE, gh: github(RED_C2) });
  writeFileSync(evidenceFile, JSON.stringify(published.events));
  const fileMode = runWith(ECHO, { promotion_evidence_binding: binding, promotion_evidence_source: evidenceFile });
  const inlineMode = runInline({ binding, fixture: RED_C2 });
  assert.equal(fileMode.failClosedReason, null);
  assert.equal(inlineMode.failClosedReason, null);
  assert.deepEqual(inlineMode.cells, fileMode.cells);
  assert.deepEqual(Object.fromEntries(CELLS.map((cell) => [cell, inlineMode.cells[cell].effective])), {
    "C2-auto-merge": "unpromoted",
    "C3-auto-merge": "promoted",
    "C3-ai-review-blocking": "promoted",
  });
  assert.equal(inlineMode.source, `github:${REPO}`);
});

test("inline mode reads GitHub when the promotion epoch started 84 days ago and refuses at 86", () => {
  const fresh = runInline({ binding: bindingFile(daysBefore(NOW, 84)) });
  assert.equal(fresh.failClosedReason, null);
  assert.equal(fresh.cells["C2-auto-merge"].effective, "promoted");
  // A GitHub that fails every read shows the guard refuses before any read.
  const stale = runInline({ binding: bindingFile(daysBefore(NOW, 86)), failWith: "HTTP 401: Bad credentials" });
  assertFailClosed(stale, /^epoch-start-expired: /);
});

test("inline mode refuses a binding with no promotion epoch start", () => {
  assertFailClosed(runInline({ binding: bindingFile(undefined), failWith: "HTTP 401: Bad credentials" }), /^epoch-start-missing: /);
  const none = join(ops, "binding-none.json");
  writeFileSync(none, JSON.stringify({ promotion_state: { "C2-auto-merge": { state: "unpromoted", ratified_at: NOW } } }));
  assertFailClosed(runInline({ binding: none, failWith: "HTTP 401: Bad credentials" }), /^epoch-start-missing: /);
});

test("inline mode refuses when a GitHub read fails", () => {
  const result = runInline({ binding: bindingFile(daysBefore(NOW, 10)), failWith: "HTTP 502: Bad Gateway" });
  assertFailClosed(result, /^github-read-failed: .*HTTP 502/);
});

test("inline mode from the CLI refuses when gh cannot run, and on a usage error", () => {
  const binding = bindingFile(new Date(Date.now() - 86_400_000).toISOString());
  const argv = ["--inline", "--repo", REPO, "--binding", binding, "--checker", ECHO, "--probe-evidence-root", surfaces.root, "--lane-login", LANE, "--gate-check", GATE[0]];
  const empty = mkdtempSync(join(base, "no-gh-"));
  const noGh = spawnSync(process.execPath, [HELPER, ...argv], { encoding: "utf8", cwd: checkout, env: { PATH: empty } });
  assert.equal(noGh.status, 0, noGh.stderr);
  assertFailClosed(JSON.parse(noGh.stdout), /^github-read-failed: /);
  const usage = spawnSync(process.execPath, [HELPER, "--inline", "--repo", REPO], { encoding: "utf8", cwd: checkout });
  assertFailClosed(JSON.parse(usage.stdout), /^usage: /);
});

test("inline mode refuses a --repo other than GITHUB_REPOSITORY", () => {
  const result = runInline({ binding: bindingFile(daysBefore(NOW, 10)), ghRepo: "melodic-software/other" });
  assertFailClosed(result, /^repo-mismatch: /);
});

test("inline mode fails closed with JSON when the publisher cannot be imported", () => {
  const lone = mkdtempSync(join(base, "no-publisher-"));
  for (const name of ["resolve-promotion-evidence.mjs", "operator-options.mjs"]) copyFileSync(join(HERE, name), join(lone, name));
  const binding = bindingFile(new Date(Date.now() - 86_400_000).toISOString());
  const argv = ["--inline", "--repo", REPO, "--binding", binding, "--checker", ECHO, "--probe-evidence-root", surfaces.root, "--lane-login", LANE, "--gate-check", GATE[0]];
  const run = spawnSync(process.execPath, [join(lone, "resolve-promotion-evidence.mjs"), ...argv], { encoding: "utf8", cwd: checkout, env: { PATH: process.env.PATH } });
  assert.equal(run.status, 0, run.stderr);
  assertFailClosed(JSON.parse(run.stdout), /^publisher-unavailable: /);
});

test("inline mode counts an in-epoch gate failure of a merge made just before the epoch", () => {
  // Merged an hour before ratification; the red full run containing it lands after.
  const epoch = "2026-09-01T00:00:00Z";
  const fixture = {
    pulls: [pr(1302, "2026-08-31T23:00:00Z", { labels: [MECHANICAL] })],
    history: [shaOf(1302), TIP],
    workflowRuns: { [FULL]: [wfRun(2, "schedule", TIP, "2026-09-01T01:00:00Z", { conclusion: "failure" })] },
  };
  const result = runInline({ binding: bindingFile(epoch), fixture });
  assert.equal(result.failClosedReason, null);
  assert.equal(result.cells["C2-auto-merge"].effective, "unpromoted");
  assert.match(result.cells["C2-auto-merge"].line, /gate-failure at 2026-09-01T01:08:00Z/);
});

test("inline --window-start demotes every cell at that instant", () => {
  const binding = bindingFile(daysBefore(NOW, 10));
  const restarted = runInline({ binding, extra: ["--window-start", daysBefore(NOW, 1).replace(".000Z", "Z")] });
  assert.equal(restarted.failClosedReason, null);
  for (const cell of CELLS) assert.equal(restarted.cells[cell].effective, "unpromoted");
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

// A failing read under an ephemeral base proves nothing about the host's credential store.
for (const base of [
  "/tmp",
  "/tmp/creds",
  "/var/tmp/creds",
  "/dev/shm",
  "/dev/shm/creds",
  "C:\\Temp",
  "C:\\TEMP\\creds",
  "C:\\Users\\runner\\AppData\\Local\\Temp\\creds",
]) {
  test(`credential root ${base} under an ephemeral base fails closed`, cli, () => {
    const checker = stub(GOOD_OUTPUT, 0, ops, ["--credential-roots", "unused"]);
    const result = runWith(checker, { promotion_evidence_credential_roots: `/home/runner,${base}` });
    const named = escapeRe(JSON.stringify(base));
    assertFailClosed(result, new RegExp(`promotion_evidence_credential_roots entry ${named} sits under an ephemeral base`));
  });
}

test("the real helper refuses a user-scope surface the test user owns", cli, () => {
  // No seam: every file this suite created is the test user's own, so the first surface the
  // helper judges, the checker, is lane-writable.
  assertFailClosed(runWith(stub(GOOD_OUTPUT), {}, { helper: HELPER }), /^lane-writable:promotion_evidence_checker$/);
});

test("a surface the lane user owns, or a directory above it, fails closed naming the option", cli, () => {
  const checker = stub(GOOD_OUTPUT);
  for (const [option, owned] of [
    ["promotion_evidence_checker", checker],
    ["promotion_evidence_checker", ops],
    ["promotion_evidence_binding", surfaces.binding],
    ["promotion_evidence_root", surfaces.root],
    ["promotion_evidence_source", surfaces.evidence],
  ]) {
    assertFailClosed(runWith(checker, {}, { helper: seam({ owned: [owned] }) }), new RegExp(`^lane-writable:${option}$`));
  }
});

test("a settings file the lane user owns, or a directory above it, fails closed naming the file", cli, () => {
  for (const owned of [userSettings, config]) {
    const result = runWith(stub(GOOD_OUTPUT), {}, { helper: seam({ owned: [owned] }) });
    assertFailClosed(result, new RegExp(`^lane-writable:${escapeRe(userSettings)}$`));
  }
});

test("on win32 the helper fails closed without judging any surface", cli, () => {
  // The checker is lane-owned, so a surface judged first would report lane-writable instead.
  const checker = stub(GOOD_OUTPUT);
  assertFailClosed(runWith(checker, {}, { helper: seam({ platform: "win32", owned: [checker] }) }), /^writability-unverifiable-on-win32$/);
});

test("a directory whose owner cannot be read fails closed as unverifiable", cli, () => {
  assertFailClosed(
    runWith(stub(GOOD_OUTPUT), {}, { helper: seam({ denied: [ops] }) }),
    /^writability-unverifiable:promotion_evidence_checker \(EACCES\)$/,
  );
});

test("administrator-owned surfaces and settings pass the writability check", cli, () => {
  const result = runWith(stub(GOOD_OUTPUT), {}, { helper: ADMIN });
  assert.equal(result.failClosedReason, null);
  assert.equal(result.cells["C2-auto-merge"].effective, "promoted");
});

// The rule babysit_merge_policy.py _lane_writable states: lane-writable when the lane can write,
// or owns, the path or any directory above it, as given or after symlinks resolve.
const ownedBy = (...dirs) => ({ uid: 1000, access: () => false, stat: (p) => ({ uid: dirs.includes(p) ? 1000 : 0 }) });

test("laneWritable: the path or any directory above it owned by the lane user", () => {
  assert.equal(laneWritable(surfaces.binding, ownedBy(base)), true);
  assert.equal(laneWritable(surfaces.binding, ownedBy(surfaces.binding)), true);
  assert.equal(laneWritable(surfaces.binding, ownedBy()), false);
});

test("laneWritable: a directory above the path the lane can write", () => {
  assert.equal(laneWritable(surfaces.binding, { ...ownedBy(), access: (p) => p === ops }), true);
});

test("laneWritable: a symlink resolving into a lane-owned directory", () => {
  const owned = mkdtempSync(join(base, "owned-"));
  writeFileSync(join(owned, "binding.json"), "{}");
  const link = join(ops, "binding-link.json");
  symlinkSync(join(owned, "binding.json"), link);
  assert.equal(laneWritable(link, ownedBy(owned)), true);
  assert.equal(laneWritable(link, ownedBy()), false);
});

test("laneWritable: a '..' path judges the directories it names as given", () => {
  // Python's Path.absolute() keeps "..", so _lane_writable walks <owned>/.. and <owned>; a
  // normalized or resolved walk never visits <owned>.
  const owned = mkdtempSync(join(base, "dotdot-"));
  const path = `${owned}/../ops/binding.json`;
  assert.equal(laneWritable(path, ownedBy(owned)), true);
  assert.equal(laneWritable(path, ownedBy()), false);
});

test("laneWritable: a missing path throws", () => {
  assert.throws(() => laneWritable(join(ops, "absent.json"), ownedBy()), { code: "ENOENT" });
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
