import assert from "node:assert/strict";
import { mkdirSync, realpathSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { folderLevel, gitRepository } from "./folder-file.mjs";
import { tempDir, writeTree } from "../tests/temp.mjs";

const LOCAL = join(".claude", "settings.local.json");

/** A main checkout with a .git folder, a linked worktree of it and a submodule inside it, as git lays them out. */
function repo() {
  const root = realpathSync(tempDir());
  const main = join(root, "main");
  const wt = join(root, "wt");
  writeTree(main, { ".git/HEAD": "ref: refs/heads/main\n", ".git/worktrees/wt/commondir": "../..\n", "src/deep/file.txt": "" });
  writeTree(wt, { ".git": `gitdir: ${join(main, ".git", "worktrees", "wt")}\n` });
  writeTree(main, { ".git/modules/sub/HEAD": "x\n", "sub/.git": "gitdir: ../.git/modules/sub\n" });
  return { root, main, wt, sub: join(main, "sub") };
}

const opts = (extra = {}) => ({ platform: "linux", home: "/nowhere-home", uid: process.getuid?.(), ...extra });

test("a subdirectory of a repository and a linked worktree both resolve to the main checkout's root file", () => {
  const r = repo();
  for (const dir of [r.main, join(r.main, "src", "deep"), r.wt]) {
    const level = folderLevel(dir, opts());
    assert.equal(level.file, join(r.main, LOCAL), dir);
    assert.equal(level.shared, true);
    assert.equal(level.commonDir, join(r.main, ".git"));
  }
});

test("a submodule, whose .git file has no commondir, is its own root", () => {
  const r = repo();
  const level = folderLevel(join(r.sub), opts());
  assert.equal(level.file, join(r.sub, LOCAL));
  assert.equal(level.commonDir, join(r.main, ".git", "modules", "sub"));
  assert.deepEqual(gitRepository(r.sub), { root: r.sub, commonDir: join(r.main, ".git", "modules", "sub") });
});

test("outside git, on Windows, at the home folder or in a root not owned by this user, the folder keeps its own file", () => {
  const r = repo();
  const outside = join(r.root, "plain");
  mkdirSync(outside);
  assert.deepEqual(folderLevel(outside, opts()), { file: join(outside, LOCAL), root: null, commonDir: null, shared: false });
  const deep = join(r.main, "src", "deep");
  assert.equal(folderLevel(deep, opts({ platform: "win32" })).file, join(deep, LOCAL));
  assert.equal(folderLevel(deep, opts({ home: r.main })).file, join(deep, LOCAL));
  assert.equal(folderLevel(r.wt, opts({ uid: 999_999 })).file, join(r.wt, LOCAL));
  assert.equal(folderLevel(deep, opts({ uid: undefined })).file, join(r.main, LOCAL), "no getuid skips the ownership test");
});
