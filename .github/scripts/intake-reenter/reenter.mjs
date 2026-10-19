#!/usr/bin/env node
// reenter.mjs: sends an answered issue back to intake triage. On a new
// comment on an open issue (never a pull request):
//
// - `status: needs-decision` and a decision comment (select-trusted-text's
//   isDecisionComment, the rule write-issue.mjs marks `decision: true` by):
//   remove `status: needs-decision` and `needs-human`;
// - `status: needs-info` and a comment by the issue's author or a listed
//   human, not posted through an App: remove `status: needs-info`;
//
// then add `needs-triage` and dispatch intake-triage.yml once. Anything else
// changes nothing. It never adds `agent-ready`. Removing the status label is
// the claim: when GitHub answers 404 another run already took it, so a second
// answer, or a racing run, dispatches nothing. Every fact is read from the API;
// the event supplies only the issue and comment numbers.
//
// Environment:
//   GITHUB_TOKEN          the job's token: issues write, actions write
//   GITHUB_REPOSITORY     owner/repo
//   ISSUE_NUMBER, COMMENT_ID
//   TRUSTED_ACTORS_PATH   the default branch's trusted-actor list
//   LANES_APP_ID          the lanes App bot's user id, or empty
//   KILL_SWITCH           `proceed`, or the run stops before any API call
//   GITHUB_API_URL
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, GitHubError, loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { isDecisionComment, selectTrustedIssueComments } from "../../actions/select-trusted-text/select-trusted-text.mjs";

export const NEEDS_DECISION = "status: needs-decision";
export const NEEDS_INFO = "status: needs-info";
export const NEEDS_HUMAN = "needs-human";
export const NEEDS_TRIAGE = "needs-triage";
const WORKFLOW = "intake-triage.yml";
const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPOSITORY = /^[A-Za-z0-9-]+\/(?!\.\.?$)[A-Za-z0-9_.-]+$/;

const labelNames = (issue) => (issue.labels ?? []).map((label) => (typeof label === "string" ? label : label?.name));

// Which answer the comment is, or null: `decision` or `info`.
export async function classify({ github, repository, issue, comment, humans, ids, lanesAppId }) {
  if (issue.pull_request || issue.state !== "open") {
    return null;
  }
  const user = comment.user ?? {};
  if (user.type !== "User" || user.id === lanesAppId || comment.performed_via_github_app != null) {
    return null;
  }
  const labels = labelNames(issue);
  const kept = async () => {
    const { kept: list } = await selectTrustedIssueComments({ github, repository, issueNumber: issue.number, ids });
    return list.find((item) => item.comment.id === comment.id) ?? null;
  };
  if (labels.includes(NEEDS_DECISION) && humans.has(user.id)) {
    const item = await kept();
    if (item && isDecisionComment(item, humans)) {
      return "decision";
    }
  }
  if (labels.includes(NEEDS_INFO)) {
    if (user.id === issue.user?.id) {
      return "info";
    }
    if (humans.has(user.id) && (await kept())) {
      return "info";
    }
  }
  return null;
}

async function removeLabel(github, base, name) {
  try {
    await github("DELETE", `${base}/labels/${encodeURIComponent(name)}`);
    return true;
  } catch (error) {
    if (error instanceof GitHubError && error.status === 404) {
      return false;
    }
    throw error;
  }
}

export async function main({ env = process.env, github, log = console.log } = {}) {
  try {
    if (env.KILL_SWITCH !== "proceed") {
      log("intake-reenter: the kill switch stops this run; nothing read or labeled");
      return 0;
    }
    if (!NUMBER.test(env.ISSUE_NUMBER ?? "") || !/^[1-9][0-9]{0,15}$/.test(env.COMMENT_ID ?? "") || !REPOSITORY.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("ISSUE_NUMBER, COMMENT_ID or GITHUB_REPOSITORY is malformed");
    }
    const lanesAppId = /^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "") ? Number(env.LANES_APP_ID) : null;
    const { ids, humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const repository = env.GITHUB_REPOSITORY;
    const base = `/repos/${repository}/issues/${env.ISSUE_NUMBER}`;
    const issue = await client("GET", base);
    const comment = await client("GET", `/repos/${repository}/issues/comments/${env.COMMENT_ID}`);
    if (comment.issue_url !== undefined && !String(comment.issue_url).endsWith(base)) {
      throw new Error("the comment is not on the issue");
    }
    const kind = await classify({ github: client, repository, issue, comment, humans, ids, lanesAppId });
    if (!kind) {
      log("intake-reenter: not an answer to a parked issue; nothing changed");
      return 0;
    }
    const status = kind === "decision" ? NEEDS_DECISION : NEEDS_INFO;
    if (!(await removeLabel(client, base, status))) {
      log(`intake-reenter: ${status} is already gone; nothing dispatched`);
      return 0;
    }
    await client("POST", `${base}/labels`, { labels: [NEEDS_TRIAGE] });
    if (kind === "decision") {
      await removeLabel(client, base, NEEDS_HUMAN);
    }
    await client("POST", `/repos/${repository}/actions/workflows/${WORKFLOW}/dispatches`, {
      ref: "main",
      inputs: { "issue-number": String(issue.number) },
    });
    log(`intake-reenter: removed ${status}, added ${NEEDS_TRIAGE}, dispatched ${WORKFLOW}`);
    return 0;
  } catch (error) {
    const detail = error?.name === "GitHubError" ? error.message : (error?.message ?? "error");
    log(`::error title=intake-reenter::${String(detail).replaceAll(/[\r\n%]/g, " ")}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
