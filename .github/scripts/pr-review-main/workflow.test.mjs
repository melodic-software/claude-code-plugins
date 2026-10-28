// pr-review-main.yml's hardening, from its header and ADR 0049: it runs only
// from main on workflow_run, its token can only read, it checks out main and
// never the head, the model reads only its data directory, and the verdict is
// uploaded once, after it is written, under the name the writer chose.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/pr-review-main.yml", import.meta.url), "utf8");
const prompt = readFileSync(new URL("./prompt.md", import.meta.url), "utf8");
const steps = text
  .split(/\n(?=      - name: )/)
  .slice(1)
  .map((block) => ({ name: /^      - name: (.*)$/m.exec(block)[1], block }));
const step = (name) => {
  const found = steps.find((s) => s.name === name);
  assert.ok(found, `a step named ${name}`);
  return found.block;
};
const index = (name) => steps.findIndex((s) => s.name === name);

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

const jobText = (id) => {
  const found = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(text);
  assert.ok(found, `a job ${id}`);
  return found[1];
};
const grantsOf = (block) =>
  [...block.matchAll(/^ {6}([a-z-]+): (\w+)(?: #.*)?$/gm)].filter(([, scope]) =>
    ["contents", "pull-requests", "actions", "checks", "issues", "statuses", "id-token"].includes(scope),
  );

test("the model's job can only read, and the one writer runs no model", () => {
  assert.match(text, /^permissions: \{\}$/m);
  const review = grantsOf(jobText("review"));
  assert.ok(review.length > 0);
  for (const [line, , level] of review) assert.equal(level, "read", line);
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
  assert.match(diff, /git -C "\$SRC" diff --text --no-ext-diff --no-textconv/);
  assert.match(diff, /\^\(Binary files \.\* differ\|GIT binary patch\)\$/);
  assert.match(diff, /-gt "\$MAX_DIFF_BYTES"/);
  assert.match(diff, /MAX_DIFF_BYTES: "\d+"/);
});

test("each leg leaves a lane record", () => {
  const report = step("Report the review's outcome");
  assert.match(report, /report-lane-outcome@[0-9a-f]{40}/);
  assert.match(report, /^ {10}lane: pr-review-main$/m);
  assert.ok(index("Review the pull request") < index("Report the review's outcome"));
  assert.match(step("Review the pull request"), /^ {8}continue-on-error: true$/m);
});

test("it checks out main only, and runs local actions from that checkout", () => {
  const checkouts = steps.filter((s) => /uses: actions\/checkout@/.test(s.block));
  assert.equal(checkouts.length, 1);
  assert.match(checkouts[0].block, /^ {10}ref: refs\/heads\/main$/m);
  assert.match(checkouts[0].block, /^ {10}persist-credentials: false$/m);
  for (const [, local] of text.matchAll(/^\s+uses: (\.\/\S+)/gm)) {
    assert.ok(local.startsWith("./.base/.github/actions/"), local);
  }
  for (const [, remote] of text.matchAll(/^\s+uses: ([^.\s]\S*)/gm)) {
    assert.match(remote, /@[0-9a-f]{40}$/, remote);
  }
});

test("the model reads its data directory alone", () => {
  const review = step("Review the pull request");
  assert.match(review, /^ {10}tools: Read$/m);
  assert.match(review, /^ {10}allowed-tools: Read\(\.\/pr-review-main-data\/\*\*\)$/m);
  assert.match(review, /^ {10}permission-mode: dontAsk$/m);
  for (const denied of ["Read(./.base/**)", "Bash", "Write", "Edit", "WebFetch", "Agent", "mcp__*"]) {
    assert.ok(review.includes(`            ${denied}\n`), denied);
  }
  for (const placeholder of ["LANE_NAME", "CRITERIA_DIR", "STANDARDS_DIR", "DIFF_FILE", "CONTEXT_FILE", "PR_FILE"]) {
    assert.ok(prompt.includes(placeholder), placeholder);
    assert.ok(step("Write the prompt and schema").includes(`prompt=\${prompt//${placeholder}/`), placeholder);
  }
});

test("the verdict uploads once, after it is written, under the writer's name", () => {
  const uploads = steps.filter((s) => /uses: actions\/upload-artifact@/.test(s.block));
  assert.equal(uploads.length, 1);
  assert.equal(uploads[0].name, "Upload the verdict");
  assert.ok(index("Write the verdict") < index("Upload the verdict"));
  assert.match(uploads[0].block, /^ {8}if: steps\.verdict\.outcome == 'success'$/m);
  assert.match(uploads[0].block, /^ {10}name: \$\{\{ steps\.verdict\.outputs\.name \}\}$/m);
  // The tree is git's, the head and base the trigger gate's: never the model's.
  const write = step("Write the verdict");
  assert.match(write, /TREE_SHA: \$\{\{ steps\.diff\.outputs\.tree \}\}/);
  assert.match(write, /HEAD_SHA: \$\{\{ steps\.gate\.outputs\.head-sha \}\}/);
  assert.match(step("Write the diff"), /rev-parse --verify "\$HEAD_SHA\^\{tree\}"/);
});

test("only a lane-source pull request is reviewed, by the gate's own predicate", () => {
  const select = step("Select a lane-source pull request");
  assert.match(select, /import babysit_review_evidence as ev/);
  assert.match(select, /ev\.lane_source\(p\)/);
  assert.match(step("Write the diff"), /^ {8}if: steps\.select\.outputs\.review == 'true'$/m);
});
