import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { laneSlots } from "../../actions/resolve-config/resolve.mjs";
import { planPasses } from "./plan-passes.mjs";

// The slots resolve.mjs expands for a pr-refine lane holding these
// activities, one slot each unless `slots` replaces them.
const slotsOf = (activities, slots = Object.keys(activities).map((activity) => ({ activity })), lane = {}) =>
  laneSlots({ activities, lanes: { "pr-refine": { stage: "refine", ...lane, slots } } }, "pr-refine");

// fix-docs as docs/conventions/pr-pipeline.yaml sets it, beside an activity of
// another stage that a planner must never pick.
const FIX_DOCS = {
  stage: "refine",
  order: 10,
  group: "docs",
  "applies-when": { paths: ["**/*.md"], "paths-ignore": [".changes/**"] },
};
const LIVE = { "fix-docs": FIX_DOCS, "resolve-conflicts": { "applies-when": { paths: ["**/*.md"] } } };

test("a markdown-only PR gets fix-docs, with the files it matched", () => {
  const plan = planPasses({ slots: slotsOf(LIVE), changedPaths: ["README.md", "docs/guide.md"] });
  assert.deepEqual(plan, {
    passes: [{ name: "fix-docs", order: 10, group: "docs", files: 2 }],
    batches: [["fix-docs"]],
  });
});

test("a PR with only changelog fragments gets no pass", () => {
  const plan = planPasses({ slots: slotsOf(LIVE), changedPaths: [".changes/pr-pipeline/a.md", ".changes/review/b.md"] });
  assert.deepEqual(plan, { passes: [], batches: [] });
});

// Node's globstar already skips a dot directory, so `.changes/**` above
// would hold with no paths-ignore; this ignore is the only thing that drops
// the file.
test("paths-ignore drops a file the paths glob matched", () => {
  const activities = { "fix-docs": { ...FIX_DOCS, "applies-when": { paths: ["**/*.md"], "paths-ignore": ["docs/archive/**"] } } };
  assert.deepEqual(planPasses({ slots: slotsOf(activities), changedPaths: ["docs/archive/old.md"] }).passes, []);
  assert.deepEqual(planPasses({ slots: slotsOf(activities), changedPaths: ["docs/archive/old.md", "docs/new.md"] }).passes, [
    { name: "fix-docs", order: 10, group: "docs", files: 1 },
  ]);
});

test("a code-only PR gets no pass", () => {
  assert.deepEqual(planPasses({ slots: slotsOf(LIVE), changedPaths: ["src/app.js", "package.json"] }), { passes: [], batches: [] });
});

test("a fragment beside code still gets no pass, and one beside a doc counts the doc alone", () => {
  assert.deepEqual(planPasses({ slots: slotsOf(LIVE), changedPaths: ["src/app.js", ".changes/x/a.md"] }).passes, []);
  assert.deepEqual(planPasses({ slots: slotsOf(LIVE), changedPaths: ["docs/a.md", ".changes/x/a.md"] }).passes, [
    { name: "fix-docs", order: 10, group: "docs", files: 1 },
  ]);
});

test("a listing that may be cut off runs every pass", () => {
  assert.deepEqual(planPasses({ slots: slotsOf(LIVE), changedPaths: ["src/app.js"], truncated: true }).batches, [["fix-docs"]]);
});

// Two synthetic passes in one group: disjoint files run together, shared files
// one after the other.
const pass = (order, group, paths) => ({ stage: "refine", order, group, "applies-when": { paths } });

test("two passes on disjoint globs land in one parallel batch", () => {
  const activities = { "format-code": pass(20, "tidy", ["**/*.js"]), "fix-docs": pass(10, "tidy", ["**/*.md"]) };
  const plan = planPasses({ slots: slotsOf(activities), changedPaths: ["a.md", "b.js"] });
  assert.deepEqual(plan.batches, [["fix-docs", "format-code"]]);
});

test("overlapping passes run serially in order, whatever their file order", () => {
  const activities = { "format-docs": pass(20, "tidy", ["docs/**"]), "fix-docs": pass(10, "tidy", ["**/*.md"]) };
  const plan = planPasses({ slots: slotsOf(activities), changedPaths: ["docs/a.md"] });
  assert.deepEqual(plan.batches, [["fix-docs"], ["format-docs"]]);
});

test("a serial pass runs alone, and a different group starts a new batch", () => {
  const activities = {
    "fix-docs": pass(10, "tidy", ["**/*.md"]),
    "format-all": pass(30, "serial", ["**/*.yaml"]),
    "lint-code": pass(20, "code", ["**/*.js"]),
  };
  const plan = planPasses({ slots: slotsOf(activities), changedPaths: ["a.md", "b.js", "c.yaml"] });
  assert.deepEqual(plan.batches, [["fix-docs"], ["lint-code"], ["format-all"]]);
});

test("a pass that matches nothing leaves no batch between two that run together", () => {
  const activities = {
    "fix-docs": pass(10, "tidy", ["**/*.md"]),
    "fix-yaml": pass(20, "tidy", ["**/*.yaml"]),
    "format-code": pass(30, "tidy", ["**/*.js"]),
  };
  assert.deepEqual(planPasses({ slots: slotsOf(activities), changedPaths: ["a.md", "b.js"] }).batches, [["fix-docs", "format-code"]]);
});

// The lane's slots decide, as the runner's resolve reads them.
test("a disabled slot or lane plans no pass, and a slot's applies-when replaces its activity's", () => {
  const activities = { "fix-docs": FIX_DOCS };
  assert.deepEqual(planPasses({ slots: slotsOf(activities, [{ activity: "fix-docs", enabled: false }]), changedPaths: ["a.md"] }).passes, []);
  assert.deepEqual(planPasses({ slots: slotsOf(activities, undefined, { enabled: false }), changedPaths: ["a.md"] }).passes, []);
  const replaced = slotsOf(activities, [{ activity: "fix-docs", "applies-when": { paths: ["docs/**"] } }]);
  assert.deepEqual(planPasses({ slots: replaced, changedPaths: ["a.md"] }).passes, []);
  assert.deepEqual(planPasses({ slots: replaced, changedPaths: ["docs/x.js"] }).passes, [{ name: "fix-docs", order: 10, group: "docs", files: 1 }]);
});

test("a composite's predicate narrows its refine leaves' files", () => {
  const activities = { tidy: { children: [{ activity: "fix-docs" }], "applies-when": { paths: ["docs/**"] } }, "fix-docs": FIX_DOCS };
  const slots = slotsOf(activities, [{ activity: "tidy" }]);
  assert.deepEqual(planPasses({ slots, changedPaths: ["README.md"] }).passes, []);
  assert.deepEqual(planPasses({ slots, changedPaths: ["README.md", "docs/a.md"] }).passes, [{ name: "fix-docs", order: 10, group: "docs", files: 1 }]);
});

// The plan job's step on this repository's own config, read as the job reads
// the base's: the outputs each pass's first job and record-passes read.
test("write-pass-plan.mjs writes the plan's outputs, and only planned passes get <pass>=true", () => {
  const dir = mkdtempSync(join(tmpdir(), "write-pass-plan-"));
  try {
    const plan = (paths) => {
      writeFileSync(join(dir, "paths.txt"), paths.join("\n"));
      writeFileSync(join(dir, "out"), "");
      const run = spawnSync(process.execPath, [fileURLToPath(new URL("./write-pass-plan.mjs", import.meta.url))], {
        env: { PATH: process.env.PATH, BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), PATHS_FILE: join(dir, "paths.txt"), TRUNCATED: "false", GITHUB_OUTPUT: join(dir, "out") },
        encoding: "utf8",
      });
      assert.equal(run.status, 0, run.stderr);
      return { out: readFileSync(join(dir, "out"), "utf8").split("\n").filter(Boolean), log: run.stdout };
    };
    const docs = plan(["docs/a.md", "src/b.js"]);
    assert.deepEqual(docs.out, ['passes=["fix-docs"]', 'batches=[["fix-docs"]]', 'files={"fix-docs":1}', "fix-docs=true"]);
    assert.match(docs.log, /^::notice title=refine-plan::changed=2 passes=fix-docs batches=fix-docs$/m);
    const code = plan(["src/b.js"]);
    assert.deepEqual(code.out, ["passes=[]", "batches=[]", "files={}"]);
    assert.match(code.log, /passes=none batches=none/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
