// The main-run review verdict: the counts the merge gate reads
// (babysit_review_evidence `_main_review_counted`), from the model's checked
// output and the job's own reads, and nothing written on doubt.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { artifactName, buildVerdict, LONG_LINE_BYTES, longestLine, main, readCoverage, structuredOutput } from "./write-verdict.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const TREE = "c".repeat(40);
const finding = (severity, extra = {}) => ({ severity, path: "a.yml", line: 3, title: "t", body: "b", ...extra });
const args = (output, extra = {}) => ({ output, lane: "claude-security-review", pr: 42, headSha: HEAD, baseSha: BASE, tree: TREE, runId: 9, maxLineBytes: 80, ...extra });

test("counts every finding and the CRITICAL ones, with the job's own head, base and tree", () => {
  const verdict = buildVerdict(args({ findings: [finding("CRITICAL"), finding("SUGGESTION"), finding("IMPORTANT")], summary: "s" }));
  assert.deepEqual(
    { schema: verdict.schema, lane: verdict.lane, pr: verdict.pr, head: verdict.head_sha, tree: verdict.tree, findings: verdict.findings, critical: verdict.critical },
    { schema: 1, lane: "claude-security-review", pr: 42, head: HEAD, tree: TREE, findings: 3, critical: 1 },
  );
  const clean = buildVerdict(args({ findings: [], summary: "nothing" }));
  assert.equal(clean.findings, 0);
  assert.equal(clean.critical, 0);
});

test("refuses output off the schema, a bad id or SHA, and a credential in model text", () => {
  for (const [name, call] of [
    ["extra key", args({ findings: [], summary: "s", verdict: "pass" })],
    ["no summary", args({ findings: [] })],
    ["bad severity", args({ findings: [finding("HIGH")], summary: "s" })],
    ["extra finding key", args({ findings: [finding("CRITICAL", { fix: "x" })], summary: "s" })],
    ["negative line", args({ findings: [finding("CRITICAL", { line: -1 })], summary: "s" })],
    ["unknown lane", args({ findings: [], summary: "s" }, { lane: "other" })],
    ["bad tree", args({ findings: [], summary: "s" }, { tree: "x" })],
    ["bad pr", args({ findings: [], summary: "s" }, { pr: "0" })],
    ["secret", args({ findings: [], summary: `key AKIA${"A".repeat(16)}` })],
  ]) {
    assert.throws(() => buildVerdict(call), Error, name);
  }
});

test("a denied tool call or a missing result voids the review", () => {
  assert.throws(() => structuredOutput([{ type: "result", structured_output: {}, permission_denials: [{ tool_name: "Bash" }] }]));
  assert.throws(() => structuredOutput([{ type: "assistant" }]));
  assert.deepEqual(structuredOutput([{ type: "result", structured_output: { a: 1 }, permission_denials: [] }]), { a: 1 });
});

test("the artifact name is the one the merge gate looks up", () => {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const python = spawnSync(
    "python3",
    [
      "-I",
      "-c",
      "import sys; sys.path.insert(0, sys.argv[1]); import babysit_review_evidence as ev; print(ev.main_review_name(sys.argv[2], 42, sys.argv[3]))",
      path.join(root, "plugins/source-control/skills/babysit-prs/scripts"),
      "claude-review",
      TREE,
    ],
    { encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  assert.equal(artifactName("claude-review", 42, TREE), python.stdout.trim());
});

const read = (id, file, extra = {}) => ({ type: "assistant", message: { content: [{ type: "tool_use", id, name: "Read", input: { file_path: file, ...extra } }] } });
const failed = (id) => ({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: id, is_error: true }] } });

test("a verdict counts only when every diff part was read whole", () => {
  const parts = ["/d/diff/part-001.patch", "/d/diff/part-002.patch"];
  assert.doesNotThrow(() => readCoverage([read("a", parts[0]), read("b", parts[1])], parts));
  const voids = {
    "a part never read": [read("a", parts[0])],
    "a part read from an offset": [read("a", parts[0]), read("b", parts[1], { offset: 500 })],
    "a part read with a limit": [read("a", parts[0]), read("b", parts[1], { limit: 10 })],
    "a read that failed": [read("a", parts[0]), read("b", parts[1]), failed("b")],
    "another tool on the path": [read("a", parts[0]), { type: "assistant", message: { content: [{ type: "tool_use", id: "b", name: "Grep", input: { file_path: parts[1] } }] } }],
  };
  for (const [name, messages] of Object.entries(voids)) {
    assert.throws(() => readCoverage(messages, parts), /did not read 1 of 2/, name);
  }
  assert.throws(() => readCoverage([read("a", parts[0])], []), /unreadable/);
});

test("a diff line past the cap writes no verdict, and the verdict records the longest", () => {
  // Read may cut a 2,500-byte line short; a 1,000-byte one is read whole.
  assert.equal(longestLine([`+${"x".repeat(1000)}\n`, " ok\n"]), 1000);
  assert.throws(() => longestLine([" ok\n", `+${"x".repeat(2500)}\n`]), /2500 bytes/);
  // Bytes, not characters: 700 euro signs are 2,100 bytes.
  assert.throws(() => longestLine([`+${"\u20ac".repeat(700)}`]));
  assert.equal(buildVerdict(args({ findings: [], summary: "s" }, { maxLineBytes: 1000 })).max_line_bytes, 1000);
  for (const bad of [2500, LONG_LINE_BYTES + 1, undefined, "10", -1]) {
    assert.throws(() => buildVerdict(args({ findings: [], summary: "s" }, { maxLineBytes: bad })), /longest diff line/, String(bad));
  }
});

test("the cap is the merge gate's", () => {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const python = spawnSync(
    "python3",
    ["-I", "-c", "import sys; sys.path.insert(0, sys.argv[1]); import babysit_risk; print(babysit_risk.LONG_LINE_BYTES)", path.join(root, "plugins/source-control/skills/babysit-prs/scripts")],
    { encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  assert.equal(Number(python.stdout.trim()), LONG_LINE_BYTES);
});

test("main writes verdict.json and the name output", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-"));
  try {
    const execution = path.join(dir, "execution.json");
    const parts = path.join(dir, "diff");
    mkdirSync(parts);
    writeFileSync(path.join(parts, "part-001.patch"), "+x\n");
    const result = { type: "result", structured_output: { findings: [finding("CRITICAL")], summary: "s" }, permission_denials: [] };
    writeFileSync(execution, JSON.stringify([read("r1", path.join(parts, "part-001.patch")), result]));
    const output = path.join(dir, "output");
    writeFileSync(output, "");
    main({
      EXECUTION_FILE: execution,
      LANE: "claude-review",
      PR_NUMBER: "42",
      HEAD_SHA: HEAD,
      BASE_SHA: BASE,
      TREE_SHA: TREE,
      GITHUB_RUN_ID: "9",
      VERDICT_DIR: path.join(dir, "verdict"),
      DIFF_DIR: parts,
      GITHUB_OUTPUT: output,
    });
    const verdict = JSON.parse(readFileSync(path.join(dir, "verdict", "verdict.json"), "utf8"));
    assert.equal(verdict.findings, 1);
    assert.equal(verdict.critical, 1);
    assert.match(readFileSync(output, "utf8"), new RegExp(`^name=pr-review-main-claude-review-42-${TREE}$`, "m"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
