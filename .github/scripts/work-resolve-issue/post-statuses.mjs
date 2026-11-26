#!/usr/bin/env node
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
import { LANES_APP_LOGIN } from "../lib/lane-vocabulary.mjs";
import { retryApi } from "../lib/retry-fetch.mjs";

const PREP_STEPS = new Set(["review", "verify", "checks"]);
const STEP_STATES = { pass: "success", fail: "failure" };
const rank = (state) => ["failure", "success", null].indexOf(state);

const jobState = (result) => ({ success: "success", failure: "failure" })[result] ?? "error";

const DESCRIPTION = {
  success: "Passed in the work lane run.",
  failure: "Failed in the work lane run.",
  error: "Did not finish, or was not reported, in the work lane run.",
};
const TURN_CAP = "Stopped at the turn cap.";
const FUNDING = "Stopped on the lane's funding.";

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
    const reported = new Map();
    for (const step of Array.isArray(outcome.steps) ? outcome.steps : []) {
      if (PREP_STEPS.has(step?.activity) && (STEP_STATES[step?.result] || step?.result === "skipped")) {
        const state = STEP_STATES[step.result] ?? null;
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

export async function main({ env = process.env, fetch = rateLimitLatch.guard(globalThis.fetch), sleep, log = (line) => console.log(line) } = {}) {
  try {
    if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "")) {
      throw new Error("ISSUE_NUMBER is not an issue number");
    }
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const issue = Number(env.ISSUE_NUMBER);
    const reuse = env.REUSE_BRANCH ?? "";
    if (reuse && !isLaneBranch(reuse, issue)) {
      throw new Error("REUSE_BRANCH is not this issue's lane branch");
    }
    const dir = env.WORK_OUTCOME_DIR ?? "";
    const ran = readBranch(dir, issue);
    const resume = env.RESUME_BRANCH ?? "";
    const resumed =
      !reuse && !ran && resume !== "" && readBranch(dir, issue, "resume") === resume ? resume : "";
    const checks = resumed ? readChecks(env.RUNNER_CHECKS ?? "", { branch: resumed }) : null;
    const repo = `/repos/${env.GITHUB_REPOSITORY}`;
    const github = retryApi({ fetch, apiUrl: env.GITHUB_API_URL || "https://api.github.com", token: env.GH_TOKEN, sleep });
    const headSha = (branch) =>
      github("GET", `${repo}/git/ref/heads/${branch.split("/").map(encodeURIComponent).join("/")}`).then(
        (answer) => answer?.object?.sha,
      );
    let checkedTip;
    if (checksPassed(checks) && (await headSha(resumed).catch(() => "")) === checks.tip) {
      const base = (await github("GET", repo))?.default_branch;
      const comparison = await github("GET", `${repo}/compare/${encodeURIComponent(base)}...${checks.tip}`);
      if (allLaneCommits(listedCommits(comparison), env.LANES_BOT_LOGIN || LANES_APP_LOGIN)) {
        checkedTip = checks.tip;
      }
    }
    const branch = reuse || ran || (checkedTip ? resumed : "");
    if (branch && env.REPORT_RESULT !== "success") {
      log(
        `::notice title=post-statuses::${branch} holds this run's work and report-outcome did not finish (${env.REPORT_RESULT || "no result"}), so it may have no pull request; while no outcome of this run names it, the issue's next run reuses it and opens one`,
      );
    }
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
