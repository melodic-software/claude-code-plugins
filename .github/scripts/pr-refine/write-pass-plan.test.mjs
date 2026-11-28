import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const repoFile = (path) => new URL(`../../../${path}`, import.meta.url);

function copyInto(root, pairs) {
  for (const [from, to] of pairs) {
    mkdirSync(dirname(join(root, to)), { recursive: true });
    copyFileSync(repoFile(from), join(root, to));
  }
}

test("write-pass-plan reads the base config with the standards checkout STANDARDS_DIR names", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "write-pass-plan-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const base = join(dir, "base");
  const standards = join(dir, "standards");
  copyInto(
    base,
    ["docs/conventions/pr-pipeline.yaml", "docs/conventions/pr-pipeline/pr-pipeline.schema.json", ".github/CODEOWNERS", "plugins/multi-agent/reference/defaults.yaml"].map((path) => [path, path]),
  );
  copyInto(standards, [
    [".github/scripts/lib/fixtures/standards/components/github-actions-conventions/vocabulary.json", "components/github-actions-conventions/vocabulary.json"],
    [".github/scripts/lib/fixtures/standards/components/trusted-actors/trusted-actors.json", "components/trusted-actors/trusted-actors.json"],
  ]);
  const paths = join(dir, "paths");
  writeFileSync(paths, "README.md\n");
  const run = (standardsDir) => {
    const output = join(dir, `output-${standardsDir ? "standards" : "base"}`);
    writeFileSync(output, "");
    const result = spawnSync(process.execPath, [fileURLToPath(new URL("./write-pass-plan.mjs", import.meta.url))], {
      env: { BASE_PATH: base, STANDARDS_DIR: standardsDir, PATHS_FILE: paths, GITHUB_OUTPUT: output },
      encoding: "utf8",
    });
    return { ...result, output: readFileSync(output, "utf8") };
  };
  const read = run(standards);
  assert.equal(read.status, 0, read.stderr);
  assert.match(read.output, /^passes=\[.*\]$/m);
  const unread = run("");
  assert.notEqual(unread.status, 0);
  assert.equal(unread.output, "");
});
