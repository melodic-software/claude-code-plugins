// pr-verify.yml's ordering rules, from its concurrency comment and the
// README's "Verifier verdict" section: GitHub cancels an older pending run in the same concurrency group, so a cancelled
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

test("pr-merge.yml gives the gate an Actions token for the verdict reads only", () => {
  // babysit_verify_evidence.py reads BABYSIT_VERIFY_GH_TOKEN; the lane token
  // the gate runs gh with holds no Actions permission.
  const merge = readFileSync(new URL("../../workflows/pr-merge.yml", import.meta.url), "utf8");
  const job = /\n  merge:\n([\s\S]*?)\n  [a-z-]+:\n/.exec(merge)[1];
  assert.match(job, /\n {6}actions: read\n/);
  const gate = /- name: Run the merge gate on each candidate\n([\s\S]*?)\n {6}- name: /.exec(job)[1];
  assert.match(gate, /\n {10}GH_TOKEN: \$\{\{ steps\.lane-token\.outputs\.token \}\}\n/);
  assert.match(gate, /\n {10}BABYSIT_VERIFY_GH_TOKEN: \$\{\{ github\.token \}\}\n/);
});

test("the concurrency group is per PR and head and never cancels a running judgment", () => {
  const group = /^concurrency:\n  group: (.*)\n  cancel-in-progress: (.*)$/m.exec(text);
  assert.ok(group, "a top-level concurrency block");
  assert.match(group[1], /workflow_run\.pull_requests\[0\]\.number/);
  assert.match(group[1], /workflow_run\.head_sha/);
  assert.equal(group[2], "false");
});

// The judgment on ci-workflows' run-claude-cli (docs/conventions/pr-pipeline/README.md,
// Funding: pr-verify takes the automations role), under the launcher's input
// contract (its action.yml: managed settings while sudo works, then runner
// isolation) and the deny rules that keep the model on its data files.
const step = (name) => {
  const found = steps.find((s) => s.name === name);
  assert.ok(found, `a step named ${name}`);
  return found.block;
};
const input = (block, key) => new RegExp(`^ {10}${key}: (.*)$`, "m").exec(block)?.[1];
const list = (block, key) => {
  const body = new RegExp(`^ {10}${key}: \\|\\n((?: {12}.*\\n?)+)`, "m").exec(block)?.[1] ?? "";
  return body.split("\n").map((line) => line.trim()).filter(Boolean);
};
const PIN = /^melodic-software\/ci-workflows\/\.github\/actions\/([a-z-]+)@[0-9a-f]{40} # v\d+\.\d+\.\d+$/;

test("the judge runs on run-claude-cli as the automations role with both of its secrets", () => {
  const judge = step("Judge the pull request");
  assert.equal(PIN.exec(/^ {8}uses: (.*)$/m.exec(judge)[1])?.[1], "run-claude-cli");
  assert.doesNotMatch(text, /anthropics\/claude-code-action/);
  assert.equal(input(judge, "lane"), "pr-verify");
  assert.equal(input(judge, "role"), "automations");
  assert.equal(input(judge, "api-key"), "${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}");
  assert.equal(input(judge, "subscription-token"), "${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN }}");
  for (const key of ["model", "effort", "max-turns"]) {
    assert.equal(input(judge, key), `\${{ steps.models.outputs.${key} }}`, key);
  }
  assert.equal(input(judge, "permission-mode"), "dontAsk");
  assert.equal(input(judge, "leg-timeout-minutes"), '"10"');
  assert.match(judge, /^ {8}continue-on-error: true$/m);
  assert.match(judge, /^ {8}timeout-minutes: 22$/m);
  assert.match(judge, /^ {10}CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: "1"$/m);
  assert.match(input(judge, "prompt-file"), /^\$\{\{ runner\.temp \}\}\//);
  assert.match(input(judge, "json-schema-file"), /^\$\{\{ runner\.temp \}\}\//);
});

test("the model reads only the data directory, with Read alone, and is told nothing is posted", () => {
  const judge = step("Judge the pull request");
  assert.equal(input(judge, "tools"), "Read");
  assert.equal(input(judge, "allowed-tools"), "Read(./pr-verify-data/**)");
  const denied = list(judge, "disallowed-tools");
  for (const rule of ["Read(./.base/**)", "Glob", "Grep", "Bash", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch", "Agent", "mcp__*"]) {
    assert.ok(denied.includes(rule), `disallowed-tools holds ${rule}`);
  }
  const preamble = /^ {10}preamble: >-\n((?: {12}.*\n)+)/m.exec(judge)?.[1].replace(/\s+/g, " ").trim();
  assert.match(preamble ?? "", /unattended/);
  assert.match(preamble ?? "", /nothing you write is posted/);
});

test("every data path the model reads sits under the working directory", () => {
  assert.doesNotMatch(text, /runner\.temp \}\}\/pr-verify-data/);
  for (const name of ["Resolve the pull request", "Select the trusted PR text", "Write the diff", "Write the prompt and schema", "Write the verdict"]) {
    assert.match(step(name), /\$\{\{ github\.workspace \}\}\/pr-verify-data/, name);
  }
});

test("the managed settings are written while sudo works, before the runner is isolated", () => {
  const settings = step("Apply the Claude managed settings");
  assert.equal(PIN.exec(/^ {8}uses: (.*)$/m.exec(settings)[1])?.[1], "apply-claude-managed-settings");
  assert.match(settings, /^ {8}if: steps\.agree\.outcome == 'success'$/m);
  assert.ok(index("Apply the Claude managed settings") < index("Isolate the runner"));
  assert.ok(index("Isolate the runner") < index("Judge the pull request"));
});

test("the outcome is reported whenever the judge ran, and a missing verdict fails the job last", () => {
  const report = step("Report the judgment's outcome");
  assert.equal(PIN.exec(/^ {8}uses: (.*)$/m.exec(report)[1])?.[1], "report-lane-outcome");
  assert.ok(index("Report the judgment's outcome") === index("Judge the pull request") + 1);
  assert.match(report, /^ {8}if: steps\.judge\.outcome == 'success' \|\| steps\.judge\.outcome == 'failure'$/m);
  assert.equal(input(report, "credential"), "${{ steps.judge.outputs.credential }}");
  assert.equal(input(report, "known-failure-class"), "${{ steps.judge.outputs.lane-class }}");
  assert.equal(input(report, "step-timeout-minutes"), "22");
  // The start time is taken right before the judge, so a timeout is told from other failures.
  assert.equal(input(report, "step-started-at"), "${{ steps.prompt.outputs.started-at }}");
  assert.ok(index("Write the prompt and schema") === index("Judge the pull request") - 1);
  assert.match(step("Write the verdict"), /^ {10}EXECUTION_FILE: \$\{\{ steps\.judge\.outputs\.execution-file \}\}$/m);
  assert.match(step("Write the verdict"), /^ {10}LOG_FILE: \$\{\{ steps\.judge\.outputs\.log-file \}\}$/m);

  const last = steps.at(-1);
  assert.equal(last.name, "Fail without a verdict");
  assert.match(last.block, /^ {8}if: always\(\) && steps\.agree\.outcome == 'success' && steps\.verdict\.outcome != 'success'$/m);
  assert.match(last.block, /exit 1/);
});
