import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../../lib/test-tmp.mjs";
import { countEntries, listEntries, partName } from "./count-entries.mjs";

const SCRIPT = fileURLToPath(new URL("./count-entries.mjs", import.meta.url));

/** A hub with a part feature, a module with one sub-feature, a legacy feature file and an index-shaped line inside a fence, which is not an index line. */
function fixtureHub() {
  const dir = tempDir("count-entries-");
  const write = (rel, lines) => {
    mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
    writeFileSync(path.join(dir, rel), `${lines.join("\n")}\n`);
  };
  write("SKILL.md", [
    "## Features",
    "",
    "- alpha | features/alpha/README.md | entry points: 2 | sources: a/**",
    "- mod | features/mod/README.md | entry points: 3 | sources: m/**",
    "```",
    "- fenced | features/fenced/README.md | entry points: 9 | sources: f/**",
    "```",
    "- legacy | features/legacy.md | entry points: 1 | sources: l/**",
  ]);
  write("features/alpha/README.md", [
    "## Parts",
    "",
    "- `one`: the first part.",
    "- **P2.** the second part.",
    "- three: the third part.",
    "- A line that names no part.",
    "",
    "## Entry points",
    "",
    "- slash command | driven",
    "- plain words | not driven: no plain-words entry",
  ]);
  write("features/mod/README.md", ["## Sub-features", "", "- inner | features/mod/inner/README.md | entry points: 3 | sources: m/**"]);
  write("features/mod/inner/README.md", ["## Parts", "", "none", "", "## Entry points", "", "- one | driven", "- two | driven", "- three | driven"]);
  write("features/fenced/README.md", ["## Entry points", "", "- one | driven"]);
  write("features/legacy.md", ["## Parts", "", "- `solo`: the only part.", "", "## Entry points", "", "- one: driven"]);
  return path.join(dir, "SKILL.md");
}

test("a Parts line names its leading code span, bold id or word before a colon, and nothing else", () => {
  assert.equal(partName("- `run-e2e`: drives the app."), "run-e2e");
  assert.equal(partName("- **P1.** the first."), "P1");
  assert.equal(partName("1. range: a range."), "range");
  assert.equal(partName("- A sentence with no id."), "");
  assert.equal(partName("not a list item: x"), "");
});

test("under part each named part is an entry, a module stands for its sub-features, and a fence hides an index line", () => {
  const entries = listEntries(fixtureHub(), "part");
  assert.deepEqual(
    entries.map((e) => [e.id, e.part, e.rows]),
    [
      ["alpha/one", "one", 2],
      ["alpha/P2", "P2", 2],
      ["alpha/three", "three", 2],
      ["mod/inner", null, 3],
      ["legacy/solo", "solo", 1],
    ],
  );
  assert.deepEqual(countEntries(entries, [], 40), { listed: 5, kept: 5, capped: 0, rows: 10, not_in_map: [] });
});

test("under feature each feature is one entry", () => {
  const entries = listEntries(fixtureHub(), "feature");
  assert.deepEqual(entries.map((e) => e.id), ["alpha", "mod/inner", "legacy"]);
  assert.deepEqual(countEntries(entries, [], 2), { listed: 3, kept: 2, capped: 1, rows: 6, not_in_map: [] });
});

test("features= keeps a named part or every part of a named feature, the cap keeps the first, and an unknown id is not in the map", () => {
  const entries = listEntries(fixtureHub(), "part");
  assert.deepEqual(countEntries(entries, ["alpha/P2", "legacy", "nope"], 1), { listed: 2, kept: 1, capped: 1, rows: 3, not_in_map: ["nope"] });
});

test("the CLI prints the counts and refuses a bad unit or cap", () => {
  const run = (...args) => spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8" });
  const hub = fixtureHub();
  const ok = run("--hub", hub, "--unit", "part", "--features", "alpha", "--max", "2");
  assert.equal(ok.status, 0, ok.stderr);
  assert.deepEqual(JSON.parse(ok.stdout), { unit: "part", listed: 3, kept: 2, capped: 1, rows: 6, not_in_map: [] });
  assert.equal(run("--hub", hub, "--unit", "module").status, 2);
  assert.equal(run("--hub", hub, "--unit", "part", "--max", "0").status, 2);
  assert.equal(run("--hub", path.join(path.dirname(hub), "missing.md"), "--unit", "part").status, 2);
});
