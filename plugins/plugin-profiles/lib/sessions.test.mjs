import assert from "node:assert/strict";
import { mkdirSync, symlinkSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { othersInFolder } from "./sessions.mjs";
import { tempDir, writeTree } from "../tests/temp.mjs";

const answer = (stdout, status = 0) => () => ({ status, stdout, stderr: "" });

test("names the other sessions in the folder, leaves out this one and other folders, and matches through a link", () => {
  const root = tempDir();
  const folder = join(root, "repo");
  mkdirSync(folder);
  symlinkSync(folder, join(root, "link"));
  const agents = [
    { cwd: folder, sessionId: "me", name: "this one", kind: "interactive" },
    { cwd: join(root, "link"), sessionId: "b", name: "builder", kind: "background" },
    { cwd: folder, sessionId: "c", kind: "interactive" },
    { cwd: join(root, "elsewhere"), sessionId: "d", name: "far", kind: "interactive" },
  ];
  assert.deepEqual(othersInFolder(folder, "me", answer(JSON.stringify(agents))), [
    { name: "builder", sessionId: "b", kind: "background" },
    { name: "c", sessionId: "c", kind: "interactive" },
  ]);
});

test("counts a session in any worktree or subdirectory of the repository as in the same folder, since all read one settings file", () => {
  const root = tempDir();
  const main = join(root, "main");
  const wt = join(root, "wt");
  writeTree(main, { ".git/HEAD": "ref: refs/heads/main\n", ".git/worktrees/wt/commondir": "../..\n", "src/x.txt": "" });
  writeTree(wt, { ".git": `gitdir: ${join(main, ".git", "worktrees", "wt")}\n` });
  mkdirSync(join(root, "other"));
  const agents = [
    { cwd: join(main, "src"), sessionId: "a", name: "sub", kind: "interactive" },
    { cwd: main, sessionId: "b", name: "main", kind: "interactive" },
    { cwd: join(root, "other"), sessionId: "c", name: "other", kind: "interactive" },
  ];
  assert.deepEqual(othersInFolder(wt, "me", answer(JSON.stringify(agents))).map((a) => a.name), ["sub", "main"]);
});

test("#16914: a session in a submodule or in a sibling worktree of a bare repository is not named, since it reads another file", () => {
  const root = tempDir();
  const main = join(root, "main");
  writeTree(main, { ".git/HEAD": "ref: refs/heads/main\n", ".git/modules/sub/HEAD": "x\n", "sub/.git": "gitdir: ../.git/modules/sub\n" });
  const bare = join(root, "bare.git");
  writeTree(bare, { HEAD: "x\n", "worktrees/b1/commondir": "../..\n", "worktrees/b2/commondir": "../..\n" });
  writeTree(join(root, "b1"), { ".git": `gitdir: ${join(bare, "worktrees", "b1")}\n` });
  writeTree(join(root, "b2"), { ".git": `gitdir: ${join(bare, "worktrees", "b2")}\n` });
  const agents = [
    { cwd: join(main, "sub"), sessionId: "s", name: "in submodule", kind: "interactive" },
    { cwd: join(root, "b2"), sessionId: "w", name: "bare sibling", kind: "interactive" },
    { cwd: main, sessionId: "m", name: "main", kind: "interactive" },
  ];
  assert.deepEqual(othersInFolder(main, "me", answer(JSON.stringify(agents))).map((a) => a.name), ["main"]);
  assert.deepEqual(othersInFolder(join(root, "b1"), "me", answer(JSON.stringify(agents))).map((a) => a.name), []);
});

test("gives an empty list when claude fails, prints something else, or cannot start", () => {
  for (const run of [answer("[]", 1), answer("not json"), answer("{}"), () => ({ error: new Error("ENOENT") })]) {
    assert.deepEqual(othersInFolder("/x", "me", run), []);
  }
});
