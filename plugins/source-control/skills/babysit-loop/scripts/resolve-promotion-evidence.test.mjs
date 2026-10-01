#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const HELPER = join(dirname(fileURLToPath(import.meta.url)), "resolve-promotion-evidence.mjs");
const CELLS = ["C2-auto-merge", "C3-auto-merge", "C3-ai-review-blocking"];

const base = realpathSync(mkdtempSync(join(tmpdir(), "resolve-promotion-evidence-")));
after(() => rmSync(base, { recursive: true, force: true }));
const checkout = join(base, "checkout");
const ops = join(base, "ops");
mkdirSync(checkout);
mkdirSync(join(ops, "probe"), { recursive: true });
const surfaces = { binding: join(ops, "binding.json"), evidence: join(ops, "evidence.json"), root: join(ops, "probe") };
writeFileSync(surfaces.binding, "{}");
writeFileSync(surfaces.evidence, "[]");

let stubCount = 0;
// A stub checker that exits 9 unless it got exactly the bootstrap argv.
function stub(stdout, exitCode = 0, dir = ops) {
  stubCount += 1;
  const path = join(dir, `checker-${stubCount}.mjs`);
  const expected = [surfaces.binding, "--evidence", surfaces.evidence, "--probe-evidence-root", surfaces.root];
  writeFileSync(
    path,
    `if (JSON.stringify(process.argv.slice(2)) !== ${JSON.stringify(JSON.stringify(expected))}) process.exit(9);
process.stdout.write(${JSON.stringify(stdout)});
process.exit(${exitCode});
`,
  );
  return path;
}

function runHelper(checker, overrides = {}) {
  const args = {
    binding: surfaces.binding,
    "probe-evidence-root": surfaces.root,
    evidence: surfaces.evidence,
    checkout,
    checker,
    ...overrides,
  };
  const argv = Object.entries(args).flatMap(([key, value]) => [`--${key}`, value]);
  const run = spawnSync(process.execPath, [HELPER, ...argv], { encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  return JSON.parse(run.stdout);
}

function assertFailClosed(result, reasonPattern) {
  assert.match(result.failClosedReason, reasonPattern);
  for (const cell of CELLS) assert.deepEqual(result.cells[cell], { bound: null, effective: "unpromoted", line: null });
}

const GOOD_OUTPUT = [
  "Security binding OK: binding.json",
  "- some verdict",
  "Effective promotion state (evaluation mode):",
  "- C2-auto-merge: bound promoted -> effective promoted",
  "- C3-auto-merge: bound unpromoted -> effective unpromoted",
  "",
].join("\n");

test("complete bootstrap reports the printed cells and leaves an unprinted cell unpromoted", () => {
  const result = runHelper(stub(GOOD_OUTPUT));
  assert.equal(result.failClosedReason, null);
  assert.equal(result.source, surfaces.evidence);
  assert.deepEqual(result.cells["C2-auto-merge"], {
    bound: "promoted",
    effective: "promoted",
    line: "C2-auto-merge: bound promoted -> effective promoted",
  });
  assert.equal(result.cells["C3-auto-merge"].effective, "unpromoted");
  assert.deepEqual(result.cells["C3-ai-review-blocking"], { bound: null, effective: "unpromoted", line: null });
});

test("checker exiting 1 fails closed", () => {
  assertFailClosed(runHelper(stub(GOOD_OUTPUT, 1)), /checker exited 1/);
});

test("relative path fails closed", () => {
  assertFailClosed(runHelper(stub(GOOD_OUTPUT), { binding: "ops/binding.json" }), /--binding .* not an absolute path/);
});

test("bootstrap path inside the checkout fails closed", () => {
  const inside = join(checkout, "evidence.json");
  writeFileSync(inside, "[]");
  assertFailClosed(runHelper(stub(GOOD_OUTPUT), { evidence: inside }), /--evidence .* is inside/);
});

test("checker inside the checkout fails closed", () => {
  assertFailClosed(runHelper(stub(GOOD_OUTPUT, 0, checkout)), /--checker .* is inside/);
});

test("missing binding file fails closed", () => {
  assertFailClosed(runHelper(stub(GOOD_OUTPUT), { binding: join(ops, "absent.json") }), /--binding .* cannot be resolved/);
});

test("garbled checker output fails closed", () => {
  const garbled = GOOD_OUTPUT.replace("effective promoted", "effective maybe");
  assertFailClosed(runHelper(stub(garbled)), /did not parse/);
  assertFailClosed(runHelper(stub("Security binding OK: binding.json\n")), /no 'Effective promotion state' block/);
});
