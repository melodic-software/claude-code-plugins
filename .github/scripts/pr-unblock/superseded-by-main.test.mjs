import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { main } from "./superseded-by-main.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const LINES = ["one", "two", "three", "four", "five", "six", "seven"];

function repoWithMainAndPrBranches() {
  const dir = tempDir("superseded-by-main-");
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1", GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@t", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@t" };
  const git = (...args) => execFileSync("git", args, { cwd: dir, env, encoding: "utf8" }).trim();
  git("init", "-q", "-b", "main");
  const write = (name, lines) => writeFileSync(join(dir, name), `${lines.join("\n")}\n`);
  const edit = (changes, message, name = "f") => {
    const lines = readFileSync(join(dir, name), "utf8").trimEnd().split("\n");
    for (const [index, text] of Object.entries(changes)) lines[index] = text;
    write(name, lines);
    git("add", "-A");
    git("commit", "-qm", message);
    return git("rev-parse", "HEAD");
  };
  write("f", LINES);
  git("add", "f");
  git("commit", "-qm", "base");
  git("branch", "pr");
  const mergingMainIntoPrConflicts = () => spawnSync("git", ["merge-tree", "--write-tree", "main", "pr"], { cwd: dir, env }).status === 1;
  return { dir, git, edit, conflicts: mergingMainIntoPrConflicts };
}

const check = ({ dir, git }) => {
  const output = join(dir, ".git", "github-output");
  writeFileSync(output, "");
  main({ GITHUB_OUTPUT: output, BASE_SHA: git("rev-parse", "main"), HEAD_SHA: git("rev-parse", "pr") }, { cwd: dir, log: () => {} });
  return readFileSync(output, "utf8");
};

test("a commit main cherry-picked, then edited again, is superseded", () => {
  const r = repoWithMainAndPrBranches();
  r.git("switch", "-q", "pr");
  const fix = r.edit({ 1: "two (pr)" }, "pr: fix two");
  r.git("switch", "-q", "main");
  r.git("cherry-pick", "-x", fix);
  r.edit({ 1: "two (pr, then main)" }, "main: reword two");
  assert.equal(r.conflicts(), true, "the fixture conflicts, so the lane would reach the check");
  assert.equal(check(r), "superseded=true\n");
});

test("a two-commit pull request main squash-merged, then edited again, is superseded", () => {
  const r = repoWithMainAndPrBranches();
  r.git("switch", "-q", "pr");
  r.edit({ 1: "two (pr)" }, "pr: fix two");
  r.edit({ 5: "six (pr)" }, "pr: fix six");
  r.git("switch", "-q", "main");
  r.git("merge", "-q", "--squash", "pr");
  r.git("commit", "-qm", "pr (#1)");
  r.edit({ 1: "two (pr, then main)" }, "main: reword two");
  assert.equal(r.conflicts(), true);
  assert.equal(check(r), "superseded=true\n");
});

test("a pull request that already merged main keeps its own commits apart from the merge", () => {
  const r = repoWithMainAndPrBranches();
  r.git("switch", "-q", "pr");
  const fix = r.edit({ 1: "two (pr)" }, "pr: fix two");
  r.git("switch", "-q", "main");
  r.edit({ 6: "seven (main)" }, "main: unrelated");
  r.git("switch", "-q", "pr");
  r.git("merge", "-q", "--no-edit", "main");
  r.git("switch", "-q", "main");
  r.git("cherry-pick", "-x", fix);
  r.edit({ 1: "two (pr, then main)" }, "main: reword two");
  assert.equal(r.conflicts(), true);
  assert.equal(check(r), "superseded=true\n");
});

test("a pull request main changed the same lines under differently is not superseded", () => {
  const r = repoWithMainAndPrBranches();
  r.git("switch", "-q", "pr");
  r.edit({ 1: "two (pr)" }, "pr: fix two");
  r.git("switch", "-q", "main");
  r.edit({ 1: "two (main)" }, "main: fix two its own way");
  assert.equal(r.conflicts(), true);
  assert.equal(check(r), "superseded=false\n");
});

test("a pull request main holds only part of is not superseded", () => {
  const r = repoWithMainAndPrBranches();
  r.git("switch", "-q", "pr");
  const first = r.edit({ 1: "two (pr)" }, "pr: fix two");
  r.edit({ 5: "six (pr)" }, "pr: fix six");
  r.git("switch", "-q", "main");
  r.git("cherry-pick", "-x", first);
  r.edit({ 1: "two (pr, then main)" }, "main: reword two");
  assert.equal(r.conflicts(), true);
  assert.equal(check(r), "superseded=false\n");
});

test("a head .gitattributes marking every file binary does not make different edits read as the same patch", () => {
  const r = repoWithMainAndPrBranches();
  r.git("switch", "-q", "pr");
  writeFileSync(join(r.dir, ".gitattributes"), "* -diff\n");
  r.edit({ 1: "two (pr)" }, "pr: fix two, diff nothing");
  r.git("switch", "-q", "main");
  writeFileSync(join(r.dir, ".gitattributes"), "* -diff\n");
  r.edit({ 1: "two (main)" }, "main: fix two its own way, diff nothing");
  r.git("switch", "-q", "pr");
  assert.equal(r.conflicts(), true);
  assert.equal(check(r), "superseded=false\n");
});

test("main refuses a base or head that is not a full commit id", () => {
  const r = repoWithMainAndPrBranches();
  const output = join(r.dir, ".git", "github-output");
  assert.throws(() => main({ GITHUB_OUTPUT: output, BASE_SHA: "main", HEAD_SHA: r.git("rev-parse", "pr") }, { cwd: r.dir }), /BASE_SHA is not a full commit id/);
  assert.throws(() => main({ GITHUB_OUTPUT: output, BASE_SHA: r.git("rev-parse", "main") }, { cwd: r.dir }), /HEAD_SHA is not set/);
});
