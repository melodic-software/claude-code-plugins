import assert from "node:assert/strict";
import { mkdirSync, symlinkSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { othersInFolder } from "./sessions.mjs";
import { tempDir } from "../tests/temp.mjs";

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

test("gives an empty list when claude fails, prints something else, or cannot start", () => {
  for (const run of [answer("[]", 1), answer("not json"), answer("{}"), () => ({ error: new Error("ENOENT") })]) {
    assert.deepEqual(othersInFolder("/x", "me", run), []);
  }
});
