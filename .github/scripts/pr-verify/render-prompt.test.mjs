import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { renderChunkNote, renderPrompt, writePrompts } from "./render-prompt.mjs";

const tempDir = (t) => {
  const dir = mkdtempSync(path.join(tmpdir(), "render-prompt-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
};

test("renderPrompt fills every occurrence of every token and ends in one newline", () => {
  const template = "Read SPEC_TEXT_FILE, SPEC_FILE, JOBS_FILE, CONTEXT_FILE and PR_FILE, PR_FILE again:\nDIFF_PARTSCHUNK_NOTE\nend\n\n\n";
  assert.equal(
    renderPrompt({ template, parts: ["/d/diff/chunk-1/part-001.patch", "/d/diff/chunk-1/part-002.patch"], dataDir: "/d" }),
    "Read /d/spec-text.json, /d/spec.json, /d/upstream-jobs.json, /d/context.json and /d/pr.json, /d/pr.json again:\n" +
      "  - `/d/diff/chunk-1/part-001.patch`\n  - `/d/diff/chunk-1/part-002.patch`\nend\n",
  );
});

test("renderPrompt puts the chunk note on its own line, last, so its text is not filled in again", () => {
  assert.equal(renderPrompt({ template: "DIFF_PARTSCHUNK_NOTE PR_FILE", parts: ["/p"], dataDir: "/d", note: "see PR_FILE" }), "  - `/p`\nsee PR_FILE /d/pr.json\n");
});

test("renderPrompt inserts a $ in a value literally", () => {
  assert.equal(renderPrompt({ template: "PR_FILE DIFF_PARTS", parts: ["/$&/p"], dataDir: "/$1" }), "/$1/pr.json   - `/$&/p`\n");
});

test("renderChunkNote names the manifest parts, the data directory and the chunk", () => {
  const template = "chunk CHUNK_INDEX of CHUNK_COUNT, relative to `DATA_DIR`:\n\nMANIFEST_PARTS\n\n";
  assert.equal(
    renderChunkNote({ template, manifestParts: ["/d/manifest/part-001.txt", "/d/manifest/part-002.txt"], dataDir: "/d", index: 2, count: 3 }),
    "chunk 2 of 3, relative to `/d`:\n\n  - `/d/manifest/part-001.txt`\n  - `/d/manifest/part-002.txt`",
  );
});

const REPLACED_BASH_STEP = [
  'template=$(<"$TEMPLATES/prompt.md")',
  'for k in $(seq "$CHUNKS"); do',
  "  prompt=$template",
  "  parts=$(printf '  - `%s`\\n' \"$DATA/diff/chunk-$k\"/part-*.patch)",
  "  prompt=${prompt//DIFF_PARTS/$parts}",
  "  prompt=${prompt//CONTEXT_FILE/$DATA/context.json}",
  "  prompt=${prompt//PR_FILE/$DATA/pr.json}",
  "  prompt=${prompt//SPEC_TEXT_FILE/$DATA/spec-text.json}",
  "  prompt=${prompt//SPEC_FILE/$DATA/spec.json}",
  "  prompt=${prompt//JOBS_FILE/$DATA/upstream-jobs.json}",
  "  note=",
  '  if [ "$CHUNKS" -gt 1 ]; then',
  '    note=$(<"$TEMPLATES/chunk-note.md")',
  "    manifest=$(printf '  - `%s`\\n' \"$DATA\"/manifest/part-*.txt)",
  "    note=${note//MANIFEST_PARTS/$manifest}",
  "    note=${note//DATA_DIR/$DATA}",
  "    note=${note//CHUNK_INDEX/$k}",
  "    note=${note//CHUNK_COUNT/$CHUNKS}",
  "    note=$'\\n'$note",
  "  fi",
  '  prompt=${prompt//CHUNK_NOTE/"$note"}',
  "  printf '%s\\n' \"$prompt\" >\"$PROMPT_STEM-$k.md\"",
  "done",
].join("\n");

for (const chunks of [1, 3, 12]) {
  test(`pin: writePrompts over the real prompt.md and chunk-note.md matches the bash step byte for byte, ${chunks} chunk(s)`, (t) => {
    const dir = tempDir(t);
    const data = path.join(dir, "data");
    for (let k = 1; k <= chunks; k += 1) {
      mkdirSync(path.join(data, `diff/chunk-${k}`), { recursive: true });
      for (let n = 1; n <= (k % 3) + 1; n += 1) writeFileSync(path.join(data, `diff/chunk-${k}/part-00${n}.patch`), "x\n");
    }
    if (chunks > 1) {
      mkdirSync(path.join(data, "manifest"));
      for (const name of ["part-001.txt", "part-002.txt"]) writeFileSync(path.join(data, "manifest", name), "x\n");
    }
    const env = { PATH: process.env.PATH, DATA: data, CHUNKS: String(chunks), TEMPLATES: import.meta.dirname, PROMPT_STEM: path.join(dir, "bash") };
    const bash = spawnSync("bash", ["-euo", "pipefail", "-c", REPLACED_BASH_STEP], { env, encoding: "utf8" });
    assert.equal(bash.status, 0, bash.stderr);
    writePrompts({ dataDir: data, chunks, stem: path.join(dir, "node") });
    for (let k = 1; k <= chunks; k += 1) {
      const rendered = readFileSync(path.join(dir, `node-${k}.md`), "utf8");
      assert.equal(rendered, readFileSync(path.join(dir, `bash-${k}.md`), "utf8"), `chunk ${k} of ${chunks}`);
      assert.doesNotMatch(rendered, /DIFF_PARTS|CHUNK_NOTE|CHUNK_INDEX|CHUNK_COUNT|DATA_DIR|MANIFEST_PARTS|SPEC_FILE|SPEC_TEXT_FILE|PR_FILE|CONTEXT_FILE|JOBS_FILE/);
      assert.equal(rendered.includes(`chunk ${k} of ${chunks}`), chunks > 1, `chunk ${k} of ${chunks} names its place only when chunked`);
    }
  });
}

test("writePrompts fails on a chunk with no parts rather than naming a missing file", (t) => {
  const data = path.join(tempDir(t), "data");
  mkdirSync(path.join(data, "diff/chunk-1"), { recursive: true });
  assert.throws(() => writePrompts({ dataDir: data, chunks: 1, stem: path.join(data, "p") }), /holds no/);
  writeFileSync(path.join(data, "diff/chunk-1/part-001.patch"), "x\n");
  writePrompts({ dataDir: data, chunks: 1, stem: path.join(data, "p") });
  assert.ok(readFileSync(path.join(data, "p-1.md"), "utf8").includes(`  - \`${data}/diff/chunk-1/part-001.patch\`\n`));
});

test("the CLI writes one prompt per chunk and reports a malformed chunk count", (t) => {
  const dir = tempDir(t);
  const data = path.join(dir, "data");
  mkdirSync(path.join(data, "diff/chunk-1"), { recursive: true });
  writeFileSync(path.join(data, "diff/chunk-1/part-001.patch"), "x\n");
  const run = (chunks) => spawnSync(process.execPath, [path.join(import.meta.dirname, "render-prompt.mjs")], { env: { DATA: data, CHUNKS: chunks, PROMPT_STEM: path.join(dir, "prompt") }, encoding: "utf8" });
  assert.equal(run("1").status, 0);
  assert.ok(readFileSync(path.join(dir, "prompt-1.md"), "utf8").includes(`${data}/upstream-jobs.json`));
  const bad = run("0");
  assert.equal(bad.status, 1);
  assert.match(bad.stdout, /^::error::pr-verify could not write the prompts: /);
});
