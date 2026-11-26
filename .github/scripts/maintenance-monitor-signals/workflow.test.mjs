import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/maintenance-monitor-signals.yml", import.meta.url), "utf8");

test("only an hourly schedule or a manual run with no inputs starts it", () => {
  const on = /\non:\n((?: {2}.*\n| {4}.*\n)+)/.exec(text)[1];
  assert.deepEqual(
    [...on.matchAll(/^ {2}([a-z_]+):/gm)].map((m) => m[1]),
    ["schedule", "workflow_dispatch"],
  );
  assert.doesNotMatch(on, /inputs:/);
  assert.deepEqual(
    [...text.matchAll(/\n {4}- cron: "([^"]+)"/g)].map((m) => m[1]),
    ["52 * * * *"],
  );
  assert.match(text, /\n {4}if: github\.ref == 'refs\/heads\/main'\n/);
});

test("the token writes issues and nothing else, and no job can mint a token", () => {
  assert.match(text, /\npermissions: \{\}\n/);
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(text)[1];
  assert.deepEqual(Object.fromEntries([...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => [m[1], m[2]])), {
    actions: "read",
    checks: "read",
    contents: "read",
    issues: "write",
    "pull-requests": "read",
  });
  assert.match(text, /\n {10}GITHUB_TOKEN: \$\{\{ github\.token \}\}\n/);
  assert.doesNotMatch(text, /id-token|request-lane-token|secrets\.|claude-code-action/);
});

test("two runs never overlap, so two cannot both file one key", () => {
  assert.match(text, /\nconcurrency:\n {2}group: maintenance-monitor-signals\n {2}cancel-in-progress: false\n/);
});

test("the kill switch is checked before the script reads anything", () => {
  const kill = text.indexOf("check-kill-switch");
  const work = text.indexOf("node .base/.github/scripts/maintenance-monitor-signals/monitor.mjs");
  assert.ok(kill > 0 && work > kill);
  assert.match(text, /\n {8}if: steps\.kill\.outputs\.proceed == 'true'\n {8}env:\n {10}GITHUB_TOKEN/);
});

test("every action ref follows the pin rule", () => {
  for (const [, ref] of text.matchAll(/uses: ([^\s]+)/g)) {
    if (ref.startsWith("./")) continue;
    assert.match(ref, /^(?:melodic-software\/\S+@main|(?:actions|github|dependabot|microsoft|azure|Azure|anthropics|openai)\/\S+@v\d+(?:\.\d+){0,2}|(?!(?:melodic-software|actions|github|dependabot|microsoft|azure|Azure|anthropics|openai)\/)\S+@[0-9a-f]{40})$/, ref);
  }
});
