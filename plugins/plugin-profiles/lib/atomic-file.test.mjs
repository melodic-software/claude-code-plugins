import assert from "node:assert/strict";
import fs, { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { join } from "node:path";
import { test } from "node:test";
import { replaceFile } from "./atomic-file.mjs";
import { readSettings, writeSettings } from "./settings-io.mjs";
import { tempDir } from "../tests/temp.mjs";

const WINDOWS = process.platform === "win32";
const RETRIES = 5;
const BEFORE = '{\n  "enabledPlugins": {\n    "a@m": true\n  }\n}\n';
const AFTER = '{\n  "enabledPlugins": {\n    "a@m": false\n  }\n}\n';
const realRename = fs.renameSync;

function withRefusedRename(code, refusals, fn) {
  let calls = 0;
  fs.renameSync = (from, to) => {
    calls++;
    if (calls <= refusals) throw Object.assign(new Error(`${code}: refused rename '${from}' -> '${to}'`), { code });
    return realRename(from, to);
  };
  syncBuiltinESMExports();
  try {
    fn();
  } finally {
    fs.renameSync = realRename;
    syncBuiltinESMExports();
  }
  return calls;
}

function settingsFile() {
  const dir = tempDir();
  const path = join(dir, "settings.local.json");
  writeFileSync(path, BEFORE);
  return { dir, path };
}

for (const code of ["EPERM", "EBUSY", "EACCES"]) {
  test(`AC8, AC21: a rename refused twice with ${code} is retried on Windows and replaces the file; elsewhere it fails with the file unchanged`, () => {
    const { dir, path } = settingsFile();
    const calls = withRefusedRename(code, 2, () => {
      if (WINDOWS) replaceFile(path, AFTER);
      else assert.throws(() => replaceFile(path, AFTER), { code });
    });
    assert.equal(calls, WINDOWS ? 3 : 1);
    assert.equal(readFileSync(path, "utf8"), WINDOWS ? AFTER : BEFORE);
    assert.deepEqual(readdirSync(dir), ["settings.local.json"]);
  });
}

test("AC8, AC21: a settings write whose rename is always refused fails after the retries with the file unchanged and no temp file left", () => {
  const { dir, path } = settingsFile();
  const calls = withRefusedRename("EPERM", Infinity, () => {
    assert.throws(() => writeSettings(path, readSettings(path).hash, AFTER), { code: "EPERM" });
  });
  assert.equal(calls, WINDOWS ? RETRIES : 1);
  assert.equal(readFileSync(path, "utf8"), BEFORE);
  assert.deepEqual(readdirSync(dir), ["settings.local.json"]);
});

test("a rename error outside EPERM, EBUSY and EACCES is not retried on any platform", () => {
  const { dir, path } = settingsFile();
  const calls = withRefusedRename("EXDEV", Infinity, () => {
    assert.throws(() => replaceFile(path, AFTER), { code: "EXDEV" });
  });
  assert.equal(calls, 1);
  assert.equal(readFileSync(path, "utf8"), BEFORE);
  assert.deepEqual(readdirSync(dir), ["settings.local.json"]);
});
