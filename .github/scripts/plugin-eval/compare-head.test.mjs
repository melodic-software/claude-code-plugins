import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "compare-head.sh");
const BIN = mkdtempSync(join(tmpdir(), "compare-head-"));
after(() => rmSync(BIN, { recursive: true, force: true }));
writeFileSync(join(BIN, "gh"), '#!/usr/bin/env bash\n[ -n "$STUB_FAIL" ] && exit 1\nprintf "%s\\n" "$STUB_TSV"\n');
chmodSync(join(BIN, "gh"), 0o755);

const HEAD = "a".repeat(40);
const REPO = "melodic-software/claude-code-plugins";
const run = (tsv, extra = {}) =>
  spawnSync("bash", [SCRIPT], {
    encoding: "utf8",
    env: { PATH: `${BIN}:${process.env.PATH}`, GITHUB_REPOSITORY: REPO, PR: "7", HEAD_SHA: HEAD, DEFAULT_BRANCH: "main", STUB_TSV: tsv, ...extra },
  }).status;

test("an open pull request from this repository into the default branch at the dispatched head stands", () => {
  assert.equal(run(`open\t${REPO}\tmain\t${HEAD}`), 0);
});

test("a head that moved, a closed pull request, a fork, another base, or a failed read does not stand", () => {
  assert.equal(run(`open\t${REPO}\tmain\t${"b".repeat(40)}`), 1);
  assert.equal(run(`closed\t${REPO}\tmain\t${HEAD}`), 1);
  assert.equal(run(`open\tsomeone/fork\tmain\t${HEAD}`), 1);
  assert.equal(run(`open\t${REPO}\trelease\t${HEAD}`), 1);
  assert.equal(run("", { STUB_FAIL: "1" }), 1);
  assert.equal(run(`open\t${REPO}\tmain\t${HEAD}`, { HEAD_SHA: "short" }), 1);
});
