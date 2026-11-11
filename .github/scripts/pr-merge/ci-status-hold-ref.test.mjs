// Runs ci-status's "Resolve the hold config's commit" step with a git stand-in
// that answers ls-remote with the default branch tip, and checks which commit
// the hold config is read from.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";

const WORKFLOW = new URL("../../workflows/pr-require-checks.yml", import.meta.url);
const STEP = "Resolve the hold config's commit";
const TIP = "1".repeat(40);
const EVENT_BASE = "2".repeat(40);

// The named step's `run: |` block, dedented.
function runScript() {
  const lines = readFileSync(WORKFLOW, "utf8").split("\n");
  const named = lines.findIndex((line) => line.trim() === `- name: ${STEP}`);
  assert.notEqual(named, -1, `pr-require-checks.yml has the step "${STEP}"`);
  const start = lines.findIndex((line, i) => i > named && /^\s+run: \|$/.test(line));
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && line.search(/\S/) <= keyIndent) break;
    body.push(line);
  }
  const indent = Math.min(...body.filter((l) => l.trim()).map((l) => l.search(/\S/)));
  return body.map((l) => l.slice(indent)).join("\n");
}

const STACK_BASE = "3".repeat(40);

// `tipFails` makes the git stand-in's ls-remote fail, as an outage would.
function run(vars, { tipFails = false } = {}) {
  const root = tempDir("hold-ref-");
  const bin = path.join(root, "bin");
  mkdirSync(bin);
  const git = path.join(bin, "git");
  writeFileSync(git, tipFails ? "#!/usr/bin/env bash\nexit 128\n" : `#!/usr/bin/env bash\nprintf '%s\\trefs/heads/main\\n' ${TIP}\n`);
  chmodSync(git, 0o755);
  const output = path.join(root, "output");
  writeFileSync(output, "");
  const result = spawnSync("bash", ["-e", "-c", runScript()], {
    encoding: "utf8",
    env: {
      PATH: `${bin}:${process.env.PATH}`,
      RUNNER_TEMP: root,
      GITHUB_OUTPUT: output,
      GITHUB_REPOSITORY: "o/r",
      EVENT: "pull_request",
      DEFAULT_BRANCH: "main",
      BASE_SHA: EVENT_BASE,
      BASE_REF: "main",
      STACK_BASE_REF: "",
      STACK_BASE_SHA: "",
      ...vars,
    },
  });
  return { status: result.status, log: result.stdout + result.stderr, output: readFileSync(output, "utf8") };
}

test("a pull request into the default branch reads the hold config at the tip", () => {
  const r = run({});
  assert.equal(r.status, 0, r.log);
  assert.equal(r.output, `sha=${TIP}\n`);
});

test("a stack layer whose stack targets the default branch reads the tip, not the layer below", () => {
  const r = run({ BASE_REF: "feat/lower-layer", STACK_BASE_REF: "main" });
  assert.equal(r.status, 0, r.log);
  assert.equal(r.output, `sha=${TIP}\n`);
});

test("a pull request into the default branch falls back to its base SHA when the tip is unreadable", () => {
  const r = run({}, { tipFails: true });
  assert.equal(r.status, 0, r.log);
  assert.equal(r.output, `sha=${EVENT_BASE}\n`);
});

test("a stack layer falls back to the stack base SHA, never the layer below, when the tip is unreadable", () => {
  const r = run({ BASE_REF: "feat/lower-layer", STACK_BASE_REF: "main", STACK_BASE_SHA: STACK_BASE }, { tipFails: true });
  assert.equal(r.status, 0, r.log);
  assert.equal(r.output, `sha=${STACK_BASE}\n`);
});

test("a stack layer with an unreadable tip and no stack base SHA fails", () => {
  const r = run({ BASE_REF: "feat/lower-layer", STACK_BASE_REF: "main" }, { tipFails: true });
  assert.equal(r.status, 1, r.log);
  assert.equal(r.output, "");
});

test("a pull request into another branch, in no stack, keeps the event's base SHA", () => {
  const r = run({ BASE_REF: "feat/lower-layer" });
  assert.equal(r.status, 0, r.log);
  assert.equal(r.output, `sha=${EVENT_BASE}\n`);
});

test("a stack layer whose stack targets another branch keeps the event's base SHA", () => {
  const r = run({ BASE_REF: "feat/lower-layer", STACK_BASE_REF: "release/x" });
  assert.equal(r.status, 0, r.log);
  assert.equal(r.output, `sha=${EVENT_BASE}\n`);
});
