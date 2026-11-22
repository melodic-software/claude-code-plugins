// test-scope: .github/workflows/*.yml
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import { generate } from "../../.github/actions/open-lane-output/keygen.mjs";
import { REPO, RUN_WORKFLOWS, TRANSCRIPT_CALLERS, TRANSCRIPT_JOB_IDS, TRANSCRIPT_NAMES } from "./pull.mjs";
import { artifact, fakeDeps, FOREVER, iso, listings, NOW, run, sealed, seedState, sinkDir, stateOf, WORKFLOWS, workflowLines } from "./pull-fixtures.mjs";
import { laneOf, readRows, writeRows } from "./store.mjs";

test("a pull lists every name built from the job-ids by attempts 1 to 3, one call per name with no artifact, and never the repository-wide listing", () => {
  const { privateText } = generate();
  const deps = fakeDeps([]);
  assert.equal(run(["pull", "--sink", sinkDir()], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps }).code, 0);
  const expected = [...new Set(Object.values(TRANSCRIPT_JOB_IDS).flat().flatMap((id) => [1, 2, 3].map((n) => `api repos/${REPO}/actions/artifacts?name=lane-transcript-${id}-${n}&per_page=100&page=1`)))];
  assert.deepEqual(listings(deps), expected, "each name once, though two workflows share the model job-id");
  for (const name of ["lane-transcript-check-intent-spec-3", "lane-transcript-assess-units-fallback-d8-1", "lane-transcript-review-subscription-claude-security-review-4-2", "lane-transcript-adjudicate-feedback-2-fallback-1", "lane-transcript-reuse-summary-1", "lane-transcript-reuse-summary-subscription-2", "lane-transcript-reuse-summary-fallback-3"]) {
    assert.ok(TRANSCRIPT_NAMES.includes(name), name);
  }
});

test("a name's listing pages until an artifact older than the last successful pull, less the overlap, then the next name is listed", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 24 * 3600_000) });
  const held = Array.from({ length: 100 }, (_, i) => artifact(1000 - i, { record: sealed(publicLine) }));
  held[99].created_at = iso(NOW - 31 * 3600_000);
  writeRows(sink, held.slice(0, 99).map((a) => ({ artifact_id: a.id, created_at: a.created_at, date: a.created_at.slice(0, 10), transcript: null })));
  const older = artifact(900, { createdAt: NOW - 40 * 3600_000, record: sealed(publicLine) });
  const deps = fakeDeps([...held, older, artifact(5, { jobId: "rate-merge-risk", record: sealed(publicLine, { jobId: "rate-merge-risk" }) })]);
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 0, result.err);
  assert.ok(!deps.calls.some((c) => c.includes("check-intent-1&per_page=100&page=2")), "the page that reached the cutoff ends that name");
  assert.ok(deps.calls.some((c) => c.includes("name=lane-transcript-check-intent-2&")), "the next name is still listed");
  assert.match(result.out, /"pulled":1,"known":99/);
  assert.deepEqual(readRows(sink).filter((r) => r.transcript).map((r) => r.artifact_id), [5]);
});

test("a re-run's attempt-2 artifact of a run created before the cutoff is pulled, by the artifact's own created_at", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 24 * 3600_000) });
  const rerun = artifact(77, { attempt: 2, runId: 77, createdAt: NOW - 3600_000, record: sealed(publicLine, { runId: 77 }) });
  const runs = { 77: { path: ".github/workflows/pr-verify.yml", name: "pr-verify", event: "pull_request", head_branch: "feat/x", conclusion: "success", created_at: iso(NOW - 3 * 86400_000) } };
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: fakeDeps([rerun], { runs }) });
  assert.equal(result.code, 0, result.err);
  const [row] = readRows(sink);
  assert.deepEqual({ id: row.artifact_id, attempt: row.run_attempt, job: row.job_id }, { id: 77, attempt: 2, job: "check-intent" });
});

test("a budget-stopped pull's successor starts listing at the name it stopped on and wraps, so two pulls together list every name", () => {
  const { privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 86400_000) });
  const listedNames = (deps) => listings(deps).map((c) => /name=([^&]+)&/.exec(c)[1]);
  const budget = RUN_WORKFLOWS.length + 500;
  const first = { ...fakeDeps([]), ghCallBudget: budget };
  run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: first });
  const second = { ...fakeDeps([]), ghCallBudget: budget };
  run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps: second });
  assert.ok(500 < TRANSCRIPT_NAMES.length && 1000 > TRANSCRIPT_NAMES.length, "one pull lists only part of the names");
  assert.equal(listedNames(second)[0], TRANSCRIPT_NAMES[500], "the second pull starts where the first stopped");
  assert.deepEqual(new Set([...listedNames(first), ...listedNames(second)]), new Set(TRANSCRIPT_NAMES));
});

test("a pull stops at its gh call budget, records a success that says so, and the next pull a day later still reaches what it left", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 3 * 86400_000) });
  const env = () => ({ LANE_TRANSCRIPT_PRIVATE_KEY: privateText });
  const backlog = [301, 302, 303].map((id) => artifact(id, { jobId: "refine-issue", runId: id, createdAt: NOW - 2 * 86400_000, record: sealed(publicLine, { runId: id, jobId: "refine-issue" }) }));
  const budget = RUN_WORKFLOWS.length + 5;
  const first = { ...fakeDeps(backlog), ghCallBudget: budget };
  const stopped = run(["pull", "--sink", sink], { env: env(), deps: first });
  assert.equal(stopped.code, 0, stopped.err);
  assert.equal(first.calls.length, budget, "no call past the budget");
  assert.match(stopped.out, new RegExp(`gh calls: ${budget} of ${budget}`));
  assert.equal(readRows(sink).length, 2);
  const state = stateOf(sink);
  assert.deepEqual({ at: state.last_success_at, error: state.last_error, exhausted: state.budget_exhausted, calls: state.gh_calls }, { at: new Date(NOW).toISOString(), error: null, exhausted: true, calls: budget });
  assert.equal(state.cursors["lane-transcript-refine-issue-1"], undefined, "the name the budget stopped inside keeps no cursor");
  const shown = JSON.parse(run(["status", "--sink", sink], { deps: fakeDeps([]) }).out);
  assert.deepEqual({ stale: shown.stale, exhausted: shown.budget_exhausted, resume: shown.resume_cutoff_at }, { stale: false, exhausted: true, resume: new Date(NOW - 78 * 3600_000).toISOString() });

  const second = fakeDeps(backlog, { now: NOW + 86400_000 });
  const resumed = run(["pull", "--sink", sink], { env: env(), deps: second });
  assert.equal(resumed.code, 0, resumed.err);
  assert.deepEqual(second.calls.filter((c) => c.endsWith("/zip")), [`api repos/${REPO}/actions/artifacts/303/zip`], "only the artifact the stopped pull left");
  assert.deepEqual(readRows(sink).map((r) => r.artifact_id).sort(), [301, 302, 303]);
  assert.equal(stateOf(sink).budget_exhausted, false);
  assert.match(resumed.out, new RegExp(`gh calls: ${second.calls.length} of `));
});


const attemptOf = (name) => Number(/-(\d+)$/.exec(name)[1]);
const FIRST_ATTEMPTS = TRANSCRIPT_NAMES.filter((name) => attemptOf(name) === 1);
const listedAgo = (hours) => Object.fromEntries(TRANSCRIPT_NAMES.map((name) => [name, iso(NOW - hours * 3600_000)]));
const listedNames = (deps) => listings(deps).map((c) => /name=([^&]+)&/.exec(c)[1]);
const runOf = (id, { attempt = 1, path: workflowPath = ".github/workflows/pr-verify.yml", createdAt = NOW - 3600_000 } = {}) => ({ id, run_attempt: attempt, path: workflowPath, name: laneOf(workflowPath), event: "pull_request", head_branch: "feat/listed", conclusion: "success", created_at: iso(createdAt) });

test("an idle pull with fresh cursors lists each attempt-1 name once and no later attempt, and the run listings cost one call per workflow", () => {
  const { privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 2 * 3600_000), cursors: listedAgo(2) });
  const deps = fakeDeps([]);
  assert.equal(run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps }).code, 0);
  assert.deepEqual(listedNames(deps), FIRST_ATTEMPTS);
  assert.deepEqual(
    deps.calls.filter((c) => c.includes("/runs?")),
    RUN_WORKFLOWS.map((workflow) => `api repos/${REPO}/actions/workflows/${workflow}/runs?per_page=100`),
  );
  assert.equal(deps.calls.length, RUN_WORKFLOWS.length + FIRST_ATTEMPTS.length);
});

test("a name's next listing stops at its own cursor less the overlap, though a budget stop kept the shared cutoff: a name with more than a page pages once on the next pull", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 24 * 3600_000), resume_name: "lane-transcript-check-intent-1" });
  const env = () => ({ LANE_TRANSCRIPT_PRIVATE_KEY: privateText });
  const busy = Array.from({ length: 150 }, (_, i) => artifact(5000 - i, { createdAt: NOW - i * 8 * 60_000, record: sealed(publicLine) }));
  const first = { ...fakeDeps(busy), ghCallBudget: RUN_WORKFLOWS.length + 2 + 151 + 5 };
  assert.equal(run(["pull", "--sink", sink], { env: env(), deps: first }).code, 0);
  assert.equal(listedNames(first).filter((name) => name === "lane-transcript-check-intent-1").length, 2, "the first pull pages back to the shared cutoff");
  const stopped = stateOf(sink);
  assert.deepEqual({ exhausted: stopped.budget_exhausted, resume: stopped.resume_cutoff_at }, { exhausted: true, resume: new Date(NOW - 30 * 3600_000).toISOString() });
  assert.equal(stopped.cursors["lane-transcript-check-intent-1"], new Date(NOW).toISOString());
  const second = fakeDeps(busy, { now: NOW + 2 * 3600_000 });
  const again = run(["pull", "--sink", sink], { env: env(), deps: second });
  assert.equal(again.code, 0, again.err);
  assert.equal(listedNames(second).filter((name) => name === "lane-transcript-check-intent-1").length, 1, "the next pull stops at the cursor");
  assert.match(again.out, /"pulled":0,"known":46/);
  assert.equal(second.calls.filter((c) => c.endsWith("/zip")).length, 0);
});

test("a re-run found in a workflow's newest runs, though the run is days older than every cutoff, lists that workflow's later-attempt names, and the run's details come from the listing", () => {
  const { publicLine, privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 2 * 3600_000), cursors: listedAgo(2) });
  const rerun = artifact(77, { attempt: 2, runId: 77, createdAt: NOW - 3600_000, record: sealed(publicLine, { runId: 77 }) });
  const workflowRuns = {
    "pr-verify.yml": [runOf(78), runOf(77, { attempt: 2, createdAt: NOW - 3 * 86400_000 })],
    "pr-refine.yml": [runOf(90, { attempt: 3, path: ".github/workflows/pr-refine.yml" })],
  };
  const deps = fakeDeps([rerun], { workflowRuns });
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 0, result.err);
  const names = new Set(listedNames(deps));
  const later = (key, attempts) => TRANSCRIPT_JOB_IDS[key].flatMap((id) => attempts.map((n) => `lane-transcript-${id}-${n}`));
  for (const name of later("pr-verify.yml", [2])) assert.ok(names.has(name), name);
  for (const name of later("pr-run-activity-read.yml", [2, 3])) assert.ok(names.has(name), name);
  assert.ok(!names.has("lane-transcript-check-intent-3"), "an attempt no run reached is not listed");
  assert.ok(!names.has("lane-transcript-rate-merge-risk-2"), "a workflow with no re-run lists no later attempt");
  assert.equal(names.size, FIRST_ATTEMPTS.length + later("pr-verify.yml", [2]).length + later("pr-run-activity-read.yml", [2, 3]).length);
  const [row] = readRows(sink);
  assert.deepEqual({ id: row.artifact_id, attempt: row.run_attempt, branch: row.head_branch }, { id: 77, attempt: 2, branch: "feat/listed" });
  assert.ok(!deps.calls.some((c) => c.endsWith("actions/runs/77")), "no run read for a run in the listing");
});

test("a workflow whose run listing fails lists every attempt of its names, and the pull still succeeds", () => {
  const { privateText } = generate();
  const sink = sinkDir();
  seedState(sink, { last_success_at: iso(NOW - 2 * 3600_000), cursors: listedAgo(2) });
  const deps = { ...fakeDeps([], { failures: { "workflows/pr-verify.yml/runs?per_page=100": FOREVER } }), ghAttempts: 1 };
  const result = run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps });
  assert.equal(result.code, 0, result.err);
  const names = new Set(listedNames(deps));
  assert.ok(names.has("lane-transcript-check-intent-2") && names.has("lane-transcript-check-intent-spec-3"));
  assert.ok(!names.has("lane-transcript-rate-merge-risk-2"));
  assert.equal(stateOf(sink).last_error, null);
});

test("a later-attempt name comes due a day after it was last listed through, whatever the runs show, and that listing moves its cursor", () => {
  const { privateText } = generate();
  const sink = sinkDir();
  const cursors = listedAgo(2);
  cursors["lane-transcript-rate-merge-risk-2"] = iso(NOW - 25 * 3600_000);
  cursors["lane-transcript-rate-merge-risk-3"] = iso(NOW - 23 * 3600_000);
  delete cursors["lane-transcript-refine-issue-3"];
  seedState(sink, { last_success_at: iso(NOW - 2 * 3600_000), cursors });
  const deps = fakeDeps([]);
  assert.equal(run(["pull", "--sink", sink], { env: { LANE_TRANSCRIPT_PRIVATE_KEY: privateText }, deps }).code, 0);
  assert.deepEqual(listedNames(deps).filter((name) => attemptOf(name) > 1).sort(), ["lane-transcript-rate-merge-risk-2", "lane-transcript-refine-issue-3"]);
  const after = stateOf(sink).cursors;
  assert.equal(after["lane-transcript-rate-merge-risk-2"], new Date(NOW).toISOString());
  assert.equal(after["lane-transcript-rate-merge-risk-3"], cursors["lane-transcript-rate-merge-risk-3"]);
});

test("a budget-stopped pull of the daily ring keeps the rest due, and its successor resumes at the name it stopped on", () => {
  const { privateText } = generate();
  const sink = sinkDir();
  const cursors = Object.fromEntries(TRANSCRIPT_NAMES.map((name) => [name, iso(NOW - (attemptOf(name) === 1 ? 2 : 30) * 3600_000)]));
  seedState(sink, { last_success_at: iso(NOW - 2 * 3600_000), cursors });
  const env = () => ({ LANE_TRANSCRIPT_PRIVATE_KEY: privateText });
  const budget = RUN_WORKFLOWS.length + 400;
  const first = { ...fakeDeps([]), ghCallBudget: budget };
  assert.equal(run(["pull", "--sink", sink], { env: env(), deps: first }).code, 0);
  const stopped = stateOf(sink);
  assert.deepEqual({ exhausted: stopped.budget_exhausted, name: stopped.resume_name }, { exhausted: true, name: TRANSCRIPT_NAMES[400] });
  assert.equal(stopped.resume_cutoff_at, new Date(NOW - 36 * 3600_000).toISOString(), "the oldest name's cutoff, its cursor less the overlap");
  const later = NOW + 2 * 3600_000;
  const second = fakeDeps([], { now: later });
  assert.equal(run(["pull", "--sink", sink], { env: env(), deps: second }).code, 0);
  assert.equal(listedNames(second)[0], TRANSCRIPT_NAMES[400]);
  assert.deepEqual(new Set([...listedNames(first), ...listedNames(second)]), new Set(TRANSCRIPT_NAMES), "the two pulls list every name between them");
  const done = stateOf(sink);
  assert.deepEqual({ exhausted: done.budget_exhausted, resume: done.resume_cutoff_at, name: done.resume_name }, { exhausted: false, resume: null, name: null });
  assert.ok(TRANSCRIPT_NAMES.every((name) => Date.parse(done.cursors[name]) >= NOW), "every name was listed through by one of them");
});

test("every caller of a transcript reusable is in TRANSCRIPT_CALLERS, every reusable with transcript names has an entry, and every run workflow exists", () => {
  const files = new Set(readdirSync(WORKFLOWS));
  const callers = {};
  for (const [file, lines] of workflowLines()) {
    lines.forEach((line, i) => {
      const local = /^\s+uses:\s*\.\/\.github\/workflows\/([^\s#]+)/.exec(line)?.[1];
      if (local && TRANSCRIPT_JOB_IDS[local]) (callers[local] ??= new Set()).add(file);
      if (/^\s+lane-transcript-public-key:/.test(line)) {
        const uses = lines.slice(0, i).findLast((l) => /^\s+uses:/.test(l));
        const reusable = /ci-workflows\/\.github\/workflows\/([^@\s]+)@/.exec(uses)[1];
        (callers[`ci-workflows/${reusable}`] ??= new Set()).add(file);
      }
    });
  }
  assert.deepEqual(Object.fromEntries(Object.entries(TRANSCRIPT_CALLERS).map(([key, list]) => [key, [...list].sort()])), Object.fromEntries(Object.entries(callers).map(([key, set]) => [key, [...set].sort()])));
  for (const workflow of RUN_WORKFLOWS) {
    assert.ok(files.has(workflow), workflow);
    const lines = readFileSync(path.join(WORKFLOWS, workflow), "utf8").split("\n");
    const on = lines.findIndex((l) => /^on:/.test(l));
    const end = lines.findIndex((l, i) => i > on && /^\S/.test(l));
    const triggers = lines.slice(on + 1, end).map((l) => /^ {2}([a-z_]+):/.exec(l)?.[1]).filter(Boolean);
    assert.ok(triggers.some((t) => t !== "workflow_call"), `${workflow} has runs of its own`);
  }
});
