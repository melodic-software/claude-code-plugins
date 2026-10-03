import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterAll, describe, expect, it } from "vitest";

const setupDeps = path.join(import.meta.dirname, "setup-deps.mjs");
const sandboxes = [];
afterAll(() => {
  for (const dir of sandboxes) fs.rmSync(dir, { recursive: true, force: true });
});

/** Another plugin's data directory, empty, the way a leaked CLAUDE_PLUGIN_DATA names it. */
function foreignDataDir() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "setup-deps-"));
  sandboxes.push(root);
  const dir = path.join(root, "codex-openai-codex");
  fs.mkdirSync(dir);
  return dir;
}

function runSetupDeps(args, env) {
  return spawnSync(process.execPath, [setupDeps, ...args], {
    encoding: "utf8",
    timeout: 20000,
    env: { ...process.env, ...env },
  });
}

describe("setup-deps.mjs data directory", () => {
  it("refuses an inherited CLAUDE_PLUGIN_DATA that names another plugin and writes nothing there", () => {
    const foreign = foreignDataDir();
    const result = runSetupDeps([], { CLAUDE_PLUGIN_DATA: foreign });
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('--data-dir "${CLAUDE_PLUGIN_DATA}"');
    expect(fs.readdirSync(foreign)).toEqual([]);
  });

  it("rejects an unsubstituted placeholder before creating anything", () => {
    const foreign = foreignDataDir();
    const result = runSetupDeps(["--data-dir", "<plugin-data>"], { CLAUDE_PLUGIN_DATA: foreign });
    expect(result.status).toBe(2);
    expect(result.stderr).toContain("unsubstituted placeholder");
    expect(fs.readdirSync(foreign)).toEqual([]);
  });

  it("rejects a flag it does not take", () => {
    const result = runSetupDeps(["--work-root", "/proj"], { CLAUDE_PLUGIN_DATA: foreignDataDir() });
    expect(result.status).toBe(2);
    expect(result.stderr).toContain("takes only `--data-dir <dir>`");
  });
});
