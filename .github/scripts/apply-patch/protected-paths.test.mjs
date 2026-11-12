import assert from "node:assert/strict";
import { test } from "node:test";

import { PATH_RULES, PROTECTED_REFUSALS, segments } from "./protected-paths.mjs";

const claudeProtected = (path) => PATH_RULES["claude-protected"](segments(path));

// The cases come from https://code.claude.com/docs/en/permission-modes#protected-paths
// and from what Claude Code 2.1.322 denied under dontAsk below the root.
test("claude-protected refuses Claude Code's protected directories and files at any depth", () => {
  for (const path of [
    ".claude/rules/a.md",
    ".claude/hooks/hook-telemetry-sink.sh",
    ".claude/settings.local.json",
    "plugins/x/.claude/source-control.md",
    "plugins/x/.claude/agent-memory/a.md",
    ".claude/agent-memory/a.txt",
    ".claude/x/worktrees/a.txt",
    ".git/config",
    ".config/git/ignore",
    "a/.config/git/attributes",
    ".vscode/settings.json",
    "plugins/x/.idea/a.xml",
    ".husky/pre-commit",
    ".cargo/config.toml",
    ".devcontainer/devcontainer.json",
    ".yarn/releases/yarn.cjs",
    ".mvn/wrapper/maven-wrapper.properties",
    "lefthook.yml",
    "plugins/x/lefthook.yaml",
    ".lefthook.yml",
    ".mcp.json",
    "plugins/miro/.mcp.json",
    "plugins/x/extraction/.npmrc",
    ".gitconfig",
    ".bashrc",
    ".envrc",
    ".pre-commit-config.yaml",
    ".github/standards/pyright/pyrightconfig.json",
    "gradle/wrapper/gradle-wrapper.properties",
    "bunfig.toml",
    ".claude.json",
    ".devcontainer.json",
    ".Claude/Rules/A.md",
    "a/../.claude/rules/a.md",
    ".claude",
    ".claude/",
    ".claude/hooks/",
    "plugins/x/.claude",
    ".vscode",
    ".vscode/",
    ".git/",
    ".config/git",
    ".config/git/",
    "a/.husky/",
  ]) {
    assert.equal(claudeProtected(path), true, path);
  }
});

test("claude-protected keeps .claude/worktrees/ at any depth, root agent-memory Markdown and its directory, and every other path", () => {
  for (const path of [
    ".claude/worktrees/x",
    ".claude/worktrees/feature/src/a.mjs",
    "plugins/x/.claude/worktrees/a.txt",
    ".claude/agent-memory/a.md",
    ".claude/agent-memory/reviewer/notes.md",
    ".claude/agent-memory-local/reviewer/notes.md",
    ".claude-plugin/plugin.json",
    "plugins/x/.claude-plugin/plugin.json",
    "CLAUDE.md",
    ".config/gitx/a",
    "docs/lefthook.yml.md",
    "lefthook-local.yml",
    ".gitmodules",
    "plugins/x/hooks/hooks.json",
    "src/git/a.mjs",
    "README.md",
    ".claude/worktrees/",
    ".claude/agent-memory/",
    ".config",
    ".config/",
    ".config/gitx/",
    ".vscodex/",
    "docs/vscode/",
    "plugins/",
  ]) {
    assert.equal(claudeProtected(path), false, path);
  }
});

test("claude-protected is optional and refuses as a protected path", () => {
  assert.equal(PROTECTED_REFUSALS["claude-protected"].kind, "protected-path");
  assert.equal(PROTECTED_REFUSALS["claude-protected"].optional, true);
  assert.equal(PROTECTED_REFUSALS["claude-protected"].test({ path: ".claude/rules/a.md" }), true);
  assert.equal(PROTECTED_REFUSALS["claude-protected"].test({ path: ".claude/worktrees/a.md" }), false);
});

// A merge or shared-copy patch carries the base's own changes, so a rename into
// a Claude Code protected path stays pushable where only the universal rules apply.
test("rename-into-refused ignores claude-protected and still reads the universal rules", () => {
  const rename = (path) => PROTECTED_REFUSALS["rename-into-refused"].test({ path, renamedFrom: "a.md" });
  assert.equal(rename(".claude/rules/a.md"), false);
  assert.equal(rename("lefthook.yml"), false);
  assert.equal(rename(".github/workflows/a.yml"), true);
  assert.equal(rename("a/.gitmodules"), true);
});
