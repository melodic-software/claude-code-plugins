// grok-availability — resolve + probe

import { strict as assert } from "node:assert";
import { chmodSync, mkdirSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import { probeGrokAvailability, resolveGrokBin } from "./lib/grok-availability.js";
import { writelnStdout } from "./lib/terminal.js";

let passed = 0;
let failed = 0;
const test = (name, fn) => {
  try {
    fn();
    writelnStdout(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    writelnStdout(`  ✗ ${name}\n    ${e.message}`);
    failed++;
  }
};

test("resolveGrokBin returns null for missing explicit path", () => {
  assert.equal(resolveGrokBin("/nonexistent/grok-binary"), null);
});

test("probeGrokAvailability not_installed when grok missing", () => {
  const probe = probeGrokAvailability({ grokBin: "/nonexistent/grok-binary" });
  assert.equal(probe.ready, false);
  assert.equal(probe.reason, "not_installed");
  assert.ok(probe.message.includes("not installed"));
});

test("probeGrokAvailability not_authenticated without auth file", () => {
  const tmp = path.join(os.tmpdir(), `grok-avail-test-${Date.now()}`);
  mkdirSync(tmp, { recursive: true });
  const fakeBin =
    process.platform === "win32" ? path.join(tmp, "grok.cmd") : path.join(tmp, "grok");
  if (process.platform === "win32") {
    writeFileSync(fakeBin, "@echo off\r\necho grok 0.0.1 (test)\r\nexit /b 0\r\n", "utf-8");
  } else {
    writeFileSync(
      fakeBin,
      `#!/bin/sh
echo "grok 0.0.1 (test)"
exit 0
`,
      "utf-8",
    );
    chmodSync(fakeBin, 0o755);
  }

  const probe = probeGrokAvailability({
    grokBin: fakeBin,
    authPath: path.join(tmp, "missing-auth.json"),
  });
  assert.equal(probe.available, true);
  assert.equal(probe.ready, false);
  assert.equal(probe.reason, "not_authenticated");
});

writelnStdout(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
