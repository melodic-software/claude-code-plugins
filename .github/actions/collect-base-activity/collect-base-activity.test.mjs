// Runs the action's skill-staging `run:` script against a throwaway base
// checkout and reads the outputs it appends to GITHUB_OUTPUT. Expected values
// come from the contract (pr-run-activity.md, "Skill activities" and
// "prepare: merge-base"): a writing skill gets the signed-commit tool and the
// instruction to commit, except in merge-base mode, where the runner commits.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";

const ACTION = new URL("./action.yml", import.meta.url);
const COMMIT_TOOL = "mcp__github_file_ops__commit_files";
const COMMIT_SENTENCE = "commit every repository file you changed";

// The `run: |` block of the step with `id: skill`, dedented.
function skillScript() {
  const lines = readFileSync(ACTION, "utf8").split("\n");
  const id = lines.findIndex((line) => /^\s+id: skill$/.test(line));
  assert.notEqual(id, -1, "action.yml has the skill step");
  const start = lines.findIndex((line, i) => i > id && /^\s+run: \|$/.test(line));
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && line.search(/\S/) <= keyIndent) break;
    body.push(line);
  }
  const indent = Math.min(...body.filter((l) => l.trim()).map((l) => l.search(/\S/)));
  return body.map((l) => l.slice(indent)).join("\n");
}

let root;
let base;
let resolved;

before(() => {
  root = mkdtempSync(path.join(tmpdir(), "collect-base-activity-"));
  base = path.join(root, "base");
  mkdirSync(path.join(base, "plugins", "source-control"), { recursive: true });
  mkdirSync(path.join(base, ".claude-plugin"));
  writeFileSync(path.join(base, ".claude-plugin", "marketplace.json"), JSON.stringify({ name: "melodic-software" }));
  resolved = path.join(root, "resolved.json");
  writeFileSync(resolved, JSON.stringify({ selected: { args: "ci" } }));
});

after(() => rmSync(root, { recursive: true, force: true }));

function stage(overrides) {
  const runTemp = mkdtempSync(path.join(root, "temp-"));
  const output = path.join(runTemp, "github-output");
  writeFileSync(output, "");
  const env = {
    PATH: process.env.PATH,
    MARKETPLACE: path.join(runTemp, "base-marketplace"),
    BASE_PATH: base,
    RESOLVED: resolved,
    SKILL: "source-control:resolve-conflicts",
    MODEL: "",
    MAX_TURNS: "75",
    GATING: "advisory",
    EFFECT: "mutate-branch",
    CAN_COMMIT: "true",
    PREPARE: "",
    SCRATCH: path.join(runTemp, "lane-scratch"),
    GITHUB_OUTPUT: output,
    ...overrides,
  };
  const result = spawnSync("bash", ["-e", "-c", skillScript()], { env, encoding: "utf8" });
  const text = readFileSync(output, "utf8");
  const args = /^claude-args=(.*)$/m.exec(text)?.[1] ?? "";
  // The --allowedTools list itself, split at the top-level commas.
  const allowed = (/--allowedTools "([^"]*)"/.exec(args)?.[1] ?? "").split(/,(?![^(]*\))/);
  const prompt = /^prompt<<(\S+)\n([\s\S]*?)\n\1$/m.exec(text)?.[2] ?? "";
  return { status: result.status, stdout: result.stdout, args, allowed, prompt };
}

test("an issue lane's prompt names the issue before the activity's args", () => {
  const { status, prompt, args } = stage({ SKILL: "work-items:work", ISSUE_NUMBER: "77" });
  assert.equal(status, 0);
  assert.equal(prompt, "/work-items:work --issue 77 ci");
  assert.match(args, /on an issue/);
});

test("a malformed issue number fails red before any output", () => {
  const { status, stdout, prompt } = stage({ SKILL: "work-items:work", ISSUE_NUMBER: "7 --x" });
  assert.notEqual(status, 0);
  assert.match(stdout, /::error::the issue number is malformed/);
  assert.equal(prompt, "");
});

test("a writing skill that can commit gets the commit tool and the instruction to commit", () => {
  const { status, args, allowed } = stage({});
  assert.equal(status, 0);
  assert.ok(allowed.includes(COMMIT_TOOL), allowed.join(" | "));
  assert.ok(args.includes(COMMIT_SENTENCE), args);
});

test("prepare: merge-base leaves out the commit tool and the instruction to commit", () => {
  const { status, args, allowed } = stage({ PREPARE: "merge-base" });
  assert.equal(status, 0);
  assert.ok(!allowed.includes(COMMIT_TOOL), allowed.join(" | "));
  assert.ok(!args.includes(COMMIT_TOOL), args);
  assert.ok(!args.includes(COMMIT_SENTENCE), args);
  // Still a writing skill: it edits and stages its resolution.
  assert.match(args, /--allowedTools "Skill\(source-control:resolve-conflicts\),Read\([^)]*\),Edit,Write,Agent,Edit\(/);
  assert.ok(args.includes("--disallowedTools \"WebFetch,WebSearch\""), args);
});

test("an unknown prepare mode fails red before any output", () => {
  const { status, stdout, args } = stage({ PREPARE: "rebase" });
  assert.notEqual(status, 0);
  assert.match(stdout, /::error::the activity's prepare mode is not a known mode/);
  assert.equal(args, "");
});
