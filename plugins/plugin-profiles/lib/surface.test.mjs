import assert from "node:assert/strict";
import { test } from "node:test";
import { detectSurface, refusal } from "./surface.mjs";

test("a cloud session allows no target, whatever its entrypoint", () => {
  const s = detectSurface({ CLAUDE_CODE_REMOTE: "true", CLAUDE_CODE_ENTRYPOINT: "cli", CLAUDECODE: "1" });
  assert.equal(s.id, "cloud");
  assert.match(refusal(s, "folder", "build"), /^plugin profiles do not apply here/);
});

test("a Desktop session inside WSL allows no target, while the CLI inside WSL allows all three", () => {
  const desktop = detectSurface({ CLAUDE_CODE_ENTRYPOINT: "claude-desktop", CLAUDECODE: "1", WSL_DISTRO_NAME: "Ubuntu" });
  assert.equal(desktop.id, "desktop-wsl");
  assert.match(refusal(desktop, "folder", "build"), /^plugin profiles do not apply here/);
  const cli = detectSurface({ CLAUDE_CODE_ENTRYPOINT: "cli", CLAUDECODE: "1", WSL_DISTRO_NAME: "Ubuntu" });
  assert.equal(refusal(cli, "session", "build"), null);
});

test("the CLI and claude -p allow all three targets", () => {
  for (const entry of ["cli", "sdk-cli"]) {
    const s = detectSurface({ CLAUDE_CODE_ENTRYPOINT: entry, CLAUDECODE: "1" });
    for (const target of ["session", "folder", "initial"]) assert.equal(refusal(s, target, "build"), null, `${entry} ${target}`);
  }
});

test("VS Code and Desktop refuse a one-session apply and offer the folder level", () => {
  for (const entry of ["claude-vscode", "claude-desktop"]) {
    const s = detectSurface({ CLAUDE_CODE_ENTRYPOINT: entry, CLAUDECODE: "1" });
    assert.match(refusal(s, "session", "build"), /--for session is not available .*apply build --for folder/);
    assert.equal(refusal(s, "folder", "build"), null);
  }
});

test("inside Claude Code with an unknown entrypoint the surface is not detected and only the folder level applies", () => {
  for (const env of [{ CLAUDECODE: "1" }, { CLAUDE_CODE_ENTRYPOINT: "something-new" }]) {
    const s = detectSurface(env);
    assert.equal(s.name, "surface not detected");
    assert.equal(refusal(s, "folder", "build"), null);
    assert.notEqual(refusal(s, "session", "build"), null);
    assert.notEqual(refusal(s, "initial", "build"), null);
  }
});

test("a terminal outside Claude Code allows a one-session apply, for the CLI it launches", () => {
  const s = detectSurface({});
  assert.equal(s.id, "terminal");
  assert.equal(refusal(s, "session", "build"), null);
});
