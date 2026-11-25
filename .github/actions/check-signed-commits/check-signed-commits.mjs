import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { createGitHub, paginate } from "../../scripts/lib/github-client.mjs";
import { readPull, REPOSITORY } from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { SIGNED_COMMITS_HOLD } from "../../scripts/pr-unblock/gate-source.mjs";

export { SIGNED_COMMITS_HOLD };

const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
const SHA = /^[0-9a-f]{40}$/;
const LISTED_COMMITS_CAP = 250;

// Compare returns at most 250 commits unpaged: https://docs.github.com/en/rest/commits/commits#compare-two-commits
async function compareSince(github, base, sinceSha, headSha) {
  if (!SHA.test(sinceSha ?? "")) {
    return null;
  }
  let comparison;
  try {
    comparison = await github("GET", `${base}/compare/${sinceSha}...${headSha}`);
  } catch (error) {
    if (error?.status === 404) {
      return null;
    }
    throw error;
  }
  if (comparison.status !== "ahead" && comparison.status !== "identical") {
    return null;
  }
  if (!Array.isArray(comparison.commits)) {
    return { commits: [], complete: false };
  }
  const { commits, total_commits: total } = comparison;
  return { commits, complete: Number.isInteger(total) && total <= commits.length };
}

function laneCommits(comparison, prCommits, prListComplete) {
  if (!comparison?.complete) {
    return { commits: prCommits, checkable: prListComplete };
  }
  if (!prListComplete) {
    return { commits: comparison.commits, checkable: true };
  }
  const inPr = new Set(prCommits.map((commit) => commit.sha));
  return { commits: comparison.commits.filter((commit) => inPr.has(commit.sha)), checkable: true };
}

function escalationComment({ unverified, sinceIsAncestor, checkable, countKnown, headConfirmed }) {
  const lines = [
    SIGNED_COMMITS_HOLD,
    unverified.length > 0
      ? "Lane commit check: these commits are not GitHub-verified, so no lane continues on this " +
        "pull request until a human reviews them."
      : "Lane commit check: the lane's commits could not be verified, so no lane continues on " +
        "this pull request until a human reviews them.",
  ];
  if (!headConfirmed) {
    lines.push(
      "",
      "The pull request's head did not match its branch, so the lane's commits cannot be checked.",
    );
  } else if (!checkable) {
    lines.push(
      "",
      countKnown
        ? `This pull request has more commits than GitHub lists (${LISTED_COMMITS_CAP}), so its ` +
            "commits cannot all be checked."
        : "GitHub did not report how many commits this pull request has, so its commits cannot " +
            "all be checked.",
    );
  }
  if (headConfirmed && !sinceIsAncestor) {
    lines.push(
      "",
      "The head recorded before the lane ran is not an ancestor of the current head, so every " +
        `${checkable ? "" : "listed "}commit on the pull request was checked.`,
    );
  }
  if (unverified.length > 0) {
    lines.push("", ...unverified.map((sha) => `- \`${sha}\``));
  }
  return lines.join("\n");
}

export async function checkSignedCommits({ github, repository, prNumber, sinceSha, sleep = delay }) {
  const base = `/repos/${repository}`;
  const { pull, headConfirmed } = await readPull(github, base, prNumber, sleep);
  const prCommits = await paginate(github, `${base}/pulls/${prNumber}/commits`);
  const countKnown = Number.isInteger(pull.commits);
  const prListComplete = countKnown && pull.commits <= prCommits.length;
  const comparison = headConfirmed ? await compareSince(github, base, sinceSha, pull.head.sha) : null;
  const lane = laneCommits(comparison, prCommits, prListComplete);
  const checkable = headConfirmed && lane.checkable;
  const unverified = lane.commits
    .filter((commit) => !SHA.test(commit.sha ?? "") || commit.commit?.verification?.verified !== true)
    .map((commit) => (SHA.test(commit.sha ?? "") ? commit.sha : "<invalid-sha>"));
  return {
    allVerified: checkable && unverified.length === 0,
    unverified,
    sinceIsAncestor: comparison !== null,
    checkable,
    countKnown,
    headConfirmed,
  };
}

export async function escalate({ github, repository, prNumber, label, result }) {
  const base = `/repos/${repository}`;
  const labels = await paginate(github, `${base}/labels`);
  if (labels.some((existing) => existing.name === label)) {
    await github("POST", `${base}/issues/${prNumber}/labels`, { labels: [label] });
  }
  await github("POST", `${base}/issues/${prNumber}/comments`, {
    body: escalationComment(result),
  });
}

const errorDetail = (error) =>
  error?.name === "GitHubError" ? error.message : (error?.name ?? "error");

export async function main({ env = process.env, github, log = console.log, sleep } = {}) {
  try {
    if (!PR_NUMBER.test(env.PR_NUMBER ?? "") || !REPOSITORY.test(env.REPOSITORY ?? "")) {
      throw new Error("pr-number or repository is malformed");
    }
    const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL });
    const target = { github: client, repository: env.REPOSITORY, prNumber: env.PR_NUMBER };
    const result = await checkSignedCommits({ ...target, sinceSha: env.SINCE_SHA, sleep });
    writeOutputs(
      {
        "all-verified": String(result.allVerified),
        unverified: result.unverified.join(" "),
        "since-is-ancestor": String(result.sinceIsAncestor),
      },
      env.GITHUB_OUTPUT,
    );
    if (result.headConfirmed && !result.sinceIsAncestor) {
      log("check-signed-commits: no comparison from the recorded head; checked the PR's commits");
    }
    if (result.allVerified) {
      log("check-signed-commits: every new commit is verified");
    } else if (result.unverified.length > 0) {
      log(`::warning::check-signed-commits: unverified commits ${result.unverified.join(" ")}`);
    } else {
      log(
        `::warning::check-signed-commits: could not verify the lane's commits (${
          result.headConfirmed
            ? "the PR's commits could not all be listed"
            : "the PR's head never matched its branch"
        })`,
      );
    }
    if (!result.allVerified) {
      try {
        await escalate({ ...target, label: env.ESCALATION_LABEL || "needs-human", result });
      } catch (error) {
        if (result.unverified.length > 0 || error?.name !== "GitHubError") {
          log(`::error::check-signed-commits: escalation failed (${errorDetail(error)})`);
          return 1;
        }
        log(`::warning::check-signed-commits: escalation refused (${errorDetail(error)})`);
      }
    }
    return 0;
  } catch (error) {
    log(`::error::check-signed-commits: could not run (${errorDetail(error)})`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
