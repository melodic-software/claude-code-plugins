import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { test } from "node:test";

const run = (body) =>
  spawnSync(process.execPath, ["--input-type=module", "-e", `import { tempDir } from ${JSON.stringify(new URL("./test-tmp.mjs", import.meta.url).href)}; ${body}`], { encoding: "utf8" });

test("a folder tempDir made is gone once the process exits", () => {
  const run1 = run('process.stdout.write(tempDir("kept-check-"));');
  assert.equal(run1.status, 0, run1.stderr);
  assert.match(run1.stdout, /kept-check-/);
  assert.equal(existsSync(run1.stdout), false);
});

test("a folder is removed when the process fails", () => {
  const failed = run('process.stdout.write(tempDir("failed-check-")); process.exitCode = 1;');
  assert.equal(failed.status, 1);
  assert.equal(existsSync(failed.stdout), false);
});
