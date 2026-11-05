// execute.mjs applies only a mutant that edits one exact span of a tracked file
// inside `mutate`, maps the covering harness's exit to a state (0 survived,
// 1 killed, 2 no-coverage, timeout, else invalid; harness contract in
// scripts/run-covering-tests.sh's header), restores every file, and ends
// restore-failed when the tree differs. assemble.mjs keeps every state the
// executor wrote and takes only dispositions from triage.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { assemble } from "./assemble.mjs";
import { applyProblem, execute, inScope, readConfig, stateOf } from "./execute.mjs";

const CONFIG = 'tool: manual\nmutate:\n  - "**/*.sh"\n  - "**/*.mjs"\n  - "!**/*.test.*"\n  - "!docs/conventions/**"\noperators: default\ntimeout-ms: 115000\n';

test("the config's mutate globs and timeout are read, and a negated glob wins when it comes later", () => {
  assert.deepEqual(readConfig(CONFIG), { globs: ["**/*.sh", "**/*.mjs", "!**/*.test.*", "!docs/conventions/**"], timeoutMs: 115000 });
  const { globs } = readConfig(CONFIG);
  assert.equal(inScope("scripts/a.sh", globs), true);
  assert.equal(inScope("a.mjs", globs), true);
  assert.equal(inScope("scripts/a.test.mjs", globs), false);
  assert.equal(inScope("docs/conventions/x.mjs", globs), false);
  assert.equal(inScope("README.md", globs), false);
});

test("a mutant applies only to one exact span of a tracked in-scope file that covers its line", () => {
  const globs = ["**/*.sh"];
  const text = "a=1\nif [ $a -eq 1 ]; then\n  echo one\nfi\n";
  const ok = { path: "s.sh", line: 2, old_string: "-eq", new_string: "-ne" };
  assert.equal(applyProblem(ok, { globs, text, tracked: true }), "");
  assert.equal(applyProblem({ ...ok, line: 3 }, { globs, text, tracked: true }), "old_string does not cover line");
  assert.equal(applyProblem({ ...ok, old_string: "1" }, { globs, text, tracked: true }), "old_string occurs more than once");
  assert.equal(applyProblem({ ...ok, old_string: "-gt" }, { globs, text, tracked: true }), "old_string not found");
  assert.equal(applyProblem({ ...ok, old_string: "" }, { globs, text, tracked: true }), "old_string occurs more than once");
  assert.equal(applyProblem({ ...ok, path: "s.py" }, { globs, text, tracked: true }), "outside the mutate globs");
  assert.equal(applyProblem(ok, { globs, text, tracked: false }), "not a tracked file");
  assert.equal(applyProblem({ ...ok, path: "a/../s.sh" }, { globs, text, tracked: true }), "path has a . or .. segment");
});

test("the harness's exit maps to the mutant's state", () => {
  assert.equal(stateOf({ status: 0 }), "survived");
  assert.equal(stateOf({ status: 1 }), "killed");
  assert.equal(stateOf({ status: 2 }), "no-coverage");
  assert.equal(stateOf({ status: 1, timedOut: true }), "timeout");
  assert.equal(stateOf({ status: 3 }), "invalid");
});

function repo() {
  const root = tempDir("execute-");
  const git = (...args) => assert.equal(spawnSync("git", ["-C", root, ...args], { encoding: "utf8" }).status, 0, args.join(" "));
  git("init", "-q");
  writeFileSync(join(root, "a.sh"), "x=1\necho $((x + 1))\n");
  writeFileSync(join(root, "b.sh"), "echo b\n");
  writeFileSync(join(root, "c.sh"), "echo c\n");
  git("add", ".");
  git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init");
  return root;
}

test("each mutant runs once on its file after one baseline, and every file is restored", () => {
  const root = repo();
  const calls = [];
  // A harness stand-in: a.sh's mutant is killed, b.sh's survives, c.sh has no covering suite.
  const run = (harness, path, ms) => {
    const text = readFileSync(join(root, path), "utf8");
    calls.push(`${path}:${text.includes("MUT") ? "mutant" : "baseline"}`);
    if (path === "c.sh") return { status: 2, ms: 1 };
    return { status: text.includes("MUT") && path === "a.sh" ? 1 : 0, ms: 10 };
  };
  const generation = {
    outcome: "generated",
    detail: "three files",
    mutants: [
      { path: "a.sh", line: 2, operator: "AOR", old_string: "x + 1", new_string: "x - 1 # MUT" },
      { path: "b.sh", line: 1, operator: "SBR", old_string: "echo b", new_string: ": MUT" },
      { path: "c.sh", line: 1, operator: "SBR", old_string: "echo c", new_string: ": MUT" },
      { path: "a.sh", line: 1, operator: "other", old_string: "nope", new_string: "MUT" },
    ],
  };
  const result = execute(generation, { root, harness: "h", config: CONFIG, run });
  assert.equal(result.outcome, "reported");
  assert.deepEqual(result.mutants.map((m) => m.state), ["killed", "survived", "no-coverage", "invalid"]);
  assert.deepEqual(calls, ["a.sh:baseline", "a.sh:mutant", "b.sh:baseline", "b.sh:mutant", "c.sh:baseline"]);
  assert.equal(readFileSync(join(root, "a.sh"), "utf8"), "x=1\necho $((x + 1))\n");
  assert.equal(spawnSync("git", ["-C", root, "status", "--porcelain"], { encoding: "utf8" }).stdout, "");
});

test("a red baseline leaves its mutants not-run, and a tree left dirty ends the run restore-failed", () => {
  const root = repo();
  const m = (path) => ({ path, line: 1, operator: "SBR", old_string: `echo ${path[0]}`, new_string: ":" });
  const red = execute({ outcome: "generated", detail: "", mutants: [m("b.sh")] }, { root, harness: "h", config: CONFIG, run: () => ({ status: 1, ms: 1 }) });
  assert.deepEqual(red.mutants.map((x) => x.state), ["not-run"]);
  // A mutant run that writes another tracked file.
  const dirty = execute({ outcome: "generated", detail: "", mutants: [m("b.sh"), m("c.sh")] }, {
    root,
    harness: "h",
    config: CONFIG,
    run: (h, path, ms) => {
      // The baseline runs under the 600 s bound and leaves the tree as it was.
      if (ms === 600000) return { status: 0, ms: 1 };
      writeFileSync(join(root, "a.sh"), "changed\n");
      return { status: 0, ms: 1 };
    },
  });
  assert.equal(dirty.outcome, "restore-failed");
  assert.deepEqual(dirty.mutants.map((x) => x.state), ["survived", "not-run"]);
});

test("a generation that is not generated or does not match its schema runs nothing", () => {
  const root = repo();
  const run = () => assert.fail("no run");
  assert.deepEqual(execute({ outcome: "scope-empty", detail: "none", mutants: [] }, { root, harness: "h", config: CONFIG, run }), { outcome: "scope-empty", detail: "none", mutants: [] });
  assert.equal(execute({ outcome: "generated", detail: "", mutants: [{ path: "a.sh" }] }, { root, harness: "h", config: CONFIG, run }).outcome, "refused");
});

test("assemble keeps the executor's states and takes only a survivor's disposition and cause from triage", () => {
  const executed = {
    outcome: "reported",
    detail: "d",
    mutants: [
      { path: "a.sh", line: 2, operator: "AOR", state: "killed", old_string: "x", new_string: "y" },
      { path: "b.sh", line: 1, operator: "SBR", state: "survived", old_string: "x", new_string: "y" },
      { path: "c.sh", line: 1, operator: "SBR", state: "survived", old_string: "x", new_string: "y" },
    ],
  };
  const triage = { verdicts: [{ index: 1, disposition: "productive", cause: "input-gap" }, { index: 0, disposition: "equivalent", cause: "none" }] };
  assert.deepEqual(assemble(executed, triage).mutants, [
    { path: "a.sh", line: 2, operator: "AOR", state: "killed", disposition: "none", cause: "none" },
    { path: "b.sh", line: 1, operator: "SBR", state: "survived", disposition: "productive", cause: "input-gap" },
    { path: "c.sh", line: 1, operator: "SBR", state: "survived", disposition: "unclassified", cause: "unclassified" },
  ]);
  assert.throws(() => assemble(executed, null), /no triage result/);
  assert.throws(() => assemble({ ...executed, outcome: "won" }, triage), /executed mutants do not match/);
  assert.throws(() => assemble(executed, { verdicts: [{ index: 1, disposition: "great", cause: "none" }] }), /triage result does not match/);
  const killedOnly = { ...executed, mutants: [executed.mutants[0]] };
  assert.equal(assemble(killedOnly, null).mutants[0].state, "killed", "no survivor needs no triage");
});
