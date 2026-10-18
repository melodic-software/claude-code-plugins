// maintenance-audit-lane-runs.yml's hardening, from docs/conventions/pr-pipeline/README.md
// ("Every lane" and "The lane sweep"): only a schedule or a manual run starts
// it, the model job holds read permissions only and runs with
// --setting-sources user and dontAsk and no shell, only the scripted file job
// may write issues, and every job checks the kill switch first.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/maintenance-audit-lane-runs.yml", import.meta.url), "utf8");
const jobs = Object.fromEntries(
  `\n${text.split("\njobs:\n")[1]}`
    .split(/\n(?= {2}[a-z][a-z-]*:\n)/)
    .slice(1)
    .map((block) => [/^ {2}([a-z-]+):/.exec(block)[1], block]),
);
const permissions = (job) => {
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(jobs[job])[1];
  return Object.fromEntries([...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => [m[1], m[2]]));
};

test("only a schedule or a manual run starts the lane, with no default permissions", () => {
  const on = /\non:\n((?: {2}.*\n| {4}.*\n)+)/.exec(text)[1];
  assert.deepEqual(
    [...on.matchAll(/^ {2}([a-z_]+):/gm)].map((m) => m[1]),
    ["schedule", "workflow_dispatch"],
  );
  assert.match(text, /\npermissions: \{\}\n/);
});

test("the three jobs are collect, judge and file, in that order", () => {
  assert.deepEqual(Object.keys(jobs), ["collect", "judge", "file"]);
  assert.match(jobs.judge, /\n {4}needs: collect\n/);
  assert.match(jobs.file, /\n {4}needs: \[collect, judge\]\n/);
});

test("only the file job writes, and no job can mint a token", () => {
  for (const job of ["collect", "judge"]) {
    assert.ok(
      Object.values(permissions(job)).every((v) => v === "read"),
      job,
    );
  }
  assert.deepEqual(permissions("file"), {
    actions: "read",
    contents: "read",
    issues: "write",
  });
  assert.doesNotMatch(text, /id-token|request-lane-token|secrets\.[A-Z_]*(APP|PRIVATE)_KEY/);
});

test("the model runs only in judge, read-only, from the user settings source", () => {
  assert.equal(text.match(/anthropics\/claude-code-action@/g).length, 1);
  assert.match(jobs.judge, /anthropics\/claude-code-action@[0-9a-f]{40} /);
  assert.match(jobs.judge, /--setting-sources user\n/);
  assert.match(jobs.judge, /--permission-mode dontAsk\n/);
  assert.match(jobs.judge, /denied="Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Agent/);
  assert.doesNotMatch(jobs.judge, /allowedTools[^\n]*Bash/);
  // A bare Grep or Glob allow rule reaches every path, /proc included.
  assert.doesNotMatch(jobs.judge, /allowedTools \\"[^"]*(^|[,"])(Grep|Glob)[,\\]/);
  for (const path of ["//proc/**", "//sys/**", "~/.*", "~/.*/**", "/$RUNNER_TEMP/**"]) {
    assert.ok(jobs.judge.includes(`Read(${path})`), `the judge denies Read(${path})`);
  }
  // The workspace is under home, so a home-wide deny would block the checkout.
  assert.doesNotMatch(jobs.judge, /Read\(~\/\*\*\)/);
});

test("every job checks the kill switch before its first API or model step", () => {
  for (const [name, block] of Object.entries(jobs)) {
    const kill = block.indexOf("check-kill-switch");
    assert.ok(kill > 0, `${name} checks the kill switch`);
    const work = block.search(/node \.base\/\.github\/scripts\/maintenance-audit-lane-runs\/|claude-code-action@/);
    assert.ok(work > kill, `${name} works only after the kill switch`);
  }
});
