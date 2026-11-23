// test-scope: .github/workflow-template-size.json .github/standards/runner-policy/package.json
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { describe, test } from "node:test";
import { tempDir } from "../lib/test-tmp.mjs";
import { calibrate, costOf, estimate, failLine, loadYaml, readConfig } from "./check-workflow-template-size.mjs";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const REPO = path.resolve(import.meta.dirname, "..");
const yaml = await loadYaml(REPO);

const fromMap = (files) => (name) => {
  if (!(name in files)) throw new Error(`no ${name}`);
  return files[name];
};

const git = (root, ...args) =>
  execFileSync("git", ["-C", root, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", ...args], {
    encoding: "utf8",
  }).trim();

const commitEach = (root, sets) => {
  git(root, "init", "-q");
  return sets.map((files) => {
    mkdirSync(path.join(root, ".github/workflows"), { recursive: true });
    for (const [name, text] of Object.entries(files)) writeFileSync(path.join(root, ".github/workflows", name), text);
    git(root, "add", ".github/workflows");
    git(root, "commit", "-q", "--allow-empty", "-m", "set");
    return git(root, "rev-parse", "HEAD");
  });
};

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

describe("calibrate", () => {
  const reusable = "on: workflow_call\njobs:\n  x:\n    runs-on: ubuntu-24.04\n";
  const caller = (calls) =>
    `on: push\njobs:\n${Array.from({ length: calls }, (_, i) => `  j${i}:\n    uses: ./.github/workflows/r.yml\n`).join("")}`;
  const bytes = (calls) => costOf(yaml, caller(calls)) + calls * costOf(yaml, reusable);
  const setup = () => {
    const root = tempDir("template-size-history-");
    const [good, failing] = commitEach(root, [
      { "c.yml": caller(2), "r.yml": reusable },
      { "c.yml": caller(3), "r.yml": reusable },
    ]);
    return { root, good, failing };
  };
  const config = (good, failing, { figure = bytes(3), margin = bytes(3) - bytes(2) - 1, tolerance = 0 } = {}) => ({
    "failing-figure": figure,
    margin,
    calibration: { caller: "c.yml", good, failing, tolerance },
  });

  test("reads each commit's files from git and finds nothing when they straddle the fail line", () => {
    const { root, good, failing } = setup();
    const result = calibrate(yaml, root, config(good, failing));
    assert.deepEqual(result, { goodBytes: bytes(2), failingBytes: bytes(3), findings: [] });
  });

  test("names a good commit at the fail line and a failing commit under it", () => {
    const { root, good, failing } = setup();
    const result = calibrate(yaml, root, config(failing, good, { figure: bytes(2) + 1, margin: 0, tolerance: bytes(3) }));
    assert.equal(result.findings.length, 2);
    assert.match(result.findings[0], /good commit .* not under the fail line/);
    assert.match(result.findings[1], /failing commit .* under the fail line/);
  });

  test("names a failing commit whose estimate left failing-figure's tolerance", () => {
    const { root, good, failing } = setup();
    const result = calibrate(yaml, root, config(good, failing, { figure: bytes(3) + 5, margin: bytes(3) - bytes(2) + 4, tolerance: 4 }));
    assert.deepEqual(result.findings, [`the failing commit ${failing} estimates ${bytes(3)}, more than 4 from failing-figure ${bytes(3) + 5}`]);
  });

  test("fails, never skips, when a commit is not in the history", () => {
    const { root, good } = setup();
    assert.throws(() => calibrate(yaml, root, config(good, "0".repeat(40))), /needs the repository's full history/);
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

  test("refuses a calibration without full commit SHAs", () => {
    const calibration = { caller: "c.yml", good: "c13006c388", failing: "b".repeat(40), tolerance: 0 };
    assert.throws(() => readConfig(write({ "failing-figure": 1000, margin: 10, calibration, reason: "r" })), /calibration/);
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
