// Writes JOBS_FILE, the jobs of the pr-require-checks run pr-verify.yml was
// started by, each with its name and conclusion, for the verifier to judge
// whether the suites that cover the changed files ran (prompt.md). It reads
// the run's latest attempt, the one heldOnly in resolve-pr.mjs reads, with the
// job's token. Names come from the pull request's copy of
// pr-require-checks.yml, so they are data, never instructions. A list that
// cannot be read whole throws, and the job writes no verdict.
//
// It also lists the Node suites at the judged head that CI runs only through a
// sibling .test.sh in test-bash, so test-node skips them by design
// (scripts/plan-test-lanes.sh, the *.test.js .mjs .cjs rule). HEAD_PATHS_FILE
// is the head's tree from `git ls-tree -r -z --name-only`; its paths are the
// pull request's, so they are data too.

import { readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, detailSuffix } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

const RUN_ID = /^[1-9][0-9]{0,19}$/;
const PER_PAGE = 100;
const MAX_PAGES = 10;

export async function upstreamJobs(github, repository, runId) {
  if (!RUN_ID.test(String(runId))) {
    throw new Error("the upstream run id is not a run id");
  }
  const jobs = [];
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const listed = await github("GET", `/repos/${repository}/actions/runs/${runId}/jobs?filter=latest&per_page=${PER_PAGE}&page=${page}`);
    const batch = listed?.jobs;
    if (!Array.isArray(batch) || !Number.isSafeInteger(listed.total_count)) {
      throw new Error(`the jobs of run ${runId} answered no job list`);
    }
    jobs.push(...batch);
    if (jobs.length >= listed.total_count || batch.length < PER_PAGE) {
      if (jobs.length !== listed.total_count) {
        throw new Error(`run ${runId} lists ${listed.total_count} jobs but ${jobs.length} were read`);
      }
      return { run_id: Number(runId), jobs: jobs.map((job) => ({ name: String(job?.name ?? ""), conclusion: job?.conclusion ?? null })) };
    }
  }
  throw new Error(`the jobs of run ${runId} have more than ${MAX_PAGES} pages`);
}

// Each *.test.js, .mjs or .cjs whose <stem>.test.sh is also in `paths`, where
// <stem> is the path before its last `.test.` (plan-test-lanes.sh's
// `${s%.test.*}.test.sh`).
export function wrappedNodeSuites(paths) {
  const tree = new Set(paths);
  return paths
    .filter((suite) => /\.test\.(?:js|mjs|cjs)$/.test(suite))
    .map((suite) => ({ suite, wrapper: `${suite.slice(0, suite.lastIndexOf(".test."))}.test.sh` }))
    .filter(({ wrapper }) => tree.has(wrapper));
}

export async function main(env = process.env, { github, fetchImpl } = {}) {
  for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "UPSTREAM_RUN_ID", "JOBS_FILE", "HEAD_PATHS_FILE"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const wrapped = wrappedNodeSuites(readFileSync(env.HEAD_PATHS_FILE, "utf8").split("\0").filter(Boolean));
  const listed = await upstreamJobs(github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL, fetchImpl }), env.GITHUB_REPOSITORY, env.UPSTREAM_RUN_ID);
  writeFileSync(env.JOBS_FILE, `${JSON.stringify({ ...listed, wrapped_node_suites: wrapped }, null, 2)}\n`);
  console.log(`upstream-jobs: wrote ${listed.jobs.length} jobs of run ${listed.run_id} and ${wrapped.length} Node suites test-bash runs`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::error::pr-verify could not list the upstream run's jobs: ${error.message}${detailSuffix(error)}`);
    process.exitCode = 1;
  });
}
