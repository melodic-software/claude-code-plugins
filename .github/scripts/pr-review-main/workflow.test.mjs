// pr-review-main.yml's hardening, from its header and ADR 0049: it runs only
// from main on workflow_run, its token can only read, it checks out main and
// never the head, the model reads only its data directory, and each leg
// uploads the verdict once, after it is written, under the name the writer
// chose. Each lane runs one leg on the review lanes' credentials in their
// order, a later leg only for a lane the previous one handed on.
// test-scope: plugins/source-control/.claude-plugin/plugin.json scripts/sync-credential-legs.mjs scripts/credential-legs/*
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, symlinkSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { admits } from "../lib/gate-expression.mjs";
import { heldNoted } from "../maintenance-reconcile-lost-runs/reconcile.mjs";
import { HELD_STEP } from "../pr-verify/resolve-pr.mjs";
import { workflowText } from "../lib/workflow-text.mjs";
import { filePatch, MIXED, MIXED_MANIFEST } from "../diff-chunking/fixtures.mjs";

const text = readFileSync(new URL("../../workflows/pr-review-main.yml", import.meta.url), "utf8");
const SELECT_PINS = new Set([...text.matchAll(/uses: melodic-software\/ci-workflows\/\.github\/actions\/select-model-credential@(main)/g)].map((m) => m[1]));
assert.equal(SELECT_PINS.size, 1, [...SELECT_PINS].join(", "));
const SELECT_USES = new RegExp(`^ {8}uses: melodic-software/ci-workflows/\\.github/actions/select-model-credential@${[...SELECT_PINS][0].replace(/[.+]/g, "\\$&")}$`, "m");
const prompt = readFileSync(new URL("./prompt.md", import.meta.url), "utf8");
const KEY = "review";
const SUB = "review-subscription";
const FB = "review-fallback";
const LEGS = [KEY, SUB, FB];
const PROBE = "review-handoffs-credit";
const TEXT = "collect-trusted-text";
const wf = workflowText(text);
const jobText = wf.job;
const stepsOf = wf.steps;
const STEPS = Object.fromEntries([...LEGS, PROBE, "review-handoffs"].map((id) => [id, stepsOf(id)]));
const step = (name, job = KEY) => {
  const found = STEPS[job].find((s) => s.name === name);
  assert.ok(found, `a step named ${name} in ${job}`);
  return found.text;
};
const index = (name, job = KEY) => STEPS[job].findIndex((s) => s.name === name);
const writeDiff = readFileSync(new URL("./write-diff.py", import.meta.url), "utf8");
const WRITE_DIFF = new URL("./write-diff.py", import.meta.url).pathname;
const input = (block, key) => new RegExp(`^ {10}${key}: (.*)$`, "m").exec(block)?.[1];
const MAX_CHUNKS = Number(/^ {10}MAX_CHUNKS: "(\d+)"$/m.exec(step("Write the diff"))?.[1]);
const RUNS = [
  { name: "Review chunk 1", id: "review-1", report: "Report chunk 1's outcome", transcript: "Upload chunk 1's sealed transcript" },
  { name: "Review the later chunks", id: "review-chunks", report: "Report the later chunks' outcome", transcript: "Upload the later chunks' sealed transcript" },
];
const LATER = RUNS[1];
const LEG_MINUTES = 15;
const PARALLELISM = Number(/^ {2}CHUNK_PARALLELISM: "(\d+)"$/m.exec(text)?.[1]);
const loopMinutes = (chunks) => 3 + Math.ceil((chunks - 1) / PARALLELISM) * (LEG_MINUTES + 1);

test("each leg reviews chunk 1, then every later chunk eight at once in one step, and stops at a handoff or a failure", () => {
  assert.equal(MAX_CHUNKS, 75);
  assert.equal(PARALLELISM, 8);
  for (const job of LEGS) {
    assert.equal(/^ {10}MAX_CHUNKS: "(\d+)"$/m.exec(step("Write the diff", job))[1], String(MAX_CHUNKS), job);
    const runs = STEPS[job].filter((s) => /ci-workflows\/\.github\/actions\/run-(?:claude-cli|review-chunks)@/.test(s.text)).map((s) => s.name);
    assert.deepEqual(runs, RUNS.map((r) => r.name), job);
    const first = step(RUNS[0].name, job);
    const later = step(LATER.name, job);
    assert.equal(/^ {8}if: (.*)$/m.exec(first)[1], "steps.prompt.outcome == 'success'", job);
    assert.equal(input(first, "prompt-file"), "${{ runner.temp }}/pr-review-main-prompts/prompt-1.md", job);
    assert.match(first, /uses: melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli@main$/m, job);
    assert.match(later, /uses: melodic-software\/ci-workflows\/\.github\/actions\/run-review-chunks@main$/m, job);
    assert.match(later, /^ {8}id: review-chunks$/m, job);
    const laterIf = "steps.prompt.outcome == 'success' && fromJSON(steps.diff.outputs.chunks || '0') >= 2 && steps.review-1.outcome == 'success' && steps.review-1.outputs.handoff != 'true'";
    assert.equal(/^ {8}if: (.*)$/m.exec(later)[1], laterIf, job);
    assert.equal(/^ {8}if: (.*)$/m.exec(step("Time the later chunks", job))[1], laterIf, job);
    assert.equal(index("Time the later chunks", job) + 1, index(LATER.name, job), job);
    assert.equal(input(later, "prompt-dir"), "${{ runner.temp }}/pr-review-main-prompts", job);
    assert.equal(input(later, "chunk-first"), '"2"', job);
    assert.equal(input(later, "chunk-last"), "${{ steps.diff.outputs.chunks }}", job);
    assert.equal(input(later, "parallelism"), "${{ env.CHUNK_PARALLELISM }}", job);
    assert.match(later, /^ {8}timeout-minutes: \$\{\{ fromJSON\(steps\.prompt\.outputs\.loop-minutes \|\| '1'\) \}\}$/m, job);
    const rest = (block) =>
      block
        .replace(/^ {6}- name: .*\n|^ {8}(?:id|if|timeout-minutes|uses): .*\n/gm, "")
        .replace(/^ {10}(?:prompt-file|prompt-dir|chunk-first|chunk-last|parallelism): .*\n/gm, "");
    assert.equal(rest(later), rest(first), job);
    assert.equal(input(step(RUNS[0].transcript, job), "execution-file"), "${{ steps.review-1.outputs.execution-file }}");
    assert.equal(input(step(RUNS[0].transcript, job), "job-id"), "${{ github.job }}-${{ matrix.lane }}");
    assert.equal(input(step(LATER.transcript, job), "execution-file"), "${{ steps.review-chunks.outputs.transcript-file }}");
    assert.equal(input(step(LATER.transcript, job), "job-id"), "${{ github.job }}-${{ matrix.lane }}-chunks");
    assert.equal(loopMinutes(MAX_CHUNKS), 163);
    const timeout = Number(/^ {4}timeout-minutes: (\d+)$/m.exec(jobText(job))[1]);
    assert.ok(timeout >= 22 + loopMinutes(MAX_CHUNKS) + 5 && timeout < 360, `${job} ${timeout}`);
    const prompts = step("Write the prompt and schema", job);
    assert.match(prompts, /printf '%s\\n' "\$prompt" >"\$PROMPT_STEM-\$k\.md"/);
    assert.equal(input(prompts, "PROMPT_STEM"), "${{ runner.temp }}/pr-review-main-prompts/prompt");
    assert.equal(input(prompts, "LEG_MINUTES"), `"${LEG_MINUTES}"`);
    assert.equal(input(later, "leg-timeout-minutes"), `"${LEG_MINUTES}"`);
  }
});

test("the prompt step writes a prompt for each of 75 chunks and the later chunks' step limit", () => {
  const run = /^ {8}run: \|\n((?:(?: {10}.*)?\n)+)/m.exec(`${step("Write the prompt and schema")}\n`)[1].replace(/^ {10}/gm, "");
  const promptsFor = (chunks) => {
    const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-prompts-"));
    try {
      const data = path.join(dir, "data");
      for (let k = 1; k <= chunks; k++) {
        mkdirSync(path.join(data, "diff", `chunk-${k}`), { recursive: true });
        writeFileSync(path.join(data, "diff", `chunk-${k}`, "part-001.patch"), "+x\n");
      }
      const base = path.join(dir, ".base", ".github", "scripts", "pr-review-main");
      mkdirSync(base, { recursive: true });
      writeFileSync(path.join(base, "prompt.md"), "DIFF_PARTS\nCHUNK_NOTE\n");
      const out = path.join(dir, "out");
      writeFileSync(out, "");
      const env = { ...process.env, DATA: data, LANE: "claude-review", SKILL: "code-review", MODEL: "opus", CHUNKS: String(chunks), PROMPT_STEM: path.join(dir, "prompts", "prompt"), SCHEMA_FILE: path.join(dir, "schema.json"), LEG_MINUTES: String(LEG_MINUTES), CHUNK_PARALLELISM: String(PARALLELISM), GITHUB_OUTPUT: out };
      const result = spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", run], { cwd: dir, encoding: "utf8", env });
      const written = result.status === 0 ? readdirSync(path.join(dir, "prompts")).length : 0;
      return { status: result.status, written, outputs: readFileSync(out, "utf8"), last: written ? readFileSync(path.join(dir, "prompts", `prompt-${chunks}.md`), "utf8") : "" };
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };
  const most = promptsFor(MAX_CHUNKS);
  assert.equal(most.status, 0);
  assert.equal(most.written, 75);
  assert.ok(most.last.includes("These parts are chunk 75 of 75"));
  assert.match(most.outputs, /^loop-minutes=163$/m);
  assert.match(promptsFor(9).outputs, /^loop-minutes=19$/m);
  assert.match(promptsFor(10).outputs, /^loop-minutes=35$/m);
  assert.notEqual(promptsFor(100).status, 0);
});

test("a chunked review that wrote no verdict records chunk-failed for the report-review-counts job", () => {
  for (const job of LEGS) {
    const stop = step("Record a failed chunk", job);
    assert.equal(index("Record a failed chunk", job), index("Write the verdict", job) + 1, job);
    assert.match(stop, /^ {8}id: chunk-stop$/m);
    const noHandoff = RUNS.map((r) => `steps.${r.id}.outputs.handoff != 'true'`).join(" && ");
    assert.equal(/^ {8}if: (.*)$/m.exec(stop)[1], `\${{ !cancelled() && fromJSON(steps.diff.outputs.chunks || '0') > 1 && steps.review-1.outcome != 'skipped' && steps.verdict.outcome != 'success' && ${noHandoff} }}`);
    const run = /^ {8}run: \|\n((?: {10}.*\n?)+)/m.exec(`${stop}\n`)[1].replace(/^ {10}/gm, "");
    const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-chunk-stop-"));
    try {
      const out = path.join(dir, "out");
      writeFileSync(out, "");
      const result = spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", run], { encoding: "utf8", env: { ...process.env, LANE: "claude-review", HEAD_SHA: SHA_A, PR_NUMBER: "7", GITHUB_OUTPUT: out } });
      assert.equal(result.status, 0);
      assert.equal(readFileSync(out, "utf8"), `claude-review-stop=chunk-failed\nclaude-review-head=${SHA_A}\n`);
      assert.match(result.stdout, /^::notice title=pr-review-main stop::reason=chunk-failed lane=claude-review pr=7; /m);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
    assert.match(step("Fail without a verdict", job), /steps\.verdict\.outcome != 'success'/);
  }
});

test("it runs only from main on pr-require-checks' completion", () => {
  const on = /\non:\n([\s\S]*?)\n\S/.exec(text)[1];
  assert.match(on, /^ {2}workflow_run: # zizmor: ignore\[dangerous-triggers\]$/m);
  assert.match(on, /^ {4}workflows: \[PR Require Checks\]$/m);
  const keys = on.split("\n").filter((line) => !line.trim().startsWith("#")).map((line) => line.split(" #")[0]).join("\n");
  assert.doesNotMatch(keys, /pull_request|push|workflow_dispatch|issue|schedule/);
  assert.match(text, /github\.ref == 'refs\/heads\/main'/);
  assert.match(text, /github\.event\.workflow_run\.event == 'pull_request'/);
  assert.match(text, /github\.event\.workflow_run\.head_repository\.full_name == github\.repository/);
});

const grantsOf = (block) =>
  [...block.matchAll(/^ {6}([a-z-]+): (\w+)(?: #.*)?$/gm)].filter(([, scope]) =>
    ["contents", "pull-requests", "actions", "checks", "issues", "statuses", "id-token"].includes(scope),
  );

test("the model's jobs can only read, and the one writer runs no model", () => {
  assert.match(text, /^permissions: \{\}$/m);
  for (const job of LEGS) {
    const review = grantsOf(jobText(job));
    assert.ok(review.length > 0, job);
    for (const [line, , level] of review) assert.equal(level, "read", `${job}: ${line}`);
  }
  // The routes between legs hold no grant, no secret and no model; the one
  // action is review-handoffs' credit-stop marker upload, on the runtime token.
  for (const job of ["review-handoffs", "collect-subscription-handoffs"]) {
    const route = jobText(job);
    assert.match(route, /^ {4}permissions: \{\}$/m, job);
    assert.doesNotMatch(route, /run-claude-cli|secrets\.|actions\/checkout@/, job);
    const uses = route.match(/uses: .*/g) ?? [];
    assert.deepEqual(uses.map((line) => line.replace(/@.*/, "")), job === "review-handoffs" ? ["uses: actions/upload-artifact"] : [], job);
  }
  // The check-trigger job reads with the key leg's grants and checks: read, for the
  // report-review-counts job's check runs its judged-head read takes; it holds no secret
  // and runs no model.
  const trigger = jobText("check-trigger");
  assert.deepEqual(
    grantsOf(trigger).map(([, scope, level]) => `${scope}:${level}`),
    [...grantsOf(jobText(KEY)).map(([, scope, level]) => `${scope}:${level}`), "checks:read"],
  );
  assert.doesNotMatch(trigger, /run-claude-cli|secrets\./);
  const record = jobText("report-review-counts");
  assert.deepEqual(grantsOf(record).map(([, scope, level]) => `${scope}:${level}`), ["checks:write"]);
  assert.doesNotMatch(record, /run-claude-cli|secrets\.|actions\/checkout@/);
  assert.match(record, /critical =~ \^\[0-9\]\{1,6\}\$/);
  assert.match(record, /repos\/\$GITHUB_REPOSITORY\/check-runs/);
  assert.doesNotMatch(text, /write-all/);
});

test("the diff shows every file as text and refuses one a review cannot read whole", () => {
  const diff = step("Write the diff");
  assert.match(diff, /python3 -I \.base\/\.github\/scripts\/pr-review-main\/write-diff\.py "\$SRC" "\$BASE_SHA" "\$HEAD_SHA" "\$DATA\/diff\.patch" "\$MAX_DIFF_BYTES"$/m);
  assert.match(writeDiff, /^DIFF = \["diff", "--text", "--no-ext-diff", "--no-textconv", "--no-color"\]$/m);
  assert.match(diff, /\^\(Binary files \.\* differ\|GIT binary patch\)\$/);
  assert.match(diff, /^ {10}python3 -I \.base\/\.github\/scripts\/diff-chunking\/diff_chunking\.py split "\$DATA\/diff\.patch" "\$DATA\/diff" "\$MAX_DIFF_BYTES" "\$MAX_CHUNKS" "\$DATA\/manifest\.txt" "\$PART_BYTES" --cut-lines \|\| split=\$\?$/m);
  assert.match(diff, /MAX_DIFF_BYTES: "\d+"/);
});

test("the diff is split into parts by the chunking module", () => {
  for (const job of LEGS) {
    const diff = step("Write the diff", job);
    assert.match(diff, /^ {10}bytes=\$\(python3 -I \.base\/\.github\/scripts\/diff-chunking\/diff_chunking\.py parts "\$DATA\/diff" "\$PART_BYTES" "\$PART_LINES"\)$/m, job);
    assert.doesNotMatch(diff, /awk/, job);
  }
});

test("a diff with a line past the review's cap is folded, and every byte of it reaches a whole read", async () => {
  const { LONG_LINE_BYTES, longestLine } = await import("./write-verdict.mjs");
  for (const job of LEGS) assert.equal(input(step("Write the diff", job), "LONG_LINE_BYTES"), undefined, `${job} folds at the module's length, not its own`);
  const patch = `diff --git a/x b/x\n@@ -1,2 +1,2 @@\n-${"o".repeat(4000)}\n+${"x".repeat(4000)}\n ${"\u00e9".repeat(1500)}\n`;
  const readParts = (data) =>
    readdirSync(path.join(data, "diff"), { recursive: true })
      .filter((p) => p.endsWith(".patch"))
      .sort()
      .map((p) => readFileSync(path.join(data, "diff", p), "utf8"));
  for (const job of LEGS) {
    const result = runDiff(patch, { job, maxBytes: "300000", after: readParts });
    assert.equal(result.status, 0, job);
    assert.doesNotMatch(result.output, /stop=/, job);
    assert.match(result.output, /^chunks=1$/m, job);
    const texts = result.after;
    assert.ok(longestLine(texts) <= LONG_LINE_BYTES, job);
    assert.equal(texts.join("").replaceAll("\n\\ continued: ", ""), patch, job);
  }
});

const CHUNKING = new URL("../diff-chunking/diff_chunking.py", import.meta.url).pathname;

const PYTHON = spawnSync("bash", ["-c", "command -v python3"], { encoding: "utf8" }).stdout.trim();
function runDiff(patch, { pythonFails = false, job = KEY, maxBytes = "300", maxChunks = "4", after } = {}) {
  const run = /^ {8}run: \|\n((?:(?: {10}.*)?\n)+)/m.exec(`${step("Write the diff", job)}\n`)[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-stop-"));
  try {
    const bin = path.join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(path.join(bin, "git"), `#!/bin/sh\ncase "$*" in *rev-parse*) echo ${"e".repeat(40)} ;; esac\n`);
    writeFileSync(path.join(dir, "fixture.patch"), patch);
    const writes = pythonFails ? "exit 1" : `cp "${path.join(dir, "fixture.patch")}" "$6"`;
    writeFileSync(path.join(bin, "python3"), `#!/bin/sh\ncase "$2" in\n  *write-diff.py) ${writes} ;;\n  *diff_chunking.py) shift 2; exec "${PYTHON}" -I "${CHUNKING}" "$@" ;;\n  *) exit 9 ;;\nesac\n`);
    chmodSync(path.join(bin, "git"), 0o755);
    chmodSync(path.join(bin, "python3"), 0o755);
    const out = path.join(dir, "out");
    writeFileSync(out, "");
    const data = path.join(dir, "data");
    const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`, GITHUB_OUTPUT: out, LANE: "claude-security-review", HEAD_SHA: SHA_A, BASE_SHA: SHA_B, PR_NUMBER: "7", DATA: data, SRC: path.join(dir, "src"), MAX_DIFF_BYTES: maxBytes, MAX_CHUNKS: maxChunks, PART_BYTES: "15000", PART_LINES: "1000" };
    const result = spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", run], { encoding: "utf8", env });
    const parts = (() => {
      try {
        return readdirSync(path.join(data, "diff"), { recursive: true }).sort();
      } catch {
        return [];
      }
    })();
    const output = readFileSync(out, "utf8");
    return { status: result.status, output, stdout: result.stdout, parts, ...(after ? { after: after(data, output) } : {}) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("a diff the review cannot read whole stops green and names its reason for the report-review-counts job", () => {
  const small = "diff --git a/x b/x\n@@ -1 +1 @@\n+short\n";
  for (const job of LEGS) {
    const tooLarge = runDiff(`diff --git a/x b/x\n@@ -1 +1 @@\n+${"x".repeat(400)}\n`, { job });
    assert.equal(tooLarge.status, 0, job);
    assert.equal(tooLarge.output, `stop=too-large\nclaude-security-review-stop=too-large\nclaude-security-review-head=${SHA_A}\n`, job);
    assert.deepEqual(tooLarge.parts, [], job);
    assert.match(tooLarge.stdout, /^::notice title=pr-review-main stop::reason=too-large lane=claude-security-review pr=7; /m, job);
    const hunks = Array.from({ length: 12 }, (_, i) => `@@ -${i * 10 + 1} +${i * 10 + 1} @@\n+line ${i}\n`).join("");
    const oneFile = `diff --git a/x b/x\n--- a/x\n+++ b/x\n${hunks}`;
    assert.ok(Buffer.byteLength(oneFile) > 300 && hunks.length / 12 < 30, job);
    const manyHunks = runDiff(oneFile, { job });
    assert.equal(manyHunks.status, 0, job);
    assert.doesNotMatch(manyHunks.output, /stop=/, job);
    assert.match(manyHunks.output, /^chunks=2$/m, job);
    assert.deepEqual(manyHunks.parts, ["chunk-1", "chunk-1/part-001.patch", "chunk-2", "chunk-2/part-001.patch"], job);
    const oneHunk = runDiff(`diff --git a/x b/x\n@@ -1,0 +1,100 @@\n${"+line\n".repeat(100)}`, { job });
    assert.equal(oneHunk.status, 0, job);
    assert.doesNotMatch(oneHunk.output, /stop=/, job);
    assert.match(oneHunk.output, /^chunks=3$/m, job);
    const files = ["a", "b", "c", "d", "e"].map((name) => filePatch(name, 200));
    const tooMany = runDiff(files.join(""), { job });
    assert.equal(tooMany.status, 0, job);
    assert.match(tooMany.output, /^stop=too-large$/m, job);
    assert.deepEqual(tooMany.parts, [], job);
    const four = runDiff(files.slice(0, 4).join(""), { job });
    assert.equal(four.status, 0, job);
    assert.doesNotMatch(four.output, /stop=/, job);
    assert.match(four.output, /^chunks=4$/m, job);
    assert.deepEqual(four.parts, ["chunk-1", "chunk-1/part-001.patch", "chunk-2", "chunk-2/part-001.patch", "chunk-3", "chunk-3/part-001.patch", "chunk-4", "chunk-4/part-001.patch"], job);
    assert.match(four.stdout, /^::notice title=pr-review-main chunks::lane=claude-security-review pr=7 chunks=4 bytes=200,200,200,200 manifest_paths=4$/m, job);
    const many = (n) => runDiff(Array.from({ length: n }, (_, i) => filePatch(`f${i}`, 200)).join(""), { job, maxChunks: String(MAX_CHUNKS) });
    const fifty = many(50);
    assert.equal(fifty.status, 0, job);
    assert.doesNotMatch(fifty.output, /stop=/, job);
    assert.match(fifty.output, /^chunks=50$/m, job);
    assert.match(many(MAX_CHUNKS).output, /^chunks=75$/m, job);
    assert.match(many(MAX_CHUNKS + 1).output, /^stop=too-large$/m, job);
    const failed = runDiff(small, { job, pythonFails: true });
    assert.notEqual(failed.status, 0, job);
    assert.doesNotMatch(failed.output, /stop=/, job);
    const whole = runDiff(small, { job });
    assert.equal(whole.status, 0, job);
    assert.doesNotMatch(whole.output, /stop=/, job);
    assert.deepEqual(whole.parts, ["chunk-1", "chunk-1/part-001.patch"], job);
    assert.match(whole.output, /^chunks=1$/m, job);
    assert.match(whole.stdout, /^::notice title=pr-review-main chunks::lane=claude-security-review pr=7 chunks=1 bytes=\d+ manifest_paths=0$/m, job);
  }
});

function renderPrompts(data, output, job) {
  const chunks = /^chunks=(\d+)$/m.exec(output)[1];
  const run = /^ {8}run: \|\n((?:(?: {10}.*)?\n)+)/m.exec(`${step("Write the prompt and schema", job)}\n`)[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-prompt-"));
  try {
    const base = path.join(dir, ".base/.github/scripts/pr-review-main");
    mkdirSync(base, { recursive: true });
    symlinkSync(new URL("./prompt.md", import.meta.url).pathname, path.join(base, "prompt.md"));
    const out = path.join(dir, "out");
    writeFileSync(out, "");
    const env = { ...process.env, DATA: data, LANE: "claude-review", SKILL: "code-review", MODEL: "opus", CHUNKS: chunks, PROMPT_STEM: path.join(dir, "prompt"), SCHEMA_FILE: path.join(dir, "schema.json"), LEG_MINUTES: String(LEG_MINUTES), CHUNK_PARALLELISM: String(PARALLELISM), GITHUB_OUTPUT: out };
    const result = spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", run], { cwd: dir, encoding: "utf8", env });
    assert.equal(result.status, 0, result.stderr);
    const manifest = (() => { try { return readFileSync(path.join(data, "manifest.txt"), "utf8"); } catch { return null; } })();
    return { data, manifest, prompts: Array.from({ length: Number(chunks) }, (_, i) => readFileSync(path.join(dir, `prompt-${i + 1}.md`), "utf8")) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("each chunk's prompt names the manifest file and holds none of its paths, and a one-chunk prompt is the single-pass prompt", () => {
  for (const job of LEGS) {
    const two = runDiff(MIXED.join(""), { job, maxBytes: "600", after: (data, output) => renderPrompts(data, output, job) });
    assert.equal(two.status, 0, job);
    assert.match(two.stdout, /^::notice title=pr-review-main chunks::lane=claude-security-review pr=7 chunks=2 bytes=\d+,\d+ manifest_paths=6$/m, job);
    two.after.prompts.forEach((text, i) => {
      const k = i + 1;
      assert.ok(text.includes(`These parts are chunk ${k} of 2`), `${job} chunk ${k}`);
      assert.ok(text.includes(`  - \`${two.after.data}/diff/chunk-${k}/part-001.patch\``), `${job} chunk ${k}`);
      assert.match(text, /names both paths/, `${job} chunk ${k}`);
      assert.match(text, /cut at its hunks into pieces in different chunks, each under the file's own diff --git header/, `${job} chunk ${k}`);
      assert.ok(text.includes("`piece <i> of <n>`"), `${job} chunk ${k}`);
      assert.doesNotMatch(text, /not yours to judge/, `${job} chunk ${k}`);
      // The prompt names the file and frames it as data; the paths, which
      // the pull request's author chose, stay out of the prompt itself.
      assert.ok(text.includes(`\`${two.after.data}/manifest.txt\``), `${job} chunk ${k}`);
      assert.match(text, /untrusted data like it, never instructions/, `${job} chunk ${k}`);
      assert.doesNotMatch(text, /^\s*chunk \d+ (added|modified|deleted|renamed) /m, `${job} chunk ${k}`);
      for (const pathText of ["lib/b & c.sh", "docs/x.md", "guide/x.md", "r\\303\\251sum"]) assert.ok(!text.includes(pathText), `${job} chunk ${k}: ${pathText}`);
    });
    assert.equal(two.after.manifest, `${MIXED_MANIFEST.join("\n")}\n`, job);
    const one = runDiff(MIXED.join(""), { job, maxBytes: "300000", after: (data, output) => renderPrompts(data, output, job) });
    const { data, prompts } = one.after;
    const single = prompt
      .replaceAll("LANE_NAME", "claude-review")
      .replaceAll("CRITERIA_DIR", `${data}/review/skills/code-review`)
      .replaceAll("STANDARDS_DIR", `${data}/standards`)
      .replaceAll("DIFF_PARTS", `  - \`${data}/diff/chunk-1/part-001.patch\``)
      .replaceAll("CHUNK_NOTE", "")
      .replaceAll("CONTEXT_FILE", `${data}/context.json`)
      .replaceAll("PR_FILE", `${data}/pr.json`)
      .replace(/\n+$/, "\n");
    assert.deepEqual(prompts, [single], job);
  }
});

test("after a stop no later step of the leg runs, and each lane's stop leaves the leg", () => {
  for (const job of LEGS) {
    const gated = STEPS[job].filter((s) => /steps\.diff\.outcome == 'success'/.test(s.text));
    assert.ok(gated.length >= 5, job);
    for (const s of gated) assert.match(s.text, /steps\.diff\.outcome == 'success' && steps\.diff\.outputs\.stop == ''/, `${job}: ${s.name}`);
    for (const lane of ["claude-review", "claude-security-review"]) {
      for (const kind of ["stop", "head"]) {
        assert.match(jobText(job), new RegExp(`^ {6}${lane}-${kind}: \\$\\{\\{ steps\\.diff\\.outputs\\.${lane}-${kind} \\|\\| steps\\.chunk-stop\\.outputs\\.${lane}-${kind} \\}\\}$`, "m"), `${job} ${lane}-${kind}`);
      }
    }
  }
});

function recordStops(env) {
  const block = stepsOf("report-review-counts").find((s) => s.name === "Record the stops").text;
  const run = /^ {8}run: \|\n((?:(?: {10}.*)?\n)+)/m.exec(`${block}\n`)[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-record-"));
  try {
    const log = path.join(dir, "gh.log");
    writeFileSync(path.join(dir, "gh"), `#!/bin/sh\nprintf '%s\\n' "$@" >>"${log}"\n`);
    chmodSync(path.join(dir, "gh"), 0o755);
    writeFileSync(log, "");
    const blank = { CODE_STOP: "", CODE_HEAD: "", SECURITY_STOP: "", SECURITY_HEAD: "" };
    const result = spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", run], { encoding: "utf8", env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, GITHUB_REPOSITORY: "o/r", RUNNER_TEMP: dir, ...blank, ...env } });
    const count = path.join(dir, "pr-review-main-stop-calls");
    return { status: result.status, calls: readFileSync(log, "utf8"), ...(env.COUNTED ? { counted: readFileSync(count, "utf8") } : {}) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("the report-review-counts job posts each stop as a neutral verdict=none record, from a closed reason", () => {
  const block = stepsOf("report-review-counts").find((s) => s.name === "Record the stops").text;
  // A stop run uploads no artifact, so the step never waits on the download.
  assert.doesNotMatch(block, /steps\.download/);
  assert.match(block, /\^\(too-large\|binary\|chunk-failed\)\$/);
  for (const [lane, prefix] of [["claude-review", "CODE"], ["claude-security-review", "SECURITY"]]) {
    for (const kind of ["stop", "head"]) {
      assert.equal(input(block, `${prefix}_${kind.toUpperCase()}`), `\${{ needs.review.outputs.${lane}-${kind} || needs.review-subscription.outputs.${lane}-${kind} || needs.review-fallback.outputs.${lane}-${kind} }}`);
    }
  }
  const posted = recordStops({ SECURITY_STOP: "too-large", SECURITY_HEAD: SHA_B });
  assert.equal(posted.status, 0);
  const args = posted.calls.split("\n");
  for (const arg of ["repos/o/r/check-runs", "name=pr-review-main: claude-security-review", `head_sha=${SHA_B}`, "conclusion=neutral", "output[title]=verdict=none reason=too-large"]) {
    assert.ok(args.includes(arg), arg);
  }
  assert.doesNotMatch(posted.calls, /claude-review\n/);
  assert.ok(recordStops({ CODE_STOP: "chunk-failed", CODE_HEAD: SHA_A }).calls.split("\n").includes("output[title]=verdict=none reason=chunk-failed"));
  assert.equal(recordStops({ COUNTED: "1", CODE_STOP: "binary", CODE_HEAD: SHA_A, SECURITY_STOP: "too-large", SECURITY_HEAD: SHA_B }).counted, "2\n");
  assert.deepEqual(recordStops({}), { status: 0, calls: "" });
  for (const bad of [{ CODE_STOP: "other", CODE_HEAD: SHA_A }, { CODE_STOP: "too-large", CODE_HEAD: "main" }, { CODE_STOP: "too-large\nx", CODE_HEAD: SHA_A }]) {
    const result = recordStops(bad);
    assert.notEqual(result.status, 0, JSON.stringify(bad));
    assert.equal(result.calls, "");
  }
});

function diffCase(build, maxBytes = 0) {
  const src = mkdtempSync(path.join(tmpdir(), "pr-review-main-rename-"));
  try {
    const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
    const git = (...args) => {
      if (args[0] === "mv") mkdirSync(path.dirname(path.join(src, args[2])), { recursive: true });
      const run = spawnSync("git", ["-C", src, ...args], { encoding: "utf8", env });
      assert.equal(run.status, 0, run.stderr);
      return run.stdout.trim();
    };
    const write = (file, body) => {
      mkdirSync(path.dirname(path.join(src, file)), { recursive: true });
      writeFileSync(path.join(src, file), body);
    };
    git("init", "-q");
    const symlink = (target, file) => {
      mkdirSync(path.dirname(path.join(src, file)), { recursive: true });
      symlinkSync(target, path.join(src, file));
    };
    const chmod = (file) => chmodSync(path.join(src, file), 0o755);
    build.base(write, symlink, chmod);
    git("add", "-A");
    git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base");
    const base = git("rev-parse", "HEAD");
    build.head(git, write, chmod);
    git("add", "-A");
    git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "head");
    const head = git("rev-parse", "HEAD");
    const out = path.join(src, "..", `${path.basename(src)}.patch`);
    const run = spawnSync("python3", ["-I", WRITE_DIFF, src, base, head, out, String(maxBytes)], { encoding: "utf8", env });
    assert.equal(run.status, 0, run.stderr);
    const patch = readFileSync(out, "utf8");
    rmSync(out);
    return patch;
  } finally {
    rmSync(src, { recursive: true, force: true });
  }
}
const lines = (prefix, n) => `${Array.from({ length: n }, (_, i) => `${prefix} ${i}`).join("\n")}\n`;

const fiveMoves = {
  base: (write) => {
    for (let i = 0; i < 5; i++) write(`docs/a${i}.md`, lines(`file ${i} line`, 400));
  },
  head: (git) => {
    for (let i = 0; i < 5; i++) git("mv", `docs/a${i}.md`, `guide/a${i}.md`);
  },
};

test("under the size cap every move prints whole, as --no-renames shows it", () => {
  const patch = diffCase(fiveMoves, 300000);
  assert.doesNotMatch(patch, /^rename from/m);
  for (let i = 0; i < 5; i++) {
    assert.equal(patch.match(new RegExp(`^\\+file ${i} line \\d+$`, "gm")).length, 400);
    assert.equal(patch.match(new RegExp(`^-file ${i} line \\d+$`, "gm")).length, 400);
  }
});

test("over the size cap a file moved unchanged outside the lane sources prints as its rename lines alone", () => {
  const patch = diffCase(fiveMoves, 1000);
  assert.equal(patch.match(/^rename from docs\/a\d\.md$/gm).length, 5);
  assert.equal(patch.match(/^rename to guide\/a\d\.md$/gm).length, 5);
  assert.doesNotMatch(patch, /^[+-]file /m);
  assert.ok(patch.length < 1000, `${patch.length} bytes`);
});

test("over the size cap a move an added line names prints whole, and so does one that move names", () => {
  const patch = diffCase({
    base: (write) => {
      write("tools/setup.sh", `source x/helper.sh\n${lines("hostile", 20)}`);
      write("lib/x/helper.sh", lines("helper", 20));
      write("lib/quiet.md", lines("quiet", 20));
      write("ci.yml", "steps: []\n");
    },
    head: (git, write) => {
      git("mv", "tools/setup.sh", "build/setup.sh");
      git("mv", "lib/x/helper.sh", "build/x/helper.sh");
      git("mv", "lib/quiet.md", "docs/quiet.md");
      write("ci.yml", "steps: []\nrun: bash build/setup.sh\n");
    },
  });
  for (const word of ["hostile", "helper"]) {
    assert.equal(patch.match(new RegExp(`^\\+${word} \\d+$`, "gm")).length, 20, word);
  }
  assert.match(patch, /^\+source x\/helper\.sh$/m);
  assert.match(patch, /^rename to docs\/quiet\.md$/m);
  assert.doesNotMatch(patch, /^\+quiet /m);
  assert.doesNotMatch(patch, /^rename to build\//m);
});

test("over the size cap a move a shown line names by its bare name, or its name without the extension, prints whole", () => {
  const patch = diffCase({
    base: (write) => {
      write("lib/helper.sh", lines("helper", 10));
      write("lib/payload.py", lines("payload", 10));
      write("lib/quiet.md", lines("quiet", 10));
      write("ci.sh", "true\n");
    },
    head: (git, write) => {
      git("mv", "lib/helper.sh", "tools/helper.sh");
      git("mv", "lib/payload.py", "tools/payload.py");
      git("mv", "lib/quiet.md", "docs/quiet.md");
      write("ci.sh", 'true\nsource "$(dirname "$0")/helper.sh"\nimport payload\n');
    },
  });
  for (const word of ["helper", "payload"]) {
    assert.equal(patch.match(new RegExp(`^\\+${word} \\d+$`, "gm")).length, 10, word);
  }
  assert.match(patch, /^rename to docs\/quiet\.md$/m);
  assert.doesNotMatch(patch, /^\+quiet /m);
});

test("over the size cap a move that may run or load prints whole", () => {
  const patch = diffCase({
    base: (write, _symlink) => {
      write("fixtures/evil/SKILL.md", lines("skill", 10));
      write("notes/run.md", lines("hook", 10));
      write("lib/x/conftest.py", lines("conftest", 10));
      write("lib/quiet.md", lines("quiet", 10));
    },
    head: (git) => {
      git("mv", "fixtures/evil/SKILL.md", "plugins/p/skills/evil/SKILL.md");
      git("mv", "notes/run.md", "plugins/p/hooks/run.md");
      git("mv", "lib/x/conftest.py", "tests/conftest.py");
      git("mv", "lib/quiet.md", "docs/quiet.md");
    },
  });
  for (const word of ["skill", "hook", "conftest"]) {
    assert.equal(patch.match(new RegExp(`^\\+${word} \\d+$`, "gm")).length, 10, word);
  }
  assert.match(patch, /^rename to docs\/quiet\.md$/m);
  assert.doesNotMatch(patch, /^\+quiet /m);
});

test("over the size cap a moved executable prints whole", () => {
  const patch = diffCase({
    base: (write, _symlink, chmod) => {
      write("tools/run", lines("exec", 10));
      chmod("tools/run");
    },
    head: (git) => git("mv", "tools/run", "bin/run"),
  });
  assert.doesNotMatch(patch, /^old mode/m);
  assert.equal(patch.match(/^\+exec \d+$/gm).length, 10);
});

test("over the size cap a moved symlink prints whole", () => {
  const patch = diffCase({
    base: (_write, symlink) => symlink("../../etc/hostile", "links/run"),
    head: (git) => git("mv", "links/run", "bin/run"),
  });
  // The link's target shows on both sides, as --no-renames prints it.
  assert.doesNotMatch(patch, /^rename from/m);
  assert.match(patch, /^new file mode 120000$/m);
  assert.match(patch, /^\+\.\.\/\.\.\/etc\/hostile$/m);
  assert.match(patch, /^-\.\.\/\.\.\/etc\/hostile$/m);
});

test("a move into or out of a lane source, or one that changes the mode, prints whole", () => {
  const patch = diffCase({
    base: (write) => {
      write("notes/hook.md", lines("into", 30));
      write(".github/workflows/old.yml", lines("out of", 30));
      write("tools/run.sh", lines("mode", 30));
    },
    head: (git, _write, chmod) => {
      git("mv", "notes/hook.md", ".claude/hook.md");
      git("mv", ".github/workflows/old.yml", "archive/old.yml");
      git("mv", "tools/run.sh", "tools/go.sh");
      chmod("tools/go.sh");
    },
  });
  assert.doesNotMatch(patch, /^rename from/m);
  // Each new file's every line is shown as added, each old one's as deleted.
  for (const word of ["into", "out of", "mode"]) {
    assert.equal(patch.match(new RegExp(`^\\+${word} \\d+$`, "gm")).length, 30, word);
    assert.equal(patch.match(new RegExp(`^-${word} \\d+$`, "gm")).length, 30, word);
  }
  assert.match(patch, /^new file mode 100755$/m);
});

test("an edited rename prints whole, as a delete and an add", () => {
  const patch = diffCase({
    base: (write) => write("notes.md", lines("line", 40)),
    head: (git, write) => {
      git("mv", "notes.md", "docs/notes.md");
      write("docs/notes.md", `${lines("line", 40)}run the payload\n`);
    },
  });
  assert.doesNotMatch(patch, /^rename from/m);
  assert.match(patch, /^\+line 0$/m);
  assert.match(patch, /^-line 0$/m);
  assert.match(patch, /^\+run the payload$/m);
});

test("each model step leaves a lane record", () => {
  for (const job of LEGS) {
    for (const run of RUNS) {
      const report = step(run.report, job);
      assert.match(report, /report-lane-outcome@main/);
      assert.match(report, /^ {10}lane: pr-review-main$/m);
      assert.match(report, /^ {10}lane-id: pr-review-main-\$\{\{ matrix\.lane \}\}$/m);
      assert.equal(input(report, "outcome"), `\${{ steps.${run.id}.outcome }}`);
      assert.equal(/^ {8}if: (.*)$/m.exec(report)[1], `steps.${run.id}.outcome == 'success' || steps.${run.id}.outcome == 'failure'`);
      assert.equal(index(run.report, job), index(run.name, job) + 1);
      assert.match(step(run.name, job), /^ {8}continue-on-error: true$/m);
    }
    assert.equal(input(step(RUNS[0].report, job), "step-started-at"), "${{ steps.prompt.outputs.started-at }}");
    assert.equal(input(step(RUNS[0].report, job), "step-timeout-minutes"), "22");
    assert.equal(input(step(LATER.report, job), "step-started-at"), "${{ steps.time-chunks.outputs.started-at }}");
    assert.equal(input(step(LATER.report, job), "step-timeout-minutes"), "${{ steps.prompt.outputs.loop-minutes }}");
  }
});

test("it checks out main only, and runs local actions from that checkout", () => {
  assert.equal(text.match(/uses: actions\/checkout@/g).length, LEGS.length + 2);
  const textCheckout = stepsOf(TEXT).filter((s) => /uses: actions\/checkout@/.test(s.text));
  assert.equal(textCheckout.length, 1);
  assert.match(textCheckout[0].text, /^ {10}ref: \$\{\{ needs\.check-trigger\.outputs\.main-sha \}\}\n {10}path: \.base\n {10}persist-credentials: false$/m);
  const triggerCheckout = jobText("check-trigger").split(/\n(?=      - name: )/).filter((s) => /uses: actions\/checkout@/.test(s));
  assert.equal(triggerCheckout.length, 1);
  assert.match(triggerCheckout[0], /^ {10}ref: \$\{\{ steps\.tip\.outputs\.sha \}\}$/m);
  assert.match(triggerCheckout[0], /^ {10}path: \.base$/m);
  assert.match(triggerCheckout[0], /^ {10}persist-credentials: false$/m);
  for (const job of LEGS) {
    const checkouts = STEPS[job].filter((s) => /uses: actions\/checkout@/.test(s.text));
    assert.equal(checkouts.length, 1, job);
    // The key leg checks out the tip when it starts, never github.sha, which
    // a re-run of an old run would bring back; a later leg checks out the
    // commit its lane's key leg recorded, which the route passed on.
    const ref = /^ {10}ref: (.*)$/m.exec(checkouts[0].text)[1];
    assert.equal(ref, job === KEY ? "${{ steps.tip.outputs.sha }}" : "${{ matrix.base }}", job);
    assert.equal(index("Record the main commit", job), index(checkouts[0].name, job) + 1, job);
    assert.match(step("Record the main commit", job), /^ {8}run: echo "\$LANE-base-sha=\$\(git -C \.base rev-parse --verify HEAD\)" >>"\$GITHUB_OUTPUT"$/m);
    assert.match(checkouts[0].text, /^ {10}persist-credentials: false$/m);
  }
  assert.doesNotMatch(text, /github\.sha/);
  for (const [route, from] of [["review-handoffs", KEY], ["collect-subscription-handoffs", SUB]]) {
    for (const lane of ["claude-review", "claude-security-review"]) {
      assert.match(jobText(from), new RegExp(`^ {6}${lane}-base-sha: \\$\\{\\{ steps\\.base\\.outputs\\.${lane}-base-sha \\}\\}$`, "m"));
    }
    const gated = route === "review-handoffs" ? " \\|\\| needs\\.check-trigger\\.outputs\\.main-sha" : "";
    assert.match(jobText(route), new RegExp(`^ {10}CODE_BASE: \\$\\{\\{ needs\\.${from}\\.outputs\\.claude-review-base-sha${gated} \\}\\}$`, "m"));
    assert.match(jobText(route), new RegExp(`^ {10}SECURITY_BASE: \\$\\{\\{ needs\\.${from}\\.outputs\\.claude-security-review-base-sha${gated} \\}\\}$`, "m"));
  }
  const triggerSteps = jobText("check-trigger").split(/\n(?=      - name: )/).slice(1);
  const mainAt = triggerSteps.findIndex((s) => s.startsWith("      - name: Record the main commit\n"));
  assert.match(triggerSteps[mainAt - 1], /uses: actions\/checkout@/);
  assert.match(triggerSteps[mainAt], /^ {8}id: main\n {8}run: echo "main-sha=\$\(git -C \.base rev-parse --verify HEAD\)" >>"\$GITHUB_OUTPUT"$/m);
  for (const [, local] of text.matchAll(/^\s+uses: (\.\/\S+)/gm)) {
    assert.ok(local.startsWith("./.base/.github/actions/"), local);
  }
  for (const [, remote] of text.matchAll(/^\s+uses: ([^.\s]\S*)/gm)) {
    assert.match(remote, /^(?:melodic-software\/\S+@main|(?:actions|github|dependabot|microsoft|azure|Azure|anthropics|openai)\/\S+@v\d+(?:\.\d+){0,2}|(?!(?:melodic-software|actions|github|dependabot|microsoft|azure|Azure|anthropics|openai)\/)\S+@[0-9a-f]{40})$/, remote);
  }
});

test("the model reads its data directory alone", () => {
  for (const job of LEGS) for (const run of RUNS) {
  const review = step(run.name, job);
  assert.match(review, /^ {10}tools: Read$/m);
  assert.match(review, /^ {10}allowed-tools: Read\(\.\/pr-review-main-data\/\*\*\)$/m);
  assert.match(review, /^ {10}permission-mode: dontAsk$/m);
  for (const denied of ["Read(./.base/**)", "Bash", "Write", "Edit", "WebFetch", "Agent", "mcp__*"]) {
    assert.ok(review.includes(`            ${denied}\n`), denied);
  }
  }
  for (const placeholder of ["LANE_NAME", "CRITERIA_DIR", "STANDARDS_DIR", "DIFF_PARTS", "CHUNK_NOTE", "CONTEXT_FILE", "PR_FILE"]) {
    assert.ok(prompt.includes(placeholder), placeholder);
    assert.ok(step("Write the prompt and schema").includes(`prompt=\${prompt//${placeholder}/`), placeholder);
  }
});

test("the prompt names the per-concern review rules the criteria step copies", () => {
  assert.ok(prompt.includes("its per-concern review rules (`review/`, when present;"));
  assert.match(readFileSync(new URL("./criteria.txt", import.meta.url), "utf8"), /^copy-if-present docs\/review standards\/review$/m);
});

test("the verdict uploads once, after it is written, under the writer's name", () => {
  assert.equal(text.match(/uses: actions\/upload-artifact@/g).length, LEGS.length + 3 + LEGS.length + 1);
  // The lane-hold marker is told by its artifact name, never its step name:
  // exactly one upload per job names lane-hold-pr-review-main, only after
  // Note the hold ran, with the fixed path that step wrote.
  const markerOf = (job, steps) => {
    const uploads = steps.filter((s) => /uses: actions\/upload-artifact@/.test(s.text));
    const markers = uploads.filter((s) => input(s.text, "name") === "lane-hold-pr-review-main");
    assert.equal(markers.length, 1, `${job}: one lane-hold marker upload`);
    const [marker] = markers;
    assert.match(marker.text, /^ {8}if: steps\.note-hold\.outcome == 'success'$/m, `${job}: the marker uploads only after Note the hold ran`);
    assert.equal(input(marker.text, "path"), "${{ runner.temp }}/lane-hold/pr-review-main", job);
    assert.equal(input(marker.text, "retention-days"), "1", job);
    assert.equal(input(marker.text, "if-no-files-found"), "ignore", job);
    assert.match(steps.find((s) => s.name === "Note the hold").text, /^ {8}id: note-hold$/m, job);
    return { marker, others: uploads.filter((s) => s !== marker) };
  };
  assert.deepEqual(markerOf("check-trigger", stepsOf("check-trigger")).others, [], "the check-trigger job uploads only its marker");
  for (const job of LEGS) {
    const { others: uploads } = markerOf(job, STEPS[job]);
    assert.equal(uploads.length, 1, job);
    assert.equal(uploads[0].name, "Upload the verdict");
    // The written verdict is scanned just before it uploads, and uploads only on the scan's clean output.
    assert.ok(index("Write the verdict", job) < index("Scan the upload for credentials", job), job);
    assert.equal(index("Scan the upload for credentials", job) + 1, index("Upload the verdict", job), job);
    const scan = step("Scan the upload for credentials", job);
    assert.match(scan, /^ {8}id: scan-upload\n {8}if: >-\n {10}steps\.verdict\.outcome == 'success'$/m, job);
    assert.match(scan, /^ {10}path: \$\{\{ runner\.temp \}\}\/pr-review-main-verdict\/verdict\.json$/m, job);
    assert.match(uploads[0].text, /^ {8}if: >-\n {10}\(steps\.verdict\.outcome == 'success'\) && steps\.scan-upload\.outputs\.clean == 'true'$/m);
    assert.match(uploads[0].text, /^ {10}name: \$\{\{ steps\.verdict\.outputs\.name \}\}$/m);
    // The tree is git's, the head and base the trigger gate's: never the model's.
    const write = step("Write the verdict", job);
    assert.match(write, /TREE_SHA: \$\{\{ steps\.diff\.outputs\.tree \}\}/);
    assert.match(write, /HEAD_SHA: \$\{\{ steps\.trigger\.outputs\.head-sha \}\}/);
    assert.equal(
      /^ {8}if: (.*)$/m.exec(write)[1],
      "steps.review-1.outcome == 'success' && (fromJSON(steps.diff.outputs.chunks || '0') < 2 || steps.review-chunks.outcome == 'success') && steps.review-1.outputs.handoff != 'true' && steps.review-chunks.outputs.handoff != 'true'",
      job,
    );
    assert.equal(input(write, "EXECUTION_FILE"), "${{ steps.review-1.outputs.execution-file }}", job);
    assert.equal(input(write, "CHUNKS_DIR"), "${{ steps.review-chunks.outputs.results-dir }}", job);
    assert.equal(input(write, "CHUNKS"), "${{ steps.diff.outputs.chunks }}");
  }
  assert.match(step("Write the diff"), /rev-parse --verify "\$HEAD_SHA\^\{tree\}"/);
});

test("only a lane-source pull request is reviewed, by the gate's own predicate", () => {
  const triggerStep = (name) => jobText("check-trigger").split(/\n(?=      - name: )/).find((s) => s.startsWith(`      - name: ${name}\n`));
  const triggerSelect = triggerStep("Select a lane-source pull request");
  const triggerFiles = triggerStep("Read the changed files");
  assert.ok(triggerSelect, "the check-trigger job selects");
  assert.ok(triggerFiles, "the check-trigger job reads the files first");
  for (const select of [triggerFiles, triggerSelect, ...LEGS.map((job) => step("Select a lane-source pull request", job))]) {
    assert.match(select, /import babysit_review_evidence as ev/);
    assert.match(select, /ev\.lane_source\(p\)/);
    assert.match(select, /^ {10}\. \.base\/\.github\/actions\/log-api-budget\/api-budget\.bash\n {10}\. \.base\/\.github\/scripts\/pr-merge\/rate-stop\.bash\n {10}\. \.base\/\.github\/scripts\/pr-merge\/retry-call\.bash\n {10}api_budget_wrap_gh github-token\n/m);
    assert.match(select, /retry_call --read 60 read_files/);
  }
  for (const job of LEGS) assert.match(step("Write the diff", job), /^ {8}if: steps\.trigger\.outputs\.review == 'true'$/m);
});

// The check-trigger job gates and reads the files once per run; the key leg takes
// its result only from the same run attempt, as fixed-shape values, and
// gates itself otherwise (a lane re-run alone keeps an earlier attempt's
// check-trigger job). The later legs always gate themselves.
test("the key leg takes the check-trigger job's gate only from this attempt, and every value has a fixed shape", () => {
  const trigger = jobText("check-trigger");
  assert.equal(needsOf(KEY), `[check-trigger, ${PROBE}, ${TEXT}]`);
  const outputs = /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(trigger)[1];
  assert.deepEqual(
    [...outputs.matchAll(/^ {6}([a-z-]+): (.*)$/gm)].map(([, name, value]) => `${name}=${value}`),
    [
      "run-attempt=${{ github.run_attempt }}",
      "proceed=${{ steps.gate.outputs.proceed }}",
      "review=${{ steps.select.outputs.review || steps.files.outputs.review }}",
      "pr-number=${{ steps.gate.outputs.pr-number }}",
      "head-sha=${{ steps.gate.outputs.head-sha }}",
      "base-sha=${{ steps.gate.outputs.pr-base-sha }}",
      "judged=${{ steps.judged.outputs.judged }}",
      "held=${{ steps.select.outputs.held }}",
      "main-sha=${{ steps.main.outputs.main-sha }}",
      "standards-sha=${{ steps.standards.outputs.sha }}",
    ],
  );
  assert.doesNotMatch(trigger, /head-ref/);
  const triggerGate = wf.stepNamed("check-trigger", "Check the trigger").text;
  assert.match(triggerGate, /^ {8}if: steps\.kill\.outputs\.proceed == 'true' && \(vars\.CLAUDE_REVIEW_DISABLED != 'true' \|\| vars\.CLAUDE_SECURITY_REVIEW_DISABLED != 'true'\) && steps\.files\.outputs\.review != 'false' && steps\.judged\.outputs\.judged != 'true'$/m);
  const gateWith = (block) => block.slice(block.indexOf("        uses: ")).replace(/\n\n {6}#[\s\S]*$/, "");
  assert.equal(gateWith(triggerGate), gateWith(step("Check the trigger")));
  assert.match(trigger, /- name: Log the API budget\n {8}if: always\(\)\n/);
  assert.match(step("Check the trigger"), /^ {8}if: steps\.switch\.outputs\.proceed == 'true' && needs\.check-trigger\.outputs\.run-attempt != github\.run_attempt$/m);
  for (const job of [SUB, FB]) assert.match(step("Check the trigger", job), /^ {8}if: steps\.switch\.outputs\.proceed == 'true'$/m);
  for (const job of LEGS) {
    const take = step("Take the gate's result", job);
    assert.ok(index("Select a lane-source pull request", job) < index("Take the gate's result", job), job);
    assert.match(take, /^ {8}if: steps\.switch\.outputs\.proceed == 'true' && steps\.select\.outputs\.held != 'true'$/m);
    assert.equal(input(take, "CARRIED"), job === KEY ? "${{ needs.check-trigger.outputs.run-attempt == github.run_attempt }}" : '"false"', job);
    // Every value is checked against a fixed shape before it leaves the step.
    assert.ok(take.includes("$review =~ ^(true|false)$ && $pr =~ ^[1-9][0-9]{0,9}$ && $head =~ ^[0-9a-f]{40}$ && $base =~ ^[0-9a-f]{40}$"), job);
    // The values reach the script only through env, never interpolated.
    assert.doesNotMatch(take.slice(take.indexOf("        run: |")), /\$\{\{/, job);
    const after = STEPS[job].slice(index("Take the gate's result", job) + 1).map((s) => s.text).join("\n");
    assert.doesNotMatch(after, /steps\.(gate|select)\.|needs\.check-trigger\./, job);
  }
  for (const name of ["PROCEED", "REVIEW", "PR", "HEAD", "BASE"]) {
    const key = { PROCEED: "proceed", REVIEW: "review", PR: "pr-number", HEAD: "head-sha", BASE: "base-sha" }[name];
    assert.equal(input(step("Take the gate's result"), `CARRIED_${name}`), `\${{ needs.check-trigger.outputs.${key} }}`);
  }
  for (const job of LEGS) assert.equal(input(step("Take the gate's result", job), "GATE_BASE"), "${{ steps.gate.outputs.pr-base-sha }}", job);
});

test("the check-trigger job reads the files first and gates every lane-source pull request", () => {
  const blocks = jobText("check-trigger").split(/\n(?=      - name: )/).slice(1);
  const names = blocks.map((block) => /^      - name: (.*)$/m.exec(block)[1]);
  const at = (name) => names.indexOf(name);
  assert.ok(at("Read the changed files") > at("Check the kill switch"), names.join(", "));
  assert.ok(at("Read the changed files") < at("Check the trigger"), names.join(", "));
  assert.ok(at("Check the trigger") < at("Select a lane-source pull request"), names.join(", "));
  const files = blocks[at("Read the changed files")];
  assert.match(files, /^ {8}id: files$/m);
  assert.match(files, /^ {8}if: steps\.kill\.outputs\.proceed == 'true' && \(vars\.CLAUDE_REVIEW_DISABLED != 'true' \|\| vars\.CLAUDE_SECURITY_REVIEW_DISABLED != 'true'\)$/m);
  assert.match(blocks[at("Check the trigger")], /^ {8}if: .* && steps\.files\.outputs\.review != 'false' && steps\.judged\.outputs\.judged != 'true'$/m);
  assert.ok(at("Read the changed files") < at("Find a head both lanes already reviewed"), names.join(", "));
  assert.ok(at("Find a head both lanes already reviewed") < at("Check the trigger"), names.join(", "));
  assert.match(blocks[at("Select a lane-source pull request")], /^ {8}if: steps\.gate\.outputs\.proceed == 'true' && \(steps\.files\.outputs\.review != 'true' \|\| steps\.files\.outputs\.pr-number != steps\.gate\.outputs\.pr-number\)$/m);
  assert.equal(input(files, "PULLS"), "${{ toJSON(github.event.workflow_run.pull_requests) }}");
  assert.equal(input(files, "HEAD_SHA"), "${{ github.event.workflow_run.head_sha }}");
  const run = /^ {8}run: \|\n((?: {10}.*\n)+)/m.exec(`${files}\n`)[1].replace(/^ {10}/gm, "");
  // Event values reach the script only through env.
  assert.doesNotMatch(run, /\$\{\{/);
  const harness = filesHarness();
  try {
    const pull = (number, sha = SHA_A, repo = 42) => ({ number, head: { sha }, base: { repo: { id: repo } } });
    const runWith = (pulls, extra = {}) => {
      const result = harness.run(run, { PULLS: JSON.stringify(pulls), HEAD_SHA: SHA_A, REPO_ID: "42", ...extra });
      assert.equal(result.status, 0, result.stderr);
      return result;
    };
    const lane = runWith([pull(7)], { GH_PATHS: ".github/workflows/x.yml README.md" });
    assert.equal(lane.out, "pr-number=7\nreview=true\n");
    assert.match(lane.calls, /^api --paginate repos\/o\/r\/pulls\/7\/files\?per_page=100 /);
    assert.equal(runWith([pull(7)], { GH_PATHS: "README.md plugins/x/y.py" }).out, "pr-number=7\nreview=false\n");
    for (const pulls of [[], [pull(7), pull(8)], [pull(7, SHA_B)], [pull(7, SHA_A, 99)], [{ number: "7; x", head: { sha: SHA_A }, base: { repo: { id: 42 } } }]]) {
      const none = runWith(pulls, { GH_PATHS: "README.md" });
      assert.equal(none.out, "", JSON.stringify(pulls));
      assert.equal(none.calls, "", JSON.stringify(pulls));
    }
    const again = runWith([pull(7)], { GH_FAIL: "1", GH_PATHS: ".github/workflows/x.yml" });
    assert.equal(again.out, "pr-number=7\nreview=true\n");
    assert.equal(again.calls.split("\n").filter(Boolean).length, 2);
    assert.equal(again.sleeps.split("\n").filter(Boolean).length, 1);
    const unread = runWith([pull(7)], { GH_FAIL: "9", GH_PATHS: "README.md" });
    assert.equal(unread.out, "");
    assert.equal(unread.calls.split("\n").filter(Boolean).length, 3);
    assert.match(unread.stdout, /^::warning::the file list did not read \(failed 3 times\); the trigger gate runs$/m);
  } finally {
    harness.remove();
  }
});

function filesHarness() {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-files-"));
  mkdirSync(path.join(dir, ".base"));
  mkdirSync(path.join(dir, "tmp"));
  symlinkSync(new URL("../../../plugins", import.meta.url).pathname, path.join(dir, ".base", "plugins"));
  symlinkSync(new URL("../../../.github", import.meta.url).pathname, path.join(dir, ".base", ".github"));
  const bin = path.join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(path.join(bin, "gh"), '#!/bin/bash\necho "$*" >>"$GH_LOG"\n[ "$(wc -l <"$GH_LOG")" -le "${GH_FAIL:-0}" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }\nprintf "%s\\n" $GH_PATHS\n');
  writeFileSync(path.join(bin, "sleep"), '#!/bin/bash\necho "$1" >>"$SLEEP_LOG"\n');
  chmodSync(path.join(bin, "gh"), 0o755);
  chmodSync(path.join(bin, "sleep"), 0o755);
  const run = (script, extra = {}) => {
    const out = path.join(dir, "out");
    const log = path.join(dir, "gh.log");
    const sleeps = path.join(dir, "sleep.log");
    for (const file of [out, log, sleeps]) writeFileSync(file, "");
    rmSync(path.join(dir, "tmp", "api-budget"), { recursive: true, force: true });
    const result = spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", script], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: path.join(dir, "tmp"), GITHUB_OUTPUT: out, GITHUB_REPOSITORY: "o/r", GH_LOG: log, SLEEP_LOG: sleeps, FILES: path.join(dir, "files.txt"), GH_PATHS: "", GH_FAIL: "0", ...extra },
    });
    return { status: result.status, stdout: result.stdout, stderr: result.stderr, out: readFileSync(out, "utf8"), calls: readFileSync(log, "utf8"), sleeps: readFileSync(sleeps, "utf8") };
  };
  return { run, remove: () => rmSync(dir, { recursive: true, force: true }) };
}

// Every select reads the files up to 3 times, and a list still unread holds
// the step green with a `held: ` notice and no review, which the lost-run
// reconciler re-runs once (reconcile.mjs faultHeld).
test("each select reads the files again after a failure and holds green on a list still unread", () => {
  const triggerSelect = jobText("check-trigger").split(/\n(?=      - name: )/).find((s) => s.startsWith("      - name: Select a lane-source pull request\n"));
  const harness = filesHarness();
  try {
    for (const [job, block] of [["check-trigger", triggerSelect], ...LEGS.map((job) => [job, step("Select a lane-source pull request", job)])]) {
      const run = /^ {8}run: \|\n((?: {10}.*\n)+)/m.exec(`${block}\n`)[1].replace(/^ {10}/gm, "");
      assert.doesNotMatch(run, /\$\{\{/, job);
      const good = harness.run(run, { PR_NUMBER: "7", GH_PATHS: ".github/workflows/x.yml" });
      assert.equal(good.status, 0, `${job}: ${good.stderr}`);
      assert.equal(good.out, "review=true\n", job);
      assert.match(good.calls, /^api --paginate repos\/o\/r\/pulls\/7\/files\?per_page=100 /, job);
      assert.equal(good.calls.split("\n").filter(Boolean).length, 1, job);
      assert.equal(harness.run(run, { PR_NUMBER: "7", GH_PATHS: "README.md" }).out, "review=false\n", job);
      const third = harness.run(run, { PR_NUMBER: "7", GH_FAIL: "2", GH_PATHS: ".github/workflows/x.yml" });
      assert.equal(third.status, 0, `${job}: ${third.stderr}`);
      assert.equal(third.out, "review=true\n", job);
      assert.equal(third.calls.split("\n").filter(Boolean).length, 3, job);
      assert.equal(third.sleeps.split("\n").filter(Boolean).length, 2, job);
      const unread = harness.run(run, { PR_NUMBER: "7", GH_FAIL: "9", GH_PATHS: "README.md" });
      assert.equal(unread.status, 0, `${job}: ${unread.stderr}`);
      assert.equal(unread.out, "held=true\n", job);
      assert.equal(unread.calls.split("\n").filter(Boolean).length, 3, job);
      assert.match(unread.stdout, /^::notice title=pr-review-main::held: the file list did not read \(failed 3 times\); no review, and the lost-run reconciler re-runs this run once$/m, job);
      assert.ok(heldNoted([{ annotation_level: "notice", message: /^::notice title=pr-review-main::(.*)$/m.exec(unread.stdout)[1] }]), job);
      assert.doesNotMatch(unread.stdout, /::error::/, job);
    }
  } finally {
    harness.remove();
  }
});

const KEY_SKIP = "      && (needs.check-trigger.outputs.run-attempt != github.run_attempt\n      || needs.check-trigger.outputs.review != 'false' && needs.check-trigger.outputs.judged != 'true' && needs.check-trigger.outputs.held != 'true')\n";

const RECORD_IF = /^ {4}if: \$\{\{ !cancelled\(\) && github\.ref == 'refs\/heads\/main' && \(needs\.review\.result != 'skipped' \|\| needs\.review-subscription\.result != 'skipped'\) \}\}$/m;

test("no leg starts, and nothing records, for a head with no lane source or one both lanes reviewed", () => {
  assert.ok(/^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(jobText(KEY))[1].endsWith(KEY_SKIP));
  assert.match(jobText("report-review-counts"), RECORD_IF);
  for (const report of ["Report the skipped claude-review key leg", "Report the skipped claude-security-review key leg"]) {
    const condition = /^ {8}if: (.*)$/m.exec(step(report, PROBE))[1];
    for (const term of GO_AHEAD.slice(1)) assert.ok(condition.includes(` && ${term} && `), `${report}: ${term}`);
  }
  for (const term of GO_AHEAD) assert.ok(jobGate("review-handoffs").includes(`&& ${term}`), term);
});

// A select whose file list did not read holds: Note the hold (the step the
// reconciler's faultHeld looks for) runs, and no lane reviews after it, in
// the check-trigger job or in any leg.
test("a held file list marks the run and starts no review, in the check-trigger job and every leg", () => {
  const selected = (held) => ({ steps: { switch: { outputs: { proceed: "true" } }, select: { outputs: held === undefined ? {} : { held } } } });
  const triggerSteps = stepsOf("check-trigger");
  for (const [job, steps] of [["check-trigger", triggerSteps], ...LEGS.map((job) => [job, STEPS[job]])]) {
    const names = steps.map((s) => s.name);
    assert.equal(names[names.indexOf("Select a lane-source pull request") + 1], HELD_STEP, job);
    const marker = /^ {8}if: (.*)$/m.exec(steps.find((s) => s.name === HELD_STEP).text)[1];
    assert.ok(admits(marker, selected("true")), job);
    for (const held of [undefined, "", "false"]) assert.ok(!admits(marker, selected(held)), `${job}: ${held}`);
    if (job === "check-trigger") continue;
    const take = /^ {8}if: (.*)$/m.exec(step("Take the gate's result", job))[1];
    assert.ok(admits(take, selected(undefined)), job);
    assert.ok(!admits(take, selected("true")), job);
  }
  const held = { ...triggered, outputs: { ...triggered.outputs, held: "true" } };
  const probe = { result: "success", outputs: {} };
  const keyRuns = (trigger) => admits(jobGate(KEY), { github: upstreamRun, needs: { "check-trigger": trigger, [PROBE]: probe } });
  assert.ok(keyRuns(triggered));
  assert.ok(!keyRuns(held));
  const handsOn = (trigger) => admits(jobGate("review-handoffs"), { github: upstreamRun, needs: { "check-trigger": trigger, review: { result: "skipped", outputs: {} }, [PROBE]: { result: "success", outputs: { "next-leg": "subscription" } } } });
  assert.ok(handsOn(triggered));
  assert.ok(!handsOn(held));
  assert.ok(keyRuns({ ...held, outputs: { ...held.outputs, "run-attempt": "0" } }));
});

const GO_AHEAD = ["needs.check-trigger.outputs.run-attempt == github.run_attempt", "needs.check-trigger.outputs.proceed == 'true'", "needs.check-trigger.outputs.review == 'true'", "needs.check-trigger.outputs.judged != 'true'", "needs.check-trigger.outputs.held != 'true'"];

const jobGate = wf.jobIf;
const upstreamRun = { ref: "refs/heads/main", repository: "o/r", run_attempt: "1", event: { workflow_run: { event: "pull_request", conclusion: "success", head_repository: { full_name: "o/r" } } } };
const triggered = { result: "success", outputs: { "run-attempt": "1", proceed: "true", review: "true", judged: "" } };

// ci-workflows select-model-credential's start call (select.cjs at the pinned
// SHA): next-leg is `subscription` only while a credit stop recorded in this
// workflow is inside the window; any failure leaves it empty, so the key runs
// as before the gate.
test("the credit gate skips the key leg only on next-leg subscription, and a gate failure runs the key", () => {
  const keyIf = jobGate(KEY);
  assert.ok(keyIf.startsWith(`needs.${PROBE}.outputs.next-leg != 'subscription' && !cancelled() && needs.check-trigger.result == 'success' && `), keyIf);
  const runs = (probe, trigger = triggered, options) => admits(keyIf, { github: upstreamRun, needs: { "check-trigger": trigger, [PROBE]: probe } }, options);
  assert.ok(!runs({ result: "success", outputs: { "next-leg": "subscription" } }));
  for (const probe of [{ result: "success", outputs: { "next-leg": "key" } }, { result: "failure", outputs: {} }, { result: "skipped", outputs: {} }]) {
    assert.ok(runs(probe), JSON.stringify(probe));
  }
  // The check-trigger job's own result still gates the key leg, as the implicit success() did.
  assert.ok(!runs({ result: "failure", outputs: {} }, { ...triggered, result: "failure" }));
  assert.ok(!runs({ result: "success", outputs: {} }, triggered, { status: "cancelled" }));
  const probeRuns = (trigger) => admits(jobGate(PROBE), { github: upstreamRun, needs: { "check-trigger": trigger } });
  const reviewRuns = (trigger) => admits(jobGate(KEY), { github: upstreamRun, needs: { "check-trigger": trigger, [PROBE]: { result: "skipped", outputs: {} } } });
  for (const outputs of [{}, { proceed: "" }, { review: "" }]) {
    const trigger = { ...triggered, outputs: { ...triggered.outputs, ...outputs } };
    assert.ok(probeRuns(trigger), JSON.stringify(outputs));
  }
  for (const outputs of [{ review: "false" }, { judged: "true" }, { held: "true" }]) {
    const trigger = { ...triggered, outputs: { ...triggered.outputs, ...outputs } };
    assert.ok(!probeRuns(trigger), JSON.stringify(outputs));
    assert.ok(!reviewRuns(trigger), `the review job runs where the gate skipped: ${JSON.stringify(outputs)}`);
  }
  assert.ok(!probeRuns({ ...triggered, outputs: { ...triggered.outputs, "run-attempt": "2" } }));
  assert.ok(!admits(jobGate(PROBE), { github: { ...upstreamRun, ref: "refs/heads/x" }, needs: { "check-trigger": triggered } }));
});

test("the credit gate holds no secret, checks nothing out and reads only the marker artifacts", () => {
  const job = jobText(PROBE);
  assert.equal(needsOf(PROBE), "check-trigger");
  assert.match(job, /^ {4}permissions:\n {6}actions: read #.*\n {4}outputs:\n {6}next-leg: \$\{\{ steps\.gate\.outputs\.next-leg \}\}\n {6}next-reason: \$\{\{ steps\.gate\.outputs\.next-reason \}\}\n {6}marker: \$\{\{ steps\.gate\.outputs\.marker \}\}\n/m);
  assert.doesNotMatch(job, /secrets\.|actions\/checkout|run-claude-cli|\.\/\.base/);
  const gate = step("Read the key's credit history", PROBE);
  assert.match(gate, /^ {8}id: gate$/m);
  assert.match(gate, /^ {8}continue-on-error: true$/m);
  assert.match(gate, SELECT_USES);
  assert.equal(input(gate, "leg"), "start");
  assert.equal(input(gate, "key-job"), "review-handoffs");
  assert.equal(input(gate, "window-hours"), "${{ vars.KEY_CREDIT_WINDOW_HOURS }}");
  assert.equal(input(gate, "reset-at"), "${{ vars.KEY_CREDIT_RESET_AT }}");
  assert.equal(input(gate, "probe-minutes"), undefined);
  for (const [lane, sw] of [["claude-review", "CLAUDE_REVIEW_DISABLED"], ["claude-security-review", "CLAUDE_SECURITY_REVIEW_DISABLED"]]) {
    const report = step(`Report the skipped ${lane} key leg`, PROBE);
    assert.match(report, new RegExp(`^ {8}if: steps\\.gate\\.outputs\\.next-leg == 'subscription' && ${GO_AHEAD.slice(1).join(" && ").replace(/[.()|]/g, "\\$&")} && vars\\.${sw} != 'true'$`, "m"));
    assert.equal(input(report, "outcome"), "skipped");
    assert.equal(input(report, "lane-id"), `pr-review-main-${lane}`);
    assert.equal(input(report, "credential"), "REVIEWS_CLAUDE_API_KEY");
    assert.equal(input(report, "known-failure-class"), "credit-stop");
    assert.equal(input(report, "handoff"), '"true"');
  }
});

// ci-workflows#980 (09cf6f2): past a credit stop's window, the gate names this
// run the probe in its `probing-marker` output, and later gates skip while that
// artifact is fresh. pr-review-cli.yml's gate job at that SHA writes, scans and
// uploads it right after the read; this gate job does the same, scanning with
// ci-workflows' scan-upload since it checks nothing out.
test("the credit gate writes, scans and uploads the probing marker right after the gate", () => {
  // gate.cjs probeName at 09cf6f2: `key-credit-probing-${workflow file}-${key-job}`.
  const probe = "key-credit-probing-REVIEWS_CLAUDE_API_KEY";
  const names = ["Write the key's probing marker", "Scan the key's probing marker for credentials", "Upload the key's probing marker"];
  const [write, scan, upload] = names.map((name) => step(name, PROBE));
  assert.match(write, /^ {8}id: probe-marker$/m);
  const writeIf = /^ {8}if: (.*)$/m.exec(write)[1];
  assert.equal(writeIf, `always() && steps.gate.outputs.probing-marker == '${probe}' && needs.check-trigger.outputs.proceed == 'true' && needs.check-trigger.outputs.review != 'false' && needs.check-trigger.outputs.judged != 'true' && needs.check-trigger.outputs.held != 'true'`);
  assert.equal(triggered.outputs.proceed, "true");
  const writes = (output, outputs = triggered.outputs) =>
    admits(writeIf.replace(/^always\(\) && /, ""), { steps: { gate: { outputs: { "probing-marker": output } } }, needs: { "check-trigger": { outputs } } });
  assert.ok(writes(probe));
  for (const output of ["", "key-credit-probing-pr-review-main.yml-other"]) assert.ok(!writes(output), output);
  for (const outputs of [{ judged: "true" }, { review: "false" }, { proceed: "" }, { proceed: "false" }, { held: "true" }]) {
    assert.ok(!writes(probe, { ...triggered.outputs, ...outputs }), JSON.stringify(outputs));
  }
  assert.match(write, /echo "\$GITHUB_RUN_ID" >"\$RUNNER_TEMP\/key-credit-probing\/run-id"/);
  assert.match(scan, /^ {8}id: probe-marker-scan$/m);
  assert.match(scan, /^ {8}if: always\(\) && steps\.probe-marker\.outcome == 'success'$/m);
  assert.match(scan, /^ {8}uses: melodic-software\/ci-workflows\/\.github\/actions\/scan-upload@main/m);
  assert.match(upload, /^ {8}if: \(always\(\) && steps\.probe-marker\.outcome == 'success'\) && steps\.probe-marker-scan\.outputs\.clean == 'true'$/m);
  assert.match(upload, /^ {8}uses: actions\/upload-artifact@v7/m);
  assert.equal(input(upload, "name"), probe);
  assert.equal(input(upload, "path"), "${{ runner.temp }}/key-credit-probing/run-id");
  assert.equal(input(scan, "path"), input(upload, "path"));
  assert.equal(input(upload, "retention-days"), "1");
  assert.equal(input(upload, "if-no-files-found"), "error");
  for (const block of [write, scan, upload]) assert.match(block, /^ {8}continue-on-error: true$/m);
  assert.equal(index(names[0], PROBE), index("Read the key's credit history", PROBE) + 1);
  assert.equal(index(names[1], PROBE), index(names[0], PROBE) + 1);
  assert.equal(index(names[2], PROBE), index(names[1], PROBE) + 1);
  assert.ok(index(names[2], PROBE) < index("Report the skipped claude-review key leg", PROBE));
  // The upload adds no job permission: the runner's token sends it.
  assert.match(jobText(PROBE), /^ {4}permissions:\n {6}actions: read #.*\n {4}outputs:/m);
  for (const job of [...LEGS, "review-handoffs"]) for (const name of names) assert.equal(index(name, job), -1, `${job} ${name}`);
});

// check-key-credit gate.cjs lists only artifacts named by its `marker` output,
// so review-handoffs must upload that artifact after a key leg's credit stop.
test("review-handoffs uploads the gate's marker only after a key leg's credit stop", () => {
  assert.match(needsOf("review-handoffs"), new RegExp(`\\b${PROBE}\\b`));
  const write = step("Write the key's credit-stop marker", "review-handoffs");
  assert.match(write, /^ {8}id: credit-marker$/m);
  assert.match(write, /^ {8}if: \$\{\{ !cancelled\(\) && needs\.review-handoffs-credit\.outputs\.marker != '' && \(needs\.review\.outputs\.claude-review == 'credit-stop' \|\| needs\.review\.outputs\.claude-security-review == 'credit-stop'\) \}\}$/m);
  assert.match(write, /^ {8}continue-on-error: true$/m);
  assert.match(write, /echo "\$GITHUB_RUN_ID" >"\$RUNNER_TEMP\/key-credit-stop\/run-id"/);
  const upload = step("Upload the key's credit-stop marker", "review-handoffs");
  assert.ok(index("Upload the key's credit-stop marker", "review-handoffs") > index("Write the key's credit-stop marker", "review-handoffs"));
  assert.match(upload, /^ {8}if: \$\{\{ !cancelled\(\) && steps\.credit-marker\.outcome == 'success' \}\}$/m);
  assert.match(upload, /^ {8}continue-on-error: true$/m);
  assert.match(upload, /^ {8}uses: actions\/upload-artifact@v7/m);
  assert.equal(input(upload, "name"), "${{ needs.review-handoffs-credit.outputs.marker }}");
  assert.equal(input(upload, "path"), "${{ runner.temp }}/key-credit-stop/run-id");
  assert.equal(input(upload, "if-no-files-found"), "error");
  assert.equal(input(upload, "retention-days"), "1");
  assert.doesNotMatch(text, /Record the key's credit stop/);
  for (const job of LEGS) assert.equal(index("Upload the key's credit-stop marker", job), -1, job);
});

test("with the key leg skipped by the credit gate, every enabled lane goes to the subscription leg as a credit stop", () => {
  const route = jobText("review-handoffs");
  assert.equal(needsOf("review-handoffs"), `[check-trigger, ${PROBE}, ${KEY}]`);
  const routeIf = jobGate("review-handoffs");
  const handsOn = (review, probe, trigger = triggered) => admits(routeIf, { github: upstreamRun, needs: { "check-trigger": trigger, review, [PROBE]: probe } });
  const gated = { result: "success", outputs: { "next-leg": "subscription", "next-reason": "credit-stop" } };
  assert.ok(handsOn({ result: "skipped", outputs: {} }, gated));
  assert.ok(handsOn({ result: "success", outputs: { "claude-review": "credit-stop" } }, { result: "success", outputs: { "next-leg": "key" } }));
  assert.ok(!handsOn({ result: "skipped", outputs: {} }, { result: "skipped", outputs: {} }));
  assert.ok(!handsOn({ result: "success", outputs: {} }, { result: "success", outputs: { "next-leg": "key" } }));
  for (const outputs of [{ review: "false" }, { judged: "true" }, { proceed: "" }, { "run-attempt": "2" }]) {
    assert.ok(!handsOn({ result: "skipped", outputs: {} }, gated, { ...triggered, outputs: { ...triggered.outputs, ...outputs } }), JSON.stringify(outputs));
  }
  for (const [env, lane, sw] of [["CODE", "claude-review", "CLAUDE_REVIEW_DISABLED"], ["SECURITY", "claude-security-review", "CLAUDE_SECURITY_REVIEW_DISABLED"]]) {
    assert.match(route, new RegExp(`^ {10}${env}: \\$\\{\\{ needs\\.review\\.outputs\\.${lane} \\|\\| needs\\.review\\.result == 'skipped' && needs\\.${PROBE}\\.outputs\\.next-leg == 'subscription' && vars\\.${sw} != 'true' && needs\\.${PROBE}\\.outputs\\.next-reason \\|\\| '' \\}\\}$`, "m"));
  }
  const { status, matrix } = routeRun("review-handoffs")({ CODE: "credit-stop", SECURITY: "credit-stop", CODE_BASE: SHA_A, SECURITY_BASE: SHA_A });
  assert.equal(status, 0);
  assert.deepEqual(matrix.include.map((row) => [row.lane, row.reason, row.base]), [["claude-review", "credit-stop", SHA_A], ["claude-security-review", "credit-stop", SHA_A]]);
});

test("a head both lanes reviewed in a successful main run, recorded on the head, is judged; anything less is not", () => {
  const block = jobText("check-trigger").split(/\n(?=      - name: )/).find((s) => s.startsWith("      - name: Find a head both lanes already reviewed\n"));
  assert.ok(block, "the check-trigger job reads the judged head");
  assert.match(block, /^ {8}id: judged$/m);
  assert.match(block, /^ {8}if: steps\.files\.outputs\.review == 'true'$/m);
  assert.equal(input(block, "PR_NUMBER"), "${{ steps.files.outputs.pr-number }}");
  assert.equal(input(block, "HEAD_SHA"), "${{ github.event.workflow_run.head_sha }}");
  assert.equal(input(block, "TREE_SHA"), "${{ github.event.workflow_run.head_commit.tree_id }}");
  assert.equal(input(block, "STANDARDS_SHA"), "${{ steps.standards.outputs.sha }}");
  const run =/^ {8}run: \|\n((?: {10}.*\n|\n)+)/m.exec(`${block}\n`)[1].replace(/^ {10}/gm, "");
  assert.doesNotMatch(run, /\$\{\{/);
  assert.match(run, /\{ \. \.base\/\.github\/actions\/log-api-budget\/api-budget\.bash 2>\/dev\/null && api_budget_wrap_gh github-token; \} \|\| true\n/);
  assert.match(run, /\{ \. \.base\/\.github\/scripts\/pr-merge\/rate-stop\.bash && \. \.base\/\.github\/scripts\/pr-merge\/retry-call\.bash; \} 2>\/dev\/null \|\| true\n/);
  assert.deepEqual(run.match(/^ *gh api .*/gm).map((line) => line.trim()), ['gh api "$@" >"$file"'], "every read goes through try_read api_into");
  const gh = readFileSync(new URL("../../../plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py", import.meta.url), "utf8");
  assert.ok(gh.includes(`MAIN_REVIEW_CHECK_TITLE = re.compile(r"findings=(\\d{1,6}) critical=(\\d{1,6})")`));
  assert.ok(run.includes(`title = re.compile(r"findings=(\\d{1,6}) critical=(\\d{1,6})")`));
  const TREE = "c".repeat(40);
  const PR = 7;
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-judged-"));
  try {
    // main's history: OLD, then CHANGED (REVIEW.md, a criterion, changes),
    // then the tip (only a file outside criteria.txt changes). Off the tip,
    // one commit per SIDE file changes that criterion alone: the skill (a
    // {skill} row), a copy-if-present row and a read row. The step's
    // checkout is a one-commit clone of the tip, as actions/checkout makes.
    const gitEnv = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1", GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.com", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.com" };
    const git = (...args) => {
      const result = spawnSync("git", args, { encoding: "utf8", env: gitEnv });
      assert.equal(result.status, 0, result.stderr);
      return result.stdout.trim();
    };
    const origin = path.join(dir, "origin");
    mkdirSync(path.join(origin, ".github", "scripts", "pr-review-main"), { recursive: true });
    git("-C", origin, "init", "--quiet");
    writeFileSync(path.join(origin, ".github", "scripts", "pr-review-main", "criteria.txt"), readFileSync(new URL("./criteria.txt", import.meta.url)));
    const commit = (file, text) => {
      mkdirSync(path.dirname(path.join(origin, file)), { recursive: true });
      writeFileSync(path.join(origin, file), text);
      git("-C", origin, "add", "-A");
      git("-C", origin, "commit", "--quiet", "-m", file);
      return git("-C", origin, "rev-parse", "HEAD");
    };
    const SIDE = ["plugins/review/skills/code-review/SKILL.md", "plugins/review/reference/x.md", "docs/review/x.md", ".github/workflows/pr-review-main.yml"];
    for (const file of SIDE) commit(file, "criterion\n");
    const OLD = commit("REVIEW.md", "old criteria\n");
    const CHANGED = commit("REVIEW.md", "new criteria\n");
    const TIP = commit("notes.txt", "not a criterion\n");
    const trunk = git("-C", origin, "symbolic-ref", "--short", "HEAD");
    const side = SIDE.map((file, i) => {
      git("-C", origin, "switch", "--quiet", "-c", `side-${i}`, TIP);
      return [file, commit(file, "changed criterion\n")];
    });
    git("-C", origin, "switch", "--quiet", trunk);
    git("clone", "--quiet", "--depth=1", `file://${origin}`, path.join(dir, ".base"));
    const has = (sha) => spawnSync("git", ["-C", path.join(dir, ".base"), "cat-file", "-e", `${sha}^{commit}`], { env: gitEnv }).status === 0;
    assert.ok(!has(CHANGED) && !has(OLD), "the checkout holds the tip alone");
    symlinkSync(new URL("../../../plugins/source-control", import.meta.url).pathname, path.join(dir, ".base", "plugins", "source-control"));
    symlinkSync(new URL("../../actions", import.meta.url).pathname, path.join(dir, ".base", ".github", "actions"));
    symlinkSync(new URL("../pr-merge", import.meta.url).pathname, path.join(dir, ".base", ".github", "scripts", "pr-merge"));
    const bin = path.join(dir, "bin");
    const fixtures = path.join(dir, "fixtures");
    mkdirSync(bin);
    writeFileSync(
      path.join(bin, "gh"),
      '#!/bin/bash\necho "$*" >>"$GH_LOG"\n[ "$2" = -i ] && set -- "$1" "${@:3}"\nif [ -n "$GH_FAIL_URL" ] && [[ $2 == *"$GH_FAIL_URL"* ]] && [ "$(grep -cF -- "$GH_FAIL_URL" "$GH_LOG")" -le "${GH_FAIL:-0}" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi\nf="$GH_FIXTURES/$(printf %s "$2" | tr -c "A-Za-z0-9" _)"\n[ -f "$f" ] || exit 1\ncat "$f"\n',
    );
    writeFileSync(path.join(bin, "sleep"), '#!/bin/bash\necho "$1" >>"$SLEEP_LOG"\n');
    chmodSync(path.join(bin, "gh"), 0o755);
    chmodSync(path.join(bin, "sleep"), 0o755);
    const key = (url) => url.replace(/[^A-Za-z0-9]/g, "_");
    const lanes = ["claude-review", "claude-security-review"];
    const RUN_AT = "2026-01-02T00:00:00Z";
    const retarget = (created_at) => ({ event: "base_ref_changed", ...(created_at === undefined ? {} : { created_at }) });
    const STANDARDS = "e".repeat(40);
    const write = ({ missing = [], conclusion = "success", head = SHA_A, standards = STANDARDS, title = "findings=2 critical=0", branch = "main", event = "workflow_run", total = 1, main = TIP, workflow = ".github/workflows/pr-review-main.yml", events = [{ event: "labeled", created_at: "2026-01-03T00:00:00Z" }] } = {}) => {
      rmSync(fixtures, { recursive: true, force: true });
      mkdirSync(fixtures);
      const at = (url, body) => writeFileSync(path.join(fixtures, key(url)), typeof body === "string" ? body : JSON.stringify(body));
      at(`repos/o/r/issues/${PR}/events?per_page=100`, events);
      lanes.forEach((lane, i) => {
        const name = `pr-review-main-${lane}-${PR}-${TREE}`;
        const artifact = 100 + i;
        const runId = 200 + i;
        if (missing.includes(lane)) return at(`repos/o/r/actions/artifacts?name=${name}&per_page=100`, { total_count: 0, artifacts: [] });
        at(`repos/o/r/actions/artifacts?name=${name}&per_page=100`, { total_count: total, artifacts: [{ id: artifact, name, expired: false, workflow_run: { id: runId } }] });
        at(`repos/o/r/actions/runs/${runId}`, { id: runId, path: workflow, event, head_branch: branch, head_sha: main, status: "completed", conclusion, created_at: RUN_AT, repository: { full_name: "o/r" }, head_repository: { full_name: "o/r" } });
        const verdict = path.join(dir, "verdict.json");
        writeFileSync(verdict, JSON.stringify({ schema: 1, lane, pr: PR, tree: TREE, head_sha: head, ...(standards === null ? {} : { standards_sha: standards }), findings: 2, critical: 0, max_line_bytes: 80 }));
        const zipped = spawnSync("python3", ["-I", "-c", "import sys, zipfile; zipfile.ZipFile(sys.argv[1], 'w').write(sys.argv[2], 'verdict.json')", path.join(fixtures, key(`repos/o/r/actions/artifacts/${artifact}/zip`)), verdict], { encoding: "utf8" });
        assert.equal(zipped.status, 0, zipped.stderr);
        at(`repos/o/r/commits/${SHA_A}/check-runs?check_name=pr-review-main%3A%20${lane}&filter=all&per_page=100`, { total_count: 2, check_runs: [{ app: { slug: "github-actions" }, output: { title } }, { app: { slug: "someone" }, output: { title: "findings=2 critical=0" } }] });
      });
    };
    const runWith = (env = {}) => {
      const out = path.join(dir, "out");
      const log = path.join(dir, "gh.log");
      const sleeps = path.join(dir, "sleep.log");
      for (const file of [out, log, sleeps]) writeFileSync(file, "");
      rmSync(path.join(dir, "tmp"), { recursive: true, force: true });
      mkdirSync(path.join(dir, "tmp"));
      const result = spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", run], {
        cwd: dir,
        encoding: "utf8",
        env: { ...gitEnv, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: path.join(dir, "tmp"), GITHUB_OUTPUT: out, GITHUB_REPOSITORY: "o/r", GH_LOG: log, SLEEP_LOG: sleeps, GH_FIXTURES: fixtures, GH_FAIL_URL: "", GH_FAIL: "0", PR_NUMBER: String(PR), HEAD_SHA: SHA_A, TREE_SHA: TREE, STANDARDS_SHA: STANDARDS, DIR: path.join(dir, "work"), ...env },
      });
      assert.equal(result.status, 0, result.stderr + result.stdout);
      const lines = (file) => readFileSync(file, "utf8").split("\n").filter(Boolean);
      return { out: readFileSync(out, "utf8"), stdout: result.stdout, calls: lines(log), sleeps: lines(sleeps) };
    };
    write();
    const judged = runWith();
    assert.equal(judged.out, "judged=true\n");
    assert.equal(judged.calls.length, 9, judged.calls.join("\n"));
    assert.ok(judged.calls.every((call) => call.startsWith("api -i repos/o/r/")), judged.calls.join("\n"));
    assert.equal(judged.calls[8], `api -i repos/o/r/issues/${PR}/events?per_page=100`);
    assert.equal(judged.sleeps.length, 0);
    for (const [why, events, said] of [
      ["retargeted before the run", [retarget("2026-01-01T00:00:00Z")], "both lanes already reviewed this head: true"],
      ["retargeted after the run", [retarget("2026-01-03T00:00:00Z")], "both lanes already reviewed this head: false"],
      ["retargeted as the run was created", [retarget(RUN_AT)], "both lanes already reviewed this head: false"],
      ["the newest of two retargets after the run", [retarget("2026-01-03T00:00:00Z"), retarget("2026-01-01T00:00:00Z")], "both lanes already reviewed this head: false"],
      ["a retarget with no time", [retarget()], "::warning::a verdict did not read; the review runs"],
      ["a retarget with no zone", [retarget("2026-01-01T00:00:00")], "::warning::a verdict did not read; the review runs"],
      ["a full page of events", Array.from({ length: 100 }, () => retarget("2026-01-01T00:00:00Z")), "::warning::the pull request's events did not read; the review runs"],
      ["events that are no list", { event: "base_ref_changed" }, "::warning::the pull request's events did not read; the review runs"],
    ]) {
      write({ events });
      const cut = runWith();
      assert.equal(cut.out, said.endsWith(": true") ? "judged=true\n" : "", why);
      assert.equal(cut.calls.length, 9, `${why}\n${cut.calls.join("\n")}`);
      assert.ok(cut.stdout.split("\n").includes(said), `${why}\n${cut.stdout}`);
    }
    write();
    const READS = [
      ["the claude-review verdict listing", "actions/artifacts?name=pr-review-main-claude-review-", 1],
      ["run 200", "actions/runs/200", 2],
      ["artifact 100", "actions/artifacts/100/zip", 3],
      ["the claude-review check runs", "check-runs?check_name=pr-review-main%3A%20claude-review&", 4],
      ["the pull request's events", `issues/${PR}/events`, 9],
    ];
    for (const [what, url, at] of READS) {
      const again = runWith({ GH_FAIL_URL: url, GH_FAIL: "1" });
      assert.equal(again.out, "judged=true\n", what);
      assert.equal(again.calls.length, 10, `${what}\n${again.calls.join("\n")}`);
      assert.equal(again.calls.filter((call) => call.includes(url)).length, 2, what);
      assert.equal(again.sleeps.length, 1, what);
      const unread = runWith({ GH_FAIL_URL: url, GH_FAIL: "9" });
      assert.equal(unread.out, "", what);
      assert.equal(unread.calls.length, at + 2, `${what}\n${unread.calls.join("\n")}`);
      assert.ok(unread.calls.slice(at - 1).every((call) => call.includes(url)), what);
      assert.equal(unread.sleeps.length, 2, what);
      assert.ok(unread.stdout.split("\n").includes(`::notice::${what} did not read (failed 3 times); the review runs`), `${what}\n${unread.stdout}`);
      assert.doesNotMatch(unread.stdout, /::warning::/, what);
    }
    for (const [why, setup] of [
      ["failed run", { conclusion: "failure" }],
      ["other head", { head: SHA_B }],
      ["counts differ", { title: "findings=3 critical=0" }],
      ["security lane unreviewed", { missing: ["claude-security-review"] }],
      ["more than one page", { total: 101 }],
    ]) {
      write(setup);
      assert.equal(runWith().out, "", why);
    }
    for (const [why, standards] of [
      ["another standards commit", SHA_B],
      ["no standards commit", null],
    ]) {
      write({ standards });
      const restale = runWith();
      assert.equal(restale.out, "", why);
      assert.ok(restale.stdout.includes("reviewed under another standards commit; its claude-review verdict does not count"), `${why}\n${restale.stdout}`);
    }
    write();
    for (const env of [{ STANDARDS_SHA: SHA_B }, { STANDARDS_SHA: "" }]) {
      const moved = runWith(env);
      assert.equal(moved.out, "", JSON.stringify(env));
    }
    assert.equal(runWith({ STANDARDS_SHA: "" }).calls.length, 0);
    assert.equal(runWith().out, "judged=true\n");
    write({ main: CHANGED });
    const older = runWith();
    assert.equal(older.out, "judged=true\n");
    assert.equal(older.calls.length, 9, older.calls.join("\n"));
    assert.ok(has(CHANGED), "the run's main commit was fetched");
    write({ main: OLD });
    const stale = runWith();
    assert.equal(stale.out, "");
    assert.equal(stale.calls.length, 6, stale.calls.join("\n"));
    assert.ok(!stale.calls.some((call) => call.includes("/zip")), stale.calls.join("\n"));
    for (const [file, main] of side) {
      write({ main });
      const one = runWith();
      assert.equal(one.out, "", file);
      assert.equal(one.calls.length, 6, `${file}\n${one.calls.join("\n")}`);
    }
    for (const [why, setup] of [
      ["other workflow", { workflow: ".github/workflows/other.yml" }],
      ["off main", { branch: "feature" }],
      ["pull_request event", { event: "pull_request" }],
    ]) {
      write(setup);
      const other = runWith();
      assert.equal(other.out, "", why);
      assert.equal(other.calls.length, 6, `${why}\n${other.calls.join("\n")}`);
      assert.ok(!other.calls.some((call) => call.includes("/zip")), why);
    }
    for (const main of ["d".repeat(40), "main"]) {
      write({ main });
      assert.equal(runWith().out, "", main);
    }
    write({ main: "d".repeat(40) });
    const unfetched = runWith();
    assert.equal(unfetched.sleeps.length, 2);
    assert.ok(unfetched.stdout.split("\n").includes(`::notice::main commit ${"d".repeat(40)} did not read (failed 3 times); the review runs`), unfetched.stdout);
    write({ missing: ["claude-review"] });
    const none = runWith();
    assert.equal(none.out, "");
    assert.equal(none.calls.length, 1, none.calls.join("\n"));
    write();
    rmSync(path.join(fixtures, key(`repos/o/r/actions/runs/201`)));
    const failed = runWith();
    assert.equal(failed.out, "");
    assert.equal(failed.calls.filter((call) => call.endsWith("actions/runs/201")).length, 3, failed.calls.join("\n"));
    assert.ok(failed.stdout.split("\n").includes("::notice::run 201 did not read (failed 3 times); the review runs"), failed.stdout);
    for (const env of [{ TREE_SHA: "" }, { PR_NUMBER: "7; x" }]) {
      const bad = runWith(env);
      assert.equal(bad.out, "", JSON.stringify(env));
      assert.equal(bad.calls.length, 0, JSON.stringify(env));
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("each leg copies the review criteria criteria.txt lists, REVIEW.md composed over the org's", () => {
  const run = /^ {8}run: \|\n((?: {10}.*\n|\n)+)/m.exec(`${step("Copy the review criteria")}\n`)[1].replace(/^ {10}/gm, "");
  for (const job of LEGS) assert.equal(step("Copy the review criteria", job), step("Copy the review criteria"), job);
  assert.equal(input(step("Copy the review criteria"), "SKILL"), "${{ matrix.skill }}");
  assert.equal(input(step("Copy the review criteria"), "ORG"), "${{ steps.standards.outputs.path }}");
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-criteria-"));
  try {
    const files = {
      ".github/scripts/pr-review-main/criteria.txt": readFileSync(new URL("./criteria.txt", import.meta.url), "utf8"),
      "lib/org-standards.sh": readFileSync(new URL("../../../lib/org-standards.sh", import.meta.url), "utf8"),
      "plugins/review/skills/code-review/SKILL.md": "skill",
      "plugins/review/skills/code-review/evals/case.md": "eval",
      "plugins/review/skills/security-review/SKILL.md": "other lane",
      "plugins/review/reference/ref.md": "ref",
      "plugins/review/skills/quality-gate/context/loosened-check.md": "criterion",
      "plugins/review/skills/quality-gate/context/code.md": "not copied",
      "REVIEW.md": "review\n",
      "docs/standards/s.md": "standard",
      ".claude/rules/r.md": "rule",
    };
    for (const [file, body] of Object.entries(files)) {
      mkdirSync(path.dirname(path.join(dir, ".base", file)), { recursive: true });
      writeFileSync(path.join(dir, ".base", file), body);
    }
    const org = path.join(dir, "org-checkout");
    for (const [file, body] of Object.entries({ "REVIEW.md": "org review\n", "standards/review/x.md": "cited", "docs/standards/README.md": "index", "other/y.md": "not copied" })) {
      mkdirSync(path.dirname(path.join(org, file)), { recursive: true });
      writeFileSync(path.join(org, file), body);
    }
    const data = path.join(dir, "data");
    const copy = () => spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", run], { cwd: dir, encoding: "utf8", env: { ...process.env, SKILL: "code-review", DATA: data, ORG: org } });
    const result = copy();
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(readdirSync(data, { recursive: true }).filter((f) => f.endsWith(".md")).sort(), [
      "org/REVIEW.md",
      "org/docs/standards/README.md",
      "org/standards/review/x.md",
      "review/reference/ref.md",
      "review/skills/code-review/SKILL.md",
      "review/skills/quality-gate/context/loosened-check.md",
      "standards/REVIEW.md",
      "standards/rules/r.md",
      "standards/standards/s.md",
    ]);
    const composed = () => readFileSync(path.join(data, "standards", "REVIEW.md"), "utf8");
    assert.match(composed(), /^org review\n\n<!-- The repository REVIEW\.md follows[^\n]*-->\n\nreview\n$/, "extend: main's REVIEW.md follows the org's");
    rmSync(data, { recursive: true, force: true });
    writeFileSync(path.join(dir, ".base", "REVIEW.md"), "<!-- review-base: replace -->\nown\n");
    assert.equal(copy().status, 0);
    assert.equal(composed(), "<!-- review-base: replace -->\nown\n", "override: the marker keeps main's alone");
    rmSync(data, { recursive: true, force: true });
    rmSync(path.join(dir, ".base", "REVIEW.md"));
    assert.equal(copy().status, 0, "a main with no REVIEW.md still copies");
    assert.equal(composed(), "org review\n", "default: the org's criteria alone");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

const hostedChain = (file) => {
  const caller = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
  const block = /^ {4}secrets:\n((?: {6}.*\n)+)/m.exec(caller)[1];
  return [...block.matchAll(/^ {6}([A-Z_]+): \$\{\{ secrets\.([A-Z_]+) \}\}$/gm)].map(([, as, secret]) => [as, secret]);
};
// The run-claude-cli input each reusable secret reaches in ci-workflows
// pr-review-cli.yml: review-key passes CLAUDE_API_KEY as api-key,
// review-subscription CLAUDE_CODE_OAUTH_TOKEN as subscription-token,
// review-fallback FALLBACK_CLAUDE_CODE_OAUTH_TOKEN as fallback-token.
const LAUNCHER_INPUT = {
  CLAUDE_API_KEY: "api-key",
  CLAUDE_CODE_OAUTH_TOKEN: "subscription-token",
  FALLBACK_CLAUDE_CODE_OAUTH_TOKEN: "fallback-token",
};
const CREDENTIAL_INPUTS = Object.values(LAUNCHER_INPUT);
const needsOf = (job) => /^ {4}needs: (.*)$/m.exec(jobText(job))?.[1];

test("the legs run the review lanes' credentials in the review lanes' order", () => {
  const hosted = hostedChain("pr-review-hosted.yml");
  assert.deepEqual(hostedChain("pr-review-security-hosted.yml"), hosted);
  assert.equal(hosted.length, 3);
  const order = [KEY];
  for (let job = KEY; ; ) {
    const route = ["review-handoffs", "collect-subscription-handoffs"].find((id) => needsOf(id).replace(/^\[|\]$/g, "").split(", ").at(-1) === job);
    if (!route) break;
    job = LEGS.find((id) => needsOf(id) === `[${TEXT}, ${route}]`);
    order.push(job);
  }
  assert.deepEqual(order, LEGS);
  const used = order.map((job) => {
    const review = step("Review chunk 1", job);
    for (const name of CREDENTIAL_INPUTS) assert.equal(input(step(LATER.name, job), name), input(review, name), `${job} ${name}`);
    const set = CREDENTIAL_INPUTS.filter((name) => input(review, name) !== undefined);
    assert.equal(set.length, 1, `${job} passes one credential`);
    return [set[0], /^\$\{\{ secrets\.([A-Z_]+) \}\}$/.exec(input(review, set[0]))[1]];
  });
  assert.deepEqual(used, hosted.map(([as, secret]) => [LAUNCHER_INPUT[as], secret]));
  const legName = { [KEY]: "key", [SUB]: "subscription", [FB]: "fallback" };
  const fallbackSet = { [KEY]: undefined, [SUB]: "${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}", [FB]: undefined };
  order.forEach((job, i) => {
    const check = step("Check the credential", job);
    assert.match(check, SELECT_USES, job);
    assert.equal(input(check, "leg"), legName[job], job);
    assert.equal(input(check, "role"), input(step("Review chunk 1", job), "role"), job);
    assert.equal(input(check, "credential-set"), `\${{ secrets.${used[i][1]} != '' }}`, job);
    assert.equal(input(check, "fallback-set"), fallbackSet[job], job);
  });
  // Each secret's value reaches only its leg's launcher step; elsewhere a
  // job may ask only whether it is set.
  for (const job of LEGS) {
    for (const s of STEPS[job]) {
      const values = [...s.text.matchAll(/secrets\.([A-Z_]+)(?![A-Z_]| != '')/g)].map(([, name]) => name);
      if (RUNS.some((r) => r.name === s.name)) assert.equal(values.length, 1, job);
      else assert.deepEqual(values, [], `${job}: ${s.name}`);
    }
  }
  assert.doesNotMatch(text, /secrets: inherit|toJSON\(secrets\)/);
});

// run-claude-cli's handoff-reason (its action.yml at the pinned SHA): a key
// leg hands off on credit-stop or auth, a subscription leg with fallback-ready
// on limit-stop, credit-stop or auth; an empty credential with a later leg's
// set hands off as no-key (report-lane-outcome's fallback-reason).
const ROUTES = {
  "review-handoffs": ["credit-stop", "auth", "no-key"],
  "collect-subscription-handoffs": ["limit-stop", "credit-stop", "auth", "no-key"],
};
const SHA_A = "a".repeat(40);
const SHA_B = "0123456789abcdef0123456789abcdef01234567";
const routeRun = (job) => {
  const block = jobText(job);
  const run = /^ {8}run: \|\n((?: {10}.*\n?)+)/m.exec(block)[1].replace(/^ {10}/gm, "");
  return (env) => {
    const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-route-"));
    try {
      const out = path.join(dir, "out");
      writeFileSync(out, "");
      const reasons = /^ {10}REASONS: (.*)$/m.exec(block)[1];
      const result = spawnSync("bash", ["-e", "-c", run], { encoding: "utf8", env: { ...process.env, REASONS: reasons, GITHUB_OUTPUT: out, CODE_BASE: SHA_A, SECURITY_BASE: SHA_B, ...env } });
      const line = readFileSync(out, "utf8").trim();
      return { status: result.status, matrix: line ? JSON.parse(line.replace(/^matrix=/, "")) : undefined };
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };
};

test("a route hands the next leg fixed lane rows, only for a lane handed on with a closed reason", () => {
  const rows = {
    "claude-review": { lane: "claude-review", skill: "code-review", route: "review-code", switch: "CLAUDE_REVIEW_DISABLED" },
    "claude-security-review": { lane: "claude-security-review", skill: "security-review", route: "review-security", switch: "CLAUDE_SECURITY_REVIEW_DISABLED" },
  };
  for (const row of Object.values(rows)) {
    assert.ok(jobText(KEY).includes(`          - lane: ${row.lane}\n            skill: ${row.skill}\n            route: ${row.route}\n            switch: ${row.switch}\n`), row.lane);
  }
  for (const [job, reasons] of Object.entries(ROUTES)) {
    assert.deepEqual(/^ {10}REASONS: (.*)$/m.exec(jobText(job))[1].split(" "), reasons, job);
    const route = routeRun(job);
    assert.deepEqual(route({ CODE: "credit-stop", SECURITY: "" }), { status: 0, matrix: { include: [{ ...rows["claude-review"], reason: "credit-stop", base: SHA_A }] } });
    assert.deepEqual(route({ CODE: "auth", SECURITY: "no-key" }), {
      status: 0,
      matrix: { include: [{ ...rows["claude-review"], reason: "auth", base: SHA_A }, { ...rows["claude-security-review"], reason: "no-key", base: SHA_B }] },
    });
    for (const base of ["", "main", "A".repeat(40), `${SHA_A}\n`, "a".repeat(39)]) {
      const result = route({ CODE: "credit-stop", SECURITY: "", CODE_BASE: base });
      assert.notEqual(result.status, 0, `${job} ${JSON.stringify(base)}`);
      assert.equal(result.matrix, undefined);
    }
    assert.equal(route({ CODE: "credit-stop", SECURITY: "", SECURITY_BASE: "" }).status, 0);
    for (const bad of ["other", "credit-stop ", "true"]) {
      const result = route({ CODE: "", SECURITY: bad });
      assert.notEqual(result.status, 0, `${job} ${JSON.stringify(bad)}`);
      assert.equal(result.matrix, undefined);
    }
  }
  assert.notEqual(routeRun("review-handoffs")({ CODE: "limit-stop", SECURITY: "" }).status, 0);
  assert.equal(routeRun("collect-subscription-handoffs")({ CODE: "limit-stop", SECURITY: "" }).status, 0);
});

test("a later leg runs only for the lanes the previous leg handed on", () => {
  for (const [route, from, to] of [["review-handoffs", KEY, SUB], ["collect-subscription-handoffs", SUB, FB]]) {
    const routeJob = jobText(route);
    assert.equal(needsOf(route), route === "review-handoffs" ? `[check-trigger, ${PROBE}, ${from}]` : from);
    const gated = route === "review-handoffs" ? `\\n {6}\\|\\| needs\\.review\\.result == 'skipped' && needs\\.${PROBE}\\.outputs\\.next-leg == 'subscription'\\n[^)]*` : "";
    assert.match(routeJob, new RegExp(`&& \\(needs\\.${from}\\.outputs\\.claude-review != '' \\|\\| needs\\.${from}\\.outputs\\.claude-security-review != ''${gated}\\)`));
    // !cancelled(): one lane's failed leg does not drop the other lane's
    // handoff; the route still passes on only closed-set reasons.
    assert.match(routeJob, /^ {4}if: >-\n {6}!cancelled\(\)\n {6}&& github\.ref == 'refs\/heads\/main'\n/m);
    assert.doesNotMatch(routeJob, /always\(\)/);
    const leg = jobText(to);
    assert.equal(needsOf(to), `[${TEXT}, ${route}]`);
    assert.match(leg, new RegExp(`^ {6}matrix: \\$\\{\\{ fromJSON\\(needs\\.${route}\\.outputs\\.matrix\\) \\}\\}$`, "m"));
    // !cancelled() with the route's own success: the implicit success() needs
    // every ancestor, so one lane's failed leg would skip the other's.
    assert.match(leg, new RegExp(`^ {4}if: >-\\n {6}!cancelled\\(\\)\\n {6}&& needs\\.${route}\\.result == 'success'\\n {6}&& github\\.ref == 'refs\\/heads\\/main'\\n`, "m"));
    assert.doesNotMatch(leg, /always\(\) \|\|/);
    for (const lane of ["claude-review", "claude-security-review"]) {
      assert.match(jobText(from), new RegExp(`^ {6}${lane}: \\$\\{\\{ steps\\.handoff\\.outputs\\.${lane} \\}\\}$`, "m"));
    }
  }
  assert.equal(index("Hand the lane on", FB), -1);
  const fbOutputs = /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(jobText(FB))[1];
  assert.deepEqual(
    [...fbOutputs.matchAll(/^ {6}([a-z-]+):/gm)].map(([, name]) => name),
    ["claude-review-stop", "claude-security-review-stop", "claude-review-head", "claude-security-review-head"],
  );
  for (const run of RUNS) {
    assert.doesNotMatch(step(run.name, KEY), /fallback-ready/);
    assert.equal(input(step(run.name, SUB), "fallback-ready"), "${{ steps.credential.outputs.fallback-ready }}");
    assert.doesNotMatch(step(run.name, FB), /fallback-ready/);
  }
  assert.match(jobText("report-review-counts"), /^ {4}needs: \[review, review-subscription, review-fallback\]$/m);
  assert.match(jobText("report-review-counts"), RECORD_IF);
  const records = (review, subscription) => admits(/^ {4}if: \$\{\{ (.*) \}\}$/m.exec(jobText("report-review-counts"))[1], { github: { ref: "refs/heads/main" }, needs: { review: { result: review }, "review-subscription": { result: subscription } } });
  assert.ok(records("success", "skipped"));
  assert.ok(records("skipped", "success"));
  assert.ok(records("skipped", "failure"));
  assert.ok(!records("skipped", "skipped"));
});

test("the handoff step names its lane and a closed reason, and a handed-off leg stays green", () => {
  for (const job of [KEY, SUB]) {
    // Any chunk's handoff hands the whole lane on: the next-leg call reads
    // every chunk's (select-model-credential, credential-legs.test.mjs).
    const next = step("Pick the next leg", job);
    assert.match(next, /^ {8}id: next$/m);
    assert.match(next, /^ {8}if: \$\{\{ always\(\) \}\}$/m);
    assert.match(next, /^ {8}continue-on-error: true$/m);
    assert.equal(input(next, "state"), "${{ steps.credential.outputs.state }}");
    assert.equal(input(next, "handoff"), "${{ steps.review-1.outputs.handoff == 'true' || steps.review-chunks.outputs.handoff == 'true' }}");
    assert.equal(input(next, "handoff-reason"), "${{ steps.review-1.outputs.handoff-reason || steps.review-chunks.outputs.handoff-reason }}");
    const handoff = step("Hand the lane on", job);
    assert.equal(/^ {8}if: (.*)$/m.exec(handoff)[1], "steps.next.outputs.next-leg != ''");
    assert.equal(input(handoff, "REASON"), "${{ steps.next.outputs.next-reason }}");
    assert.ok(index(LATER.transcript, job) + 1 === index("Pick the next leg", job));
    assert.ok(index("Pick the next leg", job) + 1 === index("Hand the lane on", job));
    for (const run of RUNS) {
      const report = step(run.report, job);
      assert.equal(/^ {8}if: (.*)$/m.exec(report)[1], `steps.${run.id}.outcome == 'success' || steps.${run.id}.outcome == 'failure'`);
      assert.equal(input(report, "handoff"), `\${{ steps.${run.id}.outputs.handoff }}`);
      assert.match(report, /^ {8}continue-on-error: true$/m);
    }
    assert.match(step("Fail without a verdict", job), /&& steps\.handoff\.outcome != 'success'$/m);
  }
  for (const run of RUNS) assert.equal(input(step(run.report, FB), "handoff"), undefined);
  const run = /^ {8}run: \|\n((?: {10}.*\n?)+)/m.exec(step("Hand the lane on"))[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-handoff-"));
  try {
    const out = path.join(dir, "out");
    const hand = (reason) => {
      writeFileSync(out, "");
      const status = spawnSync("bash", ["-e", "-c", run], { env: { ...process.env, LANE: "claude-security-review", REASON: reason, GITHUB_OUTPUT: out } }).status;
      return [status, readFileSync(out, "utf8")];
    };
    assert.deepEqual(hand("credit-stop"), [0, "claude-security-review=credit-stop\n"]);
    assert.deepEqual(hand("no-key"), [0, "claude-security-review=no-key\n"]);
    assert.notEqual(hand("")[0], 0);
    assert.equal(hand("x\nclaude-review=auth")[1], "");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the subscription and fallback legs are what scripts/sync-credential-legs.mjs renders from the key leg", () => {
  const sync = fileURLToPath(new URL("../../../scripts/sync-credential-legs.mjs", import.meta.url));
  const run = spawnSync(process.execPath, [sync, "--check"], { encoding: "utf8" });
  assert.equal(run.status, 0, run.stdout + run.stderr);
});

test("each later leg runs the key leg's steps but main's tip, and names why it ran", () => {
  const keyNames = STEPS[KEY].map((s) => s.name).filter((name) => name !== "Resolve main's tip");
  assert.deepEqual(STEPS[SUB].map((s) => s.name), keyNames);
  const FB_WARNING = "Warn that the fallback token reviews";
  assert.deepEqual(
    STEPS[FB].map((s) => s.name).filter((name) => name !== FB_WARNING),
    keyNames.filter((name) => name !== "Pick the next leg" && name !== "Hand the lane on"),
  );
  for (const job of [SUB, FB]) {
    assert.equal(input(step("Check the credential", job), "reason"), "${{ matrix.reason }}");
    for (const run of RUNS) {
      assert.equal(input(step(run.report, job), "fallback-reason"), "${{ steps.credential.outputs.fallback-reason }}");
    }
  }
  assert.equal(input(step("Report chunk 1's outcome", KEY), "fallback-reason"), undefined);
});

test("the fallback leg warns, once its credential is present, that it reviews the lane", () => {
  const warn = step("Warn that the fallback token reviews", FB);
  assert.equal(/^ {8}if: (.*)$/m.exec(warn)[1], "steps.credential.outputs.present == 'true'");
  assert.ok(index("Apply the Claude managed settings", FB) + 1 === index("Warn that the fallback token reviews", FB));
  const run = /^ {8}run: (.*)$/m.exec(warn)[1];
  const out = spawnSync("bash", ["-e", "-c", run], { env: { ...process.env, LANE: "claude-review", REASON: "limit-stop" }, encoding: "utf8" }).stdout;
  assert.match(out, /^::warning title=pr-review-main fallback::lane=claude-review reviews on FALLBACK_CLAUDE_CODE_OAUTH_TOKEN \(reason=limit-stop\)/);
  for (const job of [KEY, SUB]) assert.equal(STEPS[job].some((s) => s.name === "Warn that the fallback token reviews"), false, job);
});

test("one lane handed on beside one that reviewed routes only the handed-on lane", () => {
  for (const job of Object.keys(ROUTES)) {
    const { status, matrix } = routeRun(job)({ CODE: "credit-stop", SECURITY: "" });
    assert.equal(status, 0, job);
    assert.deepEqual(matrix.include.map((row) => [row.lane, row.reason]), [["claude-review", "credit-stop"]], job);
  }
});

test("the prompt says a folded line is the line before it, so a finding's line number holds", () => {
  assert.match(prompt, /`\\ continued:`: each is the rest of the line before it, takes that line's side, and\n\s*adds no line to the file's line numbers/);
});

test("the prompt says a rename-only entry is unseen and a change that references a moved path is a finding", () => {
  const flat = prompt.replace(/\s+/g, " ");
  assert.ok(flat.includes("A file moved unchanged may show only as its `rename from` and `rename to` lines: its content is not in the diff, so you have not seen it."));
  assert.ok(flat.includes("When any change you can see runs, sources, includes or otherwise references a path such an entry moved (its old or new path), report it as a finding"));
  assert.ok(prompt.indexOf("rename from") < prompt.indexOf("DIFF_PARTS"));
});

// An upstream-status skip fails the leg before its review starts, so the run
// is a failed first attempt the lost-run reconciler re-runs once with a record
// (reconcile.mjs RECORDED_LANES, holdReason); a kill-switch stop stays green.
test("each leg's kill-switch report fails on an upstream outage and passes a kill-switch stop", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "report-"));
  try {
    for (const job of LEGS) reportCases(job, dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

function reportCases(job, dir) {
  {
    const block = step("Report the kill switch", job);
    const body = block
      .slice(block.indexOf("        run: |\n"))
      .split("\n")
      .filter((line) => line.startsWith("          "))
      .map((line) => line.slice(10))
      .join("\n");
    const run = (env) => {
      const out = path.join(dir, `${job}-${Object.values(env).join("-")}`);
      const result = spawnSync("bash", ["-e", "-c", body], {
        env: { PATH: process.env.PATH, GITHUB_OUTPUT: out, ...env },
        encoding: "utf8",
      });
      return { ...result, output: readFileSync(out, { encoding: "utf8", flag: "a+" }) };
    };
    const outage = run({ PROCEED: "true", LANE_SWITCH: "", UPSTREAM_DEGRADED: "true" });
    assert.equal(outage.status, 1, job);
    assert.match(outage.stdout, /^::error::an upstream outage stops this review; /m, job);
    assert.equal(outage.output, "", job);
    const killed = run({ PROCEED: "false", REASON: "disabled", LANE_SWITCH: "", UPSTREAM_DEGRADED: "" });
    assert.equal(killed.status, 0, job);
    assert.match(killed.stdout, /^::notice::a kill switch stops this review \(/m, job);
    const proceed = run({ PROCEED: "true", LANE_SWITCH: "", UPSTREAM_DEGRADED: "false" });
    assert.equal(proceed.status, 0, job);
    assert.equal(proceed.output, "proceed=true\n", job);
  }
}
