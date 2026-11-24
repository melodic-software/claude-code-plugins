import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "compare-arms.sh");
const ROOT = mkdtempSync(join(tmpdir(), "compare-arms-"));
after(() => rmSync(ROOT, { recursive: true, force: true }));

const git = (repo, ...args) => {
  const out = spawnSync("git", ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", ...args], { encoding: "utf8" });
  assert.equal(out.status, 0, out.stderr);
  return out.stdout.trim();
};
const write = (repo, path, text) => {
  mkdirSync(dirname(join(repo, path)), { recursive: true });
  writeFileSync(join(repo, path), text);
};
const commit = (repo, files, message) => {
  for (const [path, text] of Object.entries(files)) write(repo, path, text);
  git(repo, "add", "-A");
  git(repo, "commit", "-q", "-m", message);
  return git(repo, "rev-parse", "HEAD");
};

const SKILL = "plugins/p/skills/s/SKILL.md";
const CASE = "plugins/p/evals/c1/case.yaml";
let repos = 0;
function fixture(change, mainAfter = {}) {
  const repo = join(ROOT, `r${repos++}`);
  mkdirSync(repo);
  git(repo, "init", "-q", "-b", "main");
  const base = commit(repo, { [SKILL]: "---\nname: s\ndescription: d\n---\nOld rule.\n", [CASE]: 'plugins: ["../.."]\nname: c1\n', "plugins/p/tests/x.sh": "echo old\n" }, "base");
  git(repo, "switch", "-q", "-c", "pr");
  const head = commit(repo, change, "pr");
  git(repo, "switch", "-q", "main");
  const main = Object.keys(mainAfter).length ? commit(repo, mainAfter, "main moves") : base;
  return { repo, base, head, main };
}

function run({ repo, main, head }) {
  const out = join(repo, "..", `${repo.split("/").at(-1)}-out`);
  const output = join(ROOT, `${repo.split("/").at(-1)}-gh-output`);
  writeFileSync(output, "");
  const result = spawnSync("bash", [SCRIPT], { encoding: "utf8", env: { ...process.env, REPO: repo, MAIN_SHA: main, HEAD_SHA: head, PLUGIN: "p", OUT: out, GITHUB_OUTPUT: output } });
  const values = Object.fromEntries(readFileSync(output, "utf8").split("\n").filter(Boolean).map((line) => line.split("=")));
  const patch = (side) => readFileSync(join(out, side, "edit.patch"), "utf8");
  return { status: result.status, stdout: result.stdout + result.stderr, values, patch, out };
}

const applies = (repo, ref, patchFile) => {
  const check = join(ROOT, `apply-${repos++}`);
  git(repo, "worktree", "add", "-q", "--detach", check, ref);
  const out = spawnSync("git", ["-C", check, "apply", "--check", patchFile], { encoding: "utf8" });
  return out.status === 0;
};

test("after carries the head's skill text and cases; before keeps the old text with the head's cases; nothing else moves", () => {
  const f = fixture({ [SKILL]: "---\nname: s\ndescription: d\n---\nNew rule.\n", "plugins/p/evals/c2/case.yaml": 'plugins: ["../.."]\nname: c2\n', "plugins/p/tests/x.sh": "echo new\n" });
  const r = run(f);
  assert.equal(r.status, 0, r.stdout);
  assert.equal(r.values["merge-base"], f.base);
  assert.match(r.patch("after"), /\+New rule\./);
  assert.match(r.patch("after"), /evals\/c2\/case\.yaml/);
  assert.match(r.patch("before"), /evals\/c2\/case\.yaml/);
  assert.doesNotMatch(r.patch("before"), /SKILL\.md/);
  for (const side of ["before", "after"]) assert.doesNotMatch(r.patch(side), /tests\/x\.sh/);
  assert.match(r.values["after-sha256"], /^[0-9a-f]{64}$/);
  assert.ok(applies(f.repo, f.main, join(r.out, "after", "edit.patch")));
  assert.ok(applies(f.repo, f.main, join(r.out, "before", "edit.patch")));
});

test("with main moved on the changed file, before restores the merge base's text and both patches apply to main", () => {
  const f = fixture({ [SKILL]: "---\nname: s\ndescription: d\n---\nNew rule.\n" }, { [SKILL]: "---\nname: s\ndescription: d\n---\nMain rule.\n" });
  const r = run(f);
  assert.equal(r.status, 0, r.stdout);
  assert.match(r.patch("before"), /\+Old rule\./);
  assert.match(r.patch("after"), /\+New rule\./);
  assert.ok(applies(f.repo, f.main, join(r.out, "before", "edit.patch")));
});

test("an unchanged main leaves the before patch empty with an empty sum", () => {
  const r = run(fixture({ [SKILL]: "---\nname: s\ndescription: d\n---\nNew rule.\n" }));
  assert.equal(r.status, 0, r.stdout);
  assert.equal(r.patch("before"), "");
  assert.equal(r.values["before-sha256"], "");
});

test("a change select-plugins refuses or a change to cases only is refused (exit 3) and builds nothing", () => {
  for (const change of [{ "plugins/p/skills/s/run.sh": "echo hi\n" }, { [CASE]: 'plugins: ["../.."]\nname: c1\ndescription: more\n' }]) {
    const r = run(fixture(change));
    assert.equal(r.status, 3, r.stdout);
    assert.deepEqual(r.values, { refused: "true" }, "a refusal writes only its marker");
  }
});

test("no change under the plugin is a wrong target (exit 1), not a refusal", () => {
  const wrong = run(fixture({ "plugins/p/tests/x.sh": "echo new\n" }));
  assert.equal(wrong.status, 1);
  assert.deepEqual(wrong.values, {}, "a wrong target writes no refusal marker");
});

test("a change to plugin text the arms do not carry, such as a reference file, is refused and builds nothing", () => {
  const r = run(fixture({ [SKILL]: "---\nname: s\ndescription: d\n---\nNew rule.\n", "plugins/p/reference/x.md": "cut\n" }));
  assert.equal(r.status, 3);
  assert.deepEqual(r.values, { refused: "true" });
  assert.match(r.stdout, /plugins\/p\/reference\/x\.md/);
});

test("a context/ markdown edit is carried: after has the head's text, before the merge base's", () => {
  const CONTEXT = "plugins/p/context/rules.md";
  const f = fixture({ [CONTEXT]: "New context.\n" }, { [CONTEXT]: "Main context.\n" });
  const r = run(f);
  assert.equal(r.status, 0, r.stdout);
  assert.match(r.patch("after"), /\+New context\./);
  assert.match(r.patch("before"), /context\/rules\.md/);
  assert.doesNotMatch(r.patch("before"), /\+New context\./);
  assert.ok(applies(f.repo, f.main, join(r.out, "after", "edit.patch")));
  assert.ok(applies(f.repo, f.main, join(r.out, "before", "edit.patch")));
});

test("a context/ file that is not markdown, plugin.json or probes/ builds nothing", () => {
  const skill = { [SKILL]: "---\nname: s\ndescription: d\n---\nNew rule.\n" };
  const script = run(fixture({ ...skill, "plugins/p/context/lookup.sh": "echo hi\n" }));
  assert.equal(script.status, 3);
  assert.deepEqual(script.values, { refused: "true" });
  assert.match(script.stdout, /select-plugins\.mjs refuses/);
  assert.match(script.stdout, /plugins\/p\/context\/lookup\.sh: /, "the refusal's reasons still reach the log");
  for (const path of ["plugins/p/.claude-plugin/plugin.json", "plugins/p/probes/p.md"]) {
    const r = run(fixture({ ...skill, [path]: "{}\n" }));
    assert.equal(r.status, 3, path);
    assert.match(r.stdout, new RegExp(`would not carry ${path.replaceAll(".", "\\.")}`));
  }
});
