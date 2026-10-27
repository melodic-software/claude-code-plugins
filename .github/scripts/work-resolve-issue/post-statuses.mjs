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
//   RESUME_BRANCH       the earlier run's lane branch resolve-issue resumed
//                       (issue-prior's output), or empty
//   RUNNER_CHECKS       the run-checks job's output, or empty
//   LANES_BOT_LOGIN     the lanes App bot login (default
//                       melodic-automation-lanes[bot])
//   RESOLVE_RESULT      the resolve-issue job's result
//   REPORT_RESULT       the report-outcome job's result
//   GITHUB_API_URL, GITHUB_SERVER_URL, GITHUB_RUN_ID
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import {
  allLaneCommits,
  checksPassed,
  isLaneBranch,
  listedCommits,
  readBranch,
  readChecks,
  readFunding,
  readOutcome,
  readTurnCap,
} from "./report-outcome.mjs";
import { retryFetch } from "./retry-fetch.mjs";

const PREP_STEPS = new Set(["review", "verify", "checks"]);
const STEP_STATES = { pass: "success", fail: "failure" };

const jobState = (result) => ({ success: "success", failure: "failure" })[result] ?? "error";

const DESCRIPTION = {
  success: "Passed in the work lane run.",
  failure: "Failed in the work lane run.",
  error: "Did not finish, or was not reported, in the work lane run.",
};
const TURN_CAP = "Stopped at the turn cap.";
const FUNDING = "Stopped on the lane's funding.";

// The statuses to post, in order; none without a lane branch. A null outcome
// is a reused branch whose run's report this run never read: only this run's
// report-outcome posts, so the statuses the earlier run posted on the same
// head stand. `turnCap` and `funding` are the runner's records, which name the
// cause only for a run that left no outcome of its own; funding wins.
export function plan({ outcome, branch, resolveResult, reportResult, turnCap = null, funding = null }) {
  if (!branch) {
    return [];
  }
  if (outcome === null) {
    const state = jobState(reportResult);
    return [{ context: "pipeline/report-outcome", state, description: DESCRIPTION[state] }];
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
  const cause = outcome.unread === true ? (funding !== null ? FUNDING : turnCap !== null ? TURN_CAP : null) : null;
  return [...states].map(([activity, state]) => ({
    context: `pipeline/${activity}`,
    state,
    description: cause && activity === "resolve-issue" ? cause : DESCRIPTION[state],
  }));
}

// A read, and a write marked safeToResend, is sent again after a network
// error or a 5xx (retry-fetch.mjs), each attempt through the rate guard.
function api({ fetch, apiUrl, token, sleep }) {
  const send = retryFetch(fetch, { sleep });
  return async (method, path, body, { safeToResend = false } = {}) => {
    const response = await send(`${apiUrl}${path}`, {
      method,
      safeToResend,
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

// Every call goes through the rate guard (rate-guard.mjs).
export async function main({ env = process.env, fetch = rateLimitLatch.guard(globalThis.fetch), sleep } = {}) {
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
    // A resumed run that committed nothing has its PR opened from the branch
    // it resumed, at the tip run-checks checked, so its statuses go on that
    // tip, under report-outcome's gate: lane.json's resume (rewritable) is
    // the runner's, a check ran and none failed, and every commit ahead of
    // the default branch is the lanes App's, and the branch is still at that
    // tip (one that cannot be read is not). Otherwise none is posted.
    const resume = env.RESUME_BRANCH ?? "";
    const resumed =
      !reuse && !ran && resume !== "" && readBranch(dir, Number(env.ISSUE_NUMBER), "resume") === resume ? resume : "";
    const checks = resumed ? readChecks(env.RUNNER_CHECKS ?? "", { branch: resumed }) : null;
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const github = api({ fetch, apiUrl: env.GITHUB_API_URL || "https://api.github.com", token: env.GH_TOKEN, sleep });
    const headSha = (branch) =>
      github("GET", `${repo}/git/ref/heads/${branch.split("/").map(encodeURIComponent).join("/")}`).then(
        (answer) => answer?.object?.sha,
      );
    let checkedTip;
    if (checksPassed(checks) && (await headSha(resumed).catch(() => "")) === checks.tip) {
      const base = (await github("GET", repo))?.default_branch;
      const comparison = await github("GET", `${repo}/compare/${encodeURIComponent(base)}...${checks.tip}`);
      if (allLaneCommits(listedCommits(comparison), env.LANES_BOT_LOGIN || "melodic-automation-lanes[bot]")) {
        checkedTip = checks.tip;
      }
    }
    const branch = reuse || ran || (checkedTip ? resumed : "");
    // On a reuse, an outcome this run cannot read counts as none, as in
    // report-outcome: the earlier run's statuses on the branch stand.
    const own = reuse && ran !== reuse ? null : readOutcome(join(dir, "work-outcome.json"));
    const statuses = plan({
      outcome: reuse && own?.unread ? null : own,
      branch,
      resolveResult: env.RESOLVE_RESULT,
      reportResult: env.REPORT_RESULT,
      turnCap: readTurnCap(dir),
      funding: readFunding(dir),
    });
    if (!statuses.length) {
      console.log("post-statuses: no lane branch, so no status is posted");
      return 0;
    }
    const sha = checkedTip ?? (await headSha(branch));
    if (!/^[0-9a-f]{40}$/.test(sha ?? "")) {
      throw new Error(`no head SHA read for ${branch}`);
    }
    const targetUrl =
      env.GITHUB_SERVER_URL && env.GITHUB_RUN_ID
        ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`
        : undefined;
    // A context's newest status is the one that counts, so a resend leaves
    // the same state.
    for (const status of statuses) {
      await github("POST", `${repo}/statuses/${sha}`, { ...status, target_url: targetUrl }, { safeToResend: true });
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
