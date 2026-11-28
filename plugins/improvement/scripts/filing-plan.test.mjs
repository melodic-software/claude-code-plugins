import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
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
  const plan = planFiling({ label, labelExists: true, cap: 5, open: 0, candidates: ["a", "b", "c"], runCap: 2 });
  assert.deepEqual(plan.file, [0, 1]);
  assert.match(plan.skipped[0].why, /run cap of 2/);
  assert.equal(plan.stop, null);
});

test("a missing label files nothing, since neither caller creates one", () => {
  const plan = planFiling({ label, labelExists: false, cap: 5, open: 0, candidates: ["a"] });
  assert.deepEqual([plan.file, plan.stop], [[], "label-missing"]);
});

test("the command reads one request on stdin and prints the cap and the plan", () => {
  const out = JSON.parse(execFileSync(process.execPath, [SCRIPT], { input: JSON.stringify({ label, labelExists: true, team: 2, personal: 1, open: 0, candidates: ["a", "b"] }), encoding: "utf8" }));
  assert.deepEqual([out.cap, out.source, out.file], [1, "personal", [0]]);
  assert.throws(() => execFileSync(process.execPath, [SCRIPT], { input: "not json", stdio: "pipe" }), (error) => error.status === 2);
});
