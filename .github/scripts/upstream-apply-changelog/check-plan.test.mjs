import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";

const SCRIPT = new URL("./check-plan.sh", import.meta.url).pathname;
const RELEASE = "2.1.300";
const MODEL_REF = "refs/heads/MODEL-WROTE-THIS-REF";

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), "uac-check-plan-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = { PATH: process.env.PATH, HOME: dir, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1", GIT_AUTHOR_NAME: "model", GIT_AUTHOR_EMAIL: "m@m", GIT_COMMITTER_NAME: "model", GIT_COMMITTER_EMAIL: "m@m" };
  const git = (cwd, ...args) => execFileSync("git", ["-C", cwd, ...args], { env, encoding: "utf8" }).trim();
  const src = join(dir, "src");
  const repo = join(dir, "base");
  const IN = join(dir, "scan-in");
  const OUT = join(dir, "scan-out");
  mkdirSync(IN);
  git(dir, "init", "-q", "-b", "main", src);
  writeFileSync(join(src, "keep.md"), "k\n");
  git(src, "add", ".");
  git(src, "commit", "-qm", "base");
  const base = git(src, "rev-parse", "HEAD");
  git(dir, "init", "-q", "-b", "main", repo);
  git(repo, "fetch", "-q", "--no-tags", src, "main:refs/base");

  const commit = (files) => {
    git(src, "checkout", "-q", "--detach", base);
    for (const [path, content] of Object.entries(files)) {
      mkdirSync(dirname(join(src, path)), { recursive: true });
      writeFileSync(join(src, path), content);
    }
    git(src, "add", ".");
    git(src, "commit", "-qm", "change");
    return git(src, "rev-parse", "HEAD");
  };
  const bundle = (...heads) => {
    heads.forEach((head, i) => git(src, "update-ref", `${MODEL_REF}-${i}`, head));
    git(src, "bundle", "create", "-q", join(IN, "branches.bundle"), `^${base}`, ...heads.map((_, i) => `${MODEL_REF}-${i}`));
  };
  const writePlan = (branches) =>
    writeFileSync(
      join(IN, "plan.json"),
      JSON.stringify({
        schema: "changelog-ci-plan/1",
        status: "planned",
        range: `${RELEASE}..${RELEASE}`,
        base_sha: base,
        branches: branches.map(({ plugin, head }) => ({ plugin, branch: `changelog/${plugin}/v${RELEASE}`, base_sha: base, head_sha: head, pr: { title: `chore(${plugin}): t`, body: "b" } })),
        handoffs: [{ key: `changelog:${RELEASE}..${RELEASE}:adopt:plugins/x/a.sh`, title: "t", body: "b" }],
      }),
    );
  const run = () => {
    const GITHUB_OUTPUT = join(dir, "github-output");
    writeFileSync(GITHUB_OUTPUT, "");
    const r = spawnSync("bash", [SCRIPT], { cwd: dir, env: { ...env, IN, OUT, RELEASE, BASE_SHA: base, REPO_DIR: repo, GITHUB_OUTPUT }, encoding: "utf8" });
    const outputs = Object.fromEntries(readFileSync(GITHUB_OUTPUT, "utf8").split("\n").filter(Boolean).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
    return { status: r.status, log: r.stdout + r.stderr, outputs };
  };
  return { src, repo, IN, OUT, base, git, commit, bundle, writePlan, run };
}

test("a planned branch in its plugin leaves its diff, the plan and a synthetic bundle, and prints no ref name", (t) => {
  const f = fixture(t);
  const head = f.commit({ "plugins/discovery/a.md": "a\n" });
  f.writePlan([{ plugin: "discovery", head }]);
  f.bundle(head);
  const { status, log, outputs } = f.run();
  assert.equal(status, 0, log);
  assert.match(log, /1 branches, 1 handoffs/);
  assert.equal(log.includes("MODEL-WROTE-THIS-REF"), false, "the bundle's ref names are never printed");
  assert.equal(readFileSync(join(f.IN, "heads.txt"), "utf8"), `${head}\n`);
  assert.equal(readFileSync(join(f.IN, "diffs.txt"), "utf8"), `${f.git(f.src, "diff", "--no-renames", "--binary", f.base, head)}\n`);
  assert.equal(readFileSync(join(f.OUT, "plan.json"), "utf8"), readFileSync(join(f.IN, "plan.json"), "utf8"));
  assert.equal(outputs.branches, "1");
  const [made, ...rest] = JSON.parse(outputs.synthetic);
  assert.deepEqual(rest, []);
  assert.equal(made.tree, f.git(f.src, "rev-parse", `${head}^{tree}`));
  f.git(f.repo, "fetch", "-q", "--no-tags", join(f.OUT, "branches.bundle"), `${made.commit}:refs/check`);
  assert.equal(f.git(f.repo, "rev-list", "--parents", "-n", "1", made.commit), `${made.commit} ${f.base}`);
});

test("a plan with no branch needs no bundle and leaves none", (t) => {
  const f = fixture(t);
  f.writePlan([]);
  const { status, log, outputs } = f.run();
  assert.equal(status, 0, log);
  assert.deepEqual([outputs.branches, outputs.synthetic], ["0", "[]"]);
  assert.equal(readFileSync(join(f.IN, "diffs.txt"), "utf8"), "");
  assert.equal(existsSync(join(f.OUT, "branches.bundle")), false);
});

test("a branch that changes a hold path stops the release with no branch, diff or bundle", (t) => {
  const f = fixture(t);
  const head = f.commit({ "plugins/review/skills/security-review/SKILL.md": "x\n" });
  f.writePlan([{ plugin: "review", head }]);
  f.bundle(head);
  const { status, log, outputs } = f.run();
  assert.equal(status, 0, log);
  assert.match(log, /::warning::branches\[0\] changes a hold path/);
  assert.deepEqual([outputs.branches, outputs.synthetic], ["0", "[]"]);
  assert.equal(JSON.parse(readFileSync(join(f.OUT, "plan.json"), "utf8")).stop_reason, "hold-path");
  assert.equal(readFileSync(join(f.IN, "diffs.txt"), "utf8"), "");
  assert.equal(existsSync(join(f.OUT, "branches.bundle")), false);
});

test("each broken input fails the step with its own error and writes no output", async (t) => {
  const cases = {
    "no plan": [() => {}, "::error::the apply-changelog job left no ci-plan.json"],
    "a plan that is not JSON": [(f) => writeFileSync(join(f.IN, "plan.json"), "{"), "::error::ci-plan.json: not valid JSON"],
    "no bundle": [(f) => f.writePlan([{ plugin: "discovery", head: f.commit({ "plugins/discovery/a.md": "a\n" }) }]), "::error::the plan names branches and the apply-changelog job left no bundle"],
    "a bundle that does not verify": [
      (f) => {
        f.writePlan([{ plugin: "discovery", head: f.commit({ "plugins/discovery/a.md": "a\n" }) }]);
        writeFileSync(join(f.IN, "branches.bundle"), "not a bundle");
      },
      "::error::the branches bundle does not verify against the base",
    ],
    "a planned head the bundle lacks": [
      (f) => {
        f.writePlan([{ plugin: "discovery", head: f.commit({ "plugins/discovery/a.md": "a\n" }) }]);
        f.bundle(f.commit({ "plugins/discovery/b.md": "b\n" }));
      },
      "::error::1 of 1 planned heads are not heads of the bundle",
    ],
    "a binary file": [
      (f) => {
        const head = f.commit({ "plugins/discovery/img.bin": Buffer.from([0, 1, 2, 0, 255]) });
        f.writePlan([{ plugin: "discovery", head }]);
        f.bundle(head);
      },
      "::error::a planned branch changes a binary file; only text is published",
    ],
    "a path outside the plugin": [
      (f) => {
        const head = f.commit({ "plugins/other/a.md": "a\n" });
        f.writePlan([{ plugin: "discovery", head }]);
        f.bundle(head);
      },
      "::error::branches[0] raw line 1 changes a path outside plugins/discovery/ and .changes/discovery/",
    ],
  };
  for (const [name, [arrange, error]] of Object.entries(cases)) {
    await t.test(name, (t) => {
      const f = fixture(t);
      arrange(f);
      const { status, log, outputs } = f.run();
      assert.equal(status, 1, log);
      assert.ok(log.includes(error), log);
      assert.deepEqual(outputs, {});
      assert.equal(log.includes("MODEL-WROTE-THIS-REF"), false);
    });
  }
});
