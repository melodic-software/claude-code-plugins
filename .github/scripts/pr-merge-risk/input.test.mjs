import assert from "node:assert/strict";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { changedFiles, factsOf, issueText, main } from "./input.mjs";

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const REPO = "example-org/example-repo";

test("changedFiles lists each diffed path once, renames by their new path", () => {
  const diff = ["diff --git a/x.js b/x.js", "--- a/x.js", "+++ b/x.js", "diff --git a/old.md b/new.md", "rename from old.md", "diff --git a/x.js b/x.js"].join("\n");
  assert.deepEqual(changedFiles(diff), ["x.js", "new.md"]);
});

test("factsOf takes the trusted title and body, never the raw ones", () => {
  const context = { pr: { number: 7, title: "feat: x", body: "Closes #3" } };
  const facts = factsOf({ context, repository: REPO, pr: 7, head: HEAD, base: BASE, files: ["x.js"] });
  assert.deepEqual(facts, {
    number: 7,
    url: `https://github.com/${REPO}/pull/7`,
    title: "feat: x",
    body: "Closes #3",
    headRefOid: HEAD,
    baseRefOid: BASE,
    files: [{ path: "x.js" }],
  });
  assert.equal(factsOf({ context: { pr: { title: "", body: null } }, repository: REPO, pr: 7, head: HEAD, base: BASE, files: [] }).body, "");
});

test("issueText writes each closing issue, and says so when none was read", () => {
  assert.match(issueText([]), /No closing issue was read/);
  const text = issueText([{ number: 3, spec_kind: "closes", body: "the spec", comments: ["a refinement"] }]);
  assert.match(text, /^## Issue #3 \(closes\)\n\nthe spec\n/);
  assert.match(text, /### Comment 1\n\na refinement/);
  assert.match(issueText([{ number: 3, spec_kind: "refs", body: null, comments: [] }]), /no trusted body/);
});

function fileDiffOfExactly(i, bytes) {
  const head = `diff --git a/f${i}.txt b/f${i}.txt\n--- a/f${i}.txt\n+++ b/f${i}.txt\n@@ -0,0 +1,1 @@\n`;
  const body = bytes - head.length;
  const lines = Array.from({ length: Math.floor(body / 100) }, () => `+${"x".repeat(98)}\n`);
  const rest = body % 100;
  if (rest > 0) lines.push(`+${"y".repeat(rest - 2)}\n`);
  return head + lines.join("");
}

function setup(diff, extra = {}) {
  const dir = tempDir("merge-risk-input-");
  const write = (name, value) => {
    const file = join(dir, name);
    writeFileSync(file, typeof value === "string" ? value : JSON.stringify(value));
    return file;
  };
  const env = {
    DATA: join(dir, "data"),
    DIFF_FILE: write("diff.patch", diff),
    CONTEXT_FILE: write("context.json", { pr: { title: "t", body: "b" } }),
    SPEC_TEXT_FILE: write("spec-text.json", []),
    COVERAGE_FILE: join(dir, "reads", "coverage.json"),
    GITHUB_OUTPUT: write("output.txt", ""),
    GITHUB_REPOSITORY: REPO,
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    BASE_SHA: BASE,
    CHUNK_BYTES: "300000",
    MAX_CHUNKS: "50",
    PART_BYTES: "15000",
    PART_LINES: "1000",
    ...extra,
  };
  const read = (name) => readFileSync(join(env.DATA, name), "utf8");
  return { dir, env, read, coverage: () => JSON.parse(readFileSync(env.COVERAGE_FILE, "utf8")), output: () => readFileSync(env.GITHUB_OUTPUT, "utf8") };
}

test("main writes facts.json, issue.md and one chunk's parts for a small diff, and refuses a malformed head", () => {
  const { env, read, coverage } = setup("diff --git a/x.js b/x.js\n+1\n");
  assert.equal(main(env), 0);
  assert.equal(JSON.parse(read("facts.json")).headRefOid, HEAD);
  assert.match(read("issue.md"), /No closing issue/);
  assert.deepEqual(JSON.parse(read("chunks.json")), { chunks: [{ chunk: 1, parts: ["diff/chunk-1/part-001.patch"] }], left_out: { chunks: 0, bytes: 0, files: 0 } });
  assert.equal(read("diff/chunk-1/part-001.patch"), "diff --git a/x.js b/x.js\n+1\n");
  assert.deepEqual(coverage().parts, [{ path: join(env.DATA, "diff/chunk-1/part-001.patch"), lines: 2 }]);
  assert.equal(main({ ...env, DATA: join(env.DATA, "..", "d3"), HEAD_SHA: "nope" }), 1);
  assert.equal(existsSync(join(env.DATA, "..", "d3", "facts.json")), false);
});

test("a diff over the old 600,000-byte cap is rated: 70 files of 10,000 bytes cut into chunks of 30, 30 and 10 files, every byte in a part", () => {
  const diff = Array.from({ length: 70 }, (_, i) => fileDiffOfExactly(i, 10_000)).join("");
  assert.equal(diff.length, 700_000);
  const { env, read, coverage, output } = setup(diff);
  assert.equal(main(env), 0);
  const { chunks, left_out: leftOut } = JSON.parse(read("chunks.json"));
  assert.deepEqual(
    chunks.map(({ chunk }) => chunk),
    [1, 2, 3],
  );
  assert.deepEqual(
    chunks.map(({ parts }) => parts.map(read).join("").match(/^diff --git /gm).length),
    [30, 30, 10],
  );
  assert.deepEqual(leftOut, { chunks: 0, bytes: 0, files: 0 });
  assert.equal(chunks.flatMap(({ parts }) => parts.map(read)).join(""), diff, "the parts, in order, are the diff");
  for (const part of coverage().parts) {
    assert.ok(part.lines <= 1000 && Buffer.byteLength(readFileSync(part.path)) <= 15_000, part.path);
  }
  assert.equal(coverage().parts.length, chunks.flatMap(({ parts }) => parts).length);
  assert.equal(JSON.parse(read("facts.json")).files.length, 70);
  assert.match(output(), /^agents=20\n$/);
});

test("chunks past MAX_CHUNKS are left out and counted, and the agents output covers a rater and a checker per chunk", () => {
  const diff = Array.from({ length: 12 }, (_, i) => fileDiffOfExactly(i, 1000)).join("");
  const capped = setup(diff, { CHUNK_BYTES: "1000", MAX_CHUNKS: "10" });
  assert.equal(main(capped.env), 0);
  const listed = JSON.parse(capped.read("chunks.json"));
  assert.equal(listed.chunks.length, 10);
  assert.deepEqual(listed.left_out, { chunks: 2, bytes: 2000, files: 2 });
  assert.deepEqual(capped.coverage().left_out, { chunks: 2, bytes: 2000, files: 2 });
  assert.equal(existsSync(join(capped.env.DATA, "diff", "chunk-11")), false);
  assert.match(capped.output(), /^agents=20\n$/);
  const all = setup(diff, { CHUNK_BYTES: "1000", MAX_CHUNKS: "50" });
  assert.equal(main(all.env), 0);
  assert.equal(JSON.parse(all.read("chunks.json")).chunks.length, 12);
  assert.match(all.output(), /^agents=24\n$/);
});

test("main refuses a cut it cannot make, writing no facts", () => {
  const { env } = setup("diff --git a/x.js b/x.js\n+1\n", { CHUNK_BYTES: "0" });
  assert.equal(main(env), 1);
  assert.equal(existsSync(join(env.DATA, "facts.json")), false);
  const line = setup(`diff --git a/m.js b/m.js\n--- a/m.js\n+++ b/m.js\n@@ -0,0 +1,1 @@\n+${"z".repeat(2000)}\n`, { CHUNK_BYTES: "500" });
  assert.equal(main(line.env), 1, "one line over a chunk with its headers is too large to cut");
});
