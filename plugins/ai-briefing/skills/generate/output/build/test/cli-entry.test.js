import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

const buildDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const script = path.join(buildDir, "emit-slides-data.js");

function run(args, env = {}) {
  return spawnSync(process.execPath, [script, ...args], {
    encoding: "utf8",
    cwd: buildDir,
    timeout: 20000,
    env: { ...process.env, ...env },
  });
}

test("importing emit-slides-data.js runs nothing", () => {
  const href = pathToFileURL(script).href;
  const result = spawnSync(
    process.execPath,
    ["--input-type=module", "-e", `await import(${JSON.stringify(href)})`],
    { encoding: "utf8", cwd: buildDir, timeout: 20000 },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "");
  assert.equal(result.stderr, "");
});

test("a missing briefing exits 1", () => {
  const missing = path.join(tmpdir(), "no-such-briefing.md");
  const result = run(["--briefing", missing, "--out", path.join(tmpdir(), "unused.js")]);
  assert.equal(result.status, 1);
  assert.match(`${result.stdout}${result.stderr}`, /ENOENT|no such file/i);
});

test("argv writes slides-data.js and formats an ASCII-arrow window", () => {
  const root = mkdtempSync(path.join(tmpdir(), "slides-"));
  const briefing = path.join(root, "briefing.md");
  const out = path.join(root, "slides-data.js");
  writeFileSync(
    briefing,
    [
      "# AI Briefing: Meeting 7",
      "",
      "Window: 2026-04-24T19:00:00Z -> 2026-05-05T20:30:00Z (~11 days)",
      "",
      "## Solstice AI",
      "",
      "### LOW",
      "",
      "- A quiet note. Source: Example, <https://example.test/note> (2026-04-25).",
      "",
    ].join("\n"),
  );
  const result = run(["--briefing", briefing, "--out", out, "--meeting-n", "7", "--date", "2026-05-08"], {
    CLAUDE_PLUGIN_DATA: root,
    CLAUDE_PROJECT_DIR: "",
    AI_BRIEFING_PROFILE: "default",
  });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  const written = readFileSync(out, "utf8");
  assert.match(written, /export const slides/);
  assert.match(written, /2026-04-24 to 2026-05-05 \(~11 days\)/);
});
