import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { main } from "./conflict-scan-refusal.mjs";

// The escalation-reason main writes, given the markers in a fresh directory
// and the download's outcome; no leg output is read.
const run = (markers, read = "success") => {
  const dir = mkdtempSync(join(tmpdir(), "conflict-scan-refusal-"));
  const scanRefused = join(dir, "scan-refused");
  mkdirSync(scanRefused);
  for (const [name, kind] of Object.entries(markers)) {
    writeFileSync(join(scanRefused, name), `${kind}\n`);
  }
  const output = join(dir, "output");
  writeFileSync(output, "");
  main({ SCAN_REFUSED_DIR: scanRefused, SCAN_REFUSED_READ: read, GITHUB_OUTPUT: output }, { log: () => {} });
  return readFileSync(output, "utf8");
};

test("the scan refusal marker alone escalates unresolved-conflict", () => {
  assert.equal(run({ "scan-refused-1.txt": "output" }), "escalation-reason=unresolved-conflict\n", "a leak-scan block");
  assert.equal(run({ "scan-refused-2.txt": "patch" }), "escalation-reason=unresolved-conflict\n", "an oversize patch");
  assert.equal(run({ "scan-refused-1-rung-up.txt": "output" }), "escalation-reason=unresolved-conflict\n");
});

test("no marker escalates nothing", () => {
  assert.equal(run({}), "escalation-reason=\n");
  assert.equal(run({ "not-a-marker.txt": "output" }), "escalation-reason=\n", "a file scanRefusal does not read");
  assert.equal(run({}, "skipped"), "escalation-reason=\n");
});

test("a failed marker download cannot rule a refusal out", () => {
  assert.equal(run({}, "failure"), "escalation-reason=unresolved-conflict\n");
});

test("GITHUB_OUTPUT is required", () => {
  assert.throws(() => main({ SCAN_REFUSED_DIR: "", SCAN_REFUSED_READ: "" }, { log: () => {} }), /GITHUB_OUTPUT is not set/);
});
