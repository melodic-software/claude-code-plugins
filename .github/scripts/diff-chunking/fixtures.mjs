import assert from "node:assert/strict";

export const filePatch = (name, bytes) => {
  const head = `diff --git a/${name} b/${name}\n@@ -1 +1 @@\n+`;
  const patch = `${head}${"x".repeat(bytes - head.length - 1)}\n`;
  assert.equal(Buffer.byteLength(patch), bytes);
  return patch;
};

export const MIXED = [
  `diff --git a/src/a.sh b/src/a.sh\nindex 1111111..2222222 100644\n--- a/src/a.sh\n+++ b/src/a.sh\n@@ -1 +1 @@\n-x\n+source lib/b.sh ${"p".repeat(400)}\n`,
  "diff --git a/lib/b & c.sh b/lib/b & c.sh\nnew file mode 100644\nindex 0000000..3333333\n--- /dev/null\n+++ b/lib/b & c.sh\t\n@@ -0,0 +1 @@\n+echo\n",
  "diff --git a/old.txt b/old.txt\ndeleted file mode 100644\nindex e69de29..0000000\n",
  "diff --git a/run.sh b/run.sh\nold mode 100644\nnew mode 100755\n",
  "diff --git a/docs/x.md b/guide/x.md\nsimilarity index 100%\nrename from docs/x.md\nrename to guide/x.md\n",
  'diff --git "a/r\\303\\251sum\\303\\251.md" "b/r\\303\\251sum\\303\\251.md"\nnew file mode 100644\nindex 0000000..4444444\n--- /dev/null\n+++ "b/r\\303\\251sum\\303\\251.md"\n@@ -0,0 +1 @@\n+hi\n',
];
export const MIXED_MANIFEST = [
  "chunk 1 modified src/a.sh",
  "chunk 2 added lib/b & c.sh",
  "chunk 2 deleted old.txt",
  "chunk 2 modified run.sh",
  "chunk 2 renamed docs/x.md -> guide/x.md",
  'chunk 2 added "r\\303\\251sum\\303\\251.md"',
];
