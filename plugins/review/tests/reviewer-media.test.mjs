// /review:reviewer-media: the decision (policy, request label, fork, draft, thresholds, the delta
// since posted media), the convention read from the base commit, and the completeness check.
import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const SCRIPTS = join(PLUGIN, "skills/reviewer-media/scripts");
const DECIDE = join(SCRIPTS, "decide.mjs");
const COMPLETENESS = join(SCRIPTS, "completeness.mjs");
const REPO = join(PLUGIN, "../..");

const { DEFAULTS, decide } = await import(pathToFileURL(DECIDE).href);
const { uncovered } = await import(pathToFileURL(COMPLETENESS).href);

const scratch = mkdtempSync(join(tmpdir(), "reviewer-media-test-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

const HEAD = "1".repeat(40);
const OLD = "2".repeat(40);
const REQUESTED = DEFAULTS.labels.requested;
const quiet = { isDraft: false, isCrossRepository: false, headRefOid: HEAD, body: "", labels: [], files: [{ path: "a.md", additions: 1, deletions: 0 }] };
const big = { ...quiet, files: Array.from({ length: 9 }, (_, i) => ({ path: `f${i}.md`, additions: 1, deletions: 0 })) };
const config = (overrides = {}) => ({ ...DEFAULTS, ...overrides });
// A stand-in for the review-digest thresholds: more than five files is "files".
const triggersOf = (facts) => (facts.files.length > 5 ? ["files"] : []);
const run = (facts, { policy, requested = false, shown = null, delta = null } = {}) =>
  decide(facts, { requested, shown, delta }, config(policy ? { policy } : {}), triggersOf);

describe("the decision", () => {
  test("never: skips, the request label and a direct request included", () => {
    assert.equal(run({ ...quiet, labels: [{ name: REQUESTED }] }, { policy: "never" }).action, "skip");
    assert.equal(run(quiet, { policy: "never", requested: true }).reason, "policy-never");
  });
  test("on-request: skips with no label, builds with it", () => {
    assert.equal(run(big).action, "skip");
    assert.equal(run(big).reason, "not-requested");
    assert.equal(run({ ...quiet, labels: [{ name: REQUESTED }] }).action, "build");
    assert.equal(run(quiet, { requested: true }).action, "build");
  });
  test("when-selected: under every threshold skips, over one builds", () => {
    assert.deepEqual([run(quiet, { policy: "when-selected" }).action, run(quiet, { policy: "when-selected" }).reason], ["skip", "under-thresholds"]);
    const over = run(big, { policy: "when-selected" });
    assert.deepEqual([over.action, over.triggers], ["build", ["files"]]);
  });
  test("always builds a ready pull request under every threshold", () => {
    assert.equal(run(quiet, { policy: "always" }).action, "build");
  });
  test("a draft gets no media unasked, and does when requested", () => {
    assert.equal(run({ ...big, isDraft: true }, { policy: "always" }).reason, "draft");
    assert.equal(run({ ...quiet, isDraft: true, labels: [{ name: REQUESTED }] }).action, "build");
  });
  test("a fork gets no media unasked, and does through the request label", () => {
    assert.equal(run({ ...big, isCrossRepository: true }, { policy: "always" }).reason, "fork");
    assert.equal(run({ ...quiet, isCrossRepository: true, labels: [{ name: REQUESTED }] }, { policy: "always" }).action, "build");
  });
  test("media already showing the head are not rebuilt", () => {
    const result = run({ ...big, labels: [{ name: REQUESTED }] }, { policy: "always", shown: HEAD });
    assert.deepEqual([result.action, result.reason], ["skip", "current"]);
  });
  test("a delta since posted media under every threshold gets the stale note only", () => {
    const result = run(quiet, { policy: "when-selected", shown: OLD, delta: { files: [{ path: "a.md", additions: 1, deletions: 0 }] } });
    assert.deepEqual([result.action, result.reason, result.shown], ["stale", "small-delta", OLD]);
  });
  test("a delta over a threshold rebuilds, measured on the delta, not the whole pull request", () => {
    const result = run(quiet, { policy: "when-selected", shown: OLD, delta: { files: big.files } });
    assert.deepEqual([result.action, result.reason, result.triggers], ["build", "rebuild", ["files"]]);
    const whole = run(big, { policy: "when-selected", shown: OLD, delta: { files: quiet.files } });
    assert.equal(whole.action, "stale");
  });
  test("the whole pull request's blast radius never rebuilds media for a small delta", () => {
    const { root, base } = repoWith(null);
    writeFileSync(join(root, "a.md"), "two\n");
    git(root, "commit", "-q", "-am", "small");
    const head = git(root, "rev-parse", "HEAD");
    const result = cli(root, { ...quiet, headRefOid: head, baseRefOid: base }, "--shown", base, "--policy", "when-selected", "--blast-radius", "HIGH");
    assert.deepEqual([result.action, result.reason], ["stale", "small-delta"]);
  });
  test("an unknown delta gets the stale note, never an unasked rebuild", () => {
    assert.equal(run(big, { policy: "always", shown: OLD }).reason, "delta-unknown");
  });
  test("a request label rebuilds stale media whatever the delta", () => {
    assert.equal(run({ ...quiet, labels: [{ name: REQUESTED }] }, { shown: OLD }).action, "build");
  });
  test("a request label turned off is never read", () => {
    const result = decide({ ...quiet, labels: [{ name: REQUESTED }] }, { requested: false, shown: null, delta: null }, config({ labels: { ...DEFAULTS.labels, requested: false } }), triggersOf);
    assert.equal(result.action, "skip");
  });
});

// ------------------------------------------------------------ the CLI and the base commit

const git = (cwd, ...args) => execFileSync("git", ["-C", cwd, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

function repoWith(teamYaml) {
  const root = mkdtempSync(join(scratch, "repo-"));
  git(root, "init", "-q", "-b", "main");
  git(root, "config", "user.email", "t@example.com");
  git(root, "config", "user.name", "t");
  mkdirSync(join(root, "docs/conventions"), { recursive: true });
  writeFileSync(join(root, "a.md"), "one\n");
  if (teamYaml !== null) writeFileSync(join(root, "docs/conventions/reviewer-media.yaml"), teamYaml);
  git(root, "add", "-A");
  git(root, "commit", "-q", "-m", "base");
  return { root, base: git(root, "rev-parse", "HEAD") };
}

function cli(root, facts, ...args) {
  const out = spawnSync(process.execPath, [DECIDE, ...args], {
    input: JSON.stringify(facts),
    encoding: "utf8",
    env: { ...process.env, CLAUDE_PROJECT_DIR: root, HOME: scratch },
  });
  assert.equal(out.status, 0, out.stderr);
  return JSON.parse(out.stdout);
}

describe("the convention layers", () => {
  test("the team file is read from the base commit, never the working tree", () => {
    const { root, base } = repoWith("policy: always\nupload_limit_mb: 100\n");
    writeFileSync(join(root, "docs/conventions/reviewer-media.yaml"), "policy: never\nupload_limit_mb: 5\n");
    const result = cli(root, { ...quiet, baseRefOid: base });
    assert.equal(result.config.policy.value, "always");
    assert.equal(result.config.upload_limit_mb.value, 100);
    assert.match(result.config.policy.source, new RegExp(`^team ${base}:`));
    assert.equal(result.action, "build");
  });
  test("no base commit: defaults, with a warning", () => {
    const { root } = repoWith("policy: always\n");
    const result = cli(root, { ...quiet, baseRefOid: "0".repeat(40) });
    assert.equal(result.config.policy.value, "on-request");
    assert.match(result.warnings.join("\n"), /not in this clone/);
  });
  test("an invalid team value falls to the default and is named", () => {
    const { root, base } = repoWith("artifact_retention_days: 400\n");
    const result = cli(root, { ...quiet, baseRefOid: base });
    assert.equal(result.config.artifact_retention_days.value, 30);
    assert.match(result.warnings.join("\n"), /artifact_retention_days/);
  });
  test("an untracked personal override refines the team file, but never sets a team-only key", () => {
    const { root, base } = repoWith("policy: on-request\nvoice_command: say {script} {out}\n");
    writeFileSync(join(root, "docs/conventions/reviewer-media.local.yaml"), "policy: always\nvoice_command: curl evil\nallow_unattended_paid_voice: true\n");
    const result = cli(root, { ...quiet, baseRefOid: base });
    assert.equal(result.config.policy.value, "always");
    assert.equal(result.config.voice_command.value, "say {script} {out}");
    assert.equal(result.config.allow_unattended_paid_voice.value, false);
  });
  test("scan.extra_patterns is add-only: the personal override adds to the team's list", () => {
    const { root, base } = repoWith("scan:\n  extra_patterns: ['\\bBLUEJAY\\b']\n");
    writeFileSync(join(root, "docs/conventions/reviewer-media.local.yaml"), "scan:\n  extra_patterns: ['ACME-\\d+', '\\bBLUEJAY\\b']\n");
    const result = cli(root, { ...quiet, baseRefOid: base });
    assert.deepEqual(result.config["scan.extra_patterns"].value, ["\\bBLUEJAY\\b", "ACME-\\d+"]);
    assert.match(result.config["scan.extra_patterns"].source, /^team .*\+ personal-override/);
  });
  test("scan.extra_patterns defaults to none", () => {
    const { root, base } = repoWith(null);
    assert.deepEqual(cli(root, { ...quiet, baseRefOid: base }).config["scan.extra_patterns"], { value: [], source: "default" });
  });
  test("a personal override a pull request commits is ignored", () => {
    const { root, base } = repoWith(null);
    writeFileSync(join(root, "docs/conventions/reviewer-media.local.yaml"), "policy: always\n");
    git(root, "add", "-A");
    git(root, "commit", "-q", "-m", "pr");
    const result = cli(root, { ...quiet, baseRefOid: base });
    assert.equal(result.config.policy.value, "on-request");
    assert.match(result.warnings.join("\n"), /tracked/);
  });
  test("--policy beats every layer", () => {
    const { root, base } = repoWith("policy: never\n");
    assert.equal(cli(root, { ...quiet, baseRefOid: base }, "--policy", "always").action, "build");
  });
  test("the delta since posted media is measured from git", () => {
    const { root, base } = repoWith(null);
    for (let i = 0; i < 9; i += 1) writeFileSync(join(root, `f${i}.md`), "x\n");
    git(root, "add", "-A");
    git(root, "commit", "-q", "-m", "more");
    const head = git(root, "rev-parse", "HEAD");
    const result = cli(root, { ...quiet, headRefOid: head, baseRefOid: base }, "--shown", base, "--policy", "when-selected");
    assert.deepEqual([result.action, result.reason], ["build", "rebuild"]);
  });
  test("the repository's own team file is valid and sets the upload limit", () => {
    const result = cli(REPO, { ...quiet, baseRefOid: git(REPO, "rev-parse", "HEAD") });
    assert.equal(result.warnings.filter((w) => w.includes("reviewer-media")).length, 0, result.warnings.join("\n"));
    assert.equal(result.config.upload_limit_mb.value, 100);
  });
});

describe("the completeness check", () => {
  const storyboard = { moments: [{ covers: ["a.md"] }, { covers: ["b.md"] }] };
  test("names each changed file no moment covers", () => {
    assert.deepEqual(uncovered(storyboard, [{ path: "a.md" }, { path: "b.md" }, { path: "c.md" }]), ["c.md"]);
    assert.deepEqual(uncovered(storyboard, [{ path: "a.md" }]), []);
  });
  test("the CLI exits 1 naming the uncovered file", () => {
    const dir = mkdtempSync(join(scratch, "complete-"));
    writeFileSync(join(dir, "storyboard.json"), JSON.stringify(storyboard));
    writeFileSync(join(dir, "facts.json"), JSON.stringify({ files: [{ path: "a.md" }, { path: "c.md" }] }));
    const out = spawnSync(process.execPath, [COMPLETENESS, "--storyboard", join(dir, "storyboard.json"), "--facts", join(dir, "facts.json")], { encoding: "utf8" });
    assert.equal(out.status, 1);
    assert.match(out.stdout, /c\.md/);
    writeFileSync(join(dir, "facts.json"), JSON.stringify({ files: [{ path: "a.md" }] }));
    assert.equal(spawnSync(process.execPath, [COMPLETENESS, "--storyboard", join(dir, "storyboard.json"), "--facts", join(dir, "facts.json")]).status, 0);
  });
});
