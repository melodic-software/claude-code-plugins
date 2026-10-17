#!/usr/bin/env node
// post-statuses.mjs: posts one `pipeline/<activity>` commit status per step of
// the work-resolve-issue lane on the lane branch's head SHA. The statuses
// skip nothing; a failing one holds the merge gate. resolve-issue and
// report-outcome come from their job results; the run's prep steps
// (`review`, `verify`, `checks`) as the run reported them in
// work-outcome.json. Descriptions are fixed text, never the run's words.
//
// Environment:
//   GH_TOKEN            the job's GITHUB_TOKEN, with statuses: write
//   GITHUB_REPOSITORY   owner/repo
//   ISSUE_NUMBER        the issue the lane worked
//   WORK_OUTCOME_DIR    holds work-outcome.json and lane.json
//   REUSE_BRANCH        the lane branch an earlier run left that resolve-issue
//                       reused instead of running the model, or empty; its
//                       outcome counts only when lane.json names it
//   RESOLVE_RESULT      the resolve-issue job's result
//   REPORT_RESULT       the report-outcome job's result
//   GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { isLaneBranch, readBranch, readOutcome } from "./report-outcome.mjs";

const PREP_STEPS = new Set(["review", "verify", "checks"]);
const STEP_STATES = { pass: "success", fail: "failure" };

const jobState = (result) => ({ success: "success", failure: "failure" })[result] ?? "error";

const DESCRIPTION = {
  success: "Passed in the work lane run.",
  failure: "Failed in the work lane run.",
  error: "Did not finish, or was not reported, in the work lane run.",
};

// The statuses to post, in order; none without a lane branch. A null outcome
// is a reused branch whose run's report this run never read: every step but
// report-outcome posts error.
export function plan({ outcome, branch, resolveResult, reportResult }) {
  if (!branch) {
    return [];
  }
  if (outcome === null) {
    return ["resolve-issue", "report-outcome", ...PREP_STEPS].map((activity) => {
      const state = activity === "report-outcome" ? jobState(reportResult) : "error";
      return { context: `pipeline/${activity}`, state, description: DESCRIPTION[state] };
    });
  }
  const resolve = jobState(resolveResult);
  const states = new Map([
    ["resolve-issue", resolve === "success" && outcome.exit !== "done" ? "failure" : resolve],
    ["report-outcome", jobState(reportResult)],
  ]);
  if (outcome.exit === "done") {
    // A prep step the run never reported fails closed as error; one it
    // reported `skipped` (prep skips steps a docs-only change does not owe)
    // posts nothing.
    const reported = new Map();
    for (const step of Array.isArray(outcome.steps) ? outcome.steps : []) {
      if (PREP_STEPS.has(step?.activity) && (STEP_STATES[step?.result] || step?.result === "skipped")) {
        // A step reported twice keeps its strictest result: fail over pass over skipped.
        const state = STEP_STATES[step.result] ?? null;
        const rank = (value) => ["failure", "success", null].indexOf(value);
        if (!reported.has(step.activity) || rank(state) < rank(reported.get(step.activity))) {
          reported.set(step.activity, state);
        }
      }
    }
    for (const activity of PREP_STEPS) {
      const state = reported.has(activity) ? reported.get(activity) : "error";
      if (state) {
        states.set(activity, state);
      }
    }
  }
  return [...states].map(([activity, state]) => ({
    context: `pipeline/${activity}`,
    state,
    description: DESCRIPTION[state],
  }));
}

function api({ fetch, apiUrl, token }) {
  return async (method, path, body) => {
    const response = await fetch(`${apiUrl}${path}`, {
      method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (!response.ok) {
      throw new Error(`${method} ${path} answered ${response.status}`);
    }
    return response.json();
  };
}

export async function main({ env = process.env, fetch = globalThis.fetch } = {}) {
  try {
    if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "")) {
      throw new Error("ISSUE_NUMBER is not an issue number");
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const reuse = env.REUSE_BRANCH ?? "";
    if (reuse && !isLaneBranch(reuse, Number(env.ISSUE_NUMBER))) {
      throw new Error("REUSE_BRANCH is not this issue's lane branch");
    }
    const dir = env.WORK_OUTCOME_DIR ?? "";
    const ran = readBranch(dir, Number(env.ISSUE_NUMBER));
    const branch = reuse || ran;
    const statuses = plan({
      outcome: reuse && ran !== reuse ? null : readOutcome(join(dir, "work-outcome.json")),
      branch,
      resolveResult: env.RESOLVE_RESULT,
      reportResult: env.REPORT_RESULT,
    });
    if (!statuses.length) {
      console.log("post-statuses: no lane branch, so no status is posted");
      return 0;
    }
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const github = api({ fetch, apiUrl: env.GITHUB_API_URL || "https://api.github.com", token: env.GH_TOKEN });
    const ref = branch.split("/").map(encodeURIComponent).join("/");
    const sha = (await github("GET", `${repo}/git/ref/heads/${ref}`))?.object?.sha;
    if (!/^[0-9a-f]{40}$/.test(sha ?? "")) {
      throw new Error(`no head SHA read for ${branch}`);
    }
    const targetUrl =
      env.GITHUB_SERVER_URL && env.GITHUB_RUN_ID
        ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`
        : undefined;
    for (const status of statuses) {
      await github("POST", `${repo}/statuses/${sha}`, { ...status, target_url: targetUrl });
    }
    console.log(`post-statuses: posted ${statuses.length} statuses on ${sha}`);
    return 0;
  } catch (error) {
    console.log(`::error title=post-statuses::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
