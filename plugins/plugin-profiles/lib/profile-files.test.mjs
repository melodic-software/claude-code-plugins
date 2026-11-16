import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { tempDir, writeTree } from "../tests/temp.mjs";
import { ProfileError, readCatalog } from "./profile-files.mjs";

const levels = (root) => [
  { level: "shipped", dir: join(root, "shipped") },
  { level: "user", dir: join(root, "user") },
  { level: "repository", dir: join(root, "repo") },
];

test("AC3: a user build.yaml with one plugins line and one remove line extends the shipped one", () => {
  const root = writeTree(tempDir(), {
    "shipped/build.yaml": "description: Build.\nplugins: [impl@m, evals@m]\nexclude: [toy@m]\n",
    "user/build.yaml": "plugins: [mine@m]\nremove: [evals@m]\n",
  });
  const build = readCatalog(levels(root)).profiles.get("build");
  assert.deepEqual([...build.plugins], ["impl@m", "mine@m"]);
  assert.deepEqual([...build.exclude], ["toy@m"]);
  assert.equal(build.description, "Build.");
});

test("AC3: a repository profile extends the user one, which extends the shipped one", () => {
  const root = writeTree(tempDir(), {
    "shipped/build.yaml": "plugins: [a@m, b@m]\n",
    "user/build.yaml": "plugins: [c@m]\nremove: [a@m]\n",
    "repo/build.yaml": "plugins:\n  - d@m\nremove: [c@m]\nhide_skills: [legacy]\n",
  });
  const build = readCatalog(levels(root)).profiles.get("build");
  assert.deepEqual([...build.plugins], ["b@m", "d@m"]);
  assert.deepEqual([...build.hideSkills], ["legacy"]);
});

test("AC24: always-on members add up across levels and a remove line takes one out", () => {
  const root = writeTree(tempDir(), {
    "shipped/always-on.yaml": "plugins: [guard@m, flow@m]\noptional: [fmt@m]\n",
    "user/always-on.yaml": "plugins: [mine@m]\nremove: [flow@m]\n",
    "shipped/build.yaml": "plugins: [impl@m]\n",
  });
  const catalog = readCatalog(levels(root));
  assert.deepEqual([...catalog.alwaysOn.plugins], ["guard@m", "mine@m"]);
  assert.deepEqual([...catalog.alwaysOn.optional], ["fmt@m"]);
  assert.deepEqual([...catalog.profiles.keys()], ["build"]);
});

test("a profile only a user file defines is a profile of its own", () => {
  const root = writeTree(tempDir(), { "user/notes.yaml": "plugins: [writing@m]\n" });
  assert.deepEqual([...readCatalog(levels(root)).profiles.get("notes").plugins], ["writing@m"]);
});

for (const [why, text] of [
  ["a bare plugin name", "plugins: [impl]\n"],
  ["an unknown key", "plugin: [impl@m]\n"],
  ["a list that is not a list", "plugins: impl@m\n"],
  ["text that is not the YAML subset", "plugins: {a: b}\n"],
]) {
  test(`a profile file with ${why} is refused, naming the file`, () => {
    const root = writeTree(tempDir(), { "shipped/build.yaml": text });
    assert.throws(() => readCatalog(levels(root)), (error) => error instanceof ProfileError && error.message.includes("build.yaml"));
  });
}
