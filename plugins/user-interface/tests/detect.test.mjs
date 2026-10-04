import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const DETECT = join(dirname(fileURLToPath(import.meta.url)), "../scripts/detect.mjs");
const detect = (...args) => JSON.parse(execFileSync(process.execPath, [DETECT, ...args], { encoding: "utf8" }));

test("prints project signals and installed tools as JSON", () => {
  const out = detect();
  assert.equal(typeof out.project, "object");
  assert.ok(Array.isArray(out.installed));
});
