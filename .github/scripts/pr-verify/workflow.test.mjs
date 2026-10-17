// pr-verify.yml's ordering rules, from the review round on #7702: GitHub
// cancels an older pending run in the same concurrency group, so a cancelled
// run must leave no verdict. The upload is therefore the job's only artifact
// step, it runs after the verdict file is written, and only when writing it
// succeeded; the group is per PR and head, never cancelling a running judgment.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/pr-verify.yml", import.meta.url), "utf8");
// Each step starts at a `      - name:` line of the one job.
const steps = text
  .split(/\n(?=      - name: )/)
  .slice(1)
  .map((block) => ({ name: /^      - name: (.*)$/m.exec(block)[1], block }));
const index = (name) => steps.findIndex((step) => step.name === name);

test("the upload is the only artifact step and follows the written verdict", () => {
  const uploads = steps.filter((step) => /uses: actions\/upload-artifact@/.test(step.block));
  assert.deepEqual(
    uploads.map((step) => step.name),
    ["Upload the verdict"],
  );
  assert.ok(index("Judge the pull request") >= 0 && index("Write the verdict") > index("Judge the pull request"));
  assert.ok(index("Upload the verdict") > index("Write the verdict"));
  assert.match(uploads[0].block, /if: steps\.verdict\.outcome == 'success'/);
  assert.doesNotMatch(text, /actions\/upload-artifact\/merge|gh api .*artifacts.* -X (POST|PUT)/);
});

test("the concurrency group is per PR and head and never cancels a running judgment", () => {
  const group = /^concurrency:\n  group: (.*)\n  cancel-in-progress: (.*)$/m.exec(text);
  assert.ok(group, "a top-level concurrency block");
  assert.match(group[1], /workflow_run\.pull_requests\[0\]\.number/);
  assert.match(group[1], /workflow_run\.head_sha/);
  assert.equal(group[2], "false");
});
