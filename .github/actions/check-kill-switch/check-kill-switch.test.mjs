import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { checkKillSwitch, writeOutputs } from "./check-kill-switch.mjs";
import { readOutputs } from "./fixtures/read-outputs.mjs";

const SCRIPT = fileURLToPath(new URL("./check-kill-switch.mjs", import.meta.url));

function runCli(env) {
  const dir = mkdtempSync(path.join(tmpdir(), "kill-switch-"));
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    const result = spawnSync(process.execPath, [SCRIPT], {
      env: { PATH: process.env.PATH, GITHUB_OUTPUT: outputPath, ...env },
      encoding: "utf8",
    });
    return { status: result.status, outputs: readOutputs(readFileSync(outputPath, "utf8")) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("proceeds only when the switch reads exactly false", () => {
  assert.deepEqual(checkKillSwitch("false"), { proceed: "true", reason: "ok" });
});

for (const [label, value] of [
  ["unset", undefined],
  ["empty", ""],
  ["true", "true"],
  ["FALSE in capitals", "FALSE"],
  ["false with whitespace", " false"],
]) {
  test(`stops when the switch is ${label}`, () => {
    assert.deepEqual(checkKillSwitch(value), { proceed: "false", reason: "kill-switch" });
  });
}

test("CLI writes proceed=true for exactly false and exits 0", () => {
  const { status, outputs } = runCli({ KILL_SWITCH_VALUE: "false" });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "true", reason: "ok" });
});

test("CLI writes proceed=false when the variable is unset and exits 0", () => {
  const { status, outputs } = runCli({});
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch" });
});

test("output values cannot inject a second output line", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "kill-switch-"));
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    writeOutputs({ "head-ref": "a\nproceed=true" }, outputPath);
    assert.deepEqual(readOutputs(readFileSync(outputPath, "utf8")), {
      "head-ref": "a\nproceed=true",
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
