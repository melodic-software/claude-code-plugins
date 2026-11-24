import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { REVIEW_STOP_NOTE, REVIEW_STOP_STEP } from "./reconcile.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const SCRIPT = fileURLToPath(new URL("./reconcile.mjs", import.meta.url));
const STATUS = readFileSync(new URL("./fixtures/components.json", import.meta.url), "utf8");
const REPO = "melodic-software/claude-code-plugins";
const CHECKS = ".github/workflows/pr-require-checks.yml";
const REVIEW = ".github/workflows/pr-review-hosted.yml";
const SECURITY_REVIEW = ".github/workflows/pr-review-security-hosted.yml";
const HEAD = "1".padStart(40, "0");
const CHILD_TIMEOUT_MS = 20_000;
const STATUS_HOSTS =["www.githubstatus.com", "status.npmjs.org"];

const ago = (minutes) => new Date(Date.now() - minutes * 60_000).toISOString();
const run = (id, workflowPath, { conclusion, status = "completed", jobs }) => ({
  id,
  path: workflowPath,
  event: "pull_request",
  status,
  conclusion: status === "completed" ? conclusion : null,
  run_attempt: 1,
  workflow_id: workflowPath.length,
  head_sha: HEAD,
  created_at: ago(30),
  updated_at: ago(10),
  head_repository: { full_name: REPO },
  jobs,
});
const redChecks = (status) =>
  run(101, CHECKS, {
    conclusion: "failure",
    status,
    jobs: [
      { id: 501, name: "Lint Repo", status: "completed", conclusion: "success", steps: [] },
      {
        id: 502,
        name: "ci-status",
        status: "completed",
        conclusion: "failure",
        steps: [],
        notes: [{ annotation_level: "failure", message: `'pr-review / claude-review-status' did not run on ${HEAD} (https://github.com/o/r/actions/runs/1): ${REVIEW_STOP_NOTE}.` }],
      },
    ],
  });
const gateJob = (runId) => runId * 10 + 2;
const deferredReview = (id, workflowPath, reset) =>
  run(id, workflowPath, {
    conclusion: "success",
    jobs: [
      { id: id * 10 + 1, name: "Resolve Model", status: "completed", conclusion: "success", steps: [] },
      {
        id: gateJob(id),
        name: "Check Kill Switch",
        status: "completed",
        conclusion: "success",
        steps: [
          { name: "Check the kill switch", status: "completed", conclusion: "success" },
          { name: REVIEW_STOP_STEP, status: "completed", conclusion: "success" },
        ],
        notes: [{ annotation_level: "notice", message: `a kill switch stops this review (lanes: kill-switch cause=defer reset=${reset}, CLAUDE_REVIEW_DISABLED: unset)` }],
      },
      { id: id * 10 + 3, name: "PR Review", status: "completed", conclusion: "skipped", steps: [] },
    ],
  });
const pull = {
  number: 1,
  state: "open",
  draft: false,
  auto_merge: null,
  base: { ref: "main" },
  head: { sha: HEAD, ref: "fix/1", repo: { full_name: REPO } },
};
const queued = [
  { checksRunId: 101, reviewRunId: 201, pr: 1, head: HEAD, path: REVIEW },
  { checksRunId: 101, reviewRunId: 301, pr: 1, head: HEAD, path: SECURITY_REVIEW },
];

function answer(runs, url) {
  if (url.pathname.startsWith("/status/")) {
    return JSON.parse(STATUS);
  }
  const route = `${url.pathname}${url.search}`;
  if (route === `/repos/${REPO}/actions/runs?head_sha=${HEAD}&per_page=100`) {
    return { total_count: runs.length, workflow_runs: runs };
  }
  if (route === `/repos/${REPO}/pulls/1`) {
    return pull;
  }
  const jobs = new RegExp(`^/repos/${REPO}/actions/runs/([0-9]+)/jobs\\?filter=latest&per_page=100$`).exec(route);
  const found = jobs && runs.find((r) => r.id === Number(jobs[1]));
  if (found) {
    return { total_count: found.jobs.length, jobs: found.jobs };
  }
  const notes = new RegExp(`^/repos/${REPO}/check-runs/([0-9]+)/annotations\\?per_page=100$`).exec(route);
  if (notes) {
    return runs.flatMap((r) => r.jobs).find((job) => job.id === Number(notes[1]))?.notes ?? [];
  }
  return undefined;
}

const routeStatusPagesTo = (base) =>
  `data:text/javascript,${encodeURIComponent(`const real = globalThis.fetch;
const hosts = new Set(${JSON.stringify(STATUS_HOSTS)});
globalThis.fetch = (input, init) => {
  const url = new URL(String(input));
  return real(hosts.has(url.host) ? ${JSON.stringify(base)} + "/status/" + url.host + url.pathname : input, init);
};`)}`;

async function planStep(rows, runs) {
  const calls = [];
  const server = createServer((req, res) => {
    const url = new URL(req.url, "http://stub");
    calls.push(`${req.method} ${url.pathname}${url.search}`);
    const body = req.method === "GET" ? answer(runs, url) : undefined;
    res.writeHead(body === undefined ? 404 : 200, { "content-type": "application/json" });
    res.end(JSON.stringify(body ?? { message: "Not Found" }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const dir = tempDir("reconcile-followup-main-");
  const files = {
    FOLLOWUP_PATH: path.join(dir, "reconcile-followup.json"),
    PLAN_PATH: path.join(dir, "reconcile-plan.json"),
    RECORD_PATH: path.join(dir, "record.json"),
    GITHUB_OUTPUT: path.join(dir, "output"),
  };
  writeFileSync(files.FOLLOWUP_PATH, JSON.stringify({ run_id: 900, waiting_reviews: rows }));
  writeFileSync(files.GITHUB_OUTPUT, "");
  const env = {
    PATH: process.env.PATH,
    RUNNER_TEMP: dir,
    MODE: "plan",
    FOLLOWUP: "true",
    ...files,
    GH_TOKEN: "stub-token",
    GITHUB_API_URL: base,
    GITHUB_REPOSITORY: REPO,
    KILL_SWITCH: "proceed",
    CLAUDE_REVIEW_DISABLED: "false",
    CLAUDE_SECURITY_REVIEW_DISABLED: "false",
  };
  try {
    const { code, signal, stdout, stderr } = await new Promise((resolve) => {
      execFile(process.execPath, [`--import=${routeStatusPagesTo(base)}`, SCRIPT], { env, timeout: CHILD_TIMEOUT_MS }, (error, out, err) =>
        resolve({ code: error ? error.code : 0, signal: error?.signal ?? null, stdout: out, stderr: err }),
      );
    });
    const plan = existsSync(files.PLAN_PATH) ? JSON.parse(readFileSync(files.PLAN_PATH, "utf8")) : null;
    return { code, signal, stdout: `${stdout}${stderr}`, plan, calls };
  } finally {
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
}

const notices = (stdout) => stdout.split("\n").filter((line) => line.startsWith("::notice title=reconcile::reconcile follow-up tick: "));
const reset = (fromNowS) => Math.floor(Date.now() / 1000) + fromNowS;
const exitedZero = ({ code, signal, stdout }) => {
  assert.equal(signal, null, `the plan step was killed by ${signal} after running past ${CHILD_TIMEOUT_MS} ms:\n${stdout}`);
  assert.equal(code, 0, `the plan step exits 0, not ${code} (13 is a top-level await left unsettled):\n${stdout}`);
};

test("a follow-up tick run as the workflow runs it exits 0 and plans the queued reviews' re-runs", async () => {
  const result = await planStep(queued, [redChecks(), deferredReview(201, REVIEW, reset(-600)), deferredReview(301, SECURITY_REVIEW, reset(-600))]);
  const { stdout, plan, calls } = result;
  exitedZero(result);
  for (const id of [201, 301]) {
    assert.ok(calls.includes(`GET /repos/${REPO}/check-runs/${gateJob(id)}/annotations?per_page=100`), `review run ${id}'s own gate notice is read for its reset`);
  }
  assert.deepEqual(notices(stdout), ["::notice title=reconcile::reconcile follow-up tick: 2 queued, 2 re-run"]);
  assert.deepEqual(
    plan.items.map((item) => [item.kind, item.id, item.path, item.record]),
    [
      ["review", 201, REVIEW, `reconcile-rerun-201-2-${HEAD}`],
      ["review", 301, SECURITY_REVIEW, `reconcile-rerun-301-2-${HEAD}`],
    ],
  );
  assert.equal(plan.failed, 0);
  assert.ok(calls.includes(`GET /repos/${REPO}/actions/runs?head_sha=${HEAD}&per_page=100`), "the queued head is read through the stand-in");
});

test("a follow-up tick with an empty queue exits 0, reads no GitHub route and plans nothing", async () => {
  const result = await planStep([], []);
  const { stdout, plan, calls } = result;
  exitedZero(result);
  assert.deepEqual(notices(stdout), ["::notice title=reconcile::reconcile follow-up tick: 0 queued, 0 re-run"]);
  assert.deepEqual(plan, { items: [], failed: 0 });
  assert.deepEqual(calls.filter((call) => call.includes("/repos/")), []);
});

test("a follow-up tick before the queued reviews' defer reset exits 0 and plans nothing", async () => {
  const result = await planStep(queued, [redChecks(), deferredReview(201, REVIEW, reset(600)), deferredReview(301, SECURITY_REVIEW, reset(600))]);
  const { stdout, plan } = result;
  exitedZero(result);
  assert.deepEqual(notices(stdout), ["::notice title=reconcile::reconcile follow-up tick: 2 queued, 0 re-run"]);
  assert.deepEqual(plan, { items: [], failed: 0 });
  assert.match(stdout, /reconcile: #1: review run 201 \(\.github\/workflows\/pr-review-hosted\.yml\) was deferred on the GITHUB_TOKEN budget; waiting for the rate-limit reset at /);
});
