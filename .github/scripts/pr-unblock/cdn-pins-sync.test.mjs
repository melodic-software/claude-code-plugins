import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";

const CLI = fileURLToPath(new URL("./cdn-pins-sync.mjs", import.meta.url));
const PINS = "lib/cdn-pins/pins.json";
const TARGET = "docs/view.md";
const OTHER = "docs/other.md";
const record = (version) => `${JSON.stringify({ packages: { x: { version } }, targets: [{ path: TARGET }, { path: OTHER }] })}\n`;
const REQUEST = { script: "", manifest: "{}", lock: "{}", files: { [PINS]: record("1.0.0"), [TARGET]: "x@1.0.0\n", [OTHER]: "y@1.0.0\n" } };

function run(t, results) {
  const dir = tempDir("cdn-pins-sync-cli-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, "request.json"), JSON.stringify(REQUEST));
  const resultDir = join(dir, "result");
  if (results) mkdirSync(resultDir);
  for (const [path, text] of Object.entries(results ?? {})) {
    mkdirSync(dirname(join(resultDir, path)), { recursive: true });
    if (text === null) symlinkSync("/dev/null", join(resultDir, path));
    else writeFileSync(join(resultDir, path), text);
  }
  const patch = join(dir, "patch.diff");
  const proc = spawnSync(process.execPath, [CLI, "patch", join(dir, "request.json"), resultDir, patch], { encoding: "utf8" });
  return { status: proc.status, stderr: proc.stderr, patch: existsSync(patch) ? readFileSync(patch, "utf8") : null };
}

test("no result directory, or results equal to the request, exit 1 and write no patch", (t) => {
  assert.deepEqual(run(t, null), { status: 1, stderr: "", patch: null });
  assert.deepEqual(run(t, {}), { status: 1, stderr: "", patch: null });
  assert.deepEqual(run(t, { [PINS]: REQUEST.files[PINS], [TARGET]: REQUEST.files[TARGET] }), { status: 1, stderr: "", patch: null });
});

test("changed results exit 0 with a patch of those files alone", (t) => {
  const got = run(t, { [PINS]: record("2.0.0"), [TARGET]: "x@2.0.0\n", [OTHER]: REQUEST.files[OTHER] });
  assert.equal(got.status, 0, got.stderr);
  assert.match(got.patch, /^diff --git a\/lib\/cdn-pins\/pins\.json b\/lib\/cdn-pins\/pins\.json$/m);
  assert.match(got.patch, /^-x@1\.0\.0\n\+x@2\.0\.0$/m);
  assert.deepEqual(got.patch.match(/^diff --git .*$/gm), [`diff --git a/${PINS} b/${PINS}`, `diff --git a/${TARGET} b/${TARGET}`]);
});

test("a result that is not a regular file fails the command, and a bad usage throws", (t) => {
  const link = run(t, { [TARGET]: null });
  assert.notEqual(link.status, 0);
  assert.match(link.stderr, /docs\/view\.md is not a regular sync result/);
  assert.equal(link.patch, null);
  const usage = spawnSync(process.execPath, [CLI, "sync"], { encoding: "utf8" });
  assert.notEqual(usage.status, 0);
  assert.match(usage.stderr, /usage: cdn-pins-sync\.mjs patch/);
});
