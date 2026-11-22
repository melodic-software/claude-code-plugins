// test-scope: .github/workflow-template-size.json .github/standards/runner-policy/package.json
// test-scope: scripts/fixtures/workflow-template-size/*
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { describe, test } from "node:test";
import { gunzipSync } from "node:zlib";
import { tempDir } from "../lib/test-tmp.mjs";
import { costOf, estimate, failLine, loadYaml, readConfig } from "./check-workflow-template-size.mjs";

const REPO = path.resolve(import.meta.dirname, "..");
const FIXTURES = path.join(REPO, "scripts/fixtures/workflow-template-size");
const TOLERANCE = 100;
const yaml = await loadYaml(REPO);

const fromMap = (files) => (name) => {
  if (!(name in files)) throw new Error(`no ${name}`);
  return files[name];
};
const fromFixture = (label) => (name) => gunzipSync(readFileSync(path.join(FIXTURES, label, `${name}.gz`))).toString("utf8");

describe("costOf", () => {
  test("charges a string 24 + 26 bytes plus 2 per character, keys included", () => {
    assert.equal(costOf(yaml, "a: bc\n"), 24 + (50 + 2) + (50 + 4));
  });

  test("charges a list, null, boolean and number 24 bytes each", () => {
    assert.equal(costOf(yaml, "a: [1, true, null]\n"), 24 + 52 + 24 + 3 * 24);
  });

  test("charges an alias as the node it names", () => {
    assert.equal(costOf(yaml, "a: &x bc\nb: *x\n"), 24 + 52 + 54 + 52 + 54);
  });

  test("refuses YAML that does not parse", () => {
    assert.throws(() => costOf(yaml, "a: [\n"), /does not parse/);
  });
});

describe("estimate", () => {
  const reusable = "on: workflow_call\njobs:\n  x:\n    runs-on: ubuntu-24.04\n";
  const caller = [
    "on: push",
    "jobs:",
    "  one:",
    "    uses: ./.github/workflows/r.yml",
    "  two:",
    "    uses: ./.github/workflows/r.yml",
    "  remote:",
    "    uses: octo/repo/.github/workflows/r.yml@v1",
    "",
  ].join("\n");

  test("adds the called file once per call job", () => {
    const result = estimate(yaml, "c.yml", fromMap({ "c.yml": caller, "r.yml": reusable }));
    assert.equal(result.bytes, costOf(yaml, caller) + 2 * costOf(yaml, reusable));
    assert.equal(result.calls, 2);
  });

  test("counts a call the called file makes in turn", () => {
    const middle = "on: workflow_call\njobs:\n  m:\n    uses: ./.github/workflows/r.yml\n";
    const top = "on: push\njobs:\n  t:\n    uses: ./.github/workflows/m.yml\n";
    const result = estimate(yaml, "t.yml", fromMap({ "t.yml": top, "m.yml": middle, "r.yml": reusable }));
    assert.equal(result.bytes, costOf(yaml, top) + costOf(yaml, middle) + costOf(yaml, reusable));
    assert.equal(result.calls, 2);
  });

  test("refuses a call cycle", () => {
    const loop = "on: workflow_call\njobs:\n  l:\n    uses: ./.github/workflows/l.yml\n";
    assert.throws(() => estimate(yaml, "l.yml", fromMap({ "l.yml": loop })), /cycle/);
  });

  test("refuses a call to a file that is not there", () => {
    assert.throws(() => estimate(yaml, "c.yml", fromMap({ "c.yml": caller })), /no r\.yml/);
  });
});

describe("the known figures", () => {
  const config = readConfig(REPO);
  const good = estimate(yaml, "pr-unblock.yml", fromFixture("c13006c388"));
  const failing = estimate(yaml, "pr-unblock.yml", fromFixture("bcc9c54076"));

  test(`reproduces the last good commit's 10,569,716 within ${TOLERANCE} bytes`, () => {
    assert.ok(Math.abs(good.bytes - 10_569_716) <= TOLERANCE, `estimated ${good.bytes}`);
    assert.equal(good.calls, 27);
  });

  test(`reproduces the #17516 commit's 10,581,308 within ${TOLERANCE} bytes`, () => {
    assert.ok(Math.abs(failing.bytes - 10_581_308) <= TOLERANCE, `estimated ${failing.bytes}`);
  });

  test("passes the last good commit and fails the #17516 commit under the committed config", () => {
    assert.ok(good.bytes < failLine(config), `good ${good.bytes} against ${failLine(config)}`);
    assert.ok(failing.bytes >= failLine(config), `failing ${failing.bytes} against ${failLine(config)}`);
  });
});

describe("readConfig", () => {
  const write = (body) => {
    const root = tempDir("template-size-config-");
    mkdirSync(path.join(root, ".github"));
    writeFileSync(path.join(root, ".github/workflow-template-size.json"), JSON.stringify(body));
    return root;
  };

  test("reads the figure and margin", () => {
    const config = readConfig(write({ "failing-figure": 1000, margin: 10, reason: "r" }));
    assert.equal(failLine(config), 990);
  });

  test("refuses a margin that is not a whole number below the figure", () => {
    assert.throws(() => readConfig(write({ "failing-figure": 1000, margin: 1000, reason: "r" })), /margin/);
    assert.throws(() => readConfig(write({ "failing-figure": 1000, margin: "5", reason: "r" })), /margin/);
  });

  test("refuses a figure that is not a positive whole number", () => {
    assert.throws(() => readConfig(write({ "failing-figure": 0, margin: 0, reason: "r" })), /failing-figure/);
  });
});

describe("check-workflow-template-size.sh", () => {
  const reusable = "on: workflow_call\njobs:\n  x:\n    runs-on: ubuntu-24.04\n";
  const tree = ({ calls, figure, margin = 0, extra = {} }) => {
    const root = tempDir("template-size-tree-");
    const policy = path.join(root, ".github/standards/runner-policy");
    mkdirSync(path.join(root, "scripts"), { recursive: true });
    mkdirSync(path.join(root, ".github/workflows"), { recursive: true });
    mkdirSync(policy, { recursive: true });
    for (const file of ["check-workflow-template-size.sh", "check-workflow-template-size.mjs"]) {
      copyFileSync(path.join(REPO, "scripts", file), path.join(root, "scripts", file));
    }
    copyFileSync(path.join(REPO, ".github/standards/runner-policy/package.json"), path.join(policy, "package.json"));
    symlinkSync(path.join(REPO, ".github/standards/runner-policy/node_modules"), path.join(policy, "node_modules"));
    const jobs = Array.from({ length: calls }, (_, i) => `  j${i}:\n    uses: ./.github/workflows/r.yml\n`).join("");
    const files = { "c.yml": `on: push\njobs:\n${jobs}`, "r.yml": reusable, "plain.yaml": reusable, ...extra };
    for (const [name, text] of Object.entries(files)) writeFileSync(path.join(root, ".github/workflows", name), text);
    const config = { "failing-figure": figure, margin, reason: "test" };
    writeFileSync(path.join(root, ".github/workflow-template-size.json"), JSON.stringify(config));
    return { root, bytes: costOf(yaml, files["c.yml"]) + calls * costOf(yaml, reusable) };
  };
  const run = (root) =>
    spawnSync("bash", [path.join(root, "scripts/check-workflow-template-size.sh"), "--check"], { encoding: "utf8" });

  test("passes a caller below the fail line and names its headroom", () => {
    const probe = tree({ calls: 2, figure: 1 });
    const { root } = tree({ calls: 2, figure: probe.bytes + 11, margin: 10 });
    const result = run(root);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, new RegExp(`\\.github/workflows/c\\.yml: ${probe.bytes} bytes, 1 under`));
    assert.doesNotMatch(result.stdout, /r\.yml:|plain\.yaml:/);
    assert.equal(result.stderr, "");
  });

  test("fails a caller that reaches the fail line, on stderr only", () => {
    const probe = tree({ calls: 3, figure: 1 });
    const { root } = tree({ calls: 3, figure: probe.bytes + 10, margin: 10 });
    const result = run(root);
    assert.equal(result.status, 1);
    assert.match(result.stderr, new RegExp(`^\\.github/workflows/c\\.yml:1: estimated template memory ${probe.bytes}`, "m"));
    assert.doesNotMatch(result.stdout, /estimated template memory/);
  });

  test("exits 2 when a called file is missing", () => {
    const { root } = tree({ calls: 1, figure: 10_000_000, extra: { "d.yml": "on: push\njobs:\n  d:\n    uses: ./.github/workflows/gone.yml\n" } });
    const result = run(root);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /gone\.yml/);
    assert.equal(result.stdout, "");
  });

  test("exits 2 on an unreadable config", () => {
    const { root } = tree({ calls: 1, figure: -1 });
    const result = run(root);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /failing-figure/);
  });

  test("exits 2 on an argument it does not take", () => {
    const { root } = tree({ calls: 1, figure: 10_000_000 });
    const result = spawnSync("bash", [path.join(root, "scripts/check-workflow-template-size.sh"), "--nope"], { encoding: "utf8" });
    assert.equal(result.status, 2);
    assert.match(result.stderr, /usage/);
  });
});
