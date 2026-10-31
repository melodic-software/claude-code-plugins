// chunk-diff.sh, run as the "Write the diff" step runs it, on fixture patches:
// a diff over one verifier's read budget becomes chunks of whole files, each
// cut into parts one Read returns whole, and a diff no slot can hold leaves no
// chunk and names why.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, test } from "node:test";

const SCRIPT = new URL("./chunk-diff.sh", import.meta.url).pathname;
const dirs = [];
after(() => dirs.forEach((dir) => rmSync(dir, { recursive: true, force: true })));

const file = (name, lines, line = "+x") =>
  `diff --git a/${name} b/${name}\n--- a/${name}\n+++ b/${name}\n@@ -0,0 +1,${lines} @@\n${`${line}\n`.repeat(lines)}`;

function run(patch, limits = {}) {
  const data = mkdtempSync(path.join(tmpdir(), "pr-verify-chunks-"));
  dirs.push(data);
  writeFileSync(path.join(data, "diff.patch"), patch);
  const output = path.join(data, "output");
  const result = spawnSync("bash", [SCRIPT], {
    encoding: "utf8",
    env: {
      PATH: process.env.PATH,
      DATA: data,
      PR_NUMBER: "41",
      GITHUB_OUTPUT: output,
      MAX_DIFF_BYTES: "300",
      MAX_CHUNKS: "4",
      PART_BYTES: "120",
      PART_LINES: "1000",
      ...limits,
    },
  });
  return { ...result, data, outputs: existsSync(output) ? readFileSync(output, "utf8") : "" };
}

const manifestFiles = (data) => readdirSync(path.join(data, "manifest")).sort().map((name) => path.join(data, "manifest", name));
const manifestOf = (data) => manifestFiles(data).map((name) => readFileSync(name, "utf8")).join("");
const partsOf = (data, k) =>
  readdirSync(path.join(data, "diff", `chunk-${k}`)).sort().map((name) => readFileSync(path.join(data, "diff", `chunk-${k}`, name), "utf8"));

test("a diff over the budget splits across files into chunks of whole files", () => {
  const patch = file("a.mjs", 60) + file("b.mjs", 60) + file("c.md", 60);
  const { status, data, outputs, stdout } = run(patch, { PART_BYTES: "400" });
  assert.equal(status, 0);
  assert.equal(outputs, "chunks=3\n");
  assert.match(stdout, /::notice title=pr-verify chunks::pr=41 chunks=3 bytes=\d+,\d+,\d+ manifest_paths=3/);
  assert.equal([1, 2, 3].map((k) => partsOf(data, k).join("")).join(""), patch);
  assert.ok(partsOf(data, 1).join("").startsWith("diff --git a/a.mjs"));
  assert.ok(!partsOf(data, 1).join("").includes("b.mjs"));
  assert.ok(partsOf(data, 1).every((part) => Buffer.byteLength(part) <= 400));
  assert.match(manifestOf(data), /^chunk 1 diff\/chunk-1\/part-001\.patch modified a\.mjs\nchunk 2 diff\/chunk-2\/part-001\.patch modified b\.mjs\nchunk 3 diff\/chunk-3\/part-001\.patch modified c\.md\n$/);
  assert.equal(existsSync(path.join(data, "diff.patch")), false, "the model reads only the parts");
});

test("a diff under the budget is one chunk with no manifest", () => {
  const patch = file("a.mjs", 10);
  const { status, data, outputs } = run(patch);
  assert.equal(status, 0);
  assert.equal(outputs, "chunks=1\n");
  assert.equal(partsOf(data, 1).join(""), patch);
  assert.equal(existsSync(path.join(data, "manifest")), false);
  assert.equal(existsSync(path.join(data, "manifest.txt")), false);
});

test("an empty diff is one chunk with one empty part, so the verifier still judges it", () => {
  const { status, data, outputs } = run("");
  assert.equal(status, 0);
  assert.equal(outputs, "chunks=1\n");
  assert.deepEqual(partsOf(data, 1), [""]);
});

test("a line longer than a part stays whole in its own part, for the verifier to judge", () => {
  const patch = file("a.min.js", 1, `+${"x".repeat(200)}`);
  const { status, data } = run(patch);
  assert.equal(status, 0);
  assert.equal(partsOf(data, 1).join(""), patch);
});

test("a single file over the budget is named, and leaves no chunk and no output", () => {
  const { status, data, outputs, stdout } = run(file("small.mjs", 5) + file("huge.lock", 400) + file("big.json", 400));
  assert.equal(status, 1);
  assert.equal(outputs, "");
  assert.match(stdout, /^::error::.*huge\.lock.*big\.json/m);
  assert.doesNotMatch(stdout, /small\.mjs/);
  assert.deepEqual(readdirSync(path.join(data, "diff")), []);
});

test("a diff that needs more chunks than the job has slots stops and says so", () => {
  const { status, outputs, stdout } = run(file("a", 80) + file("b", 80) + file("c", 80), { MAX_CHUNKS: "2" });
  assert.equal(status, 1);
  assert.equal(outputs, "");
  assert.match(stdout, /^::error::.*needs 3 chunks, more than 2/m);
});

test("the manifest names every file's part, in files of one Read each", () => {
  const names = Array.from({ length: 200 }, (_, i) => `src/module-${i}.mjs`);
  const { status, data, stdout } = run(names.map((name) => file(name, 1)).join(""), { MAX_DIFF_BYTES: "8000", PART_BYTES: "1000" });
  assert.equal(status, 0);
  assert.match(stdout, /manifest_paths=200\b/);
  assert.ok(manifestFiles(data).length > 1);
  for (const name of manifestFiles(data)) assert.ok(Buffer.byteLength(readFileSync(name)) <= 1000, name);
  const lines = manifestOf(data).trim().split("\n");
  assert.equal(lines.length, 200);
  lines.forEach((line, i) => {
    const [, k, part, name] = /^chunk (\d) (\S+) modified (\S+)$/.exec(line);
    assert.equal(name, names[i]);
    assert.ok(part.startsWith(`diff/chunk-${k}/part-`), line);
    assert.ok(readFileSync(path.join(data, part), "utf8").includes(`diff --git a/${name} `), line);
  });
  assert.doesNotMatch(manifestOf(data), /not listed/);
  assert.equal(existsSync(path.join(data, "manifest.txt")), false);
  assert.equal(existsSync(path.join(data, "file-parts.txt")), false);
});
