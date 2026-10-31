// Expected values come from the gate's contract (action.yml): degraded is
// true only while the Actions or npm Package installation component lists
// partial_outage or major_outage, the two Statuspage statuses that mean the
// component is broken for some or all customers
// (https://support.atlassian.com/statuspage/docs/what-is-a-component); a
// page that cannot be read or lists no such component fails open. Pages are
// built in the Statuspage components.json shape component-status.mjs reads.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { ACTIONS, NPM_INSTALL } from "../../scripts/maintenance-reconcile-lost-runs/component-status.mjs";
import { readOutputs } from "../check-kill-switch/fixtures/read-outputs.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { checkUpstreamStatus } from "./check-upstream-status.mjs";

const page = (name, status) => ({ components: [{ name, status, group: false }] });
const pages = (actions, npm) => ({ [ACTIONS.url]: actions, [NPM_INSTALL.url]: npm });
const reader = (byUrl) => async (url) => {
  const value = byUrl[url];
  if (value instanceof Error) {
    throw value;
  }
  return value;
};

test("proceeds when both components are operational", async () => {
  const result = await checkUpstreamStatus({
    fetchStatus: reader(pages(page("Actions", "operational"), page("Package installation", "operational"))),
  });
  assert.deepEqual(result, { degraded: "false", reason: "ok", notes: [] });
});

test("skips with a logged reason when npm package installation is degraded", async () => {
  const result = await checkUpstreamStatus({
    fetchStatus: reader(pages(page("Actions", "operational"), page("Package installation", "major_outage"))),
  });
  assert.equal(result.degraded, "true");
  assert.equal(result.reason, "Package installation major_outage");
  assert.deepEqual(result.notes, ["status.npmjs.org lists Package installation as major_outage; this run is skipped"]);
});

test("skips when Actions is degraded", async () => {
  const result = await checkUpstreamStatus({
    fetchStatus: reader(pages(page("Actions", "partial_outage"), page("Package installation", "operational"))),
  });
  assert.equal(result.degraded, "true");
  assert.equal(result.reason, "Actions partial_outage");
});

test("fails open when a status page cannot be read", async () => {
  const result = await checkUpstreamStatus({
    fetchStatus: reader(pages(new Error("the status page answered 503"), page("Package installation", "operational"))),
  });
  assert.equal(result.degraded, "false");
  assert.equal(result.reason, "unknown");
  assert.deepEqual(result.notes, [
    "www.githubstatus.com could not be read (the status page answered 503); the gate fails open for it",
  ]);
});

test("fails open when a page lists no such component", async () => {
  const result = await checkUpstreamStatus({
    fetchStatus: reader(pages(page("Actions", "operational"), { components: [] })),
  });
  assert.equal(result.degraded, "false");
  assert.equal(result.reason, "unknown");
});

test("an outage still skips when the other page cannot be read", async () => {
  const result = await checkUpstreamStatus({
    fetchStatus: reader(pages(new Error("timeout"), page("Package installation", "partial_outage"))),
  });
  assert.equal(result.degraded, "true");
  assert.equal(result.notes.length, 2);
});

// Incident pwxsjgnvrk6b listed Actions as degraded_performance while Actions
// jobs kept succeeding; a slow or maintained component still runs.
for (const status of ["degraded_performance", "under_maintenance"]) {
  test(`runs, with a logged note, while a component lists ${status}`, async () => {
    const result = await checkUpstreamStatus({
      fetchStatus: reader(pages(page("Actions", status), page("Package installation", "operational"))),
    });
    assert.deepEqual(result, {
      degraded: "false",
      reason: "ok",
      notes: [`www.githubstatus.com lists Actions as ${status}; the gate lets this run proceed`],
    });
  });
}

test("a status the gate does not know runs, fail open", async () => {
  const result = await checkUpstreamStatus({
    fetchStatus: reader(pages(page("Actions", "operational"), page("Package installation", "something_new"))),
  });
  assert.equal(result.degraded, "false");
});

test("page text cannot start a workflow command or a second log line", async () => {
  const result = await checkUpstreamStatus({
    fetchStatus: reader(pages(page("Actions", "x\n::error::injected"), page("Package installation", "operational"))),
  });
  assert.equal(result.degraded, "false");
  assert.equal(result.notes.length, 1);
  for (const text of [result.reason, ...result.notes]) {
    assert.ok(!text.includes("\n") && !text.includes("::"), text);
  }
});

test("the script fails open with exit 0 when no page can be reached", () => {
  const dir = tempDir("upstream-status-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    // A preload that makes every fetch throw, so the run needs no network.
    const preload = path.join(dir, "no-fetch.mjs");
    writeFileSync(preload, 'globalThis.fetch = async () => { throw new Error("offline"); };\n');
    const script = fileURLToPath(new URL("./check-upstream-status.mjs", import.meta.url));
    const run = spawnSync(process.execPath, ["--import", preload, script], {
      env: { PATH: process.env.PATH, GITHUB_OUTPUT: outputPath },
      encoding: "utf8",
    });
    assert.equal(run.status, 0, run.stderr);
    assert.deepEqual(readOutputs(readFileSync(outputPath, "utf8")), { degraded: "false", reason: "unknown" });
    assert.match(run.stdout, /::notice::upstream status: .*could not be read \(offline\); the gate fails open/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// Admissions and dispatches that start token-spending runs call the gate;
// pr-merge enqueues never do, since status pages lag an incident's end and
// would hold merges that already pass (#9016 item 5).
const workflow = (name) => readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8");
const GATE = "./.base/.github/actions/check-upstream-status";
const GATED_WORKFLOWS = [
  "eval-browser-dispatch.yml",
  "intake-triage.yml",
  "pr-feedback-dispatch.yml",
  "pr-review-hosted.yml",
  "pr-review-main.yml",
  "pr-review-security-hosted.yml",
  "pr-unblock-dispatch.yml",
  "work-resolve-issue.yml",
];

test("the token-spending admission and dispatch workflows call the gate, and pr-merge does not", () => {
  for (const name of GATED_WORKFLOWS) {
    assert.ok(workflow(name).includes(GATE), `${name} calls check-upstream-status`);
  }
  assert.ok(!workflow("pr-merge.yml").includes("check-upstream-status"), "pr-merge.yml never calls the gate");
});

test("every gate step fails open: continue-on-error, and no condition requires degraded to read false", () => {
  for (const name of GATED_WORKFLOWS) {
    const text = workflow(name);
    const steps = text.split(GATE).length - 1;
    const guarded = [...text.matchAll(/id: upstream\n(?:\s+if: .*\n)?\s+continue-on-error: true\n/g)].length;
    assert.equal(guarded, steps, `${name}: each gate step sets continue-on-error`);
    assert.doesNotMatch(text, /degraded == 'false'|degraded != 'false'/, name);
  }
});

// A hosted review caller's gate skip fails its kill-switch job with this
// lane's error, so the run is a failed first attempt the lost-run reconciler
// re-runs (reconcile.mjs `upstream`), the merge gate binds the re-run
// (babysit_review_evidence UPSTREAM_STOP_RE) and ci-status names the stop.
const HOSTED = [
  ["pr-review-hosted.yml", "review", "CLAUDE_REVIEW_DISABLED"],
  ["pr-review-security-hosted.yml", "security review", "CLAUDE_SECURITY_REVIEW_DISABLED"],
];

test("a hosted review caller fails its kill-switch job when the gate skips the review", () => {
  for (const [name, what, lane] of HOSTED) {
    const text = workflow(name);
    const step = text.slice(text.indexOf("      - name: Stop on upstream status\n"));
    assert.ok(text.includes("      - name: Stop on upstream status\n"), `${name} has the stop step`);
    const body = step.slice(0, step.indexOf("\n      - name: ", 1));
    assert.match(
      body,
      new RegExp(`if: steps\\.kill\\.outputs\\.proceed == 'true' && steps\\.upstream\\.outputs\\.degraded == 'true' && vars\\.${lane} != 'true'\\n`),
      name,
    );
    assert.match(body, /REASON: \$\{\{ steps\.upstream\.outputs\.reason \}\}/, name);
    assert.match(body, new RegExp(`echo "::error::an upstream outage stops this ${what} \\(\\$\\{REASON:-unknown\\}\\); `), name);
    assert.match(body, /\n\s+exit 1\n/, name);
    assert.ok(text.indexOf("- name: Report the kill switch") < text.indexOf("- name: Stop on upstream status"), `${name}: the stop follows the kill-switch report`);
  }
});
