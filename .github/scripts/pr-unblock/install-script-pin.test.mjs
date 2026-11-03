import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { allowScriptsRefusal, installScriptPinRefusal, packageJsonRefusal } from "./dependency-classify.mjs";
import { lockedVersion, main, movePin, unifiedDiff } from "./install-script-pin.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const CLI = "@anthropic-ai/claude-code";

const manifest = (version, allowScripts) =>
  `${JSON.stringify(
    {
      name: "ci",
      private: true,
      devDependencies: { [CLI]: version, "@biomejs/biome": "2.6.4" },
      overrides: { glob: "14.0.3" },
      allowScripts,
    },
    null,
    2,
  )}\n`;

const lock = (version) =>
  JSON.stringify({ lockfileVersion: 3, packages: { "": { name: "ci" }, [`node_modules/${CLI}`]: { version }, "node_modules/esbuild": { version: "0.25.0" } } });

test("the lockfile names a newer version: the pin moves to it and nothing else changes", () => {
  const before = manifest("2.1.317", { [`${CLI}@2.1.316`]: true });
  const moved = movePin(before, lock("2.1.317"));
  assert.equal(moved.from, "2.1.316");
  assert.equal(moved.to, "2.1.317");
  assert.equal(moved.text, before.replace(`"${CLI}@2.1.316"`, `"${CLI}@2.1.317"`));
  assert.deepEqual(JSON.parse(moved.text).allowScripts, { [`${CLI}@2.1.317`]: true });
  assert.equal(installScriptPinRefusal(before, moved.text), null);
  assert.equal(packageJsonRefusal(before, moved.text), null, "a lane fix that moves only the pin is admitted");
});

test("the pin already names the locked version: nothing changes", () => {
  assert.equal(movePin(manifest("2.1.317", { [`${CLI}@2.1.317`]: true }), lock("2.1.317")), null);
});

test("no pin for the package: nothing is added", () => {
  assert.equal(movePin(manifest("2.1.317", { "esbuild@0.25.0": true }), lock("2.1.317")), null);
  assert.equal(movePin(manifest("2.1.317", undefined), lock("2.1.317")), null);
});

test("other packages' pins keep their keys and values", () => {
  const before = manifest("2.1.317", { "esbuild@0.25.0": true, [`${CLI}@2.1.316`]: true, "sharp@0.33.0": false });
  const after = JSON.parse(movePin(before, lock("2.1.317")).text).allowScripts;
  assert.deepEqual(after, { "esbuild@0.25.0": true, [`${CLI}@2.1.317`]: true, "sharp@0.33.0": false });
  assert.deepEqual(Object.keys(after), ["esbuild@0.25.0", `${CLI}@2.1.317`, "sharp@0.33.0"], "key order holds");
});

test("a lockfile with no entry for the package moves nothing", () => {
  assert.equal(lockedVersion(JSON.stringify({ packages: {} })), null);
  assert.equal(movePin(manifest("2.1.317", { [`${CLI}@2.1.316`]: true }), JSON.stringify({ packages: {} })), null);
});

test("a lockfile that disagrees with the manifest's exact version throws instead of writing a pin the gate refuses", () => {
  assert.throws(() => movePin(manifest("2.1.317", { [`${CLI}@2.1.316`]: true }), lock("2.1.318")), /allow-scripts-version/);
});

test("the gate admits only the exact pin move", () => {
  const old = JSON.parse(manifest("2.1.317", { [`${CLI}@2.1.316`]: true, "esbuild@0.25.0": true }));
  const withScripts = (allowScripts) => ({ ...old, allowScripts });
  const cases = [
    [{ [`${CLI}@2.1.318`]: true, "esbuild@0.25.0": true }, "allow-scripts-version", "a version the manifest does not pin"],
    [{ [CLI]: true, "esbuild@0.25.0": true }, "allow-scripts-package", "a name-only approval"],
    [{ [`${CLI}@*`]: true, "esbuild@0.25.0": true }, "allow-scripts-version", "a wildcard"],
    [{ [`${CLI}@2.1.316`]: true, "esbuild@0.25.1": true }, "allow-scripts-package", "another package's pin"],
    [{ [`${CLI}@2.1.317`]: true, "esbuild@0.25.0": false }, "allow-scripts-other-key", "another pin's value"],
    [{ [`${CLI}@2.1.317`]: false, "esbuild@0.25.0": true }, "allow-scripts-value", "the moved pin's value"],
    [{ [`${CLI}@2.1.317`]: true }, "allow-scripts-not-one-pin", "a pin dropped"],
    [{ [`${CLI}@2.1.317`]: true, "esbuild@0.25.0": true, "sharp@1.0.0": true }, "allow-scripts-not-one-pin", "a pin added"],
  ];
  for (const [allowScripts, reason, what] of cases) {
    assert.equal(allowScriptsRefusal(old, withScripts(allowScripts)), reason, what);
    assert.equal(packageJsonRefusal(JSON.stringify(old), JSON.stringify(withScripts(allowScripts))), "package-json-key:allowScripts", what);
  }
  const ranged = { ...old, devDependencies: { ...old.devDependencies, [CLI]: "^2.1.317" }, allowScripts: { [`${CLI}@2.1.317`]: true, "esbuild@0.25.0": true } };
  assert.equal(allowScriptsRefusal(old, ranged), "allow-scripts-version", "a range pins no version");
});

test("the pin rule refuses any other key the patch changes", () => {
  const before = manifest("2.1.317", { [`${CLI}@2.1.316`]: true });
  const after = manifest("2.1.317", { [`${CLI}@2.1.317`]: true }).replace('"14.0.3"', '"14.0.4"');
  assert.equal(installScriptPinRefusal(before, after), "package-json-key:overrides");
});

test("the unified diff applies with git and changes one line", () => {
  const dir = tempDir("install-script-pin-");
  execFileSync("git", ["init", "-q", dir]);
  const before = manifest("2.1.317", { [`${CLI}@2.1.316`]: true });
  writeFileSync(join(dir, "package.json"), before);
  const moved = movePin(before, lock("2.1.317"));
  const diff = unifiedDiff("package.json", before, moved.text);
  assert.equal(diff.split("\n").filter((line) => /^[-+][^-+]/.test(line)).length, 2);
  writeFileSync(join(dir, "patch.diff"), diff);
  execFileSync("git", ["-C", dir, "apply", "patch.diff"]);
  assert.equal(readFileSync(join(dir, "package.json"), "utf8"), moved.text);
  assert.equal(unifiedDiff("package.json", before, before), "");
});

test("check fails while the pin and the lockfile disagree, and passes once they match", () => {
  const dir = tempDir("install-script-pin-");
  writeFileSync(join(dir, "package.json"), manifest("2.1.317", { [`${CLI}@2.1.316`]: true }));
  writeFileSync(join(dir, "package-lock.json"), lock("2.1.317"));
  const lines = [];
  assert.equal(main(["check", dir], { log: (line) => lines.push(line) }), 1);
  assert.match(lines[0], /^::error file=package\.json::allowScripts approves @anthropic-ai\/claude-code@2\.1\.316, but package-lock\.json installs 2\.1\.317/);
  writeFileSync(join(dir, "package.json"), manifest("2.1.317", { [`${CLI}@2.1.317`]: true }));
  assert.equal(main(["check", dir], { log: () => {} }), 0);
});

test("the repository's own package.json pin matches its lockfile", () => {
  assert.equal(main(["check", join(import.meta.dirname, "../../..")], { log: () => {} }), 0);
});
