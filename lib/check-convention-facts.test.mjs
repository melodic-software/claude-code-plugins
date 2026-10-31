import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { findClaims } from "./check-convention-facts.mjs";
import { tempDir } from "./test-tmp.mjs";

const SCRIPT = fileURLToPath(new URL("./check-convention-facts.mjs", import.meta.url));
const dir = tempDir("check-convention-facts-test-");
const write = (name, text) => {
  const path = join(dir, name);
  writeFileSync(path, text);
  return path;
};
const run = (...args) => spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8" });

const CLAIM = "Every command supports `--yes` to skip confirmation.";
const FILE = [
  "---",
  "written_against: developer-experience@1.0.0",
  "---",
  "# Developer tooling conventions",
  "",
  "## Tools",
  "<!-- developer-experience: source=chosen -->",
  `- ${CLAIM}`,
  "",
  "## Not yet",
  `- ${CLAIM}`,
  "",
].join("\n");

test("a universal claim outside ## Not yet is reported with its line number", () => {
  const path = write("claim.md", FILE);
  const result = run(path);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `${path}:8: universal claim "every": - ${CLAIM}\n`);
});

test("the same sentence under ## Not yet is not reported", () => {
  const claims = findClaims(FILE);
  assert.deepEqual(
    claims.map((c) => c.line),
    [8],
  );
  const onlyNotYet = findClaims(`# T\n\n## Not yet\n- ${CLAIM}\n`);
  assert.deepEqual(onlyNotYet, []);
});

test("a file with no claims prints nothing", () => {
  const path = write(
    "clean.md",
    "# Developer tooling conventions\n\n## Tools\n- `tools/deploy` asks for confirmation; no flag skips it.\n",
  );
  const result = run(path);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "");
});

test("a section after ## Not yet is checked again", () => {
  const claims = findClaims(`## Not yet\n- ${CLAIM}\n\n## Platforms\nAll tools run on Linux.\n`);
  assert.deepEqual(
    claims.map((c) => [c.line, c.word]),
    [[5, "all"]],
  );
});

test("front matter, fenced code, comments, inline code and team rules are skipped", () => {
  const text = [
    "---",
    "note: every key",
    "---",
    "<!-- every command",
    "always prompts -->",
    "```sh",
    "every --all",
    "```",
    "- `git add --all` stages files.",
    "New and changed tools read secrets from stdin, never from a flag value.",
    "We test them all.",
  ].join("\n");
  assert.deepEqual(findClaims(text), []);
});

test("a wrapped team rule, a code span and a fence with an info string do not hide or invent a claim", () => {
  const text = [
    "New and changed tools read secrets from environment variables, stdin or a file",
    "the caller names, never from a flag value.",
    "- `tools/lint` rejects a stray `<!--` in a doc.",
    "- `New-Release.ps1` always pushes the tag.",
    "```md",
    "```sh",
    "every line here is code",
    "```",
    "Every command prompts.",
  ].join("\n");
  assert.deepEqual(
    findClaims(text).map((c) => [c.line, c.word]),
    [
      [4, "always"],
      [9, "every"],
    ],
  );
});

test("a usage error or an unreadable file exits 2", () => {
  assert.equal(run().status, 2);
  assert.equal(run("--help").status, 2);
  assert.equal(run(join(dir, "missing.md")).status, 2);
});
