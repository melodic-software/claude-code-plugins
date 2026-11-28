import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import process from "node:process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { DEFAULT_OPEN_CAP, openCap, planFiling } from "./filing-plan.mjs";

const SCRIPT = fileURLToPath(new URL("./filing-plan.mjs", import.meta.url));
const label = "source: improvement-find";

test("the open cap defaults to 5, a team layer sets it, and a personal layer only lowers it", () => {
  assert.deepEqual(openCap({}), { cap: DEFAULT_OPEN_CAP, source: "default", warnings: [] });
  assert.deepEqual(openCap({ team: 2 }), { cap: 2, source: "team", warnings: [] });
  assert.deepEqual(openCap({ team: 3, personal: 1 }), { cap: 1, source: "personal", warnings: [] });
  assert.deepEqual(openCap({ team: 5, user: 1 }), { cap: 1, source: "user", warnings: [] }, "a lower userConfig value lowers the cap");
  assert.deepEqual(openCap({ team: 5, user: 2, personal: 3 }).cap, 2, "the effective cap is the smallest of the three");
  const raised = openCap({ team: 2, personal: 9 });
  assert.equal(raised.cap, 2);
  assert.match(raised.warnings[0], /only lowers it/);
  const bad = openCap({ team: -1, personal: "4" });
  assert.equal(bad.cap, DEFAULT_OPEN_CAP);
  assert.equal(bad.warnings.length, 2);
});

test("filing stops at the label's room, skips a title the label already holds whatever its case or spacing, and files a repeat once", () => {
  const plan = planFiling({ label, labelExists: true, cap: 5, open: 3, existingTitles: ["deepen  MODULE 2"], candidates: ["Deepen module 1", "Deepen module 2", "Deepen module 1", "Deepen module 3", "Deepen module 4"] });
  assert.deepEqual(plan.file, [0, 3]);
  assert.deepEqual(plan.skipped.map((entry) => entry.why), [
    "an item with this title already carries `source: improvement-find`",
    "an item with this title already carries `source: improvement-find`",
    "the open `source: improvement-find` items reached the cap of 5",
  ]);
  assert.equal(plan.stop, "open-cap");
});

test("a run cap below the room stops filing first", () => {
  const plan = planFiling({ label, labelExists: true, cap: 5, open: 0, existingTitles: [], candidates: ["a", "b", "c"], runCap: 2 });
  assert.deepEqual(plan.file, [0, 1]);
  assert.match(plan.skipped[0].why, /run cap of 2/);
  assert.equal(plan.stop, null);
});

test("a request missing or misstating a field files nothing: the plan throws, and the command exits 2", () => {
  const good = { label, labelExists: true, cap: 5, open: 0, existingTitles: [], candidates: ["a", "b", "c", "d", "e", "f"] };
  for (const [name, bad] of [
    ["no open", { ...good, open: undefined }],
    ["open as text", { ...good, open: "0" }],
    ["a null run cap", { ...good, runCap: null }],
    ["a negative run cap", { ...good, runCap: -1 }],
    ["no labelExists", { ...good, labelExists: undefined }],
    ["candidates not a list", { ...good, candidates: "a" }],
    ["no existingTitles", { ...good, existingTitles: undefined }],
  ]) {
    assert.throws(() => planFiling(bad), Error, name);
  }
  assert.throws(() => execFileSync(process.execPath, [SCRIPT], { input: JSON.stringify({ label, labelExists: true, existingTitles: [], candidates: ["a"] }), stdio: "pipe" }), (error) => error.status === 2);
  assert.throws(() => execFileSync(process.execPath, [SCRIPT], { input: JSON.stringify({ label, labelExists: true, open: 0, candidates: ["Deepen module 1"] }), stdio: "pipe" }), (error) => error.status === 2, "a request without existingTitles cannot skip the repeat check");
});

test("a missing label files nothing, since neither caller creates one", () => {
  const plan = planFiling({ label, labelExists: false, cap: 5, open: 0, existingTitles: [], candidates: ["a"] });
  assert.deepEqual([plan.file, plan.stop], [[], "label-missing"]);
});

test("the command reads one request on stdin and prints the cap and the plan", () => {
  const out = JSON.parse(execFileSync(process.execPath, [SCRIPT], { input: JSON.stringify({ label, labelExists: true, team: 2, personal: 1, open: 0, existingTitles: [], candidates: ["a", "b"] }), encoding: "utf8" }));
  assert.deepEqual([out.cap, out.source, out.file], [1, "personal", [0]]);
  const user = JSON.parse(execFileSync(process.execPath, [SCRIPT], { input: JSON.stringify({ label, labelExists: true, team: 5, user: 1, open: 0, existingTitles: [], candidates: ["a", "b", "c"], runCap: 3 }), encoding: "utf8" }));
  assert.deepEqual([user.cap, user.file], [1, [0]], "Codex's case: userConfig 1, team 5, run cap 3 files one item");
  assert.throws(() => execFileSync(process.execPath, [SCRIPT], { input: "not json", stdio: "pipe" }), (error) => error.status === 2);
});

test("the command still prints its plan when run through a symlinked plugin path", () => {
  const dir = mkdtempSync(join(tmpdir(), "improvement-filing-plan-"));
  try {
    const link = join(dir, "scripts");
    symlinkSync(dirname(SCRIPT), link);
    const out = JSON.parse(execFileSync(process.execPath, [join(link, "filing-plan.mjs")], { input: JSON.stringify({ label, labelExists: true, open: 0, existingTitles: [], candidates: ["a"] }), encoding: "utf8" }));
    assert.deepEqual(out.file, [0]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a cap layer that is not a non-negative integer makes the command exit 2, so nothing is filed", () => {
  for (const layer of ["team", "user", "personal"]) {
    assert.throws(
      () => execFileSync(process.execPath, [SCRIPT], { input: JSON.stringify({ label, labelExists: true, open: 0, existingTitles: [], candidates: ["a"], [layer]: "2" }), stdio: "pipe" }),
      (error) => error.status === 2,
      layer,
    );
  }
});
