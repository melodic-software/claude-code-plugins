// maintenance-delete-stale-branches.yml's hardening (README.md, "Branch
// cleanup"): the kill switch stops each job before it reads, the plan job's
// token writes nothing, only the delete job's token writes contents and it
// reads no issue text, a manual run is a dry-run by default and starts no
// delete job, and the ledger is uploaded even after a failed step.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/maintenance-delete-stale-branches.yml", import.meta.url), "utf8");
const job = (name) => {
  const start = text.indexOf(`\n  ${name}:\n`);
  assert.ok(start > 0, `job ${name}`);
  const next = text.slice(start + 1).search(/\n {2}[a-z-]+:\n/);
  return next < 0 ? text.slice(start) : text.slice(start, start + 1 + next);
};
const grants = (body) =>
  /\n {4}permissions:\n((?: {6}.+\n)+)/
    .exec(body)[1]
    .trim()
    .split("\n")
    .map((line) => line.trim().replace(/ #.*$/, ""))
    .sort();
const step = (body, name) => body.slice(body.indexOf(`- name: ${name}`)).split("\n      - name:")[0];

test("the plan job's token writes nothing; the delete job's writes contents and reads no issues", () => {
  assert.match(text, /\npermissions: \{\}\n/);
  assert.deepEqual(grants(job("plan")), ["contents: read", "issues: read", "pull-requests: read"]);
  assert.deepEqual(grants(job("delete")), ["contents: write", "pull-requests: read"]);
});

test("each job checks the kill switch before every step that reads or deletes", () => {
  for (const [name, steps] of [
    ["plan", ["Install resolve-config's dependencies", "Plan the deletes"]],
    ["delete", ["Install resolve-config's dependencies", "Download the candidate list", "Delete stale branches", "Upload the ledger"]],
  ]) {
    const body = job(name);
    assert.match(body, /uses: \.\/\.base\/\.github\/actions\/check-kill-switch/, name);
    for (const s of steps) assert.match(step(body, s), /steps\.kill\.outputs\.proceed == 'true'/, `${name}: ${s}`);
  }
});

test("only the plan stage reads issue and pull request text; the delete stage takes the plan job's list", () => {
  assert.match(step(job("plan"), "Plan the deletes"), /STAGE: plan\n/);
  assert.match(step(job("delete"), "Delete stale branches"), /STAGE: delete\n/);
  assert.match(job("delete"), /needs: plan\n/);
  assert.match(step(job("delete"), "Download the candidate list"), /name: branch-cleanup-candidates-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}\n/);
});

test("a manual run is a dry-run unless set and starts no delete job, and the schedule deletes", () => {
  assert.match(text, /dry-run:\n {8}description: .+\n {8}type: boolean\n {8}default: true\n/);
  for (const name of ["plan", "delete"]) {
    assert.match(
      job(name),
      /DRY_RUN: \$\{\{ github\.event_name == 'workflow_dispatch' && format\('\{0\}', inputs\.dry-run\) \|\| 'false' \}\}/,
      name,
    );
  }
  assert.match(job("delete"), /&& \(github\.event_name != 'workflow_dispatch' \|\| !inputs\.dry-run\)\n/);
});

test("the ledger artifact uploads after a failed step too", () => {
  const body = step(job("delete"), "Upload the ledger");
  assert.match(body, /if: always\(\) && steps\.kill\.outputs\.proceed == 'true'/);
  assert.match(body, /path: \$\{\{ runner\.temp \}\}\/branch-cleanup-ledger\.jsonl/);
});

test("each job runs only on main and checks out no branch code, with no credential kept", () => {
  for (const name of ["plan", "delete"]) {
    const body = job(name);
    assert.match(body, /github\.ref == 'refs\/heads\/main'/, name);
    assert.match(body, /ref: \$\{\{ github\.sha \}\}\n {10}path: \.base\n {10}persist-credentials: false/, name);
  }
});
