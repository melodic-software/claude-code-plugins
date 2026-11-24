import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { workflowText } from "../lib/workflow-text.mjs";

const text = readFileSync(new URL("../../workflows/maintenance-delete-stale-branches.yml", import.meta.url), "utf8");
const wf = workflowText(text);
const { job } = wf;
const grants = (body) =>
  /\n {4}permissions:\n((?: {6}.+\n)+)/
    .exec(body)[1]
    .trim()
    .split("\n")
    .map((line) => line.trim().replace(/ #.*$/, ""))
    .sort();
const step = (id, name) => wf.stepNamed(id, name).text;

test("the select-stale-branches job's token writes nothing; the delete job's writes contents and reads no issues", () => {
  assert.match(text, /\npermissions: \{\}\n/);
  assert.deepEqual(grants(job("select-stale-branches")), ["contents: read", "issues: read", "pull-requests: read"]);
  assert.deepEqual(grants(job("delete")), ["contents: write", "pull-requests: read"]);
});

test("each job checks the kill switch before every step that reads or deletes", () => {
  for (const [name, steps] of [
    ["select-stale-branches", ["Install resolve-config's dependencies", "Plan the deletes"]],
    ["delete", ["Install resolve-config's dependencies", "Download the candidate list", "Delete stale branches", "Upload the ledger"]],
  ]) {
    const body = job(name);
    assert.match(body, /uses: \.\/\.base\/\.github\/actions\/check-kill-switch/, name);
    for (const s of steps) assert.match(step(name, s), /steps\.kill\.outputs\.proceed == 'true'/, `${name}: ${s}`);
  }
});

test("only the plan stage reads issue and pull request text; the delete stage takes the select-stale-branches job's list", () => {
  assert.match(step("select-stale-branches", "Plan the deletes"), /STAGE: plan\n/);
  assert.match(step("delete", "Delete stale branches"), /STAGE: delete\n/);
  assert.match(job("delete"), /needs: select-stale-branches\n/);
});

// Re-running only a failed delete job keeps the select-stale-branches job's outputs from the
// attempt that uploaded the list, so the download names that attempt's
// artifact, never the re-run's own attempt.
test("the delete job downloads the artifact name the select-stale-branches job uploaded", () => {
  const name = "branch-cleanup-candidates-${{ github.run_id }}-${{ github.run_attempt }}";
  assert.ok(job("select-stale-branches").includes(`\n      candidates: ${name}\n`));
  assert.ok(step("select-stale-branches", "Upload the candidate list").includes(`\n          name: ${name}\n`));
  assert.match(step("delete", "Download the candidate list"), /\n {10}name: \$\{\{ needs\.select-stale-branches\.outputs\.candidates \}\}\n/);
  assert.doesNotMatch(step("delete", "Download the candidate list"), /github\.run_attempt/);
});

test("a manual run is a dry-run unless set and starts no delete job, and the schedule deletes", () => {
  assert.match(text, /dry-run:\n {8}description: .+\n {8}type: boolean\n {8}default: true\n/);
  for (const name of ["select-stale-branches", "delete"]) {
    assert.match(
      job(name),
      /DRY_RUN: \$\{\{ github\.event_name == 'workflow_dispatch' && format\('\{0\}', inputs\.dry-run\) \|\| 'false' \}\}/,
      name,
    );
  }
  assert.match(job("delete"), /&& \(github\.event_name != 'workflow_dispatch' \|\| !inputs\.dry-run\)\n/);
});

test("the ledger artifact uploads after a failed step too", () => {
  const body = step("delete", "Upload the ledger");
  assert.match(body, /if: always\(\) && steps\.kill\.outputs\.proceed == 'true'/);
  assert.match(body, /path: \$\{\{ runner\.temp \}\}\/branch-cleanup-ledger\.jsonl/);
});

test("each job runs only on main and checks out no branch code, with no credential kept", () => {
  for (const name of ["select-stale-branches", "delete"]) {
    const body = job(name);
    assert.match(body, /github\.ref == 'refs\/heads\/main'/, name);
    assert.match(body, /ref: \$\{\{ github\.sha \}\}\n {10}path: \.base\n {10}persist-credentials: false/, name);
  }
});
