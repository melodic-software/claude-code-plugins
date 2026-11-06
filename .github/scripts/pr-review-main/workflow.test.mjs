// pr-review-main.yml's hardening, from its header and ADR 0049: it runs only
// from main on workflow_run, its token can only read, it checks out main and
// never the head, the model reads only its data directory, and each leg
// uploads the verdict once, after it is written, under the name the writer
// chose. Each lane runs one leg on the review lanes' credentials in their
// order, a later leg only for a lane the previous one handed on.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, symlinkSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { admits } from "../lib/gate-expression.mjs";
import { heldNoted } from "../maintenance-reconcile-lost-runs/reconcile.mjs";
import { HELD_STEP } from "../pr-verify/resolve-pr.mjs";

const text = readFileSync(new URL("../../workflows/pr-review-main.yml", import.meta.url), "utf8");
const prompt = readFileSync(new URL("./prompt.md", import.meta.url), "utf8");
const KEY = "review";
const SUB = "review-subscription";
const FB = "review-fallback";
const LEGS = [KEY, SUB, FB];
// The credit gate before the key leg: no model, no secret.
const PROBE = "review-handoffs-credit";
const jobText = (id) => {
  const found = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(text);
  assert.ok(found, `a job ${id}`);
  return found[1];
};
// Each step starts at a `      - name:` line of its job.
const stepsOf = (id) =>
  jobText(id)
    .split(/\n(?=      - name: )/)
    .slice(1)
    // A step ends before the next step's or job's comment.
    .map((block) => ({ name: /^      - name: (.*)$/m.exec(block)[1], block: block.replace(/\n\n {2}(?: {4})?#[\s\S]*$/, "") }));
const STEPS = Object.fromEntries([...LEGS, PROBE, "review-handoffs"].map((id) => [id, stepsOf(id)]));
const step = (name, job = KEY) => {
  const found = STEPS[job].find((s) => s.name === name);
  assert.ok(found, `a step named ${name} in ${job}`);
  return found.block;
};
const index = (name, job = KEY) => STEPS[job].findIndex((s) => s.name === name);
const writeDiff = readFileSync(new URL("./write-diff.py", import.meta.url), "utf8");
const WRITE_DIFF = new URL("./write-diff.py", import.meta.url).pathname;
const input = (block, key) => new RegExp(`^ {10}${key}: (.*)$`, "m").exec(block)?.[1];
// The most chunks a diff splits into, one review step each.
const SLOTS = Number(/^ {10}MAX_CHUNKS: "(\d+)"$/m.exec(step("Write the diff"))?.[1]);

test("each leg reviews every chunk in order, one run each, and stops at a handoff or a failure", () => {
  assert.ok(SLOTS >= 2 && SLOTS <= 9, String(SLOTS));
  for (const job of LEGS) {
    assert.equal(/^ {10}MAX_CHUNKS: "(\d+)"$/m.exec(step("Write the diff", job))[1], String(SLOTS), job);
    const runs = STEPS[job].filter((s) => /run-claude-cli@/.test(s.block)).map((s) => s.name);
    assert.deepEqual(runs, Array.from({ length: SLOTS }, (_, i) => `Review chunk ${i + 1}`), job);
    const first = step("Review chunk 1", job);
    assert.equal(/^ {8}if: (.*)$/m.exec(first)[1], "steps.prompt.outcome == 'success'", job);
    for (let k = 1; k <= SLOTS; k++) {
      const review = step(`Review chunk ${k}`, job);
      assert.match(review, new RegExp(`^ {8}id: review-${k}$`, "m"), job);
      assert.equal(input(review, "prompt-file"), `\${{ runner.temp }}/pr-review-main-prompt-${k}.md`, job);
      // Every input but the prompt is chunk 1's, credentials included.
      const rest = (block) => block.replace(/^ {6}- name: .*\n|^ {8}(?:id|if): .*\n/gm, "").replace(/^ {10}prompt-file: .*$/m, "");
      assert.equal(rest(review), rest(first), `${job} ${k}`);
      if (k > 1) {
        assert.equal(/^ {8}if: (.*)$/m.exec(review)[1], `steps.prompt.outcome == 'success' && fromJSON(steps.diff.outputs.chunks || '0') >= ${k} && steps.review-${k - 1}.outcome == 'success' && steps.review-${k - 1}.outputs.handoff != 'true'`, `${job} ${k}`);
      }
      // Each run's transcript is its own artifact.
      const transcript = step(`Upload chunk ${k}'s sealed transcript`, job);
      assert.equal(input(transcript, "execution-file"), `\${{ steps.review-${k}.outputs.execution-file }}`);
      assert.equal(input(transcript, "job-id"), k === 1 ? "${{ github.job }}-${{ matrix.lane }}" : `\${{ github.job }}-\${{ matrix.lane }}-${k}`);
    }
    // The job's time holds every chunk's review.
    assert.ok(Number(/^ {4}timeout-minutes: (\d+)$/m.exec(jobText(job))[1]) >= SLOTS * 22 + 5, job);
    // The prompt step writes one prompt per chunk.
    const prompts = step("Write the prompt and schema", job);
    assert.match(prompts, /printf '%s\\n' "\$prompt" >"\$PROMPT_STEM-\$k\.md"/);
    assert.equal(input(prompts, "PROMPT_STEM"), "${{ runner.temp }}/pr-review-main-prompt");
  }
});

test("a chunked review that wrote no verdict records chunk-failed for the record job", () => {
  for (const job of LEGS) {
    const stop = step("Record a failed chunk", job);
    assert.equal(index("Record a failed chunk", job), index("Write the verdict", job) + 1, job);
    assert.match(stop, /^ {8}id: chunk-stop$/m);
    // A chunked leg that reviewed, handed nothing on and wrote no verdict:
    // a failed chunk skips the write, a void chunk fails it.
    const noHandoff = Array.from({ length: SLOTS }, (_, i) => `steps.review-${i + 1}.outputs.handoff != 'true'`).join(" && ");
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
    // The job still fails: no verdict binds.
    assert.match(step("Fail without a verdict", job), /steps\.verdict\.outcome != 'success'/);
  }
});

test("it runs only from main on pr-require-checks' completion", () => {
  const on = /\non:\n([\s\S]*?)\n\S/.exec(text)[1];
  assert.match(on, /^ {2}workflow_run: # zizmor: ignore\[dangerous-triggers\]$/m);
  assert.match(on, /^ {4}workflows: \[pr-require-checks\]$/m);
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
  for (const job of ["review-handoffs", "subscription-handoffs"]) {
    const route = jobText(job);
    assert.match(route, /^ {4}permissions: \{\}$/m, job);
    assert.doesNotMatch(route, /run-claude-cli|secrets\.|actions\/checkout@/, job);
    const uses = route.match(/uses: .*/g) ?? [];
    assert.deepEqual(uses.map((line) => line.replace(/@.*/, "")), job === "review-handoffs" ? ["uses: actions/upload-artifact"] : [], job);
  }
  // The trigger job reads with the key leg's grants and checks: read, for the
  // record job's check runs its judged-head read takes; it holds no secret
  // and runs no model.
  const trigger = jobText("trigger");
  assert.deepEqual(
    grantsOf(trigger).map(([, scope, level]) => `${scope}:${level}`),
    [...grantsOf(jobText(KEY)).map(([, scope, level]) => `${scope}:${level}`), "checks:read"],
  );
  assert.doesNotMatch(trigger, /run-claude-cli|secrets\./);
  const record = jobText("record");
  assert.deepEqual(grantsOf(record).map(([, scope, level]) => `${scope}:${level}`), ["checks:write"]);
  assert.doesNotMatch(record, /run-claude-cli|secrets\.|actions\/checkout@/);
  // It posts counts only, read as numbers from this run's verdicts.
  assert.match(record, /critical =~ \^\[0-9\]\{1,6\}\$/);
  assert.match(record, /repos\/\$GITHUB_REPOSITORY\/check-runs/);
  assert.doesNotMatch(text, /write-all/);
});

test("the diff shows every file as text and refuses one a review cannot read whole", () => {
  const diff = step("Write the diff");
  assert.match(diff, /python3 -I \.base\/\.github\/scripts\/pr-review-main\/write-diff\.py "\$SRC" "\$BASE_SHA" "\$HEAD_SHA" "\$DATA\/diff\.patch" "\$MAX_DIFF_BYTES"$/m);
  assert.match(writeDiff, /^DIFF = \["diff", "--text", "--no-ext-diff", "--no-textconv", "--no-color"\]$/m);
  assert.match(diff, /\^\(Binary files \.\* differ\|GIT binary patch\)\$/);
  assert.match(diff, /^ {10}python3 -I \.base\/\.github\/scripts\/pr-review-main\/split-diff\.py "\$DATA\/diff\.patch" "\$DATA\/diff" "\$MAX_DIFF_BYTES" "\$MAX_CHUNKS" "\$DATA\/manifest\.txt" "\$PART_BYTES" \|\| split=\$\?$/m);
  assert.match(diff, /MAX_DIFF_BYTES: "\d+"/);
});

test("the diff is split into parts one read returns whole, and a longer line folds", () => {
  const diff = step("Write the diff");
  const awk = diff.match(/LC_ALL=C (awk -v dir=.*?' "\$dir\.patch")/s)[1];
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-split-"));
  try {
    const run = (text, env = {}) => {
      rmSync(path.join(dir, "diff"), { recursive: true, force: true });
      mkdirSync(path.join(dir, "diff"));
      writeFileSync(path.join(dir, "diff.patch"), text);
      return spawnSync("bash", ["-c", `LC_ALL=C ${awk}`], { env: { ...process.env, dir: path.join(dir, "diff"), PART_BYTES: "10", PART_LINES: "2", LONG_LINE_BYTES: "40", ...env } });
    };
    const read = () =>
      readdirSync(path.join(dir, "diff"))
        .sort()
        .map((p) => readFileSync(path.join(dir, "diff", p)));
    // 5 lines of 4 bytes: 2 lines per part at most, so 3 parts, in order.
    assert.equal(run("aaa\nbbb\nccc\nddd\neee\n").status, 0);
    const parts = readdirSync(path.join(dir, "diff")).sort();
    assert.deepEqual(parts, ["part-001.patch", "part-002.patch", "part-003.patch"]);
    assert.equal(parts.map((p) => readFileSync(path.join(dir, "diff", p), "utf8")).join(""), "aaa\nbbb\nccc\nddd\neee\n");
    // A line over LONG_LINE_BYTES continues on `\ continued: ` lines of at
    // most that many bytes, never cut inside a UTF-8 character, and every
    // byte comes back when the folds are joined.
    const long = `+${"x".repeat(50)}${"\u00e9\u20ac".repeat(20)}\n ${"y".repeat(39)}\n`;
    assert.equal(run(long, { PART_BYTES: "1000", PART_LINES: "100" }).status, 0);
    const folded = Buffer.concat(read());
    const lines = folded.toString("utf8").split("\n").slice(0, -1);
    assert.ok(lines.length > 4);
    for (const line of lines) {
      assert.ok(Buffer.byteLength(line) <= 40, line);
      assert.doesNotThrow(() => new TextDecoder("utf-8", { fatal: true }).decode(Buffer.from(line)));
    }
    assert.ok(lines.slice(1, -1).every((line) => line.startsWith("\\ continued: ")));
    assert.equal(folded.toString("utf8").replaceAll("\n\\ continued: ", ""), long);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a diff with a line past the review's cap is folded, and every byte of it reaches a whole read", async () => {
  const { LONG_LINE_BYTES, longestLine } = await import("./write-verdict.mjs");
  assert.match(step("Write the diff"), new RegExp(`LONG_LINE_BYTES: "${LONG_LINE_BYTES}"`));
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

// split-diff.py on a fixture patch: the chunk files it writes, by name.
const SPLIT_DIFF = new URL("./split-diff.py", import.meta.url).pathname;
// With `manifestBytes`, it returns the manifest it wrote (null for none).
// With `maxFiles`, it passes the optional seventh argument.
function split(patch, maxBytes, maxChunks, manifestBytes, maxFiles) {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-chunks-"));
  try {
    writeFileSync(path.join(dir, "diff.patch"), patch);
    mkdirSync(path.join(dir, "out"));
    const manifest = path.join(dir, "manifest.txt");
    const args = [path.join(dir, "diff.patch"), path.join(dir, "out"), String(maxBytes), String(maxChunks), manifest, String(manifestBytes ?? 15000)];
    const run = spawnSync("python3", ["-I", SPLIT_DIFF, ...args, ...(maxFiles === undefined ? [] : [String(maxFiles)])], { encoding: "utf8" });
    const chunks = Object.fromEntries(readdirSync(path.join(dir, "out")).sort().map((name) => [name, readFileSync(path.join(dir, "out", name), "utf8")]));
    if (manifestBytes !== undefined) {
      return { status: run.status, chunks, stderr: run.stderr, manifest: (() => { try { return readFileSync(manifest, "utf8"); } catch { return null; } })() };
    }
    return { status: run.status, chunks, stderr: run.stderr };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
// A file's patch of exactly `bytes` bytes: its header and one hunk padded
// with one added line.
const filePatch = (name, bytes) => {
  const head = `diff --git a/${name} b/${name}\n@@ -1 +1 @@\n+`;
  const patch = `${head}${"x".repeat(bytes - head.length - 1)}\n`;
  assert.equal(Buffer.byteLength(patch), bytes);
  return patch;
};
// The 43-byte header of the file big, and a hunk of exactly `bytes` bytes.
const BIG = "diff --git a/big b/big\n--- a/big\n+++ b/big\n";
const hunkPatch = (n, bytes) => {
  const head = `@@ -${n} +${n} @@\n+`;
  const hunk = `${head}${"y".repeat(bytes - head.length - 1)}\n`;
  assert.equal(Buffer.byteLength(hunk), bytes);
  return hunk;
};

test("an oversize diff splits into chunks under the cap at file boundaries, in order", () => {
  const [a, b, c] = [filePatch("a", 60), filePatch("b", 70), filePatch("c", 50)];
  // 60 + 70 fits 150; 50 more does not, so c starts the second chunk.
  assert.deepEqual(split(a + b + c, 150, 4), { status: 0, chunks: { "chunk-1.patch": a + b, "chunk-2.patch": c }, stderr: "" });
  // At 180 bytes the whole diff is one chunk.
  assert.deepEqual(split(a + b + c, 180, 4).chunks, { "chunk-1.patch": a + b + c });
});

test("a single file over the cap is too large and writes nothing, however small its hunks", () => {
  const [h1, h2, h3] = [hunkPatch(1, 30), hunkPatch(5, 30), hunkPatch(9, 30)];
  assert.equal(BIG.length, 43);
  // 43 + 3 * 30 = 133 is over 110: each file stays whole, so it fits no chunk.
  const result = split(BIG + h1 + h2 + h3, 110, 4);
  assert.equal(result.status, 3);
  assert.deepEqual(result.chunks, {});
  assert.match(result.stderr, /a file is larger than one chunk/);
  // Beside a small file it is still too large; at 133 it is one whole chunk.
  const small = filePatch("s", 40);
  assert.equal(split(BIG + h1 + h2 + h3 + small, 120, 4).status, 3);
  assert.deepEqual(split(BIG + h1 + h2 + h3 + small, 133, 4).chunks, { "chunk-1.patch": BIG + h1 + h2 + h3, "chunk-2.patch": small });
});

test("a chunk of exactly the cap, and exactly the most chunks, still split", () => {
  const [a, b] = [filePatch("a", 100), filePatch("b", 100)];
  assert.deepEqual(split(a, 100, 1), { status: 0, chunks: { "chunk-1.patch": a }, stderr: "" });
  assert.deepEqual(split(a + b, 100, 2).chunks, { "chunk-1.patch": a, "chunk-2.patch": b });
});

test("with a file cap a chunk also ends at that many files, and without one only bytes cut", () => {
  const files = ["a", "b", "c", "d", "e"].map((name) => filePatch(name, 50));
  const [a, b, c, d, e] = files;
  const all = files.join("");
  // Five 50-byte files fit one 1000-byte chunk; a cap of 2 cuts at every second file.
  assert.deepEqual(split(all, 1000, 4).chunks, { "chunk-1.patch": all });
  assert.deepEqual(split(all, 1000, 4, 15000, 0).chunks, { "chunk-1.patch": all });
  assert.deepEqual(split(all, 1000, 4, undefined, 2), { status: 0, chunks: { "chunk-1.patch": a + b, "chunk-2.patch": c + d, "chunk-3.patch": e }, stderr: "" });
  // Bytes still cut first: at 100 bytes and a cap of 3, each chunk holds two files.
  assert.deepEqual(split(all, 100, 4, undefined, 3).chunks, { "chunk-1.patch": a + b, "chunk-2.patch": c + d, "chunk-3.patch": e });
  // A cap that needs more than the most chunks is too large and writes nothing.
  const over = split(all, 1000, 2, undefined, 2);
  assert.equal(over.status, 3);
  assert.deepEqual(over.chunks, {});
  assert.match(over.stderr, /3 chunks/);
});

test("more chunks than the most, or a file larger than one chunk, is too large and writes nothing", () => {
  const [a, b, c] = [filePatch("a", 100), filePatch("b", 100), filePatch("c", 100)];
  const over = split(a + b + c, 100, 2);
  assert.equal(over.status, 3);
  assert.deepEqual(over.chunks, {});
  assert.match(over.stderr, /3 chunks/);
  const hunk = split(BIG + hunkPatch(1, 30) + hunkPatch(5, 80), 110, 4);
  assert.equal(hunk.status, 3);
  assert.deepEqual(hunk.chunks, {});
  // An empty diff is no chunk at all.
  assert.deepEqual(split("", 100, 2), { status: 0, chunks: {}, stderr: "" });
});

// One file of each status, as write-diff.py prints them over the cap: an
// edit, an add whose path has a space and `&`, an empty delete, a mode
// change, a move collapsed to its rename lines, and an add git quotes.
const MIXED = [
  `diff --git a/src/a.sh b/src/a.sh\nindex 1111111..2222222 100644\n--- a/src/a.sh\n+++ b/src/a.sh\n@@ -1 +1 @@\n-x\n+source lib/b.sh ${"p".repeat(400)}\n`,
  "diff --git a/lib/b & c.sh b/lib/b & c.sh\nnew file mode 100644\nindex 0000000..3333333\n--- /dev/null\n+++ b/lib/b & c.sh\t\n@@ -0,0 +1 @@\n+echo\n",
  "diff --git a/old.txt b/old.txt\ndeleted file mode 100644\nindex e69de29..0000000\n",
  "diff --git a/run.sh b/run.sh\nold mode 100644\nnew mode 100755\n",
  "diff --git a/docs/x.md b/guide/x.md\nsimilarity index 100%\nrename from docs/x.md\nrename to guide/x.md\n",
  'diff --git "a/r\\303\\251sum\\303\\251.md" "b/r\\303\\251sum\\303\\251.md"\nnew file mode 100644\nindex 0000000..4444444\n--- /dev/null\n+++ "b/r\\303\\251sum\\303\\251.md"\n@@ -0,0 +1 @@\n+hi\n',
];
const MIXED_MANIFEST = [
  "chunk 1 modified src/a.sh",
  "chunk 2 added lib/b & c.sh",
  "chunk 2 deleted old.txt",
  "chunk 2 modified run.sh",
  "chunk 2 renamed docs/x.md -> guide/x.md",
  'chunk 2 added "r\\303\\251sum\\303\\251.md"',
];

test("a diff in more than one chunk writes a manifest of every file, its chunk and its status", () => {
  const [first, ...rest] = MIXED.map((p) => Buffer.byteLength(p));
  // The edit fills chunk 1 alone; the rest fit chunk 2.
  assert.ok(first <= 600 && first + rest[0] > 600 && rest.reduce((a, b) => a + b) <= 600);
  const two = split(MIXED.join(""), 600, 4, 15000);
  assert.equal(two.status, 0, two.stderr);
  assert.deepEqual(Object.keys(two.chunks), ["chunk-1.patch", "chunk-2.patch"]);
  assert.equal(two.manifest, `${MIXED_MANIFEST.join("\n")}\n`);
  // One chunk is the single-pass review: no manifest.
  assert.equal(split(MIXED.join(""), 100000, 4, 15000).manifest, null);
  // Past its cap the manifest lists what fits and counts the rest, the count's
  // line included in the cap.
  const capped = split(MIXED.join(""), 600, 4, 83);
  assert.ok(Buffer.byteLength(capped.manifest) <= 83);
  assert.equal(capped.manifest, `${MIXED_MANIFEST.slice(0, 2).join("\n")}\nand 4 more files, not listed\n`);
  // A diff too large to split writes no manifest either.
  assert.equal(split(MIXED.join(""), 600, 1, 15000).manifest, null);
});

// The "Write the diff" script run under bash as Actions runs it, with git and
// python3 stubbed: python3 (write-diff.py) writes the given patch, or fails.
const PYTHON = spawnSync("bash", ["-c", "command -v python3"], { encoding: "utf8" }).stdout.trim();
// `after(data)` runs on the step's data before the directory goes.
function runDiff(patch, { pythonFails = false, job = KEY, maxBytes = "300", maxChunks = "4", after } = {}) {
  const run = /^ {8}run: \|\n((?:(?: {10}.*)?\n)+)/m.exec(`${step("Write the diff", job)}\n`)[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-stop-"));
  try {
    const bin = path.join(dir, "bin");
    mkdirSync(bin);
    writeFileSync(path.join(bin, "git"), `#!/bin/sh\ncase "$*" in *rev-parse*) echo ${"e".repeat(40)} ;; esac\n`);
    writeFileSync(path.join(dir, "fixture.patch"), patch);
    // write-diff.py writes the fixture, or fails; split-diff.py runs as is.
    const writes = pythonFails ? "exit 1" : `cp "${path.join(dir, "fixture.patch")}" "$6"`;
    writeFileSync(path.join(bin, "python3"), `#!/bin/sh\ncase "$2" in\n  *write-diff.py) ${writes} ;;\n  *split-diff.py) shift 2; exec "${PYTHON}" -I "${SPLIT_DIFF}" "$@" ;;\n  *) exit 9 ;;\nesac\n`);
    chmodSync(path.join(bin, "git"), 0o755);
    chmodSync(path.join(bin, "python3"), 0o755);
    const out = path.join(dir, "out");
    writeFileSync(out, "");
    const data = path.join(dir, "data");
    const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`, GITHUB_OUTPUT: out, LANE: "claude-security-review", HEAD_SHA: SHA_A, BASE_SHA: SHA_B, PR_NUMBER: "7", DATA: data, SRC: path.join(dir, "src"), MAX_DIFF_BYTES: maxBytes, MAX_CHUNKS: maxChunks, PART_BYTES: "15000", PART_LINES: "1000", LONG_LINE_BYTES: "1800" };
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

test("a diff the review cannot read whole stops green and names its reason for the record job", () => {
  const small = "diff --git a/x b/x\n@@ -1 +1 @@\n+short\n";
  for (const job of LEGS) {
    // One file of 612 bytes fits no 300-byte chunk.
    const tooLarge = runDiff(`diff --git a/x b/x\n@@ -1 +1 @@\n${"+line\n".repeat(100)}`, { job });
    assert.equal(tooLarge.status, 0, job);
    assert.equal(tooLarge.output, `stop=too-large\nclaude-security-review-stop=too-large\nclaude-security-review-head=${SHA_A}\n`, job);
    assert.deepEqual(tooLarge.parts, [], job);
    assert.match(tooLarge.stdout, /^::notice title=pr-review-main stop::reason=too-large lane=claude-security-review pr=7; /m, job);
    // One file over the cap in many small hunks is still too large: a file
    // is never split at its hunks.
    const hunks = Array.from({ length: 12 }, (_, i) => `@@ -${i * 10 + 1} +${i * 10 + 1} @@\n+line ${i}\n`).join("");
    const oneFile = `diff --git a/x b/x\n--- a/x\n+++ b/x\n${hunks}`;
    assert.ok(Buffer.byteLength(oneFile) > 300 && hunks.length / 12 < 30, job);
    const manyHunks = runDiff(oneFile, { job });
    assert.equal(manyHunks.status, 0, job);
    assert.equal(manyHunks.output, `stop=too-large\nclaude-security-review-stop=too-large\nclaude-security-review-head=${SHA_A}\n`, job);
    assert.deepEqual(manyHunks.parts, [], job);
    // Five 200-byte files need five 300-byte chunks, one more than the four.
    const files = ["a", "b", "c", "d", "e"].map((name) => filePatch(name, 200));
    const tooMany = runDiff(files.join(""), { job });
    assert.equal(tooMany.status, 0, job);
    assert.match(tooMany.output, /^stop=too-large$/m, job);
    assert.deepEqual(tooMany.parts, [], job);
    // Four fit: one chunk each, each split into its parts, and the counts
    // and bytes per chunk in a notice.
    const four = runDiff(files.slice(0, 4).join(""), { job });
    assert.equal(four.status, 0, job);
    assert.doesNotMatch(four.output, /stop=/, job);
    assert.match(four.output, /^chunks=4$/m, job);
    assert.deepEqual(four.parts, ["chunk-1", "chunk-1/part-001.patch", "chunk-2", "chunk-2/part-001.patch", "chunk-3", "chunk-3/part-001.patch", "chunk-4", "chunk-4/part-001.patch"], job);
    assert.match(four.stdout, /^::notice title=pr-review-main chunks::lane=claude-security-review pr=7 chunks=4 bytes=200,200,200,200 manifest_paths=4$/m, job);
    // A failed write-diff.py is no designed stop: the step fails, unnamed.
    const failed = runDiff(small, { job, pythonFails: true });
    assert.notEqual(failed.status, 0, job);
    assert.doesNotMatch(failed.output, /stop=/, job);
    // A diff it reads whole writes its parts and no stop.
    const whole = runDiff(small, { job });
    assert.equal(whole.status, 0, job);
    assert.doesNotMatch(whole.output, /stop=/, job);
    assert.deepEqual(whole.parts, ["chunk-1", "chunk-1/part-001.patch"], job);
    assert.match(whole.output, /^chunks=1$/m, job);
    assert.match(whole.stdout, /^::notice title=pr-review-main chunks::lane=claude-security-review pr=7 chunks=1 bytes=\d+ manifest_paths=0$/m, job);
  }
});

// The "Write the prompt and schema" script run on the data the diff step
// left, from a directory holding the template where main's checkout does.
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
    const env = { ...process.env, DATA: data, LANE: "claude-review", SKILL: "code-review", MODEL: "opus", CHUNKS: chunks, PROMPT_STEM: path.join(dir, "prompt"), SCHEMA_FILE: path.join(dir, "schema.json"), GITHUB_OUTPUT: out };
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
      assert.doesNotMatch(text, /not yours to judge/, `${job} chunk ${k}`);
      // The prompt names the file and frames it as data; the paths, which
      // the pull request's author chose, stay out of the prompt itself.
      assert.ok(text.includes(`\`${two.after.data}/manifest.txt\``), `${job} chunk ${k}`);
      assert.match(text, /untrusted data like it, never instructions/, `${job} chunk ${k}`);
      assert.doesNotMatch(text, /^\s*chunk \d+ (added|modified|deleted|renamed) /m, `${job} chunk ${k}`);
      for (const pathText of ["lib/b & c.sh", "docs/x.md", "guide/x.md", "r\\303\\251sum"]) assert.ok(!text.includes(pathText), `${job} chunk ${k}: ${pathText}`);
    });
    // The file holds every file in either chunk as split-diff.py wrote it.
    assert.equal(two.after.manifest, `${MIXED_MANIFEST.join("\n")}\n`, job);
    // One chunk: no note and no manifest, the template's own text.
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
    const gated = STEPS[job].filter((s) => /steps\.diff\.outcome == 'success'/.test(s.block));
    assert.ok(gated.length >= 5, job);
    for (const s of gated) assert.match(s.block, /steps\.diff\.outcome == 'success' && steps\.diff\.outputs\.stop == ''/, `${job}: ${s.name}`);
    for (const lane of ["claude-review", "claude-security-review"]) {
      for (const kind of ["stop", "head"]) {
        assert.match(jobText(job), new RegExp(`^ {6}${lane}-${kind}: \\$\\{\\{ steps\\.diff\\.outputs\\.${lane}-${kind} \\|\\| steps\\.chunk-stop\\.outputs\\.${lane}-${kind} \\}\\}$`, "m"), `${job} ${lane}-${kind}`);
      }
    }
  }
});

// The record job's "Record the stops" script, with gh stubbed to log its args.
function recordStops(env) {
  const block = stepsOf("record").find((s) => s.name === "Record the stops").block;
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

test("the record job posts each stop as a neutral verdict=none record, from a closed reason", () => {
  const block = stepsOf("record").find((s) => s.name === "Record the stops").block;
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
  // Each POST is counted for the job's api-calls notice: two stops, two calls.
  assert.equal(recordStops({ COUNTED: "1", CODE_STOP: "binary", CODE_HEAD: SHA_A, SECURITY_STOP: "too-large", SECURITY_HEAD: SHA_B }).counted, "2\n");
  // No stop, nothing posted; a reason or head outside the closed set fails.
  assert.deepEqual(recordStops({}), { status: 0, calls: "" });
  for (const bad of [{ CODE_STOP: "other", CODE_HEAD: SHA_A }, { CODE_STOP: "too-large", CODE_HEAD: "main" }, { CODE_STOP: "too-large\nx", CODE_HEAD: SHA_A }]) {
    const result = recordStops(bad);
    assert.notEqual(result.status, 0, JSON.stringify(bad));
    assert.equal(result.calls, "");
  }
});

// write-diff.py run on a fixture repository: each case is a commit on top of
// a base, and the patch it prints for base...head.
// A cap of 0 makes every patch over it, so moves may collapse.
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
  // Five 400-line files, each about 7 KB as added and again as deleted.
  const patch = diffCase(fiveMoves, 300000);
  assert.doesNotMatch(patch, /^rename from/m);
  for (let i = 0; i < 5; i++) {
    assert.equal(patch.match(new RegExp(`^\\+file ${i} line \\d+$`, "gm")).length, 400);
    assert.equal(patch.match(new RegExp(`^-file ${i} line \\d+$`, "gm")).length, 400);
  }
});

test("over the size cap a file moved unchanged outside the lane sources prints as its rename lines alone", () => {
  const patch = diffCase(fiveMoves, 1000);
  // Five moves of 400 lines each: five headers, no content line.
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
      // The edit names the first move by its whole path; that move, printed
      // whole, names the second by its last directory and name.
      write("ci.yml", "steps: []\nrun: bash build/setup.sh\n");
    },
  });
  for (const word of ["hostile", "helper"]) {
    assert.equal(patch.match(new RegExp(`^\\+${word} \\d+$`, "gm")).length, 20, word);
  }
  assert.match(patch, /^\+source x\/helper\.sh$/m);
  // The move nothing names still collapses.
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
  // An unrelated pure move still collapses.
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
    // Executable on both sides, so the mode does not change.
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

test("each chunk's review leaves a lane record", () => {
  assert.ok(SLOTS >= 2, String(SLOTS));
  for (const job of LEGS) {
    for (let k = 1; k <= SLOTS; k++) {
      const report = step(`Report chunk ${k}'s outcome`, job);
      assert.match(report, /report-lane-outcome@[0-9a-f]{40}/);
      assert.match(report, /^ {10}lane: pr-review-main$/m);
      assert.match(report, /^ {10}lane-id: pr-review-main-\$\{\{ matrix\.lane \}\}$/m);
      assert.equal(input(report, "outcome"), `\${{ steps.review-${k}.outcome }}`);
      assert.equal(input(report, "step-started-at"), k === 1 ? "${{ steps.prompt.outputs.started-at }}" : `\${{ steps.time-${k}.outputs.started-at }}`);
      assert.equal(index(`Report chunk ${k}'s outcome`, job), index(`Review chunk ${k}`, job) + 1);
      assert.match(step(`Review chunk ${k}`, job), /^ {8}continue-on-error: true$/m);
      if (k > 1) {
        assert.equal(index(`Time chunk ${k}`, job) + 1, index(`Review chunk ${k}`, job));
        assert.equal(/^ {8}if: (.*)$/m.exec(step(`Time chunk ${k}`, job))[1], /^ {8}if: (.*)$/m.exec(step(`Review chunk ${k}`, job))[1]);
      }
    }
  }
});

test("it checks out main only, and runs local actions from that checkout", () => {
  // One checkout per leg, and the trigger job's of the tip, like the key leg's.
  assert.equal(text.match(/uses: actions\/checkout@/g).length, LEGS.length + 1);
  const triggerCheckout = jobText("trigger").split(/\n(?=      - name: )/).filter((s) => /uses: actions\/checkout@/.test(s));
  assert.equal(triggerCheckout.length, 1);
  assert.match(triggerCheckout[0], /^ {10}ref: \$\{\{ steps\.tip\.outputs\.sha \}\}$/m);
  assert.match(triggerCheckout[0], /^ {10}path: \.base$/m);
  assert.match(triggerCheckout[0], /^ {10}persist-credentials: false$/m);
  for (const job of LEGS) {
    const checkouts = STEPS[job].filter((s) => /uses: actions\/checkout@/.test(s.block));
    assert.equal(checkouts.length, 1, job);
    // The key leg checks out the tip when it starts, never github.sha, which
    // a re-run of an old run would bring back; a later leg checks out the
    // commit its lane's key leg recorded, which the route passed on.
    const ref = /^ {10}ref: (.*)$/m.exec(checkouts[0].block)[1];
    assert.equal(ref, job === KEY ? "${{ steps.tip.outputs.sha }}" : "${{ matrix.base }}", job);
    // Right after it, the leg records the commit under the lane's name.
    assert.equal(index("Record the main commit", job), index(checkouts[0].name, job) + 1, job);
    assert.match(step("Record the main commit", job), /^ {8}run: echo "\$LANE-base-sha=\$\(git -C \.base rev-parse --verify HEAD\)" >>"\$GITHUB_OUTPUT"$/m);
    assert.match(checkouts[0].block, /^ {10}persist-credentials: false$/m);
  }
  assert.doesNotMatch(text, /github\.sha/);
  // The key and subscription legs pass each lane's commit on, and each route
  // reads the previous leg's.
  for (const [route, from] of [["review-handoffs", KEY], ["subscription-handoffs", SUB]]) {
    for (const lane of ["claude-review", "claude-security-review"]) {
      assert.match(jobText(from), new RegExp(`^ {6}${lane}-base-sha: \\$\\{\\{ steps\\.base\\.outputs\\.${lane}-base-sha \\}\\}$`, "m"));
    }
    // A lane the credit gate handed on had no key leg to record a commit, so
    // the key route falls back to the trigger job's.
    const gated = route === "review-handoffs" ? " \\|\\| needs\\.trigger\\.outputs\\.main-sha" : "";
    assert.match(jobText(route), new RegExp(`^ {10}CODE_BASE: \\$\\{\\{ needs\\.${from}\\.outputs\\.claude-review-base-sha${gated} \\}\\}$`, "m"));
    assert.match(jobText(route), new RegExp(`^ {10}SECURITY_BASE: \\$\\{\\{ needs\\.${from}\\.outputs\\.claude-security-review-base-sha${gated} \\}\\}$`, "m"));
  }
  // The trigger job's commit is the tip it checked out, right after that checkout.
  const triggerSteps = jobText("trigger").split(/\n(?=      - name: )/).slice(1);
  const mainAt = triggerSteps.findIndex((s) => s.startsWith("      - name: Record the main commit\n"));
  assert.match(triggerSteps[mainAt - 1], /uses: actions\/checkout@/);
  assert.match(triggerSteps[mainAt], /^ {8}id: main\n {8}run: echo "main-sha=\$\(git -C \.base rev-parse --verify HEAD\)" >>"\$GITHUB_OUTPUT"$/m);
  for (const [, local] of text.matchAll(/^\s+uses: (\.\/\S+)/gm)) {
    assert.ok(local.startsWith("./.base/.github/actions/"), local);
  }
  for (const [, remote] of text.matchAll(/^\s+uses: ([^.\s]\S*)/gm)) {
    // Actions pin a full SHA (org policy); first-party reusable workflows float on main.
    assert.match(remote, /^melodic-software\/[^/]+\/\.github\/workflows\//.test(remote) ? /@main$/ : /@[0-9a-f]{40}$/, remote);
  }
});

test("the model reads its data directory alone", () => {
  for (const job of LEGS) for (let k = 1; k <= SLOTS; k++) {
  const review = step(`Review chunk ${k}`, job);
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

// The criteria step copies docs/review to STANDARDS_DIR/review; the prompt
// lists that directory, or a reviewer told to read only the listed files
// never applies the per-concern rules.
test("the prompt names the per-concern review rules the criteria step copies", () => {
  assert.ok(prompt.includes("its per-concern review rules (`review/`, when present;"));
  assert.match(readFileSync(new URL("./criteria.txt", import.meta.url), "utf8"), /^copy-if-present docs\/review standards\/review$/m);
});

test("the verdict uploads once, after it is written, under the writer's name", () => {
  // Each leg's verdict, plus review-handoffs' credit-stop marker and the gate's probing marker.
  assert.equal(text.match(/uses: actions\/upload-artifact@/g).length, LEGS.length + 2);
  for (const job of LEGS) {
    const uploads = STEPS[job].filter((s) => /uses: actions\/upload-artifact@/.test(s.block));
    assert.equal(uploads.length, 1, job);
    assert.equal(uploads[0].name, "Upload the verdict");
    // The written verdict is scanned just before it uploads, and uploads only on the scan's clean output.
    assert.ok(index("Write the verdict", job) < index("Scan the upload for credentials", job), job);
    assert.equal(index("Scan the upload for credentials", job) + 1, index("Upload the verdict", job), job);
    const scan = step("Scan the upload for credentials", job);
    assert.match(scan, /^ {8}id: scan-upload\n {8}if: >-\n {10}steps\.verdict\.outcome == 'success'$/m, job);
    assert.match(scan, /^ {10}path: \$\{\{ runner\.temp \}\}\/pr-review-main-verdict\/verdict\.json$/m, job);
    assert.match(uploads[0].block, /^ {8}if: >-\n {10}\(steps\.verdict\.outcome == 'success'\) && steps\.scan-upload\.outputs\.clean == 'true'$/m);
    assert.match(uploads[0].block, /^ {10}name: \$\{\{ steps\.verdict\.outputs\.name \}\}$/m);
    // The tree is git's, the head and base the trigger gate's: never the model's.
    const write = step("Write the verdict", job);
    assert.match(write, /TREE_SHA: \$\{\{ steps\.diff\.outputs\.tree \}\}/);
    assert.match(write, /HEAD_SHA: \$\{\{ steps\.trigger\.outputs\.head-sha \}\}/);
    // The verdict is written only when every chunk's review truly
    // succeeded (the reconciler holds a lost run once it starts), and a
    // handed-off leg writes none.
    const slots = Array.from({ length: SLOTS }, (_, i) => i + 1);
    const each = slots.slice(1).map((k) => `(fromJSON(steps.diff.outputs.chunks || '0') < ${k} || steps.review-${k}.outcome == 'success')`);
    const noHandoff = slots.map((k) => `steps.review-${k}.outputs.handoff != 'true'`);
    assert.equal(/^ {8}if: (.*)$/m.exec(write)[1], ["steps.review-1.outcome == 'success'", ...each, ...noHandoff].join(" && "), job);
    assert.ok(write.includes(`          EXECUTION_FILES: |\n${slots.map((k) => `            \${{ steps.review-${k}.outputs.execution-file }}\n`).join("")}`), job);
    assert.equal(input(write, "CHUNKS"), "${{ steps.diff.outputs.chunks }}");
  }
  assert.match(step("Write the diff"), /rev-parse --verify "\$HEAD_SHA\^\{tree\}"/);
});

test("only a lane-source pull request is reviewed, by the gate's own predicate", () => {
  const triggerStep = (name) => jobText("trigger").split(/\n(?=      - name: )/).find((s) => s.startsWith(`      - name: ${name}\n`));
  const triggerSelect = triggerStep("Select a lane-source pull request");
  const triggerFiles = triggerStep("Read the changed files");
  assert.ok(triggerSelect, "the trigger job selects");
  assert.ok(triggerFiles, "the trigger job reads the files first");
  for (const select of [triggerFiles, triggerSelect, ...LEGS.map((job) => step("Select a lane-source pull request", job))]) {
    assert.match(select, /import babysit_review_evidence as ev/);
    assert.match(select, /ev\.lane_source\(p\)/);
    // The files read goes through the api-budget gh wrapper, so it is
    // counted, and through retry_call, so it is read up to 3 times.
    assert.match(select, /^ {10}\. \.base\/\.github\/actions\/log-api-budget\/api-budget\.bash\n {10}\. \.base\/\.github\/scripts\/pr-merge\/rate-stop\.bash\n {10}\. \.base\/\.github\/scripts\/pr-merge\/retry-call\.bash\n {10}api_budget_wrap_gh github-token\n/m);
    assert.match(select, /retry_call --read 60 read_files/);
  }
  for (const job of LEGS) assert.match(step("Write the diff", job), /^ {8}if: steps\.trigger\.outputs\.review == 'true'$/m);
});

// The trigger job gates and reads the files once per run; the key leg takes
// its result only from the same run attempt, as fixed-shape values, and
// gates itself otherwise (a lane re-run alone keeps an earlier attempt's
// trigger job). The later legs always gate themselves.
test("the key leg takes the trigger job's gate only from this attempt, and every value has a fixed shape", () => {
  const trigger = jobText("trigger");
  assert.equal(needsOf(KEY), `[trigger, ${PROBE}]`);
  const outputs = /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(trigger)[1];
  assert.deepEqual(
    [...outputs.matchAll(/^ {6}([a-z-]+): (.*)$/gm)].map(([, name, value]) => `${name}=${value}`),
    [
      "run-attempt=${{ github.run_attempt }}",
      "proceed=${{ steps.gate.outputs.proceed }}",
      "review=${{ steps.select.outputs.review || steps.files.outputs.review }}",
      "pr-number=${{ steps.gate.outputs.pr-number }}",
      "head-sha=${{ steps.gate.outputs.head-sha }}",
      "base-sha=${{ steps.gate.outputs.base-sha }}",
      "judged=${{ steps.judged.outputs.judged }}",
      "held=${{ steps.select.outputs.held }}",
      "main-sha=${{ steps.main.outputs.main-sha }}",
    ],
  );
  assert.doesNotMatch(trigger, /head-ref/);
  // Its gate is the legs' gate, skipped under the kill switch or when both lanes are off.
  const gateOf = (block) => block.split(/\n(?=      - name: )/).find((s) => s.startsWith("      - name: Check the trigger\n"));
  const triggerGate = gateOf(trigger);
  assert.match(triggerGate, /^ {8}if: steps\.kill\.outputs\.proceed == 'true' && \(vars\.CLAUDE_REVIEW_DISABLED != 'true' \|\| vars\.CLAUDE_SECURITY_REVIEW_DISABLED != 'true'\) && steps\.files\.outputs\.review != 'false' && steps\.judged\.outputs\.judged != 'true'$/m);
  const gateWith = (block) => block.slice(block.indexOf("        uses: ")).replace(/\n\n {6}#[\s\S]*$/, "");
  assert.equal(gateWith(triggerGate), gateWith(step("Check the trigger")));
  // Its calls reach the api-budget notice.
  assert.match(trigger, /- name: Log the API budget\n {8}if: always\(\)\n/);
  // The key leg gates itself only when the trigger job is from another attempt.
  assert.match(step("Check the trigger"), /^ {8}if: steps\.switch\.outputs\.proceed == 'true' && needs\.trigger\.outputs\.run-attempt != github\.run_attempt$/m);
  for (const job of [SUB, FB]) assert.match(step("Check the trigger", job), /^ {8}if: steps\.switch\.outputs\.proceed == 'true'$/m);
  for (const job of LEGS) {
    const take = step("Take the gate's result", job);
    assert.ok(index("Select a lane-source pull request", job) < index("Take the gate's result", job), job);
    assert.match(take, /^ {8}if: steps\.switch\.outputs\.proceed == 'true' && steps\.select\.outputs\.held != 'true'$/m);
    assert.equal(input(take, "CARRIED"), job === KEY ? "${{ needs.trigger.outputs.run-attempt == github.run_attempt }}" : '"false"', job);
    // Every value is checked against a fixed shape before it leaves the step.
    assert.ok(take.includes("$review =~ ^(true|false)$ && $pr =~ ^[1-9][0-9]{0,9}$ && $head =~ ^[0-9a-f]{40}$ && $base =~ ^[0-9a-f]{40}$"), job);
    // The values reach the script only through env, never interpolated.
    assert.doesNotMatch(take.slice(take.indexOf("        run: |")), /\$\{\{/, job);
    // Past it, the leg reads the gate's values only through it.
    const after = STEPS[job].slice(index("Take the gate's result", job) + 1).map((s) => s.block).join("\n");
    assert.doesNotMatch(after, /steps\.(gate|select)\.|needs\.trigger\./, job);
  }
  for (const name of ["PROCEED", "REVIEW", "PR", "HEAD", "BASE"]) {
    const key = { PROCEED: "proceed", REVIEW: "review", PR: "pr-number", HEAD: "head-sha", BASE: "base-sha" }[name];
    assert.equal(input(step("Take the gate's result"), `CARRIED_${name}`), `\${{ needs.trigger.outputs.${key} }}`);
  }
});

// The trigger job reads the event's PR's files before the gate and skips the
// gate only when that read finds no lane source; no single PR or a failed
// read leaves no result, so the gate runs and the select reads the gate's PR.
test("the trigger job reads the files first and gates every lane-source pull request", () => {
  const blocks = jobText("trigger").split(/\n(?=      - name: )/).slice(1);
  const names = blocks.map((block) => /^      - name: (.*)$/m.exec(block)[1]);
  const at = (name) => names.indexOf(name);
  assert.ok(at("Read the changed files") > at("Check the kill switch"), names.join(", "));
  assert.ok(at("Read the changed files") < at("Check the trigger"), names.join(", "));
  assert.ok(at("Check the trigger") < at("Select a lane-source pull request"), names.join(", "));
  const files = blocks[at("Read the changed files")];
  assert.match(files, /^ {8}id: files$/m);
  // The read runs under the gate's own kill-switch and lane conditions.
  assert.match(files, /^ {8}if: steps\.kill\.outputs\.proceed == 'true' && \(vars\.CLAUDE_REVIEW_DISABLED != 'true' \|\| vars\.CLAUDE_SECURITY_REVIEW_DISABLED != 'true'\)$/m);
  assert.match(blocks[at("Check the trigger")], /^ {8}if: .* && steps\.files\.outputs\.review != 'false' && steps\.judged\.outputs\.judged != 'true'$/m);
  assert.ok(at("Read the changed files") < at("Find a head both lanes already reviewed"), names.join(", "));
  assert.ok(at("Find a head both lanes already reviewed") < at("Check the trigger"), names.join(", "));
  // The select reads again unless the read found a lane source in the gate's own PR.
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
    // A lane-source PR: review=true, so the gate's `!= 'false'` runs it.
    const lane = runWith([pull(7)], { GH_PATHS: ".github/workflows/x.yml README.md" });
    assert.equal(lane.out, "pr-number=7\nreview=true\n");
    assert.match(lane.calls, /^api --paginate repos\/o\/r\/pulls\/7\/files\?per_page=100 /);
    // A PR that changes no lane source: review=false skips the gate.
    assert.equal(runWith([pull(7)], { GH_PATHS: "README.md plugins/x/y.py" }).out, "pr-number=7\nreview=false\n");
    // No single PR at the head in this repository, or a failed read: no
    // result, so the gate runs.
    for (const pulls of [[], [pull(7), pull(8)], [pull(7, SHA_B)], [pull(7, SHA_A, 99)], [{ number: "7; x", head: { sha: SHA_A }, base: { repo: { id: 42 } } }]]) {
      const none = runWith(pulls, { GH_PATHS: "README.md" });
      assert.equal(none.out, "", JSON.stringify(pulls));
      assert.equal(none.calls, "", JSON.stringify(pulls));
    }
    // One failed read is read again after a jittered wait, and the second
    // answer counts.
    const again = runWith([pull(7)], { GH_FAIL: "1", GH_PATHS: ".github/workflows/x.yml" });
    assert.equal(again.out, "pr-number=7\nreview=true\n");
    assert.equal(again.calls.split("\n").filter(Boolean).length, 2);
    assert.equal(again.sleeps.split("\n").filter(Boolean).length, 1);
    // A list unread after 3 reads leaves no result, so the gate runs.
    const unread = runWith([pull(7)], { GH_FAIL: "9", GH_PATHS: "README.md" });
    assert.equal(unread.out, "");
    assert.equal(unread.calls.split("\n").filter(Boolean).length, 3);
    assert.match(unread.stdout, /^::warning::the file list did not read \(failed 3 times\); the trigger gate runs$/m);
  } finally {
    harness.remove();
  }
});

// A temporary .base with the predicate's scripts and the real api-budget,
// rate-stop and retry-call helpers, a stub gh that fails its first GH_FAIL
// calls and prints GH_PATHS, and a sleep that only logs its wait.
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
  const triggerSelect = jobText("trigger").split(/\n(?=      - name: )/).find((s) => s.startsWith("      - name: Select a lane-source pull request\n"));
  const harness = filesHarness();
  try {
    for (const [job, block] of [["trigger", triggerSelect], ...LEGS.map((job) => [job, step("Select a lane-source pull request", job)])]) {
      const run = /^ {8}run: \|\n((?: {10}.*\n)+)/m.exec(`${block}\n`)[1].replace(/^ {10}/gm, "");
      assert.doesNotMatch(run, /\$\{\{/, job);
      // A good read: one call, and the predicate's answer.
      const good = harness.run(run, { PR_NUMBER: "7", GH_PATHS: ".github/workflows/x.yml" });
      assert.equal(good.status, 0, `${job}: ${good.stderr}`);
      assert.equal(good.out, "review=true\n", job);
      assert.match(good.calls, /^api --paginate repos\/o\/r\/pulls\/7\/files\?per_page=100 /, job);
      assert.equal(good.calls.split("\n").filter(Boolean).length, 1, job);
      assert.equal(harness.run(run, { PR_NUMBER: "7", GH_PATHS: "README.md" }).out, "review=false\n", job);
      // Two failures, then an answer: three reads, two jittered waits.
      const third = harness.run(run, { PR_NUMBER: "7", GH_FAIL: "2", GH_PATHS: ".github/workflows/x.yml" });
      assert.equal(third.status, 0, `${job}: ${third.stderr}`);
      assert.equal(third.out, "review=true\n", job);
      assert.equal(third.calls.split("\n").filter(Boolean).length, 3, job);
      assert.equal(third.sleeps.split("\n").filter(Boolean).length, 2, job);
      // Three failures: no fourth read, no review answer, and the step holds
      // green with the notice the reconciler reads.
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

// The key leg's job-level skip: no leg starts when this attempt's trigger job
// found no lane source, or a head both lanes already reviewed.
const KEY_SKIP = "      && (needs.trigger.outputs.run-attempt != github.run_attempt\n      || needs.trigger.outputs.review != 'false' && needs.trigger.outputs.judged != 'true' && needs.trigger.outputs.held != 'true')\n";

// The record job runs once a leg could have reviewed: the key leg, or a
// subscription leg the credit gate's skip of the key leg handed every lane to.
const RECORD_IF = /^ {4}if: \$\{\{ !cancelled\(\) && github\.ref == 'refs\/heads\/main' && \(needs\.review\.result != 'skipped' \|\| needs\.review-subscription\.result != 'skipped'\) \}\}$/m;

test("no leg starts, and nothing records, for a head with no lane source or one both lanes reviewed", () => {
  assert.ok(/^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(jobText(KEY))[1].endsWith(KEY_SKIP));
  assert.match(jobText("record"), RECORD_IF);
  // A skipped key leg is reported, and a lane handed on, only where this
  // attempt's trigger job starts the key leg.
  for (const report of ["Report the skipped claude-review key leg", "Report the skipped claude-security-review key leg"]) {
    const condition = /^ {8}if: (.*)$/m.exec(step(report, PROBE))[1];
    for (const term of GO_AHEAD.slice(1)) assert.ok(condition.includes(` && ${term} && `), `${report}: ${term}`);
  }
  for (const term of GO_AHEAD) assert.ok(jobGate("review-handoffs").includes(`&& ${term}`), term);
});

// A select whose file list did not read holds: Note the hold (the step the
// reconciler's faultHeld looks for) runs, and no lane reviews after it, in
// the trigger job or in any leg.
test("a held file list marks the run and starts no review, in the trigger job and every leg", () => {
  const selected = (held) => ({ steps: { switch: { outputs: { proceed: "true" } }, select: { outputs: held === undefined ? {} : { held } } } });
  const triggerSteps = stepsOf("trigger");
  for (const [job, steps] of [["trigger", triggerSteps], ...LEGS.map((job) => [job, STEPS[job]])]) {
    const names = steps.map((s) => s.name);
    // The marker is the step right after the select, under faultHeld's name.
    assert.equal(names[names.indexOf("Select a lane-source pull request") + 1], HELD_STEP, job);
    const marker = /^ {8}if: (.*)$/m.exec(steps.find((s) => s.name === HELD_STEP).block)[1];
    assert.ok(admits(marker, selected("true")), job);
    for (const held of [undefined, "", "false"]) assert.ok(!admits(marker, selected(held)), `${job}: ${held}`);
    if (job === "trigger") continue;
    // A held leg takes no gate result, so its diff and review never run.
    const take = /^ {8}if: (.*)$/m.exec(step("Take the gate's result", job))[1];
    assert.ok(admits(take, selected(undefined)), job);
    assert.ok(!admits(take, selected("true")), job);
  }
  // A trigger job that held starts no key leg, even with a lane-source answer
  // from the event's own read, and hands nothing to the subscription leg.
  const held = { ...triggered, outputs: { ...triggered.outputs, held: "true" } };
  const probe = { result: "success", outputs: {} };
  const keyRuns = (trigger) => admits(jobGate(KEY), { github: upstreamRun, needs: { trigger, [PROBE]: probe } });
  assert.ok(keyRuns(triggered));
  assert.ok(!keyRuns(held));
  const handsOn = (trigger) => admits(jobGate("review-handoffs"), { github: upstreamRun, needs: { trigger, review: { result: "skipped", outputs: {} }, [PROBE]: { result: "success", outputs: { "skip-key": "true" } } } });
  assert.ok(handsOn(triggered));
  assert.ok(!handsOn(held));
  // A lane a person re-runs alone gates itself, so an earlier attempt's hold does not stop it.
  assert.ok(keyRuns({ ...held, outputs: { ...held.outputs, "run-attempt": "0" } }));
});

// This attempt's trigger job starts the key leg: a lane-source head not yet
// judged, whose file list read.
const GO_AHEAD = ["needs.trigger.outputs.run-attempt == github.run_attempt", "needs.trigger.outputs.proceed == 'true'", "needs.trigger.outputs.review == 'true'", "needs.trigger.outputs.judged != 'true'", "needs.trigger.outputs.held != 'true'"];

const jobGate = (id) => /^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(jobText(id))?.[1].replace(/\s+/g, " ").trim();
const upstreamRun = { ref: "refs/heads/main", repository: "o/r", run_attempt: "1", event: { workflow_run: { event: "pull_request", conclusion: "success", head_repository: { full_name: "o/r" } } } };
const triggered = { result: "success", outputs: { "run-attempt": "1", proceed: "true", review: "true", judged: "" } };

// ci-workflows check-key-credit (gate.cjs at the pinned SHA): skip-key is
// `true` only while a credit stop recorded in this workflow is inside the
// window; any failure leaves it empty, so the key runs as before the gate.
test("the credit gate skips the key leg only on skip-key true, and a gate failure runs the key", () => {
  const keyIf = jobGate(KEY);
  assert.ok(keyIf.startsWith(`needs.${PROBE}.outputs.skip-key != 'true' && !cancelled() && needs.trigger.result == 'success' && `), keyIf);
  const runs = (probe, trigger = triggered, options) => admits(keyIf, { github: upstreamRun, needs: { trigger, [PROBE]: probe } }, options);
  assert.ok(!runs({ result: "success", outputs: { "skip-key": "true" } }));
  for (const probe of [{ result: "success", outputs: { "skip-key": "false" } }, { result: "failure", outputs: {} }, { result: "skipped", outputs: {} }]) {
    assert.ok(runs(probe), JSON.stringify(probe));
  }
  // The trigger job's own result still gates the key leg, as the implicit success() did.
  assert.ok(!runs({ result: "failure", outputs: {} }, { ...triggered, result: "failure" }));
  assert.ok(!runs({ result: "success", outputs: {} }, triggered, { cancelled: true }));
  // The gate runs on every run of this attempt's trigger job, a head with no
  // lane source or one already judged included.
  const probeRuns = (trigger) => admits(jobGate(PROBE), { github: upstreamRun, needs: { trigger } });
  for (const outputs of [{}, { proceed: "" }, { review: "false" }, { judged: "true" }]) {
    assert.ok(probeRuns({ ...triggered, outputs: { ...triggered.outputs, ...outputs } }), JSON.stringify(outputs));
  }
  assert.ok(!probeRuns({ ...triggered, outputs: { ...triggered.outputs, "run-attempt": "2" } }));
  assert.ok(!admits(jobGate(PROBE), { github: { ...upstreamRun, ref: "refs/heads/x" }, needs: { trigger: triggered } }));
});

test("the credit gate holds no secret, checks nothing out and reads only the marker artifacts", () => {
  const job = jobText(PROBE);
  assert.equal(needsOf(PROBE), "trigger");
  assert.match(job, /^ {4}permissions:\n {6}actions: read #.*\n {4}outputs:\n {6}skip-key: \$\{\{ steps\.gate\.outputs\.skip-key \}\}\n {6}marker: \$\{\{ steps\.gate\.outputs\.marker \}\}\n/m);
  assert.doesNotMatch(job, /secrets\.|actions\/checkout|run-claude-cli|\.\/\.base/);
  const gate = step("Read the key's credit history", PROBE);
  assert.match(gate, /^ {8}id: gate$/m);
  assert.match(gate, /^ {8}continue-on-error: true$/m);
  // The marker gate (ci-workflows#973) with the probing marker (#980); a pin
  // before #973 reads run history for a record step this workflow no longer
  // writes, so it would never skip.
  assert.match(gate, /^ {8}uses: melodic-software\/ci-workflows\/\.github\/actions\/check-key-credit@b8bdd7fa2319b2457cbbef32c5348c394b9bc3f6 # \S/m);
  // The marker's name carries key-job: review-handoffs, the job that uploads it.
  assert.equal(input(gate, "key-job"), "review-handoffs");
  assert.equal(input(gate, "window-hours"), "${{ vars.KEY_CREDIT_WINDOW_HOURS || '1' }}");
  // Each skipped key leg leaves its lane record, so leg counts compare.
  for (const [lane, sw] of [["claude-review", "CLAUDE_REVIEW_DISABLED"], ["claude-security-review", "CLAUDE_SECURITY_REVIEW_DISABLED"]]) {
    const report = step(`Report the skipped ${lane} key leg`, PROBE);
    assert.match(report, new RegExp(`^ {8}if: steps\\.gate\\.outputs\\.skip-key == 'true' && ${GO_AHEAD.slice(1).join(" && ").replace(/[.()|]/g, "\\$&")} && vars\\.${sw} != 'true'$`, "m"));
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
  const probe = "key-credit-probing-pr-review-main.yml-review-handoffs";
  const names = ["Write the key's probing marker", "Scan the key's probing marker for credentials", "Upload the key's probing marker"];
  const [write, scan, upload] = names.map((name) => step(name, PROBE));
  assert.match(write, /^ {8}id: probe-marker$/m);
  const writeIf = /^ {8}if: (.*)$/m.exec(write)[1];
  // The review job's trigger terms: only a run whose key legs start probes the key.
  assert.equal(writeIf, `always() && steps.gate.outputs.probing-marker == '${probe}' && needs.trigger.outputs.proceed == 'true' && needs.trigger.outputs.review != 'false' && needs.trigger.outputs.judged != 'true' && needs.trigger.outputs.held != 'true'`);
  assert.equal(triggered.outputs.proceed, "true");
  // Written when the gate names this probe and the key legs start; not when it names none
  // or a renamed one, or when the trigger found no lane source or a head already judged.
  const writes = (output, outputs = triggered.outputs) =>
    admits(writeIf.replace(/^always\(\) && /, ""), { steps: { gate: { outputs: { "probing-marker": output } } }, needs: { trigger: { outputs } } });
  assert.ok(writes(probe));
  for (const output of ["", "key-credit-probing-pr-review-main.yml-other"]) assert.ok(!writes(output), output);
  for (const outputs of [{ judged: "true" }, { review: "false" }, { proceed: "" }, { proceed: "false" }, { held: "true" }]) {
    assert.ok(!writes(probe, { ...triggered.outputs, ...outputs }), JSON.stringify(outputs));
  }
  assert.match(write, /echo "\$GITHUB_RUN_ID" >"\$RUNNER_TEMP\/key-credit-probing\/run-id"/);
  assert.match(scan, /^ {8}id: probe-marker-scan$/m);
  assert.match(scan, /^ {8}if: always\(\) && steps\.probe-marker\.outcome == 'success'$/m);
  assert.match(scan, /^ {8}uses: melodic-software\/ci-workflows\/\.github\/actions\/scan-upload@[0-9a-f]{40} # \S/m);
  assert.match(upload, /^ {8}if: \(always\(\) && steps\.probe-marker\.outcome == 'success'\) && steps\.probe-marker-scan\.outputs\.clean == 'true'$/m);
  assert.match(upload, /^ {8}uses: actions\/upload-artifact@[0-9a-f]{40} # \S/m);
  assert.equal(input(upload, "name"), probe);
  assert.equal(input(upload, "path"), "${{ runner.temp }}/key-credit-probing/run-id");
  assert.equal(input(scan, "path"), input(upload, "path"));
  assert.equal(input(upload, "retention-days"), "1");
  assert.equal(input(upload, "if-no-files-found"), "error");
  for (const block of [write, scan, upload]) assert.match(block, /^ {8}continue-on-error: true$/m);
  // Right after the gate, before the skipped-leg reports.
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
  // The key leg's own handoff reason, never the route's: a lane the gate handed
  // on must not restart the window, or the key would never be tried again.
  assert.match(write, /^ {8}if: \$\{\{ !cancelled\(\) && needs\.review-handoffs-credit\.outputs\.marker != '' && \(needs\.review\.outputs\.claude-review == 'credit-stop' \|\| needs\.review\.outputs\.claude-security-review == 'credit-stop'\) \}\}$/m);
  assert.match(write, /^ {8}continue-on-error: true$/m);
  assert.match(write, /echo "\$GITHUB_RUN_ID" >"\$RUNNER_TEMP\/key-credit-stop\/run-id"/);
  const upload = step("Upload the key's credit-stop marker", "review-handoffs");
  assert.ok(index("Upload the key's credit-stop marker", "review-handoffs") > index("Write the key's credit-stop marker", "review-handoffs"));
  assert.match(upload, /^ {8}if: \$\{\{ !cancelled\(\) && steps\.credit-marker\.outcome == 'success' \}\}$/m);
  assert.match(upload, /^ {8}continue-on-error: true$/m);
  assert.match(upload, /^ {8}uses: actions\/upload-artifact@[0-9a-f]{40} # \S/m);
  assert.equal(input(upload, "name"), "${{ needs.review-handoffs-credit.outputs.marker }}");
  assert.equal(input(upload, "path"), "${{ runner.temp }}/key-credit-stop/run-id");
  assert.equal(input(upload, "if-no-files-found"), "error");
  assert.equal(input(upload, "retention-days"), "1");
  // The run-history record steps the old gate read are gone everywhere.
  assert.doesNotMatch(text, /Record the key's credit stop/);
  for (const job of LEGS) assert.equal(index("Upload the key's credit-stop marker", job), -1, job);
});

test("with the key leg skipped by the credit gate, every enabled lane goes to the subscription leg as a credit stop", () => {
  const route = jobText("review-handoffs");
  assert.equal(needsOf("review-handoffs"), `[trigger, ${PROBE}, ${KEY}]`);
  const routeIf = jobGate("review-handoffs");
  const handsOn = (review, probe, trigger = triggered) => admits(routeIf, { github: upstreamRun, needs: { trigger, review, [PROBE]: probe } });
  const gated = { result: "success", outputs: { "skip-key": "true" } };
  assert.ok(handsOn({ result: "skipped", outputs: {} }, gated));
  assert.ok(handsOn({ result: "success", outputs: { "claude-review": "credit-stop" } }, { result: "success", outputs: { "skip-key": "false" } }));
  // A key leg skipped for any other reason, or that handed nothing on, routes nothing.
  assert.ok(!handsOn({ result: "skipped", outputs: {} }, { result: "skipped", outputs: {} }));
  assert.ok(!handsOn({ result: "success", outputs: {} }, { result: "success", outputs: { "skip-key": "false" } }));
  // With the key out of credit, a run whose trigger job starts no key leg
  // (no lane source, a judged head, a refused gate, another attempt) routes nothing.
  for (const outputs of [{ review: "false" }, { judged: "true" }, { proceed: "" }, { "run-attempt": "2" }]) {
    assert.ok(!handsOn({ result: "skipped", outputs: {} }, gated, { ...triggered, outputs: { ...triggered.outputs, ...outputs } }), JSON.stringify(outputs));
  }
  for (const [env, lane, sw] of [["CODE", "claude-review", "CLAUDE_REVIEW_DISABLED"], ["SECURITY", "claude-security-review", "CLAUDE_SECURITY_REVIEW_DISABLED"]]) {
    assert.match(route, new RegExp(`^ {10}${env}: \\$\\{\\{ needs\\.review\\.outputs\\.${lane} \\|\\| needs\\.review\\.result == 'skipped' && needs\\.${PROBE}\\.outputs\\.skip-key == 'true' && vars\\.${sw} != 'true' && 'credit-stop' \\|\\| '' \\}\\}$`, "m"));
  }
  // Both lanes handed on as credit-stop at the trigger job's commit.
  const { status, matrix } = routeRun("review-handoffs")({ CODE: "credit-stop", SECURITY: "credit-stop", CODE_BASE: SHA_A, SECURITY_BASE: SHA_A });
  assert.equal(status, 0);
  assert.deepEqual(matrix.include.map((row) => [row.lane, row.reason, row.base]), [["claude-review", "credit-stop", SHA_A], ["claude-security-review", "credit-stop", SHA_A]]);
});

// The trigger job's judged-head read: judged=true only when the merge gate's
// own predicate binds both lanes at the event's head; anything less, or any
// failed read, leaves no output and the review runs.
test("a head both lanes reviewed in a successful main run, recorded on the head, is judged; anything less is not", () => {
  const block = jobText("trigger").split(/\n(?=      - name: )/).find((s) => s.startsWith("      - name: Find a head both lanes already reviewed\n"));
  assert.ok(block, "the trigger job reads the judged head");
  assert.match(block, /^ {8}id: judged$/m);
  assert.match(block, /^ {8}if: steps\.files\.outputs\.review == 'true'$/m);
  assert.equal(input(block, "PR_NUMBER"), "${{ steps.files.outputs.pr-number }}");
  assert.equal(input(block, "HEAD_SHA"), "${{ github.event.workflow_run.head_sha }}");
  assert.equal(input(block, "TREE_SHA"), "${{ github.event.workflow_run.head_commit.tree_id }}");
  const run = /^ {8}run: \|\n((?: {10}.*\n|\n)+)/m.exec(`${block}\n`)[1].replace(/^ {10}/gm, "");
  assert.doesNotMatch(run, /\$\{\{/);
  // Its reads go through the api-budget gh wrapper, so they are counted, and
  // through retry_call; a helper that does not load runs the review.
  assert.match(run, /\{ \. \.base\/\.github\/actions\/log-api-budget\/api-budget\.bash 2>\/dev\/null && api_budget_wrap_gh github-token; \} \|\| true\n/);
  assert.match(run, /\{ \. \.base\/\.github\/scripts\/pr-merge\/rate-stop\.bash && \. \.base\/\.github\/scripts\/pr-merge\/retry-call\.bash; \} 2>\/dev\/null \|\| true\n/);
  assert.deepEqual(run.match(/^ *gh api .*/gm).map((line) => line.trim()), ['gh api "$@" >"$file"'], "every read goes through try_read api_into");
  // The record title the gate reads as counts is the one this step reads.
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
    // The real api-budget, rate-stop and retry-call helpers.
    symlinkSync(new URL("../../actions", import.meta.url).pathname, path.join(dir, ".base", ".github", "actions"));
    symlinkSync(new URL("../pr-merge", import.meta.url).pathname, path.join(dir, ".base", ".github", "scripts", "pr-merge"));
    const bin = path.join(dir, "bin");
    const fixtures = path.join(dir, "fixtures");
    mkdirSync(bin);
    // Answers `gh api [-i] <url>` from a fixture file named after the url (a
    // body with no header block, which the wrapper passes on whole); a url
    // with no fixture fails as a failed read does. The first GH_FAIL calls to
    // a url holding GH_FAIL_URL fail as a 502.
    writeFileSync(
      path.join(bin, "gh"),
      '#!/bin/bash\necho "$*" >>"$GH_LOG"\n[ "$2" = -i ] && set -- "$1" "${@:3}"\nif [ -n "$GH_FAIL_URL" ] && [[ $2 == *"$GH_FAIL_URL"* ]] && [ "$(grep -cF -- "$GH_FAIL_URL" "$GH_LOG")" -le "${GH_FAIL:-0}" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi\nf="$GH_FIXTURES/$(printf %s "$2" | tr -c "A-Za-z0-9" _)"\n[ -f "$f" ] || exit 1\ncat "$f"\n',
    );
    writeFileSync(path.join(bin, "sleep"), '#!/bin/bash\necho "$1" >>"$SLEEP_LOG"\n');
    chmodSync(path.join(bin, "gh"), 0o755);
    chmodSync(path.join(bin, "sleep"), 0o755);
    const key = (url) => url.replace(/[^A-Za-z0-9]/g, "_");
    const lanes = ["claude-review", "claude-security-review"];
    const write = ({ missing = [], conclusion = "success", head = SHA_A, title = "findings=2 critical=0", branch = "main", event = "workflow_run", total = 1, main = TIP, workflow = ".github/workflows/pr-review-main.yml" } = {}) => {
      rmSync(fixtures, { recursive: true, force: true });
      mkdirSync(fixtures);
      lanes.forEach((lane, i) => {
        const name = `pr-review-main-${lane}-${PR}-${TREE}`;
        const artifact = 100 + i;
        const runId = 200 + i;
        const at = (url, body) => writeFileSync(path.join(fixtures, key(url)), typeof body === "string" ? body : JSON.stringify(body));
        // A lane with no verdict lists no artifact for the tree.
        if (missing.includes(lane)) return at(`repos/o/r/actions/artifacts?name=${name}&per_page=100`, { total_count: 0, artifacts: [] });
        at(`repos/o/r/actions/artifacts?name=${name}&per_page=100`, { total_count: total, artifacts: [{ id: artifact, name, expired: false, workflow_run: { id: runId } }] });
        at(`repos/o/r/actions/runs/${runId}`, { id: runId, path: workflow, event, head_branch: branch, head_sha: main, status: "completed", conclusion, repository: { full_name: "o/r" }, head_repository: { full_name: "o/r" } });
        const verdict = path.join(dir, "verdict.json");
        writeFileSync(verdict, JSON.stringify({ schema: 1, lane, pr: PR, tree: TREE, head_sha: head, findings: 2, critical: 0, max_line_bytes: 80 }));
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
        env: { ...gitEnv, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: path.join(dir, "tmp"), GITHUB_OUTPUT: out, GITHUB_REPOSITORY: "o/r", GH_LOG: log, SLEEP_LOG: sleeps, GH_FIXTURES: fixtures, GH_FAIL_URL: "", GH_FAIL: "0", PR_NUMBER: String(PR), HEAD_SHA: SHA_A, TREE_SHA: TREE, DIR: path.join(dir, "work"), ...env },
      });
      assert.equal(result.status, 0, result.stderr + result.stdout);
      const lines = (file) => readFileSync(file, "utf8").split("\n").filter(Boolean);
      return { out: readFileSync(out, "utf8"), stdout: result.stdout, calls: lines(log), sleeps: lines(sleeps) };
    };
    write();
    const judged = runWith();
    assert.equal(judged.out, "judged=true\n");
    // Per lane: the listing, the run, the zip and the head's check runs, each
    // sent once through the counting wrapper, with no wait.
    assert.equal(judged.calls.length, 8, judged.calls.join("\n"));
    assert.ok(judged.calls.every((call) => call.startsWith("api -i repos/o/r/")), judged.calls.join("\n"));
    assert.equal(judged.sleeps.length, 0);
    // Each read is sent again after a failure. At every one of the four
    // reads, one failure then an answer: one more call, one jittered wait,
    // and the head is still judged. Three failures: no fourth send, a notice
    // naming the read, no later read, and the review runs.
    const READS = [
      ["the claude-review verdict listing", "actions/artifacts?name=pr-review-main-claude-review-", 1],
      ["run 200", "actions/runs/200", 2],
      ["artifact 100", "actions/artifacts/100/zip", 3],
      ["the claude-review check runs", "check-runs?check_name=pr-review-main%3A%20claude-review&", 4],
    ];
    for (const [what, url, at] of READS) {
      const again = runWith({ GH_FAIL_URL: url, GH_FAIL: "1" });
      assert.equal(again.out, "judged=true\n", what);
      assert.equal(again.calls.length, 9, `${what}\n${again.calls.join("\n")}`);
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
    // A run that did not succeed, a verdict for another head of the tree, a
    // record whose counts differ, a lane with no verdict, a
    // listing past one page: no output, so the review runs.
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
    // A run from an older main commit with the tip's criteria counts: that
    // commit is fetched, and only a path outside criteria.txt differs.
    write({ main: CHANGED });
    const older = runWith();
    assert.equal(older.out, "judged=true\n");
    assert.equal(older.calls.length, 8, older.calls.join("\n"));
    assert.ok(has(CHANGED), "the run's main commit was fetched");
    // A run from a commit whose criteria differ (REVIEW.md) does not count,
    // and its verdict is never downloaded: per lane, the listing, the run and
    // the check runs.
    write({ main: OLD });
    const stale = runWith();
    assert.equal(stale.out, "");
    assert.equal(stale.calls.length, 6, stale.calls.join("\n"));
    assert.ok(!stale.calls.some((call) => call.includes("/zip")), stale.calls.join("\n"));
    // A run whose main commit changes one criterion alone, whatever its row's
    // kind, does not count either.
    for (const [file, main] of side) {
      write({ main });
      const one = runWith();
      assert.equal(one.out, "", file);
      assert.equal(one.calls.length, 6, `${file}\n${one.calls.join("\n")}`);
    }
    // A run of another workflow, off main, or for another event is dropped
    // before any fetch or download, even at the tip: per lane, the listing,
    // the run and the check runs.
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
    // A commit main does not have (the fetch fails), or a run head that is no
    // SHA: no output, and the step stays green.
    for (const main of ["d".repeat(40), "main"]) {
      write({ main });
      assert.equal(runWith().out, "", main);
    }
    // The fetch of a commit main does not have is sent 3 times, then the
    // review runs with a notice.
    write({ main: "d".repeat(40) });
    const unfetched = runWith();
    assert.equal(unfetched.sleeps.length, 2);
    assert.ok(unfetched.stdout.split("\n").includes(`::notice::main commit ${"d".repeat(40)} did not read (failed 3 times); the review runs`), unfetched.stdout);
    // No verdict for the first lane: one listing read and no more.
    write({ missing: ["claude-review"] });
    const none = runWith();
    assert.equal(none.out, "");
    assert.equal(none.calls.length, 1, none.calls.join("\n"));
    // A read that keeps failing: 3 sends, no output, and the step stays green.
    write();
    rmSync(path.join(fixtures, key(`repos/o/r/actions/runs/201`)));
    const failed = runWith();
    assert.equal(failed.out, "");
    assert.equal(failed.calls.filter((call) => call.endsWith("actions/runs/201")).length, 3, failed.calls.join("\n"));
    assert.ok(failed.stdout.split("\n").includes("::notice::run 201 did not read (failed 3 times); the review runs"), failed.stdout);
    // No tree in the event, or a malformed number: no read at all.
    for (const env of [{ TREE_SHA: "" }, { PR_NUMBER: "7; x" }]) {
      const bad = runWith(env);
      assert.equal(bad.out, "", JSON.stringify(env));
      assert.equal(bad.calls.length, 0, JSON.stringify(env));
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// Every leg copies what criteria.txt lists, to the places the prompt names:
// the skill without its evals beside the plugin's reference, and REVIEW.md,
// the standards and the rules under standards; docs/review and the rules may
// be absent, REVIEW.md may not.
test("each leg copies the review criteria criteria.txt lists", () => {
  const run = /^ {8}run: \|\n((?: {10}.*\n|\n)+)/m.exec(`${step("Copy the review criteria")}\n`)[1].replace(/^ {10}/gm, "");
  for (const job of LEGS) assert.equal(step("Copy the review criteria", job), step("Copy the review criteria"), job);
  assert.equal(input(step("Copy the review criteria"), "SKILL"), "${{ matrix.skill }}");
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-criteria-"));
  try {
    const files = {
      ".github/scripts/pr-review-main/criteria.txt": readFileSync(new URL("./criteria.txt", import.meta.url), "utf8"),
      "plugins/review/skills/code-review/SKILL.md": "skill",
      "plugins/review/skills/code-review/evals/case.md": "eval",
      "plugins/review/skills/security-review/SKILL.md": "other lane",
      "plugins/review/reference/ref.md": "ref",
      "REVIEW.md": "review",
      "docs/standards/s.md": "standard",
      ".claude/rules/r.md": "rule",
    };
    for (const [file, body] of Object.entries(files)) {
      mkdirSync(path.dirname(path.join(dir, ".base", file)), { recursive: true });
      writeFileSync(path.join(dir, ".base", file), body);
    }
    const data = path.join(dir, "data");
    const copy = () => spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", run], { cwd: dir, encoding: "utf8", env: { ...process.env, SKILL: "code-review", DATA: data } });
    const result = copy();
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(readdirSync(data, { recursive: true }).filter((f) => f.endsWith(".md")).sort(), [
      "review/reference/ref.md",
      "review/skills/code-review/SKILL.md",
      "standards/REVIEW.md",
      "standards/rules/r.md",
      "standards/standards/s.md",
    ]);
    rmSync(data, { recursive: true, force: true });
    rmSync(path.join(dir, ".base", "REVIEW.md"));
    assert.notEqual(copy().status, 0, "a main with no REVIEW.md fails the copy");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// The review lanes' credential order, read from their callers' `secrets:`
// blocks, never from this workflow: each names the reusable's secret and the
// repository secret it passes.
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
  // Walk this workflow's chain from the key leg through each route, which
  // needs the leg before it last (the key route also the trigger and gate).
  const order = [KEY];
  for (let job = KEY; ; ) {
    const route = ["review-handoffs", "subscription-handoffs"].find((id) => needsOf(id).replace(/^\[|\]$/g, "").split(", ").at(-1) === job);
    if (!route) break;
    job = LEGS.find((id) => needsOf(id) === route);
    order.push(job);
  }
  assert.deepEqual(order, LEGS);
  const used = order.map((job) => {
    const review = step("Review chunk 1", job);
    const set = CREDENTIAL_INPUTS.filter((name) => input(review, name) !== undefined);
    assert.equal(set.length, 1, `${job} passes one credential`);
    return [set[0], /^\$\{\{ secrets\.([A-Z_]+) \}\}$/.exec(input(review, set[0]))[1]];
  });
  assert.deepEqual(used, hosted.map(([as, secret]) => [LAUNCHER_INPUT[as], secret]));
  // Each leg checks its own credential; the key leg hands an empty key on,
  // and the subscription leg checks whether the fallback token is set.
  const later = {
    [KEY]: '"true"',
    [SUB]: "${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}",
    [FB]: '"false"',
  };
  order.forEach((job, i) => {
    const check = step("Check the credential", job);
    assert.equal(input(check, "PRESENT"), `\${{ secrets.${used[i][1]} != '' }}`, job);
    assert.equal(input(check, "SECRET_NAME"), used[i][1], job);
    assert.equal(input(check, "LATER_PRESENT"), later[job], job);
  });
  // Each secret's value reaches only its leg's launcher step; elsewhere a
  // job may ask only whether it is set.
  for (const job of LEGS) {
    for (const s of STEPS[job]) {
      const values = [...s.block.matchAll(/secrets\.([A-Z_]+)(?![A-Z_]| != '')/g)].map(([, name]) => name);
      if (/^Review chunk \d$/.test(s.name)) assert.equal(values.length, 1, job);
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
  "subscription-handoffs": ["limit-stop", "credit-stop", "auth", "no-key"],
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
  // The rows are the key leg's own matrix.
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
    // A handed-on lane with no main commit, or one that is not 40 hex, fails
    // the route, so no later leg runs for it; a lane not handed on needs none.
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
  // limit-stop comes only from a subscription leg.
  assert.notEqual(routeRun("review-handoffs")({ CODE: "limit-stop", SECURITY: "" }).status, 0);
  assert.equal(routeRun("subscription-handoffs")({ CODE: "limit-stop", SECURITY: "" }).status, 0);
});

test("a later leg runs only for the lanes the previous leg handed on", () => {
  for (const [route, from, to] of [["review-handoffs", KEY, SUB], ["subscription-handoffs", SUB, FB]]) {
    const routeJob = jobText(route);
    // The key route also reads the trigger job's commit and the credit gate's
    // skip, which hands every lane on (its own test above).
    assert.equal(needsOf(route), route === "review-handoffs" ? `[trigger, ${PROBE}, ${from}]` : from);
    const gated = route === "review-handoffs" ? `\\n {6}\\|\\| needs\\.review\\.result == 'skipped' && needs\\.${PROBE}\\.outputs\\.skip-key == 'true'\\n[^)]*` : "";
    assert.match(routeJob, new RegExp(`&& \\(needs\\.${from}\\.outputs\\.claude-review != '' \\|\\| needs\\.${from}\\.outputs\\.claude-security-review != ''${gated}\\)`));
    // !cancelled(): one lane's failed leg does not drop the other lane's
    // handoff; the route still passes on only closed-set reasons.
    assert.match(routeJob, /^ {4}if: >-\n {6}!cancelled\(\)\n {6}&& github\.ref == 'refs\/heads\/main'\n/m);
    assert.doesNotMatch(routeJob, /always\(\)/);
    const leg = jobText(to);
    assert.equal(needsOf(to), route);
    assert.match(leg, new RegExp(`^ {6}matrix: \\$\\{\\{ fromJSON\\(needs\\.${route}\\.outputs\\.matrix\\) \\}\\}$`, "m"));
    // !cancelled() with the route's own success: the implicit success() needs
    // every ancestor, so one lane's failed leg would skip the other's.
    assert.match(leg, new RegExp(`^ {4}if: >-\\n {6}!cancelled\\(\\)\\n {6}&& needs\\.${route}\\.result == 'success'\\n {6}&& github\\.ref == 'refs\\/heads\\/main'\\n`, "m"));
    assert.doesNotMatch(leg, /always\(\) \|\|/);
    // Each lane's reason is its own output, set only by the handoff step.
    for (const lane of ["claude-review", "claude-security-review"]) {
      assert.match(jobText(from), new RegExp(`^ {6}${lane}: \\$\\{\\{ steps\\.handoff\\.outputs\\.${lane} \\}\\}$`, "m"));
    }
  }
  // The fallback leg is the last: it hands nothing on.
  assert.equal(index("Hand the lane on", FB), -1);
  // Its outputs are the designed stops alone, for the record job.
  const fbOutputs = /^ {4}outputs:\n((?: {6}.*\n)+)/m.exec(jobText(FB))[1];
  assert.deepEqual(
    [...fbOutputs.matchAll(/^ {6}([a-z-]+):/gm)].map(([, name]) => name),
    ["claude-review-stop", "claude-security-review-stop", "claude-review-head", "claude-security-review-head"],
  );
  for (let k = 1; k <= SLOTS; k++) {
    assert.doesNotMatch(step(`Review chunk ${k}`, KEY), /fallback-ready/);
    assert.equal(input(step(`Review chunk ${k}`, SUB), "fallback-ready"), "${{ steps.credential.outputs.fallback-ready }}");
    assert.doesNotMatch(step(`Review chunk ${k}`, FB), /fallback-ready/);
  }
  // The record job waits for every leg and runs when a later one skipped,
  // but not when the key leg and the subscription leg both did (its own test above).
  assert.match(jobText("record"), /^ {4}needs: \[review, review-subscription, review-fallback\]$/m);
  assert.match(jobText("record"), RECORD_IF);
  const records = (review, subscription) => admits(/^ {4}if: \$\{\{ (.*) \}\}$/m.exec(jobText("record"))[1], { github: { ref: "refs/heads/main" }, needs: { review: { result: review }, "review-subscription": { result: subscription } } });
  assert.ok(records("success", "skipped"));
  assert.ok(records("skipped", "success"));
  assert.ok(records("skipped", "failure"));
  assert.ok(!records("skipped", "skipped"));
});

test("the handoff step names its lane and a closed reason, and a handed-off leg stays green", () => {
  for (const job of [KEY, SUB]) {
    const handoff = step("Hand the lane on", job);
    // Any chunk's handoff hands the whole lane on.
    const slots = Array.from({ length: SLOTS }, (_, i) => i + 1);
    assert.equal(/^ {8}if: (.*)$/m.exec(handoff)[1], `${slots.map((k) => `steps.review-${k}.outputs.handoff == 'true'`).join(" || ")} || steps.credential.outputs.present == 'false'`);
    assert.equal(input(handoff, "REASON"), `\${{ steps.credential.outputs.present == 'false' && 'no-key' || ${slots.map((k) => `steps.review-${k}.outputs.handoff-reason`).join(" || ")} }}`);
    assert.ok(index(`Upload chunk ${SLOTS}'s sealed transcript`, job) + 1 === index("Hand the lane on", job));
    // A chunk that handed off still leaves its lane record, marked handoff.
    for (const k of slots) {
      const report = step(`Report chunk ${k}'s outcome`, job);
      assert.equal(/^ {8}if: (.*)$/m.exec(report)[1], `steps.review-${k}.outcome == 'success' || steps.review-${k}.outcome == 'failure'`);
      assert.equal(input(report, "handoff"), `\${{ steps.review-${k}.outputs.handoff }}`);
      // A report that throws must not block "Hand the lane on".
      assert.match(report, /^ {8}continue-on-error: true$/m);
    }
    assert.match(step("Fail without a verdict", job), /&& steps\.handoff\.outcome != 'success'$/m);
  }
  // The fallback leg hands nothing on, so its records carry no handoff.
  for (let k = 1; k <= SLOTS; k++) assert.equal(input(step(`Report chunk ${k}'s outcome`, FB), "handoff"), undefined);
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

test("every later leg repeats the key leg's steps but for its credential and why it ran", () => {
  const normal = (block) =>
    block
      .replace(/secrets\.[A-Z_]+/g, "secrets.X")
      .replace(/^( {8}with:\n)(?: {10}#.*\n)+ {10}ref: .*\n/m, "$1          ref: REF\n")
      .replace(/^( {10}SECRET_NAME: ).*$/m, "$1X")
      .replace(new RegExp(`^( {10})(?:${CREDENTIAL_INPUTS.join("|")}): `, "m"), "$1credential: ")
      .replace(/^ {10}LATER_PRESENT: .*\n/m, "")
      // The key leg's take on the trigger job's gate (its own test above).
      .replace(/ && needs\.trigger\.outputs\.run-attempt != github\.run_attempt$/m, "")
      .replace(/^ {10}# The trigger job's result, only from this run attempt\.\n/m, "")
      .replace(/^ {10}CARRIED(?:_[A-Z]+)?: .*\n/gm, "")
      .replace(/^ {10}fallback-ready: \$\{\{ steps\.credential\.outputs\.fallback-ready \}\}\n/m, "")
      .replace(/\n {10}# Why this leg ran, for its lane record\.\n {10}fallback-reason: [^\n]*/, "")
      // The handoff input, pinned per leg in the handoff test.
      .replace(/^ {10}handoff: \$\{\{ steps\.review-\d\.outputs\.handoff \}\}\n/m, "")
      .replace(/ && steps\.handoff\.outcome != 'success'|and handed nothing on\n {6}# fails here,|fails here,/g, "");
  // Only the key leg reads main's tip; a later leg checks out the commit it recorded.
  const keyNames = STEPS[KEY].map((s) => s.name).filter((name) => name !== "Resolve main's tip");
  assert.deepEqual(STEPS[SUB].map((s) => s.name), keyNames);
  assert.deepEqual(STEPS[FB].map((s) => s.name), keyNames.filter((name) => name !== "Hand the lane on"));
  for (const job of [SUB, FB]) {
    for (const s of STEPS[job]) assert.equal(normal(s.block), normal(step(s.name, KEY)), `${job}: ${s.name}`);
    // Each record names why it ran, from the route's closed reason.
    for (let k = 1; k <= SLOTS; k++) {
      assert.equal(
        input(step(`Report chunk ${k}'s outcome`, job), "fallback-reason"),
        "${{ matrix.reason == 'credit-stop' && 'credit-stop' || matrix.reason == 'auth' && 'auth' || matrix.reason == 'limit-stop' && 'limit-stop' || matrix.reason == 'no-key' && 'no-key' || '' }}",
      );
    }
    // Its gates are the key leg's.
    // Past the route checks, its gates are the key leg's.
    // The key leg's skip on the trigger job's answer (its own test below).
    const gates = (id) =>
      /^ {4}if: >-\n((?: {6}.*\n)+)/m
        .exec(jobText(id))[1]
        .replace(/^ {6}!cancelled\(\)\n {6}&& needs\.[a-z-]+\.result == 'success'\n {6}&& /, "      ")
        // The key leg's credit gate and its trigger job's success (their own test above).
        .replace(/^ {6}needs\.review-handoffs-credit\.outputs\.skip-key != 'true'\n {6}&& !cancelled\(\)\n {6}&& needs\.trigger\.result == 'success'\n {6}&& /, "      ")
        .replace(KEY_SKIP, "");
    assert.equal(gates(job), gates(KEY));
  }
  assert.equal(input(step("Report chunk 1's outcome", KEY), "fallback-reason"), undefined);
});

test("one lane handed on beside one that reviewed routes only the handed-on lane", () => {
  for (const job of Object.keys(ROUTES)) {
    // The security lane reviewed (no output); the code lane handed on.
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
  // It sits with the diff parts, before the placeholder they replace.
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
