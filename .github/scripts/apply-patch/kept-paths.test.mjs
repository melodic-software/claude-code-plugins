import assert from "node:assert/strict";
import { test } from "node:test";

import { KEPT_MARKER, KEPT_PATCH_FILE, keptArtifactName, keptComment, keptPaths } from "./kept-paths.mjs";

const PATCH = [
  "diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml",
  "index 1..2 100644",
  "--- a/.github/workflows/ci.yml",
  "+++ b/.github/workflows/ci.yml",
  "@@ -1 +1 @@",
  "-on: push",
  "+on: pull_request",
  "diff --git a/bin.dat b/bin.dat",
  "new file mode 100644",
  "index 0..3",
  "GIT binary patch",
  "literal 3",
  "KcmZQzWB>pF00961",
  "",
  "literal 0",
  "HcmV?d00001",
  "",
  "diff --git a/settings.json b/settings.json",
  "new file mode 100644",
  "--- /dev/null",
  "+++ b/settings.json",
  "@@ -0,0 +1 @@",
  "+{}",
  "",
].join("\n");

const args = { patch: PATCH, sha256: "a".repeat(64), headSha: "b".repeat(40), runId: "123", runUrl: "https://github.com/o/r/actions/runs/123", paths: keptPaths(PATCH) };

test("the hand-off names are fixed for the job that applies the kept part", () => {
  assert.equal(KEPT_MARKER, "<!-- lane-kept-paths -->");
  assert.equal(KEPT_PATCH_FILE, "kept.diff");
  assert.equal(keptArtifactName({ lane: "pr-unblock", activity: "apply-ci-patch", attempt: "2" }), "kept-paths-pr-unblock-apply-ci-patch-2");
});

test("keptPaths lists each path a diff changes once", () => {
  assert.deepEqual(keptPaths(PATCH), [".github/workflows/ci.yml", "bin.dat", "settings.json"]);
});

test("the comment opens with the marker and names the head, the SHA-256 and the run, then the diff fenced", () => {
  const body = keptComment(args);
  assert.ok(body.startsWith(`${KEPT_MARKER}\n`));
  assert.match(body, /Pending an automated apply/);
  assert.match(body, new RegExp(`head: \`${"b".repeat(40)}\``));
  assert.match(body, new RegExp(`SHA-256: \`${"a".repeat(64)}\``));
  assert.match(body, /\[123\]\(https:\/\/github\.com\/o\/r\/actions\/runs\/123\)/);
  assert.match(body, /```diff\n-on: push|```diff\ndiff --git a\/\.github/);
  assert.match(body, /\+on: pull_request/);
  assert.match(body, /\(binary, not shown\)/);
  assert.doesNotMatch(body, /KcmZQz/);
  assert.match(body, /\+\{\}/, "the hunk after a binary one is shown");
});

test("a diff holding a backtick fence gets a longer fence", () => {
  const body = keptComment({ ...args, patch: "diff --git a/x.md b/x.md\n+```\n+````\n" });
  assert.match(body, /`````diff\n/);
});

test("a diff too large for one comment is cut to fit", () => {
  const body = keptComment({ ...args, patch: `diff --git a/x b/x\n${"+x\n".repeat(40000)}` });
  assert.ok(body.length <= 65536, String(body.length));
  assert.match(body, /cut to fit one comment/);
});
