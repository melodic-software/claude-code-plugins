import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { globMatch } from "./check.mjs";
process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const script = join(fileURLToPath(new URL(".", import.meta.url)), "check.mjs");
const temps = [];
test.after(() => {
  for (const dir of temps) rmSync(dir, { recursive: true, force: true });
});

const git = (dir, ...args) => {
  const r = spawnSync("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", "-c", "maintenance.auto=false", "-c", "gc.auto=0", ...args], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
};

const write = (root, rel, body) => {
  mkdirSync(join(root, rel, ".."), { recursive: true });
  writeFileSync(join(root, rel), body);
};

const RUN = "/formal-verification:chart .claude/skills/formal-lock/model/Lock.tla";

const skillBody = ({ name = "formal-lock", drop = [], run = RUN, head = true, description = true, swap = null } = {}) => {
  const desc = description ? 'description: "Lock model. Use when src/lock.js changes."\n' : "";
  const fm = head ? `---\nname: ${name}\n${desc}---\n\n` : "";
  const parts = [
    ["Property", "Only one holder: `src/lock.js`: \"if (held) return false\"."],
    ["Harm", "Two writers corrupt the file."],
    ["Tool and why", "A model checker: the question is an ordering."],
    ["Bounds and assumptions", "Two clients."],
    ["Not covered", "Crashes."],
    ["Run", `\`\`\`text\n${run}\n\`\`\``],
    ["Reading a result", "Replay each step."],
    ["Updating", "Move the commit after confirming."],
  ].filter(([s]) => !drop.includes(s));
  if (swap) {
    const [a, b] = swap.map((s) => parts.findIndex(([n]) => n === s));
    [parts[a], parts[b]] = [parts[b], parts[a]];
  }
  return `${fm}# Formal check: lock\n\n${parts.map(([s, b]) => `## ${s}\n\n${b}\n`).join("\n")}`;
};

const syncYaml = (commit, { covers = ["src/lock.js"], extra = "", command = RUN, seeded = commit } = {}) =>
  `checks:\n  - id: one-holder\n    covers:\n${covers.map((c) => `      - ${c}\n`).join("")}    commit: ${commit}\n    command: ${command}\n    seeded_break:\n      change: the held check removed\n      caught: true\n      commit: ${seeded}\n${extra}outside_model: []\n`;

const repo = ({ skill = {}, sync = {}, conventions } = {}) => {
  const root = mkdtempSync(join(tmpdir(), "fv-check-"));
  temps.push(root);
  git(root, "init", "-q", "-b", "main");
  write(root, "src/lock.js", "export const take = (held) => !held;\n");
  write(root, "src/util/a.js", "export const a = 1;\n");
  git(root, "add", "-A");
  git(root, "commit", "-q", "-m", "code");
  const commit = git(root, "rev-parse", "HEAD");
  if (skill !== null) write(root, ".claude/skills/formal-lock/SKILL.md", skillBody(skill));
  if (sync !== null) write(root, ".claude/skills/formal-lock/sync.yaml", typeof sync === "string" ? sync : syncYaml(sync.commit ?? commit, sync));
  if (skill !== null) write(root, ".claude/skills/formal-lock/model/Lock.tla", "---- MODULE Lock ----\n====\n");
  if (conventions) write(root, "docs/conventions/formal-verification.yaml", conventions);
  git(root, "add", "-A");
  git(root, "commit", "-q", "--allow-empty", "-m", "skill");
  return { root, commit };
};

const checkWith = (env, root, ...args) => {
  const r = spawnSync(process.execPath, [script, "--project-dir", root, ...args], { encoding: "utf8", env: { ...process.env, ...env }, timeout: 20000 });
  return { code: r.status, out: r.stdout, fails: r.stdout.split("\n").filter((l) => l.startsWith("FAIL ")), warns: r.stdout.split("\n").filter((l) => l.startsWith("WARN ")) };
};
const check = (root, ...args) => checkWith({}, root, ...args);

test("a formal-area skill that meets the contract passes with no failure and no warning", () => {
  const r = check(repo().root);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.fails, []);
  assert.deepEqual(r.warns, []);
  assert.match(r.out, /1 formal-<area> skill\(s\), 0 failure\(s\), 0 warning\(s\)/);
});

test("SKILL.md without frontmatter fails", () => {
  const r = check(repo({ skill: { head: false } }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /^FAIL "formal-lock": frontmatter: missing/m);
});

test("frontmatter whose name is not the folder's name fails", () => {
  const r = check(repo({ skill: { name: "lock" } }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /frontmatter: name/);
});

for (const section of ["Harm", "Not covered", "Reading a result"]) {
  test(`a missing ## ${section} section fails`, () => {
    const r = check(repo({ skill: { drop: [section] } }).root);
    assert.equal(r.code, 1, r.out);
    assert.deepEqual(r.fails, [`FAIL "formal-lock": section: ## ${section} missing`]);
  });
}

test("a missing sync.yaml fails", () => {
  const r = check(repo({ sync: null }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /sync\.yaml: missing/);
});

test("a sync.yaml that does not parse fails", () => {
  const r = check(repo({ sync: "checks:\n  - id: [unclosed\n" }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /sync\.yaml: not valid/);
});

test("a sync.yaml entry without seeded_break fails", () => {
  const { root, commit } = repo();
  write(root, ".claude/skills/formal-lock/sync.yaml", `checks:\n  - id: one-holder\n    covers: [src/lock.js]\n    commit: ${commit}\n    command: ${RUN}\n`);
  git(root, "commit", "-q", "-am", "drop the break");
  const r = check(root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /seeded_break: missing/);
});

test("a sync.yaml commit that is not a full commit id fails", () => {
  const r = check(repo({ sync: { commit: "abc123" } }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /commit: must be a full commit id/);
});

test("an entry whose command ## Run does not give fails as no run command", () => {
  const r = check(repo({ skill: { run: "see the model folder" } }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /no run command/);
});

test("a sync commit that is not an ancestor of HEAD fails", () => {
  const { root } = repo();
  git(root, "checkout", "-q", "-b", "side", "HEAD~1");
  write(root, "src/side.js", "1\n");
  git(root, "add", "-A");
  git(root, "commit", "-q", "-m", "side");
  const side = git(root, "rev-parse", "HEAD");
  git(root, "checkout", "-q", "main");
  write(root, ".claude/skills/formal-lock/sync.yaml", syncYaml(side));
  git(root, "commit", "-q", "-am", "point at the side branch");
  const r = check(root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /is not an ancestor of HEAD/);
});

const branchOnly = () => {
  const made = repo();
  git(made.root, "checkout", "-q", "-b", "feature");
  write(made.root, "src/feature.js", "1\n");
  git(made.root, "add", "-A");
  git(made.root, "commit", "-q", "-m", "feature work");
  return { ...made, feature: git(made.root, "rev-parse", "HEAD") };
};

test("with --default-ref, sync and seeded-break commits on the default branch pass", () => {
  const r = check(branchOnly().root, "--default-ref", "main");
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.fails, []);
  assert.deepEqual(r.warns, []);
});

test("with --default-ref, a sync commit only on the feature branch fails", () => {
  const { root, feature } = branchOnly();
  write(root, ".claude/skills/formal-lock/sync.yaml", syncYaml(feature));
  git(root, "commit", "-q", "-am", "sync at the feature commit");
  const r = check(root, "--default-ref", "main");
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /sync commit [0-9a-f]{40} is not on the default branch "main"; a squash or rebase merge will discard it/);
  assert.ok(!/is not an ancestor of HEAD/.test(r.out), r.out);
});

test("with --default-ref, a seeded-break commit only on the feature branch fails", () => {
  const { root, commit, feature } = branchOnly();
  write(root, ".claude/skills/formal-lock/sync.yaml", syncYaml(commit, { seeded: feature }));
  git(root, "commit", "-q", "-am", "break at the feature commit");
  const r = check(root, "--default-ref", "main");
  assert.equal(r.code, 1, r.out);
  assert.deepEqual(r.fails, [`FAIL "formal-lock": check "one-holder": seeded-break commit ${feature} is not on the default branch "main"; a squash or rebase merge will discard it`]);
});

test("without --default-ref, a feature-branch sync commit still passes", () => {
  const { root, feature } = branchOnly();
  write(root, ".claude/skills/formal-lock/sync.yaml", syncYaml(feature));
  git(root, "commit", "-q", "-am", "sync at the feature commit");
  assert.equal(check(root).code, 0);
});

test("a --default-ref that does not resolve warns once and skips the check", () => {
  const { root, feature } = branchOnly();
  write(root, ".claude/skills/formal-lock/sync.yaml", syncYaml(feature));
  git(root, "commit", "-q", "-am", "sync at the feature commit");
  const r = check(root, "--default-ref", "refs/remotes/origin/nope");
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.warns, ['WARN "default-ref": "refs/remotes/origin/nope" does not resolve to a commit here; the default-branch check is skipped']);
});

test("a covered file missing at HEAD fails, and a glob that matches no file fails", () => {
  const r = check(repo({ sync: { covers: ["src/lock.js", "src/gone.js", "lib/**/*.js"] } }).root);
  assert.equal(r.code, 1, r.out);
  assert.deepEqual(r.fails, [
    'FAIL "formal-lock": check "one-holder": covered path "src/gone.js" is missing at HEAD',
    'FAIL "formal-lock": check "one-holder": covered path "lib/**/*.js" is missing at HEAD',
  ]);
});

test("a covered folder and a glob that match files at HEAD pass", () => {
  const r = check(repo({ sync: { covers: ["src/util", "src/**/*.js"] } }).root);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.fails, []);
});

const staleRepo = (opts) => {
  const made = repo(opts);
  write(made.root, "src/lock.js", "export const take = () => true;\n");
  write(made.root, "src/other.js", "1\n");
  git(made.root, "add", "-A");
  git(made.root, "commit", "-q", "-m", "change the lock");
  return made;
};

test("covered code changed since the sync commit warns by default and still passes", () => {
  const r = check(staleRepo().root);
  assert.equal(r.code, 0, r.out);
  assert.equal(r.warns.length, 1, r.out);
  assert.match(r.warns[0], /^WARN "formal-lock": check "one-holder": covered code changed since sync commit [0-9a-f]{12}: "src\/lock\.js"; run \/formal-verification:specify refresh$/);
});

test("a change outside every covered path draws no refresh line", () => {
  const made = repo();
  write(made.root, "src/other.js", "1\n");
  git(made.root, "add", "-A");
  git(made.root, "commit", "-q", "-m", "uncovered change");
  const r = check(made.root);
  assert.equal(r.code, 0, r.out);
  assert.ok(!/refresh/.test(r.out), r.out);
});

test("on_stale: fail on the entry makes stale coverage fail and still names refresh", () => {
  const r = check(staleRepo({ sync: { extra: "    on_stale: fail\n" } }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /^FAIL "formal-lock": check "one-holder": covered code changed since sync commit [0-9a-f]{12}: "src\/lock\.js"; run \/formal-verification:specify refresh$/m);
});

test("check.on_stale: fail in the convention file makes stale coverage fail", () => {
  const r = check(staleRepo({ conventions: "check:\n  on_stale: fail\n" }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /covered code changed since sync commit/);
});

test("an entry's on_stale: warn wins over the convention file's fail", () => {
  const r = check(staleRepo({ conventions: "check:\n  on_stale: fail\n", sync: { extra: "    on_stale: warn\n" } }).root);
  assert.equal(r.code, 0, r.out);
  assert.equal(r.warns.length, 1, r.out);
});

test("an on_stale value other than warn or fail makes sync.yaml invalid", () => {
  const r = check(repo({ sync: { extra: "    on_stale: never\n" } }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /on_stale: must be warn or fail/);
});

test("a verification skill outside the contract warns and does not fail", () => {
  const { root } = repo();
  write(root, ".claude/skills/verify-cache/sync.yaml", "checks: []\n");
  write(root, ".claude/skills/verify-cache/SKILL.md", "---\nname: verify-cache\n---\n");
  const r = check(root);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.warns, ['WARN "verify-cache": verification skill outside the contract: it holds a sync.yaml or model/ but is not named formal-<area>']);
});

test("the skills folder comes from the convention file's skills_dir", () => {
  const { root } = repo({ conventions: "skills_dir: verification\n" });
  const r = check(root);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /no formal-<area> skill under "verification"/);
});

test("a repository with no formal-area skill passes", () => {
  const r = check(repo({ skill: null, sync: null }).root);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /no formal-<area> skill under "\.claude\/skills", 0 failure\(s\)/);
});

test("outside a git work tree the check exits 2", () => {
  const dir = mkdtempSync(join(tmpdir(), "fv-check-nogit-"));
  temps.push(dir);
  assert.equal(check(dir).code, 2);
});

const workingTreeSnapshot = (root) => {
  const walk = (dir) =>
    readdirSync(dir).filter((e) => e !== ".git").flatMap((e) => {
      const p = join(dir, e);
      return statSync(p).isDirectory() ? walk(p) : [`${p} ${statSync(p).mtimeMs} ${createHash("sha256").update(readFileSync(p)).digest("hex")}`];
    });
  return walk(root).sort();
};

test("the check is deterministic and edits no file", () => {
  const { root } = staleRepo({ sync: { covers: ["src/lock.js", "src/gone.js"] } });
  const before = workingTreeSnapshot(root);
  const first = check(root);
  const second = check(root);
  assert.equal(first.code, 1);
  assert.equal(first.out, second.out);
  assert.deepEqual(workingTreeSnapshot(root), before);
});

test("** crosses folders and * stays inside one", () => {
  assert.ok(globMatch("src/**/*.js", "src/a/b/c.js"));
  assert.ok(globMatch("src/**/*.js", "src/c.js"));
  assert.ok(globMatch("src/**", "src/a/b"));
  assert.ok(globMatch("src/?.js", "src/c.js"));
  assert.ok(!globMatch("src/*.js", "src/a/c.js"));
  assert.ok(!globMatch("src/?.js", "src/ab.js"));
  assert.ok(!globMatch("src/**/*.js", "lib/c.js"));
});

test("**/ matches whole folders only, and zero folders", () => {
  assert.equal(globMatch("src/**/lock.js", "src/unlock.js"), false);
  assert.equal(globMatch("src/**/lock.js", "src/sub/unlock.js"), false);
  assert.equal(globMatch("**/x.js", "ax.js"), false);
  assert.equal(globMatch("src/**/lock.js", "src/lock.js"), true);
  assert.equal(globMatch("src/**/lock.js", "src/a/b/lock.js"), true);
  assert.equal(globMatch("**/x.js", "x.js"), true);
});

test("a pattern of many ** against a long path that cannot match ends in well under a second", () => {
  const start = Date.now();
  assert.equal(globMatch("**a**a**a**a**a**a**a**a**a**a**a**a**a**a**b", "a".repeat(60)), false);
  assert.ok(Date.now() - start < 1000, `took ${Date.now() - start} ms`);
});

test("a covers glob of many ** finishes the check within its time bound", () => {
  const { root, commit } = repo();
  write(root, "a".repeat(60), "1\n");
  write(root, ".claude/skills/formal-lock/sync.yaml", syncYaml(commit, { covers: ["src/lock.js", '"**a**a**a**a**a**a**a**a**a**a**a**a**a**a**b"'] }));
  git(root, "add", "-A");
  git(root, "commit", "-q", "-m", "slow glob");
  const start = Date.now();
  const r = check(root);
  assert.ok(Date.now() - start < 10000, `took ${Date.now() - start} ms`);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /is missing at HEAD/);
});

test("a formal-area folder that is a symlink fails and is not read", () => {
  const { root } = repo();
  renameSync(join(root, ".claude/skills/formal-lock"), join(root, "real-lock"));
  symlinkSync(join(root, "real-lock"), join(root, ".claude/skills/formal-lock"));
  const r = check(root);
  assert.equal(r.code, 1, r.out);
  assert.deepEqual(r.fails, ['FAIL "formal-lock": folder: is a symlink or not a folder; the check reads only real folders']);
});

for (const file of ["SKILL.md", "sync.yaml"]) {
  test(`a ${file} that is a symlink fails and is not read`, () => {
    const { root } = repo();
    const target = join(root, ".claude/skills/formal-lock", file);
    renameSync(target, join(root, `real-${file}`));
    symlinkSync(join(root, `real-${file}`), target);
    const r = check(root);
    assert.equal(r.code, 1, r.out);
    assert.match(r.fails.join("\n"), new RegExp(`${file.replace(".", "\\.")}: is a symlink`));
  });
}

test("a folder named on the command line outside the repository fails", () => {
  const { root } = repo();
  const outside = mkdtempSync(join(tmpdir(), "fv-check-outside-"));
  temps.push(outside);
  const r = check(root, outside);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /is outside the repository/);
});

test("a skills folder outside the repository fails", () => {
  const { root } = repo();
  const outside = mkdtempSync(join(tmpdir(), "fv-check-outside-"));
  temps.push(outside);
  symlinkSync(outside, join(root, "elsewhere"));
  const r = check(root, "--skills-dir", "elsewhere");
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /skills folder "elsewhere" is outside the repository/);
});

test("--skills-dir wins over the convention file's skills_dir", () => {
  const { root } = repo({ conventions: "skills_dir: verification\n" });
  const r = check(root, "--skills-dir", ".claude/skills");
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /1 formal-<area> skill\(s\)/);
});

test("a folder name holding a line break prints on one line", () => {
  const { root } = repo();
  write(root, ".claude/skills/formal-x\n::error title=forged::owned/SKILL.md", "no frontmatter\n");
  const r = check(root);
  assert.equal(r.code, 1, r.out);
  assert.ok(!r.out.split("\n").some((l) => l.startsWith("::")), r.out);
  assert.match(r.out, /^FAIL "formal-x\\n::error title=forged::owned": /m);
});

for (const bad of ["../escape.tla", "/abs/model.tla", "model/../../up.tla"]) {
  test(`an outside_model entry ${bad} fails`, () => {
    const { root, commit } = repo();
    write(root, ".claude/skills/formal-lock/sync.yaml", syncYaml(commit).replace("outside_model: []", `outside_model:\n  - ${bad}`));
    git(root, "commit", "-q", "-am", "outside model");
    const r = check(root);
    assert.equal(r.code, 1, r.out);
    assert.match(r.fails.join("\n"), /outside_model: .* must be a repository-relative path/);
  });
}

test("a repository-relative outside_model entry passes", () => {
  const { root, commit } = repo();
  write(root, ".claude/skills/formal-lock/sync.yaml", syncYaml(commit).replace("outside_model: []", "outside_model:\n  - src/harness.js"));
  git(root, "commit", "-q", "-am", "outside model");
  assert.equal(check(root).code, 0);
});

test("a ## Run that holds the command only inside a longer line fails", () => {
  const r = check(repo({ skill: { run: `${RUN} --extra-flag` } }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /no run command/);
});

test("a ## Run that gives the command as an inline code line passes", () => {
  const { root } = repo();
  const file = join(root, ".claude/skills/formal-lock/SKILL.md");
  writeFileSync(file, readFileSync(file, "utf8").replace(`\`\`\`text\n${RUN}\n\`\`\``, `\`${RUN}\``));
  git(root, "commit", "-q", "-am", "inline run");
  assert.equal(check(root).code, 0);
});

test("sections out of the contract's order fail", () => {
  const r = check(repo({ skill: { swap: ["Harm", "Run"] } }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /section: out of order/);
});

test("frontmatter without a description fails", () => {
  const r = check(repo({ skill: { description: false } }).root);
  assert.equal(r.code, 1, r.out);
  assert.deepEqual(r.fails, ['FAIL "formal-lock": frontmatter: description: missing']);
});

test("git runs with lazy fetching off", () => {
  const { root } = repo();
  const bin = mkdtempSync(join(tmpdir(), "fv-check-bin-"));
  temps.push(bin);
  const seen = join(bin, "seen");
  const real = spawnSync("sh", ["-c", "command -v git"], { encoding: "utf8" }).stdout.trim();
  writeFileSync(join(bin, "git"), `#!/bin/sh\nprintf '%s\\n' "\${GIT_NO_LAZY_FETCH:-unset}" >> "${seen}"\nexec "${real}" "$@"\n`);
  chmodSync(join(bin, "git"), 0o755);
  const r = checkWith({ PATH: `${bin}:${process.env.PATH}` }, root);
  assert.equal(r.code, 0, r.out);
  const values = readFileSync(seen, "utf8").trim().split("\n");
  assert.ok(values.length > 0 && values.every((v) => v === "1"), values.join(","));
});
