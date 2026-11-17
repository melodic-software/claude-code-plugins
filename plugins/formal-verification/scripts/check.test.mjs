import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { globRegex } from "./check.mjs";

const script = join(fileURLToPath(new URL(".", import.meta.url)), "check.mjs");
const temps = [];
test.after(() => {
  for (const dir of temps) rmSync(dir, { recursive: true, force: true });
});

const git = (dir, ...args) => {
  const r = spawnSync("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", ...args], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
};

const write = (root, rel, body) => {
  mkdirSync(join(root, rel, ".."), { recursive: true });
  writeFileSync(join(root, rel), body);
};

const RUN = "/formal-verification:chart .claude/skills/formal-lock/model/Lock.tla";

const skillBody = ({ name = "formal-lock", drop = [], run = RUN, head = true } = {}) => {
  const fm = head ? `---\nname: ${name}\ndescription: "Lock model. Use when src/lock.js changes."\n---\n\n` : "";
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
  return `${fm}# Formal check: lock\n\n${parts.map(([s, b]) => `## ${s}\n\n${b}\n`).join("\n")}`;
};

const syncYaml = (commit, { covers = ["src/lock.js"], extra = "", command = RUN } = {}) =>
  `checks:\n  - id: one-holder\n    covers:\n${covers.map((c) => `      - ${c}\n`).join("")}    commit: ${commit}\n    command: ${command}\n    seeded_break:\n      change: the held check removed\n      caught: true\n      commit: ${commit}\n${extra}outside_model: []\n`;

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

const check = (root, ...args) => {
  const r = spawnSync(process.execPath, [script, "--project-dir", root, ...args], { encoding: "utf8" });
  return { code: r.status, out: r.stdout, fails: r.stdout.split("\n").filter((l) => l.startsWith("FAIL ")), warns: r.stdout.split("\n").filter((l) => l.startsWith("WARN ")) };
};

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
  assert.match(r.fails.join("\n"), /^FAIL formal-lock: frontmatter: missing/m);
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
    assert.deepEqual(r.fails, [`FAIL formal-lock: section: ## ${section} missing`]);
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

test("a covered file missing at HEAD fails, and a glob that matches no file fails", () => {
  const r = check(repo({ sync: { covers: ["src/lock.js", "src/gone.js", "lib/**/*.js"] } }).root);
  assert.equal(r.code, 1, r.out);
  assert.deepEqual(r.fails, [
    'FAIL formal-lock: check "one-holder": covered path "src/gone.js" is missing at HEAD',
    'FAIL formal-lock: check "one-holder": covered path "lib/**/*.js" is missing at HEAD',
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
  assert.match(r.warns[0], /^WARN formal-lock: check "one-holder": covered code changed since sync commit [0-9a-f]{12}: src\/lock\.js$/);
});

test("on_stale: fail on the entry makes stale coverage fail", () => {
  const r = check(staleRepo({ sync: { extra: "    on_stale: fail\n" } }).root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.fails.join("\n"), /covered code changed since sync commit/);
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
  assert.deepEqual(r.warns, ["WARN verify-cache: verification skill outside the contract: it holds a sync.yaml or model/ but is not named formal-<area>"]);
});

test("the skills folder comes from the convention file's skills_dir", () => {
  const { root } = repo({ conventions: "skills_dir: verification\n" });
  const r = check(root);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /no formal-<area> skill under verification/);
});

test("a repository with no formal-area skill passes", () => {
  const r = check(repo({ skill: null, sync: null }).root);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /no formal-<area> skill under \.claude\/skills, 0 failure\(s\)/);
});

test("outside a git work tree the check exits 2", () => {
  const dir = mkdtempSync(join(tmpdir(), "fv-check-nogit-"));
  temps.push(dir);
  assert.equal(check(dir).code, 2);
});

const snapshot = (root) => {
  const walk = (dir) =>
    readdirSync(dir).flatMap((e) => {
      const p = join(dir, e);
      return statSync(p).isDirectory() ? walk(p) : [`${p} ${statSync(p).mtimeMs} ${createHash("sha256").update(readFileSync(p)).digest("hex")}`];
    });
  return walk(root).sort();
};

test("the check is deterministic and edits no file", () => {
  const { root } = staleRepo({ sync: { covers: ["src/lock.js", "src/gone.js"] } });
  const before = snapshot(root);
  const first = check(root);
  const second = check(root);
  assert.equal(first.code, 1);
  assert.equal(first.out, second.out);
  assert.deepEqual(snapshot(root), before);
});

test("** crosses folders and * stays inside one", () => {
  assert.ok(globRegex("src/**/*.js").test("src/a/b/c.js"));
  assert.ok(globRegex("src/**/*.js").test("src/c.js"));
  assert.ok(!globRegex("src/*.js").test("src/a/c.js"));
});
