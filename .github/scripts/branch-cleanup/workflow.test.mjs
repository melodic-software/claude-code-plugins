// maintenance-delete-stale-branches.yml's hardening (README.md, "Branch
// cleanup"): the kill switch stops it before it reads, its token writes
// contents only, a manual run is a dry-run by default, and the ledger is
// uploaded even after a failed step.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/maintenance-delete-stale-branches.yml", import.meta.url), "utf8");

test("the job's token writes contents and reads issues and pull requests, nothing else", () => {
  assert.match(text, /\npermissions: \{\}\n/);
  const block = /\n {4}permissions:\n((?: {6}.+\n)+)/.exec(text)[1];
  const grants = block.trim().split("\n").map((line) => line.trim().replace(/ #.*$/, "")).sort();
  assert.deepEqual(grants, ["contents: write", "issues: read", "pull-requests: read"]);
});

test("the kill switch gates every step that reads or deletes", () => {
  assert.match(text, /uses: \.\/\.base\/\.github\/actions\/check-kill-switch/);
  for (const step of ["Install resolve-config's dependencies", "Delete stale branches", "Upload the ledger"]) {
    const body = text.slice(text.indexOf(`- name: ${step}`)).split("\n      - name:")[0];
    assert.match(body, /steps\.kill\.outputs\.proceed == 'true'/, step);
  }
});

test("a manual run is a dry-run unless set, and the schedule deletes", () => {
  assert.match(text, /dry-run:\n {8}description: .+\n {8}type: boolean\n {8}default: true\n/);
  assert.match(
    text,
    /DRY_RUN: \$\{\{ github\.event_name == 'workflow_dispatch' && format\('\{0\}', inputs\.dry-run\) \|\| 'false' \}\}/,
  );
});

test("the ledger artifact uploads after a failed step too", () => {
  const body = text.slice(text.indexOf("- name: Upload the ledger"));
  assert.match(body, /if: always\(\) && steps\.kill\.outputs\.proceed == 'true'/);
  assert.match(body, /path: \$\{\{ runner\.temp \}\}\/branch-cleanup-ledger\.jsonl/);
});

test("it runs only on main and checks out no branch code", () => {
  assert.match(text, /if: github\.ref == 'refs\/heads\/main'/);
  assert.match(text, /ref: \$\{\{ github\.sha \}\}\n {10}path: \.base\n {10}persist-credentials: false/);
});
