// Expected values come from docs/conventions/pr-pipeline/README.md ("Verifier
// verdict", upstream-jobs.json): each judging job writes the jobs of the
// pr-require-checks run it was started by, each with its name and
// conclusion, and a list read short writes nothing. The
// list endpoint pages at most 100 jobs and reports total_count
// (https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run).
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { main, upstreamJobs } from "./upstream-jobs.mjs";

const REPO = "melodic-software/claude-code-plugins";
const RUN = 4242;
const job = (n, conclusion = "success") => ({ id: n, name: `job-${n}`, conclusion, steps: [{ name: "x" }] });

// A GitHub that serves `all` in pages of 100 and records each path.
const paged = (all, total = all.length) => {
  const paths = [];
  const github = async (method, apiPath) => {
    paths.push(apiPath);
    assert.equal(method, "GET");
    const page = Number(/[?&]page=(\d+)$/.exec(apiPath)[1]);
    return { total_count: total, jobs: all.slice((page - 1) * 100, page * 100) };
  };
  return { github, paths };
};

test("every page of the run's latest jobs is read, keeping only each name and conclusion", async () => {
  const all = [...Array.from({ length: 100 }, (_, i) => job(i + 1)), job(101, "skipped"), { id: 102, name: "ci-status", conclusion: null }];
  const { github, paths } = paged(all);
  const listed = await upstreamJobs(github, REPO, RUN);
  assert.deepEqual(paths, [1, 2].map((page) => `/repos/${REPO}/actions/runs/${RUN}/jobs?filter=latest&per_page=100&page=${page}`));
  assert.equal(listed.run_id, RUN);
  assert.equal(listed.jobs.length, 102);
  assert.deepEqual(listed.jobs.at(0), { name: "job-1", conclusion: "success" });
  assert.deepEqual(listed.jobs.slice(-2), [
    { name: "job-101", conclusion: "skipped" },
    { name: "ci-status", conclusion: null },
  ]);
});

test("a list read short of its total_count, or with no job list, throws", async () => {
  await assert.rejects(upstreamJobs(paged([job(1)], 2).github, REPO, RUN), /lists 2 jobs but 1 were read/);
  await assert.rejects(
    upstreamJobs(async () => ({ message: "Not Found" }), REPO, RUN),
    /answered no job list/,
  );
  await assert.rejects(upstreamJobs(paged([]).github, REPO, "12; rm"), /not a run id/);
});

test("main writes the list to JOBS_FILE, and writes nothing when the read fails", async () => {
  const dir = tempDir("pr-verify-upstream-jobs-");
  const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPO, UPSTREAM_RUN_ID: String(RUN), JOBS_FILE: path.join(dir, "upstream-jobs.json") };
  await main(env, { github: paged([job(1), job(2, "failure")]).github });
  assert.deepEqual(JSON.parse(readFileSync(env.JOBS_FILE, "utf8")), {
    run_id: RUN,
    jobs: [
      { name: "job-1", conclusion: "success" },
      { name: "job-2", conclusion: "failure" },
    ],
  });
  const short = { ...env, JOBS_FILE: path.join(dir, "short.json") };
  await assert.rejects(main(short, { github: paged([job(1)], 3).github }));
  assert.equal(existsSync(short.JOBS_FILE), false);
  await assert.rejects(main({ ...env, JOBS_FILE: "" }, { github: paged([]).github }), /JOBS_FILE is not set/);
});
