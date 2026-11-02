import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  alreadyProcessed,
  branchFor,
  checkRawLog,
  newestRelease,
  readCommits,
  releasesFromStatus,
  replayCommits,
  startedInWindow,
  validatePlan,
} from "./upstream-apply-changelog.mjs";

const BASE = "a".repeat(40);
const HEAD = "b".repeat(40);
const plan = (over = {}) => ({
  schema: "changelog-ci-plan/1",
  status: "planned",
  range: "2.1.300..2.1.300",
  base_sha: BASE,
  branches: [
    {
      plugin: "hooks-kit",
      branch: "changelog/hooks-kit/v2.1.300",
      base_sha: BASE,
      head_sha: HEAD,
      pr: { title: "chore(hooks-kit): address Claude Code v2.1.300 changelog", body: "Refs: #7407" },
    },
  ],
  handoffs: [{ key: "changelog:2.1.300..2.1.300:adopt:plugins/x/a.sh", title: "t", body: "b" }],
  ...over,
});
const ctx = { release: "2.1.300", baseSha: BASE };

test("the newest release is the highest version, skipping drafts, prereleases and other tags", () => {
  const releases = [
    { tag_name: "v2.1.99" },
    { tag_name: "v2.1.300" },
    { tag_name: "v2.1.301", prerelease: true },
    { tag_name: "v9.9.9", draft: true },
    { tag_name: "nightly" },
  ];
  assert.equal(newestRelease(releases), "2.1.300");
  assert.equal(newestRelease([]), "");
});

test("the per-day cap counts only start records from the last 24 hours", () => {
  const now = Date.parse("2026-11-02T12:00:00Z");
  const artifacts = [
    { name: "upstream-apply-changelog-started-2.1.300-1", created_at: "2026-11-02T01:00:00Z" },
    { name: "upstream-apply-changelog-started-2.1.299-2", created_at: "2026-11-01T11:00:00Z" },
    { name: "upstream-apply-changelog-done-2.1.300", created_at: "2026-11-02T02:00:00Z" },
  ];
  assert.equal(startedInWindow(artifacts, now), 1);
});

test("a valid plan passes and a stopped plan acts on nothing", () => {
  assert.equal(validatePlan(plan(), ctx).branches.length, 1);
  assert.deepEqual(validatePlan(plan({ status: "stopped" }), ctx), { branches: [], handoffs: [] });
});

test("a plan for another release, base or branch name is refused", () => {
  assert.throws(() => validatePlan(plan({ range: "2.1.299..2.1.299" }), ctx), /range/);
  assert.throws(() => validatePlan(plan({ base_sha: HEAD }), ctx), /base_sha/);
  const renamed = plan();
  renamed.branches[0].branch = "main";
  assert.throws(() => validatePlan(renamed, ctx), /branch is not changelog\/hooks-kit\/v2\.1\.300/);
  const titled = plan();
  titled.branches[0].pr.title = "feat(other): x";
  assert.throws(() => validatePlan(titled, ctx), /title/);
  assert.throws(() => validatePlan(plan({ handoffs: [{ key: "changelog:2.1.1..2.1.1:adopt:x", title: "t", body: "b" }] }), ctx), /key/);
  assert.equal(branchFor("hooks-kit", "2.1.300"), "changelog/hooks-kit/v2.1.300");
});

test("a commit outside its plugin, or writing a link or submodule, is refused", () => {
  const ok = ":000000 100644 0000 1111 A\tplugins/hooks-kit/SKILL.md\n:000000 100644 0000 2222 A\t.changes/hooks-kit/x.md";
  assert.doesNotThrow(() => checkRawLog(ok, "hooks-kit"));
  assert.throws(() => checkRawLog(":100644 100644 1 2 M\tplugins/other/SKILL.md", "hooks-kit"), /outside/);
  assert.throws(() => checkRawLog(":100644 100644 1 2 M\t.github/workflows/x.yml", "hooks-kit"), /outside/);
  assert.throws(() => checkRawLog(":000000 120000 0 2 A\tplugins/hooks-kit/link", "hooks-kit"), /mode 120000/);
  assert.throws(() => checkRawLog(":000000 160000 0 2 A\tplugins/hooks-kit/sub", "hooks-kit"), /mode 160000/);
});

test("only the done marker skips a release, so a run after a failed publish finishes the work", () => {
  assert.equal(alreadyProcessed({ total_count: 1, artifacts: [{ name: "upstream-apply-changelog-done-2.1.300" }] }), true);
  assert.equal(alreadyProcessed({ total_count: 0, artifacts: [] }), false);
  assert.equal(alreadyProcessed(null), false);
});

test("the status file gives the unread releases, none when up to date, and stops on anything else", () => {
  assert.deepEqual(releasesFromStatus("range: 2.1.299..2.1.300 (2 releases, 5 core items)\nreleases: 2.1.299 2.1.300\ncap: within budget (2 releases / 5 items)\n"), ["2.1.299", "2.1.300"]);
  assert.deepEqual(releasesFromStatus("range: up to date\n"), []);
  assert.throws(() => releasesFromStatus("range: 2.1.1..2.1.90 (90 releases, 400 core items)\ncap: exceeded (90 releases / 400 items)\n"), /cap: exceeded/);
  assert.throws(() => releasesFromStatus("range: a..b\ncap: within budget\nreleases: v2\n"), /malformed/);
});

// A fake Git Data API: each object's sha is its index in the calls made.
function fakeApi() {
  const calls = [];
  const sha = (kind) => {
    calls.push(kind);
    return `${kind}-${calls.length}`;
  };
  return {
    calls,
    createBlob: async (content) => sha(`blob:${content}`),
    createTree: async (base, entries) => sha(`tree:${base}:${entries.map((e) => `${e.path}=${e.sha}`).join(",")}`),
    createCommit: async (message, tree, parents) => sha(`commit:${message.trim()}:${tree}:${parents.join(",")}`),
  };
}

test("the replay makes one App commit per planned commit, chained from the base, and deletes a removed file", async () => {
  const api = fakeApi();
  const commits = [
    { message: "first\n", entries: [{ path: "plugins/p/a.md", mode: "100644", content: Buffer.from("a") }] },
    { message: "second\n", entries: [{ path: "plugins/p/a.md", mode: "100644", content: null }] },
  ];
  const tree1 = "tree:t0:plugins/p/a.md=blob:YQ==-1-2";
  const tree2 = `tree:${tree1}:plugins/p/a.md=null-4`;
  const head = await replayCommits(commits, { baseSha: BASE, baseTree: "t0", headTree: tree2, api });
  assert.equal(api.calls[2], `commit:first:${tree1}:${BASE}`);
  assert.equal(api.calls[4], `commit:second:${tree2}:commit:first:${tree1}:${BASE}-3`);
  assert.equal(head, `${api.calls[4]}-5`);
});

test("a replay whose tree is not the planned head's is refused before any ref is made", async () => {
  const commits = [{ message: "m", entries: [{ path: "plugins/p/a.md", mode: "100644", content: Buffer.from("a") }] }];
  await assert.rejects(replayCommits(commits, { baseSha: BASE, baseTree: "t0", headTree: "other", api: fakeApi() }), /not the planned head's/);
});

test("the planned commits are read oldest first with their files, and a merge commit is refused", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "uac-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = { PATH: process.env.PATH, HOME: dir, GIT_CONFIG_NOSYSTEM: "1", GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@t", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@t" };
  const git = (...args) => execFileSync("git", ["-C", dir, ...args], { env, encoding: "utf8" }).trim();
  git("init", "-q", "-b", "main");
  writeFileSync(join(dir, "keep.md"), "k");
  git("add", ".");
  git("commit", "-qm", "base");
  const base = git("rev-parse", "HEAD");
  writeFileSync(join(dir, "new.md"), "n");
  git("add", ".");
  git("commit", "-qm", "add new");
  git("rm", "-q", "keep.md");
  git("commit", "-qm", "drop keep");
  const commits = readCommits(dir, base, git("rev-parse", "HEAD"));
  assert.deepEqual(commits.map((c) => c.message.trim()), ["add new", "drop keep"]);
  assert.deepEqual(commits[0].entries.map((e) => [e.path, e.mode, String(e.content)]), [["new.md", "100644", "n"]]);
  assert.deepEqual(commits[1].entries, [{ path: "keep.md", mode: "100644", content: null }]);
  git("checkout", "-qb", "side", base);
  writeFileSync(join(dir, "side.md"), "s");
  git("add", ".");
  git("commit", "-qm", "side");
  git("merge", "-q", "--no-edit", "main");
  assert.throws(() => readCommits(dir, base, git("rev-parse", "HEAD")), /merge commit/);
});
