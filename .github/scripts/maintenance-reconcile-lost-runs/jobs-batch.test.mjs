/**
 * The batched first-attempt job reads (reconcile.mjs servedReads and
 * prefetchJobs). Expected values come from two sources: the recorded pair in
 * fixtures/jobs-graphql-parity.json, where GitHub answered the same two runs
 * through JOBS_QUERY and through REST attempts/1/jobs plus each job's
 * annotations, so the served answer must equal REST's on every field the
 * rules read; and the rule that a served pass decides exactly as a REST pass
 * does, so each plan below is run with /graphql refused and with it answered,
 * and must give the same re-runs, outputs and carry with fewer calls.
 */
import assert from "node:assert/strict";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import { INTAKE, JOBS_BATCH, JOBS_QUERY, main, servedReads, SETTLED_VERSION, VERDICT_DISPATCH, VERDICT_STOP_STEP, WRITE_STEP } from "./reconcile.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const REPO = "melodic-software/claude-code-plugins";
const NOW = Date.parse("2026-10-19T20:00:00Z");
const STATUS = JSON.parse(readFileSync(new URL("./fixtures/components.json", import.meta.url), "utf8"));
const PARITY = JSON.parse(readFileSync(new URL("./fixtures/jobs-graphql-parity.json", import.meta.url), "utf8"));
const VERIFY = ".github/workflows/pr-verify.yml";
const MAIN_REVIEW = ".github/workflows/pr-review-main.yml";
const LAST_PASS = { id: 900, path: ".github/workflows/maintenance-reconcile-lost-runs.yml", event: "schedule", head_branch: "main" };
const MAIN_TIP = "e".repeat(40);

test("a recorded GraphQL answer stands in for REST's job listing and annotations on every field the rules read", () => {
  assert.equal(PARITY.graphql.data.nodes.length, 2);
  for (const node of PARITY.graphql.data.nodes) {
    const rest = PARITY.rest[node.databaseId];
    const reads = servedReads(REPO, { id: node.databaseId }, node);
    assert.ok(reads, `run ${node.databaseId} is served`);
    const listing = reads.get(`/repos/${REPO}/actions/runs/${node.databaseId}/attempts/1/jobs?per_page=100`);
    const fields = (job) => ({ id: job.id, name: job.name, status: job.status, conclusion: job.conclusion, steps: job.steps });
    const byId = (a, b) => a.id - b.id;
    assert.equal(listing.total_count, rest.listing.total_count);
    assert.deepEqual(listing.jobs.map(fields), [...rest.listing.jobs].sort(byId).map(fields));
    for (const job of rest.listing.jobs) {
      if (job.steps.length === 0) {
        assert.equal(listing.jobs.find((j) => j.id === job.id).runner_id, job.runner_id, "a job with no steps carries the runner_id stepsKnown reads");
      }
      assert.deepEqual(reads.get(`/repos/${REPO}/check-runs/${job.id}/annotations?per_page=100`), rest.annotations[job.id]);
    }
  }
  assert.ok(
    PARITY.graphql.data.nodes.some((n) => n.checkSuite.checkRuns.nodes.some((c) => c.head.totalCount > 100)),
    "pr-verify's Check Intent lists more steps than one connection page",
  );
});

test("a node that does not answer for the run's first attempt in full is left to REST", () => {
  const node = PARITY.graphql.data.nodes.find((n) => n.checkSuite.checkRuns.nodes.some((c) => c.head.totalCount > 100));
  const run = { id: node.databaseId };
  const checks = node.checkSuite.checkRuns;
  const withCheck = (change) => ({ ...node, checkSuite: { checkRuns: { ...checks, nodes: checks.nodes.map((c, i) => (i === checks.nodes.length - 1 ? change(c) : c)) } } });
  const cases = {
    "no node": null,
    "another run": { ...node, databaseId: node.databaseId + 1 },
    "attempt 2": { ...node, runAttempt: 2 },
    "a job not listed": { ...node, checkSuite: { checkRuns: { ...checks, totalCount: checks.totalCount + 1 } } },
    "no jobs": { ...node, checkSuite: { checkRuns: { totalCount: 0, nodes: [] } } },
    "a null job": { ...node, checkSuite: { checkRuns: { ...checks, nodes: [...checks.nodes.slice(1), null] } } },
    "steps past both pages": withCheck((c) => ({ ...c, head: { ...c.head, totalCount: 201 }, tail: { ...c.tail, totalCount: 201 } })),
    "an annotation not listed": withCheck((c) => ({ ...c, annotations: { ...c.annotations, totalCount: c.annotations.totalCount + 1 } })),
    "a ran job with no steps": withCheck((c) => ({ ...c, head: { totalCount: 0, nodes: [] }, tail: { totalCount: 0, nodes: [] } })),
  };
  assert.ok(servedReads(REPO, run, node));
  for (const [label, changed] of Object.entries(cases)) {
    assert.equal(servedReads(REPO, run, changed), undefined, label);
  }
});

/**
 * GitHub as the reconciler reads it with no open pull request: lane runs by
 * workflow and status, first-attempt jobs and annotations by REST, and the
 * same jobs through JOBS_QUERY when `graphql` is "on". "refused" answers
 * every query 502; "errors" answers it with a GraphQL error body; "nulls"
 * answers no node. `carry` lists one trusted pass with a settled-runs artifact.
 */
function fakeGitHub(runs, graphql, carry) {
  const calls = [];
  const byId = new Map(runs.map((r) => [r.id, r]));
  const byNode = new Map(runs.map((r) => [r.node_id, r]));
  const jobsOf = (r) => r?.jobs ?? [];
  const upper = (v) => (typeof v === "string" ? v.toUpperCase() : v);
  const steps = (job, from, to) => ({ totalCount: job.steps.length, nodes: job.steps.slice(from, to) });
  const node = (r) =>
    r && {
      databaseId: r.id,
      runAttempt: r.run_attempt,
      checkSuite: {
        checkRuns: {
          totalCount: jobsOf(r).length,
          nodes: jobsOf(r).map((job) => ({
            databaseId: job.id,
            name: job.name,
            status: upper(job.status),
            conclusion: upper(job.conclusion),
            head: steps(job, 0, 100),
            tail: steps(job, Math.max(0, job.steps.length - 100)),
            annotations: { totalCount: (job.notes ?? []).length, nodes: (job.notes ?? []).map((a) => ({ annotationLevel: upper(a.annotation_level), title: a.title, message: a.message })) },
          })),
        },
      },
    };
  const github = async (method, apiPath, body) => {
    calls.push(`${method} ${apiPath}`);
    if (method === "POST" && apiPath === "/graphql") {
      assert.equal(body.query, JOBS_QUERY);
      assert.ok(body.variables.ids.length >= 2 && body.variables.ids.length <= JOBS_BATCH);
      if (graphql === "refused") {
        throw Object.assign(new Error("POST /graphql failed with status 502"), { status: 502 });
      }
      if (graphql === "errors") {
        throw new Error("POST /graphql (GraphQL errors)");
      }
      return { data: { nodes: body.variables.ids.map((id) => (graphql === "nulls" ? null : (node(byNode.get(id)) ?? null))) } };
    }
    if (method === "GET" && apiPath.startsWith(`/repos/${REPO}/pulls?`)) {
      return [];
    }
    if (method === "GET" && apiPath.includes("/actions/workflows/maintenance-reconcile-lost-runs.yml/runs?")) {
      return { total_count: carry ? 1 : 0, workflow_runs: carry ? [LAST_PASS] : [] };
    }
    if (method === "GET" && apiPath === `/repos/${REPO}/actions/runs/${LAST_PASS.id}/artifacts?per_page=100`) {
      return { total_count: 1, artifacts: [{ id: 4242, name: "reconcile-settled-runs", expired: false }] };
    }
    const byWorkflow = /\/actions\/workflows\/([a-z0-9-]+\.yml)\/runs\?created=[^&]+&status=([a-z_]+)&per_page=100(?:&page=([0-9]+))?$/.exec(apiPath);
    if (method === "GET" && byWorkflow) {
      const found = runs.filter((r) => r.path === `.github/workflows/${byWorkflow[1]}` && (r.status === byWorkflow[2] || r.conclusion === byWorkflow[2]));
      return { total_count: found.length, workflow_runs: Number(byWorkflow[3] ?? 1) === 1 ? found : [] };
    }
    const byStatus = /\/actions\/runs\?created=[^&]+&status=([a-z_]+)&per_page=100$/.exec(apiPath);
    if (method === "GET" && byStatus) {
      const found = runs.filter((r) => r.status === byStatus[1] || r.conclusion === byStatus[1]);
      return { total_count: found.length, workflow_runs: found };
    }
    const jobs = /\/actions\/runs\/([0-9]+)\/attempts\/1\/jobs\?per_page=100$/.exec(apiPath);
    if (method === "GET" && jobs) {
      const found = jobsOf(byId.get(Number(jobs[1]))).map(({ notes: _, ...job }) => job);
      return { total_count: found.length, jobs: found };
    }
    const notes = /\/check-runs\/([0-9]+)\/annotations\?per_page=100$/.exec(apiPath);
    if (method === "GET" && notes) {
      return runs.flatMap(jobsOf).find((j) => j.id === Number(notes[1]))?.notes ?? [];
    }
    const one = /\/actions\/runs\/([0-9]+)(\/rerun|\/rerun-failed-jobs)?$/.exec(apiPath);
    if (one && method === "GET") {
      return byId.get(Number(one[1]));
    }
    if (one && method === "POST" && one[2]) {
      return {};
    }
    throw new Error(`unexpected call ${method} ${apiPath}`);
  };
  return { github, calls };
}

/** Plan then act, as the workflow runs them; the plan's carry is returned. */
async function reconcile(runs, graphql, carry) {
  const { github, calls } = fakeGitHub(runs, graphql, carry);
  const dir = tempDir("reconcile-batch-");
  try {
    const files = { PLAN_PATH: path.join(dir, "plan.json"), RECORD_PATH: path.join(dir, "record.json"), GITHUB_OUTPUT: path.join(dir, "output"), SETTLED_PATH: path.join(dir, "settled.json") };
    writeFileSync(files.GITHUB_OUTPUT, "");
    const step = (mode) =>
      main({ env: { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed", ...files, MODE: mode }, github, fetchStatus: async () => STATUS, sleep: async () => {}, now: NOW, download: () => carry ?? "" });
    const planCode = await step("plan");
    const code = planCode === 0 ? await step("act") : planCode;
    return {
      code,
      calls,
      outputs: Object.fromEntries([...readFileSync(files.GITHUB_OUTPUT, "utf8").matchAll(/^([a-z0-9-]+)<<(\S+)\n([^\n]*)\n\2$/gm)].map((m) => [m[1], m[3]])),
      plan: JSON.parse(readFileSync(files.PLAN_PATH, "utf8")),
      settled: JSON.parse(readFileSync(files.SETTLED_PATH, "utf8")),
      reruns: calls.filter((c) => c.startsWith("POST ") && c.endsWith("/rerun")).map((c) => Number(/runs\/([0-9]+)\//.exec(c)[1])),
      failedJobReruns: calls.filter((c) => c.startsWith("POST ") && c.endsWith("/rerun-failed-jobs")).map((c) => Number(/runs\/([0-9]+)\//.exec(c)[1])),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const step = (name, number, conclusion = "success") => ({ name, number, status: "completed", conclusion });
/**
 * A pr-verify Check Intent job as REST lists it: numbered steps, the ones it
 * never reached skipped. `held` ran "Note the hold" with the resolver's notice;
 * `judged` reached the judge step; `wrote` started the verdict write.
 */
const intentJob = (id, { held = false, judged = false, wrote = false, failed = false } = {}) => ({
  id,
  name: "Check Intent",
  status: "completed",
  conclusion: failed ? "failure" : "success",
  steps: [
    step("Set up job", 1),
    step("Resolve the pull request", 2),
    step("Note the hold", 3, held ? "success" : "skipped"),
    step("Check the trigger", 4, failed && !judged ? "failure" : "success"),
    step("Judge the pull request", 5, judged ? "success" : "skipped"),
    step(WRITE_STEP, 6, wrote ? "success" : "skipped"),
    ...Array.from({ length: 110 }, (_, i) => step(`Later step ${i + 1}`, i + 7, "skipped")),
    step("Complete job", 117),
  ],
  notes: held ? [{ annotation_level: "notice", title: "pr-verify", message: "held: pr-verify could not resolve the pull request: GET /repos/x failed with status 502" }] : [{ annotation_level: "notice", title: "api", message: "api calls: 12" }],
});
const skippedJob = (id) => ({ id, name: "Check Intent Fallback", status: "completed", conclusion: "skipped", runner_id: null, steps: [] });
const verifyRun = (id, conclusion, jobs, { path: runPath = VERIFY, event = "workflow_run" } = {}) => ({
  id,
  node_id: `WFR_${id}`,
  path: runPath,
  event,
  status: "completed",
  conclusion,
  run_attempt: 1,
  head_branch: "main",
  head_sha: MAIN_TIP,
  head_repository: { full_name: REPO },
  created_at: "2026-10-19T19:40:00Z",
  updated_at: "2026-10-19T19:45:00Z",
  jobs,
});
const oneJob = (id, name, failedStep, notes = []) => ({
  id,
  name,
  status: "completed",
  conclusion: "failure",
  steps: [step("Set up job", 1), step(failedStep, 2, "failure"), step("Later step", 3, "skipped"), step("Complete job", 4)],
  notes,
});
/** A pr-review-main run as it lists: seven skipped jobs and two that ran. */
const reviewJobs = (id) => [
  ...Array.from({ length: 7 }, (_, i) => ({ ...skippedJob(id * 10 + i), name: `Review ${i}` })),
  { ...intentJob(id * 10 + 7), name: "Check Trigger" },
  { ...intentJob(id * 10 + 8), name: "Review Handoffs Credit" },
];
/**
 * Six succeeded pr-verify runs, one of them held on a GitHub fault, and a
 * succeeded pr-review-main run; three failed lost lane runs: one before its
 * judge step (701, whose read the last pass carried), one past it, one that
 * wrote its verdict; two failed intake runs, one only in its floor-label job;
 * two failed verdict posts, one the kill switch stopped and one that broke.
 */
const WORLD = [
  ...[601, 602, 603, 604, 605].map((id) => verifyRun(id, "success", [intentJob(id * 10), skippedJob(id * 10 + 1)])),
  verifyRun(606, "success", [intentJob(6060, { held: true }), skippedJob(6061)]),
  verifyRun(607, "success", reviewJobs(607), { path: MAIN_REVIEW }),
  verifyRun(701, "failure", [intentJob(7010, { failed: true }), skippedJob(7011)]),
  verifyRun(702, "failure", [intentJob(7020, { failed: true, judged: true }), skippedJob(7021)]),
  verifyRun(703, "failure", [intentJob(7030, { failed: true, judged: true, wrote: true }), skippedJob(7031)]),
  verifyRun(801, "failure", [oneJob(8010, "Intake Label Needs Triage / label", "Add the label")], { path: INTAKE, event: "issues" }),
  verifyRun(802, "failure", [oneJob(8020, "Triage / triage", "Triage the issue")], { path: INTAKE, event: "issues" }),
  verifyRun(901, "failure", [oneJob(9010, "Post Verify Notes", VERDICT_STOP_STEP)], { path: VERDICT_DISPATCH }),
  verifyRun(902, "failure", [oneJob(9020, "Post Verify Notes", "Post the notes", [{ annotation_level: "failure", title: "", message: "the post broke" }])], { path: VERDICT_DISPATCH }),
];
const slim = ({ notes: _, ...job }) => job;
/** The last pass's carry: run 701's first-attempt read, which holdReason takes instead of reading. */
const CARRY = JSON.stringify({
  version: SETTLED_VERSION,
  repository: REPO,
  runs: [],
  jobs: [{ id: 701, attempt: 1, head: MAIN_TIP, updated_at: "2026-10-19T19:45:00Z", jobs: WORLD.find((r) => r.id === 701).jobs.map(slim) }],
});
const restReads = (calls) => calls.filter((c) => c.includes("/attempts/1/jobs?") || c.includes("/check-runs/")).length;
const queries = (calls) => calls.filter((c) => c === "POST /graphql").length;

test("a pass that batches its job reads decides as a REST pass does, with fewer calls", async () => {
  const rest = await reconcile(WORLD, "refused", CARRY);
  const served = await reconcile(WORLD, "on", CARRY);
  assert.equal(rest.code, 0);
  assert.deepEqual(rest.reruns.sort(), [606, 701, 702].sort(), "the held run and the lost runs whose write never started");
  assert.deepEqual(rest.failedJobReruns.sort(), [801, 901].sort(), "the floor-label intake run and the switch-stopped verdict post");
  assert.ok(!rest.calls.includes(`GET /repos/${REPO}/actions/runs/701/attempts/1/jobs?per_page=100`), "the carried read is taken");
  for (const key of ["code", "reruns", "failedJobReruns", "outputs", "plan", "settled"]) {
    assert.deepEqual(served[key], rest[key], key);
  }
  assert.equal(queries(served.calls), 5, "lane runs 702-703, succeeded runs 601-605 and 606-607, intake 801-802, verdicts 901-902");
  assert.ok(served.calls.length < rest.calls.length, `${served.calls.length} calls against ${rest.calls.length}`);
  assert.deepEqual(served.calls.filter((c) => c.includes("/attempts/1/jobs?")), []);
});

test("a query that fails or answers for none of its runs sends no later batch, and every run is read through REST as before", async () => {
  const rest = await reconcile(WORLD, "refused", CARRY);
  for (const mode of ["errors", "nulls"]) {
    const failed = await reconcile(WORLD, mode, CARRY);
    for (const key of ["code", "reruns", "failedJobReruns", "outputs", "plan", "settled"]) {
      assert.deepEqual(failed[key], rest[key], `${mode}: ${key}`);
    }
    assert.equal(queries(failed.calls), 1, mode);
    assert.equal(restReads(failed.calls), restReads(rest.calls), mode);
  }
  assert.equal(queries(rest.calls), 1);
});

test("one run to read, or runs listed without a node id, send no query", async () => {
  const one = await reconcile([verifyRun(601, "success", [intentJob(6010)])], "on");
  assert.ok(!one.calls.includes("POST /graphql"));
  const unnamed = await reconcile(WORLD.map(({ node_id: _, ...r }) => r), "on");
  assert.ok(!unnamed.calls.includes("POST /graphql"));
  assert.deepEqual(unnamed.reruns.sort(), [606, 701, 702].sort());
});
