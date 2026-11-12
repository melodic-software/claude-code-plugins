import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { pathToFileURL } from "node:url";

const dir = mkdtempSync(join(tmpdir(), "run-main-"));
after(() => rmSync(dir, { recursive: true, force: true }));

const fixture = join(dir, "fixture.mjs");
writeFileSync(
  fixture,
  `import { runAsScript } from ${JSON.stringify(new URL("./run-main.mjs", import.meta.url).href)};
globalThis.runCalls = 0;
runAsScript(import.meta.url, "x", async () => {
  globalThis.runCalls++;
  if (process.env.MODE === "reject") throw new Error("boom");
  return Number(process.env.CODE);
});
`,
);

const run = (env) => spawnSync(process.execPath, [fixture], { encoding: "utf8", env: { PATH: process.env.PATH, ...env } });

test("runAsScript passes a resolved run's code through as the exit code", () => {
  for (const code of [0, 3]) {
    const result = run({ CODE: String(code) });
    assert.equal(result.status, code);
    assert.equal(result.stdout, "");
  }
});

test("runAsScript prints the labeled error line and exits 1 on a rejection", () => {
  const result = run({ MODE: "reject" });
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "::error::x failed: boom\n");
});

test("runAsScript runs nothing when the module is imported", async () => {
  await import(pathToFileURL(fixture).href);
  assert.equal(globalThis.runCalls, 0);
});
