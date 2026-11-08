// maintenance-monitor-signals.yml's hardening, from docs/conventions/pr-pipeline/README.md
// ("Every lane" and "The monitoring lane"): only a schedule or a manual run
// starts it, on main; the monitor job holds only the job's own token, writes
// only issues and runs no model; only the file-incidents job can mint, and it
// makes no other write; and the kill switch is checked before anything reads.
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

const job = (name) => new RegExp(`\\n {2}${name}:\\n([\\s\\S]*?)(?=\\n {2}[a-z0-9-]+:\\n|$)`).exec(text)?.[1] ?? "";
const permissions = (block) => Object.fromEntries([.../\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(block)[1].matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => [m[1], m[2]]));

test("the monitor job's token writes issues and nothing else, and it cannot mint", () => {
  assert.match(text, /\npermissions: \{\}\n/);
  assert.deepEqual(permissions(job("monitor")), {
    actions: "read",
    checks: "read",
    contents: "read",
    issues: "write",
    "pull-requests": "read",
  });
  assert.match(job("monitor"), /\n {10}GITHUB_TOKEN: \$\{\{ github\.token \}\}\n/);
  assert.doesNotMatch(job("monitor"), /id-token|request-lane-token/);
  assert.doesNotMatch(text, /secrets\.|claude-code-action/);
});

test("only the file-incidents job can mint, holds no write of its own, and runs the filer alone with the token", () => {
  const filing = job("file-incidents");
  assert.deepEqual(permissions(filing), { contents: "read", "id-token": "write" });
  assert.match(filing, /needs: monitor\n/);
  assert.match(filing, /needs\.monitor\.outputs\.plan-artifact-id != ''/);
  assert.match(filing, /uses: \.\/\.base\/\.github\/actions\/request-lane-token/);
  assert.match(filing, /lane: maintenance-monitor-signals\n {10}activity: file-incident\n/);
  assert.match(filing, /kill-switch-ok: true/);
  assert.equal(filing.match(/\$\{\{ steps\.lane-token\.outputs\.token \}\}/g).length, 2, "the filer and the revoke step");
  assert.match(filing, /file-incidents\.mjs/);
  assert.match(filing, /Revoke the lane token/);
  assert.doesNotMatch(filing, /GITHUB_TOKEN/);
});

test("a filing plan is checked against the monitor job's hash before any token is minted", () => {
  const filing = job("file-incidents");
  assert.ok(filing.indexOf("Check the filing plan") < filing.indexOf("Request the lane token"));
  assert.match(filing, /steps\.verify\.outcome == 'success'/);
  assert.match(job("monitor"), /scan-upload/);
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

test("every action is pinned to a full commit", () => {
  for (const [, ref] of text.matchAll(/uses: ([^\s]+)/g)) {
    if (ref.startsWith("./")) continue;
    assert.match(ref, /@[0-9a-f]{40}$/, ref);
  }
});
