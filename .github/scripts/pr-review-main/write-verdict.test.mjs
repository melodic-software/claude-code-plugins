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

import { artifactName, buildChunkedVerdict, buildVerdict, LONG_LINE_BYTES, longestLine, main, readCoverage, structuredOutput } from "./write-verdict.mjs";

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

test("a chunked review's verdict sums every chunk's findings and takes the most CRITICAL ones in a chunk", () => {
  const { output: _, ...rest } = args(undefined);
  // The chunk with the most CRITICAL findings comes first: the max wins, not
  // the last chunk or the sum.
  const verdict = buildChunkedVerdict({
    ...rest,
    outputs: [
      { findings: [finding("CRITICAL"), finding("CRITICAL"), finding("SUGGESTION")], summary: "first" },
      { findings: [finding("CRITICAL"), finding("IMPORTANT")], summary: "second" },
    ],
  });
  assert.deepEqual({ findings: verdict.findings, critical: verdict.critical, items: verdict.items.length }, { findings: 5, critical: 2, items: 5 });
  assert.equal(verdict.summary, "Chunk 1 of 2: first\n\nChunk 2 of 2: second");
  assert.deepEqual(Object.keys(verdict).sort(), Object.keys(buildVerdict(args({ findings: [], summary: "s" }))).sort());
  // One chunk is the single-pass verdict, unchanged.
  const one = { findings: [finding("CRITICAL")], summary: "s" };
  assert.deepEqual(buildChunkedVerdict({ ...rest, outputs: [one] }), buildVerdict(args(one)));
  // Any chunk off the schema voids the whole verdict.
  assert.throws(() => buildChunkedVerdict({ ...rest, outputs: [one, { findings: [finding("HIGH")], summary: "s" }] }), /chunk 2 of 2/);
  assert.throws(() => buildChunkedVerdict({ ...rest, outputs: [] }));
});

// A diff directory of chunk-<k>/part-<n>.patch files, and each chunk's
// execution file: a Read of each of its own parts and a result.
function chunkedRun(dir, chunks, { skip = [], result = () => ({ findings: [finding("CRITICAL")], summary: "s" }) } = {}) {
  const diff = path.join(dir, "diff");
  const files = chunks.map((texts, i) => {
    const chunk = path.join(diff, `chunk-${i + 1}`);
    mkdirSync(chunk, { recursive: true });
    const parts = texts.map((body, j) => {
      const part = path.join(chunk, `part-00${j + 1}.patch`);
      writeFileSync(part, body);
      return part;
    });
    if (skip.includes(i + 1)) return "";
    const execution = path.join(dir, `execution-${i + 1}.json`);
    const output = result(i + 1);
    const messages = parts.map((part, j) => read(`r${i}-${j}`, part));
    if (output !== undefined) messages.push({ type: "result", structured_output: output, permission_denials: [] });
    writeFileSync(execution, JSON.stringify(messages));
    return execution;
  });
  const output = path.join(dir, "output");
  writeFileSync(output, "");
  return {
    EXECUTION_FILES: `${files.join("\n")}\n`,
    CHUNKS: String(chunks.length),
    LANE: "claude-review",
    PR_NUMBER: "42",
    HEAD_SHA: HEAD,
    BASE_SHA: BASE,
    TREE_SHA: TREE,
    GITHUB_RUN_ID: "9",
    VERDICT_DIR: path.join(dir, "verdict"),
    DIFF_DIR: diff,
    GITHUB_OUTPUT: output,
  };
}

test("main writes verdict.json and the name output", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-"));
  try {
    const env = chunkedRun(dir, [["+x\n"]]);
    main(env);
    const verdict = JSON.parse(readFileSync(path.join(dir, "verdict", "verdict.json"), "utf8"));
    assert.equal(verdict.findings, 1);
    assert.equal(verdict.critical, 1);
    assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), new RegExp(`^name=pr-review-main-claude-review-42-${TREE}$`, "m"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a chunked run writes one verdict over its chunks, the most CRITICAL in a chunk, and a notice per chunk", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-"));
  try {
    // Chunk 1 is 3 + 4 bytes with one CRITICAL; chunk 2 is 5 bytes with two
    // CRITICAL and one IMPORTANT.
    const outputs = { 1: { findings: [finding("CRITICAL")], summary: "a" }, 2: { findings: [finding("CRITICAL"), finding("IMPORTANT"), finding("CRITICAL")], summary: "b" } };
    const env = chunkedRun(dir, [["+x\n", "+yz\n"], ["+abc\n"]], { result: (k) => outputs[k] });
    const script = fileURLToPath(new URL("./write-verdict.mjs", import.meta.url));
    const run = spawnSync(process.execPath, [script], { encoding: "utf8", env: { ...process.env, ...env } });
    assert.equal(run.status, 0, run.stdout + run.stderr);
    const verdict = JSON.parse(readFileSync(path.join(dir, "verdict", "verdict.json"), "utf8"));
    assert.deepEqual({ findings: verdict.findings, critical: verdict.critical }, { findings: 4, critical: 2 });
    assert.match(run.stdout, /^::notice title=pr-review-main chunk::lane=claude-review chunk=1\/2 bytes=7 findings=1 critical=1$/m);
    assert.match(run.stdout, /^::notice title=pr-review-main chunk::lane=claude-review chunk=2\/2 bytes=5 findings=3 critical=2$/m);
    assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^findings=4\ncritical=2$/m);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a chunk that failed, left no verdict, or skipped a part writes no verdict at all", () => {
  const cases = {
    "a chunk never ran": { skip: [2] },
    "a chunk left no result": { result: (k) => (k === 2 ? undefined : { findings: [], summary: "s" }) },
    "a chunk's output is off the schema": { result: (k) => (k === 2 ? { findings: [], verdict: "pass" } : { findings: [], summary: "s" }) },
  };
  for (const [name, options] of Object.entries(cases)) {
    const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-"));
    try {
      const env = chunkedRun(dir, [["+x\n"], ["+y\n"]], options);
      assert.throws(() => main(env), /chunk 2 of 2/, name);
      assert.throws(() => readFileSync(path.join(dir, "verdict", "verdict.json")), /ENOENT/, name);
      assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "", name);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
  // A run that read chunk 1's parts for chunk 2, or a chunk count that is
  // not the directories on disk, voids the verdict too.
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-"));
  try {
    const env = chunkedRun(dir, [["+x\n"], ["+y\n"]]);
    const [first] = env.EXECUTION_FILES.split("\n");
    assert.throws(() => main({ ...env, EXECUTION_FILES: `${first}\n${first}\n` }), /chunk 2 of 2: the run did not read 1 of 1/);
    assert.throws(() => main({ ...env, CHUNKS: "1" }), /2 chunk directories/);
    assert.throws(() => main({ ...env, CHUNKS: "3" }), /2 chunk directories/);
    assert.throws(() => readFileSync(path.join(dir, "verdict", "verdict.json")), /ENOENT/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
