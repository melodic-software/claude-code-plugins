import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { afterAll, describe, expect, it } from "vitest";

const dir = path.dirname(fileURLToPath(import.meta.url));
const sandboxes = [];
afterAll(() => {
  for (const sandbox of sandboxes) fs.rmSync(sandbox, { recursive: true, force: true });
});

/** Another plugin's data directory, empty, the way a leaked CLAUDE_PLUGIN_DATA names it. */
function foreignDataDir() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "course-setup-deps-"));
  sandboxes.push(root);
  const foreign = path.join(root, "codex-openai-codex");
  fs.mkdirSync(foreign);
  return foreign;
}

function run(script, args, env) {
  return spawnSync(process.execPath, [path.join(dir, script), ...args], {
    encoding: "utf8",
    timeout: 20000,
    env: { ...process.env, ...env },
  });
}

describe("data directory resolution in the Bash-run entry points", () => {
  it("setup-deps refuses an inherited CLAUDE_PLUGIN_DATA naming another plugin and writes nothing there", () => {
    const foreign = foreignDataDir();
    const result = run("setup-deps.mjs", [], { CLAUDE_PLUGIN_DATA: foreign });
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('--data-dir "${CLAUDE_PLUGIN_DATA}"');
    expect(fs.readdirSync(foreign)).toEqual([]);
  });

  it("setup-deps rejects an unsubstituted placeholder before creating anything", () => {
    const foreign = foreignDataDir();
    const result = run("setup-deps.mjs", ["--data-dir", "<plugin-data>"], { CLAUDE_PLUGIN_DATA: foreign });
    expect(result.status).toBe(2);
    expect(result.stderr).toContain("unsubstituted placeholder");
    expect(fs.readdirSync(foreign)).toEqual([]);
  });

  it("run.mjs hands the child the --data-dir value, not an inherited one naming another plugin", () => {
    const foreign = foreignDataDir();
    const knowledge = path.join(path.dirname(foreign), "knowledge-melodic-software");
    const dest = path.join(path.dirname(foreign), "course");
    const stub = pathToFileURL(path.join(dir, "test-support", "register-playwright-stub.mjs")).href;
    const result = run(
      "run.mjs",
      ["--data-dir", knowledge, "build-course-json.js", "--course-url", "https://example.test/courses/enrolled/1", "--output-dir", dest],
      { CLAUDE_PLUGIN_DATA: foreign, NODE_OPTIONS: `--import ${stub}` },
    );
    expect(result.stderr).toContain("playwright stub: chromium.launch blocked in tests");
    expect(fs.existsSync(path.join(knowledge, "auth"))).toBe(true);
    expect(fs.readdirSync(foreign)).toEqual([]);
  });

  it("run.mjs drops an inherited value naming another plugin when no flag is given", () => {
    const foreign = foreignDataDir();
    const home = path.dirname(foreign);
    const dest = path.join(home, "course");
    const stub = pathToFileURL(path.join(dir, "test-support", "register-playwright-stub.mjs")).href;
    const result = run(
      "run.mjs",
      ["build-course-json.js", "--course-url", "https://example.test/courses/enrolled/1", "--output-dir", dest],
      { CLAUDE_PLUGIN_DATA: foreign, HOME: home, USERPROFILE: home, NODE_OPTIONS: `--import ${stub}` },
    );
    expect(result.stderr).toContain("playwright stub: chromium.launch blocked in tests");
    expect(fs.readdirSync(foreign)).toEqual([]);
    expect(fs.existsSync(path.join(home, ".claude", "course-digest", "auth"))).toBe(true);
  });

  it("run.mjs rejects an unsubstituted placeholder instead of launching the script", () => {
    const result = run("run.mjs", ["--data-dir", "${CLAUDE_PLUGIN_DATA}", "validate-extraction.js"], {});
    expect(result.status).toBe(2);
    expect(result.stderr).toContain("unsubstituted placeholder");
  });
});
