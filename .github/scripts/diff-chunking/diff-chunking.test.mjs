// test-scope: plugins/source-control/skills/babysit-prs/scripts/diff_risk.py
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { filePatch, MIXED, MIXED_MANIFEST } from "./fixtures.mjs";
import { LONG_LINE_BYTES } from "../pr-review-main/write-verdict.mjs";

const MODULE = fileURLToPath(new URL("./diff_chunking.py", import.meta.url));
const ROOT = path.resolve(path.dirname(MODULE), "../../..");

function split(patch, maxBytes, maxChunks, manifestBytes, maxFiles) {
  const dir = mkdtempSync(path.join(tmpdir(), "diff-chunking-split-"));
  try {
    writeFileSync(path.join(dir, "diff.patch"), patch);
    mkdirSync(path.join(dir, "out"));
    const manifest = path.join(dir, "manifest.txt");
    const args = [path.join(dir, "diff.patch"), path.join(dir, "out"), String(maxBytes), String(maxChunks), manifest, String(manifestBytes ?? 15000)];
    const run = spawnSync("python3", ["-I", MODULE, "split", ...args, ...(maxFiles === undefined ? [] : [String(maxFiles)])], { encoding: "utf8" });
    const chunks = Object.fromEntries(readdirSync(path.join(dir, "out")).sort().map((name) => [name, readFileSync(path.join(dir, "out", name), "utf8")]));
    if (manifestBytes !== undefined) {
      return { status: run.status, chunks, stderr: run.stderr, manifest: existsSync(manifest) ? readFileSync(manifest, "utf8") : null };
    }
    return { status: run.status, chunks, stderr: run.stderr };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function parts(chunks, partBytes, partLines, { wrap, fileParts = false } = {}) {
  const data = mkdtempSync(path.join(tmpdir(), "diff-chunking-parts-"));
  try {
    const diff = path.join(data, "diff");
    mkdirSync(diff);
    chunks.forEach((text, i) => writeFileSync(path.join(diff, `chunk-${i + 1}.patch`), text));
    const args = [diff, String(partBytes), String(partLines), ...(fileParts ? ["--file-parts", path.join(data, "file-parts.txt")] : []), ...(wrap === undefined ? [] : ["--wrap", String(wrap)])];
    const run = spawnSync("python3", ["-I", MODULE, "parts", ...args]);
    const files = Object.fromEntries(
      readdirSync(data, { recursive: true })
        .filter((p) => !p.endsWith("diff") && !/chunk-\d+$/.test(p))
        .sort()
        .map((p) => [p, readFileSync(path.join(data, p))]),
    );
    return { status: run.status, stdout: run.stdout.toString(), files };
  } finally {
    rmSync(data, { recursive: true, force: true });
  }
}
const text = (files) => Object.fromEntries(Object.entries(files).map(([name, bytes]) => [name, bytes.toString("utf8")]));

const BIG = "diff --git a/big b/big\n--- a/big\n+++ b/big\n";
const hunkPatch = (n, bytes) => {
  const head = `@@ -${n} +${n} @@\n+`;
  const hunk = `${head}${"y".repeat(bytes - head.length - 1)}\n`;
  assert.equal(Buffer.byteLength(hunk), bytes);
  return hunk;
};

test("an oversize diff splits into chunks under the cap at file boundaries, in order", () => {
  const [a, b, c] = [filePatch("a", 60), filePatch("b", 70), filePatch("c", 50)];
  assert.deepEqual(split(a + b + c, 150, 4), { status: 0, chunks: { "chunk-1.patch": a + b, "chunk-2.patch": c }, stderr: "" });
  assert.deepEqual(split(a + b + c, 180, 4).chunks, { "chunk-1.patch": a + b + c });
});

test("a single file over the cap is cut at its hunks into pieces, each under the file's header", () => {
  const [h1, h2, h3] = [hunkPatch(1, 30), hunkPatch(5, 30), hunkPatch(9, 30)];
  assert.equal(BIG.length, 43);
  const result = split(BIG + h1 + h2 + h3, 110, 4, 15000);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(result.chunks, { "chunk-1.patch": BIG + h1 + h2, "chunk-2.patch": BIG + h3 });
  assert.equal(result.manifest, "chunk 1 piece 1 of 2 modified big\nchunk 2 piece 2 of 2 modified big\n");
  const small = filePatch("s", 40);
  const beside = split(BIG + h1 + h2 + h3 + small, 120, 4, 15000);
  assert.deepEqual(beside.chunks, { "chunk-1.patch": BIG + h1 + h2, "chunk-2.patch": BIG + h3 + small });
  assert.equal(beside.manifest, "chunk 1 piece 1 of 2 modified big\nchunk 2 piece 2 of 2 modified big\nchunk 2 modified s\n");
  const whole = split(BIG + h1 + h2 + h3 + small, 133, 4, 15000);
  assert.deepEqual(whole.chunks, { "chunk-1.patch": BIG + h1 + h2 + h3, "chunk-2.patch": small });
  assert.equal(whole.manifest, "chunk 1 modified big\nchunk 2 modified s\n");
  const over = split(BIG + h1 + h2 + h3, 80, 2);
  assert.equal(over.status, 3);
  assert.deepEqual(over.chunks, {});
  assert.match(over.stderr, /the diff needs 3 chunks, more than 2/);
  assert.deepEqual(split(BIG + h1 + h2 + h3, 80, 3).chunks, { "chunk-1.patch": BIG + h1, "chunk-2.patch": BIG + h2, "chunk-3.patch": BIG + h3 });
  assert.deepEqual(split(BIG + h1 + h2 + h3 + small, 120, 4, undefined, 1).chunks, { "chunk-1.patch": BIG + h1 + h2, "chunk-2.patch": BIG + h3, "chunk-3.patch": small });
});

test("a hunk over the cap with its file's header is too large and writes nothing", () => {
  const hunk = split(BIG + hunkPatch(1, 30) + hunkPatch(5, 80) + filePatch("s", 40), 110, 4);
  assert.equal(hunk.status, 3);
  assert.deepEqual(hunk.chunks, {});
  assert.match(hunk.stderr, /^split-diff: a file has a hunk larger than one chunk of 110 bytes: modified big$/m);
  assert.equal(split(BIG + hunkPatch(1, 80), 110, 4).status, 3);
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
  assert.deepEqual(split(all, 1000, 4).chunks, { "chunk-1.patch": all });
  assert.deepEqual(split(all, 1000, 4, 15000, 0).chunks, { "chunk-1.patch": all });
  assert.deepEqual(split(all, 1000, 4, undefined, 2), { status: 0, chunks: { "chunk-1.patch": a + b, "chunk-2.patch": c + d, "chunk-3.patch": e }, stderr: "" });
  assert.deepEqual(split(all, 100, 4, undefined, 3).chunks, { "chunk-1.patch": a + b, "chunk-2.patch": c + d, "chunk-3.patch": e });
  const over = split(all, 1000, 2, undefined, 2);
  assert.equal(over.status, 3);
  assert.deepEqual(over.chunks, {});
  assert.match(over.stderr, /3 chunks/);
});

test("more chunks than the most is too large and writes nothing", () => {
  const [a, b, c] = [filePatch("a", 100), filePatch("b", 100), filePatch("c", 100)];
  const over = split(a + b + c, 100, 2);
  assert.equal(over.status, 3);
  assert.deepEqual(over.chunks, {});
  assert.match(over.stderr, /3 chunks/);
  assert.deepEqual(split("", 100, 2), { status: 0, chunks: {}, stderr: "" });
});

test("a diff in more than one chunk writes a manifest of every file, its chunk and its status", () => {
  const [first, ...rest] = MIXED.map((p) => Buffer.byteLength(p));
  assert.ok(first <= 600 && first + rest[0] > 600 && rest.reduce((a, b) => a + b) <= 600);
  const two = split(MIXED.join(""), 600, 4, 15000);
  assert.equal(two.status, 0, two.stderr);
  assert.deepEqual(Object.keys(two.chunks), ["chunk-1.patch", "chunk-2.patch"]);
  assert.equal(two.manifest, `${MIXED_MANIFEST.join("\n")}\n`);
  assert.equal(split(MIXED.join(""), 100000, 4, 15000).manifest, null);
  const capped = split(MIXED.join(""), 600, 4, 83);
  assert.ok(Buffer.byteLength(capped.manifest) <= 83);
  assert.equal(capped.manifest, `${MIXED_MANIFEST.slice(0, 2).join("\n")}\nand 4 more files, not listed\n`);
  assert.equal(split(MIXED.join(""), 600, 1, 15000).manifest, null);
});

test("each chunk is cut into parts one read returns whole, in order, and its chunk file goes", () => {
  const run = parts(["aaa\nbbb\nccc\nddd\neee\n", "fff\n"], 10, 2, { wrap: 40 });
  assert.equal(run.status, 0);
  assert.equal(run.stdout, "20,4\n", "each chunk's bytes, comma-separated");
  assert.deepEqual(
    text(run.files),
    {
      "diff/chunk-1/part-001.patch": "aaa\nbbb\n",
      "diff/chunk-1/part-002.patch": "ccc\nddd\n",
      "diff/chunk-1/part-003.patch": "eee\n",
      "diff/chunk-2/part-001.patch": "fff\n",
    },
    "five 4-byte lines at 2 lines a part are 3 parts in order, and no chunk file is left",
  );
  assert.deepEqual(Object.keys(parts(["aaa\nbbb\nccc\n"], 10, 1000).files), ["diff/chunk-1/part-001.patch", "diff/chunk-1/part-002.patch"], "a third 4-byte line passes 10 bytes and starts a part");
  assert.deepEqual(text(parts(["aaa"], 10, 2).files), { "diff/chunk-1/part-001.patch": "aaa\n" }, "a last line with no newline gains one");
  assert.deepEqual(text(parts([""], 10, 2).files), { "diff/chunk-1/part-001.patch": "" }, "an empty chunk is one empty part");
});

test("a line over the wrap continues on marked lines, never cut inside a UTF-8 character, and every byte comes back", () => {
  const long = `+${"x".repeat(50)}${"é€".repeat(20)}\n ${"y".repeat(39)}\n`;
  const run = parts([long], 1000, 100, { wrap: 40 });
  assert.equal(run.status, 0);
  const folded = Buffer.concat(Object.values(run.files));
  const lines = folded.toString("utf8").split("\n").slice(0, -1);
  assert.ok(lines.length > 4);
  for (const line of lines) {
    assert.ok(Buffer.byteLength(line) <= 40, line);
    assert.doesNotThrow(() => new TextDecoder("utf-8", { fatal: true }).decode(Buffer.from(line)));
  }
  assert.ok(lines.slice(1, -1).every((line) => line.startsWith("\\ continued: ")));
  assert.equal(folded.toString("utf8").replaceAll("\n\\ continued: ", ""), long);
  assert.equal(
    text(parts([`+${"z".repeat(40)}\n`], 1000, 100, { wrap: 40 }).files)["diff/chunk-1/part-001.patch"],
    `+${"z".repeat(39)}\n\\ continued: z\n`,
    "41 bytes at a wrap of 40 are the first 40, then the mark and the last byte",
  );
});

test("with no wrap a line folds at LONG_LINE_BYTES, and a wrap no mark fits is refused", () => {
  const at = `+${"x".repeat(LONG_LINE_BYTES - 1)}\n`;
  const over = `+${"y".repeat(LONG_LINE_BYTES)}\n`;
  const run = parts([at + over], 100000, 100);
  assert.equal(run.status, 0);
  assert.equal(text(run.files)["diff/chunk-1/part-001.patch"], `${at}+${"y".repeat(LONG_LINE_BYTES - 1)}\n\\ continued: y\n`);
  assert.notEqual(parts([at], 100000, 100, { wrap: 13 }).status, 0);
});

test("with a file-parts list each file's header names the part it starts in, and a folded header-like line does not", () => {
  const spoof = `+${"x".repeat(39)}diff --git a/evil b/evil\n`;
  const chunk1 = `diff --git a/a b/a\n+1\n${spoof}diff --git a/b b/b\n+2\n`;
  const run = parts([chunk1, "diff --git a/c b/c\n+3\n"], 1000, 3, { wrap: 40, fileParts: true });
  assert.equal(run.status, 0);
  assert.equal(
    run.files["file-parts.txt"].toString(),
    ["diff/chunk-1/part-001.patch", "diff/chunk-1/part-002.patch", "diff/chunk-2/part-001.patch", ""].join("\n"),
  );
  const longHeader = `diff --git a/${"n".repeat(20)} b/${"n".repeat(20)}\n+1\n`;
  const folded = parts([longHeader], 1000, 1, { wrap: 40, fileParts: true });
  assert.equal(Object.keys(folded.files).length, 4, "a header folded over two parts, then its line");
  assert.equal(folded.files["file-parts.txt"].toString(), "diff/chunk-1/part-001.patch\n", "a folded header names only its first part");
});

test("every copy of the fold length is the module's", () => {
  const read = (dir, name) =>
    spawnSync("python3", ["-I", "-c", `import sys; sys.path.insert(0, sys.argv[1]); import ${name}; print(${name}.LONG_LINE_BYTES)`, dir], { encoding: "utf8" });
  const own = read(path.dirname(MODULE), "diff_chunking");
  assert.equal(own.status, 0, own.stderr);
  const gate = read(path.join(ROOT, "plugins/source-control/skills/babysit-prs/scripts"), "diff_risk");
  assert.equal(gate.status, 0, gate.stderr);
  assert.equal(Number(gate.stdout), Number(own.stdout));
  assert.equal(LONG_LINE_BYTES, Number(own.stdout));
});
