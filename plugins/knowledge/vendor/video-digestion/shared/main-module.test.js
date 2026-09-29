import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, it } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const moduleUrl = pathToFileURL(
  path.join(path.dirname(fileURLToPath(import.meta.url)), "main-module.js"),
).href;

/** A directory holding probe.mjs (prints isMainModule for itself) and runner.mjs (imports the probe). */
function fixture() {
  const dir = mkdtempSync(path.join(tmpdir(), "main-module-"));
  writeFileSync(
    path.join(dir, "probe.mjs"),
    `import { isMainModule } from ${JSON.stringify(moduleUrl)};\nconsole.log(isMainModule(import.meta.url));\n`,
  );
  writeFileSync(path.join(dir, "runner.mjs"), `await import("./probe.mjs");\n`);
  return dir;
}

function run(args) {
  const result = spawnSync(process.execPath, args, { encoding: "utf8", timeout: 20000 });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

describe("isMainModule", () => {
  it("is true when the file is run directly", () => {
    assert.equal(run([path.join(fixture(), "probe.mjs")]), "true");
  });

  it("is false when the file is imported by another entrypoint", () => {
    assert.equal(run([path.join(fixture(), "runner.mjs")]), "false");
  });

  it("is true when the entrypoint path goes through a symlink to its directory", () => {
    const link = path.join(mkdtempSync(path.join(tmpdir(), "main-module-link-")), "linked");
    symlinkSync(fixture(), link, "junction");
    assert.equal(run([path.join(link, "probe.mjs")]), "true");
  });

  it("is false when argv[1] is unset", () => {
    const probeUrl = pathToFileURL(path.join(fixture(), "probe.mjs")).href;
    assert.equal(run(["--input-type=module", "-e", `await import(${JSON.stringify(probeUrl)})`]), "false");
  });
});
