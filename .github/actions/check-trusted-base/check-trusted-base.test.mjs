// Runs the action's own `run:` script against a throwaway repository: a bare
// origin whose main holds commits A, B, C (C the tip) and a side branch holding
// D, cloned with full history the way the run job checks out `.base`.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";

const ACTION = new URL("./action.yml", import.meta.url);

// The step's `run: |` block, dedented: every line after it indented deeper
// than the `run:` key, blank lines kept.
function runScript() {
  const lines = readFileSync(ACTION, "utf8").split("\n");
  const start = lines.findIndex((line) => /^\s+run: \|$/.test(line));
  assert.notEqual(start, -1, "action.yml has a run: | block");
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && line.search(/\S/) <= keyIndent) break;
    body.push(line);
  }
  const indent = Math.min(...body.filter((l) => l.trim()).map((l) => l.search(/\S/)));
  return body.map((l) => l.slice(indent)).join("\n");
}

// No inherited git environment reaches the fixture.
let root;
let env;
const sha = {};

function git(cwd, ...args) {
  return execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.com", ...args], {
    cwd,
    env,
    encoding: "utf8",
  }).trim();
}

before(() => {
  root = mkdtempSync(path.join(tmpdir(), "trusted-base-"));
  const home = path.join(root, "home");
  mkdirSync(home);
  env = { PATH: process.env.PATH, HOME: home, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null" };
  const work = path.join(root, "work");
  mkdirSync(work);
  git(work, "init", "-q", "-b", "main");
  for (const name of ["A", "B", "C"]) {
    git(work, "commit", "-q", "--allow-empty", "-m", name);
    sha[name] = git(work, "rev-parse", "HEAD");
  }
  git(work, "checkout", "-q", "-b", "side", sha.A);
  git(work, "commit", "-q", "--allow-empty", "-m", "D");
  sha.D = git(work, "rev-parse", "HEAD");
  git(root, "clone", "-q", "--bare", work, "origin.git");

  // A gh stand-in answering the PR read with the base branch in $FAKE_BASE_REF.
  const bin = path.join(root, "bin");
  mkdirSync(bin);
  const gh = path.join(bin, "gh");
  writeFileSync(gh, '#!/usr/bin/env bash\nprintf "%s\\n" "$FAKE_BASE_REF"\n');
  chmodSync(gh, 0o755);
  env.PATH = `${bin}:${env.PATH}`;
});

after(() => rmSync(root, { recursive: true, force: true }));

function run(vars) {
  const dir = mkdtempSync(path.join(root, "run-"));
  const base = path.join(dir, ".base");
  git(dir, "clone", "-q", "-b", "main", path.join(root, "origin.git"), base);
  const output = path.join(dir, "output");
  writeFileSync(output, "");
  const result = spawnSync("bash", ["-e", "-c", runScript()], {
    encoding: "utf8",
    env: {
      ...env,
      GITHUB_OUTPUT: output,
      GITHUB_REPOSITORY: "o/r",
      EVENT_NAME: "pull_request",
      EVENT_BASE_REF: "main",
      DEFAULT_BRANCH: "main",
      PR_NUMBER: "7",
      BASE_PATH: base,
      MODE: "pr-base",
      ...vars,
    },
  });
  return {
    status: result.status,
    stdout: result.stdout,
    log: result.stdout + result.stderr,
    output: readFileSync(output, "utf8"),
    head: git(base, "rev-parse", "HEAD"),
  };
}

test("pr-base checks out the gated base SHA and outputs it", () => {
  const r = run({ BASE_SHA: sha.A });
  assert.equal(r.status, 0, r.log);
  assert.equal(r.output, `commit=${sha.A}\n`);
  assert.equal(r.head, sha.A);
});

test("pr-base fails when the gated base SHA is not on the default branch", () => {
  const r = run({ BASE_SHA: sha.D });
  assert.equal(r.status, 1);
  assert.match(r.log, /not on the default branch/);
  assert.equal(r.output, "");
});

test("default-tip checks out the default branch tip, not the stale base SHA", () => {
  const r = run({ MODE: "default-tip", BASE_SHA: sha.A });
  assert.equal(r.status, 0, r.log);
  assert.equal(r.output, `commit=${sha.C}\n`);
  assert.equal(r.head, sha.C);
  assert.match(r.stdout, new RegExp(`trusted-base-sha=${sha.C}`));
});

test("default-tip still refuses a PR into a branch other than the default branch", () => {
  const r = run({ MODE: "default-tip", BASE_SHA: sha.A, EVENT_BASE_REF: "side" });
  assert.equal(r.status, 1);
  assert.match(r.log, /other than the default branch/);
  assert.equal(r.output, "");
});

test("default-tip reads the PR's base branch on a workflow_dispatch", () => {
  const ok = run({ MODE: "default-tip", BASE_SHA: sha.A, EVENT_NAME: "workflow_dispatch", EVENT_BASE_REF: "", FAKE_BASE_REF: "main" });
  assert.equal(ok.status, 0, ok.log);
  assert.equal(ok.output, `commit=${sha.C}\n`);
  const bad = run({ MODE: "default-tip", BASE_SHA: sha.A, EVENT_NAME: "workflow_dispatch", EVENT_BASE_REF: "", FAKE_BASE_REF: "side" });
  assert.equal(bad.status, 1);
  assert.equal(bad.output, "");
});

for (const mode of ["", "tip", "PR-BASE"]) {
  test(`an unknown mode ${JSON.stringify(mode)} fails before any checkout`, () => {
    const r = run({ MODE: mode, BASE_SHA: sha.A });
    assert.equal(r.status, 1);
    assert.match(r.log, /mode/);
    assert.equal(r.output, "");
    assert.equal(r.head, sha.C);
  });
}
