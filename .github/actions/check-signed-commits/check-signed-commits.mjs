// Post-model check for CI lanes: every commit the lane added after the
// recorded head must be GitHub-verified. On any unverified commit it adds the
// escalation label (only if the repository already has it) and posts one
// fixed comment listing the SHAs. It never rewrites or force-pushes.
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { createGitHub, paginate, readPull, REPOSITORY } from "../check-trusted-trigger/check-trusted-trigger.mjs";

const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
const SHA = /^[0-9a-f]{40}$/;
const LISTED_COMMITS_CAP = 250;
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// The comparison `sinceSha...headSha` when `sinceSha` is a well-formed SHA
// GitHub knows as an ancestor of the head; otherwise null. `complete` is false
// when the comparison lists fewer commits than it counts (it lists at most 250
// unpaged).
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
  const commits = Array.isArray(comparison.commits) ? comparison.commits : [];
  const complete =
    Array.isArray(comparison.commits) &&
    Number.isInteger(comparison.total_commits) &&
    comparison.total_commits <= commits.length;
  return { commits, complete };
}

// The lane's commits and whether they could all be read. A complete comparison
// from an ancestor `sinceSha` lists them; its commit objects carry the
// verification read. The PR list (at most 250) then only drops base commits a
// merge brought in, and only when it holds the whole PR: a capped list would
// drop lane commits it never listed. Anything else checks every PR commit,
// which is whole only when the PR list is.
function laneCommits(comparison, prCommits, prListComplete) {
  if (comparison?.complete) {
    if (!prListComplete) {
      return { commits: comparison.commits, checkable: true };
    }
    const inPr = new Set(prCommits.map((commit) => commit.sha));
    return {
      commits: comparison.commits.filter((commit) => inPr.has(commit.sha)),
      checkable: true,
    };
  }
  return { commits: prCommits, checkable: prListComplete };
}

function escalationComment({ unverified, sinceIsAncestor, checkable, countKnown, headConfirmed }) {
  const lines = [
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

export async function checkSignedCommits({
  github,
  repository,
  prNumber,
  sinceSha,
  sleep = delay,
}) {
  const base = `/repos/${repository}`;
  const { pull, headConfirmed } = await readPull(github, base, prNumber, sleep);
  const prCommits = await paginate(github, `${base}/pulls/${prNumber}/commits`);
  // The PR commit list stops at LISTED_COMMITS_CAP; it holds the whole PR only
  // when the PR's commit count says so.
  const countKnown = Number.isInteger(pull.commits);
  const prListComplete = countKnown && pull.commits <= prCommits.length;
  const comparison = headConfirmed
    ? await compareSince(github, base, sinceSha, pull.head.sha)
    : null;
  const lane = laneCommits(comparison, prCommits, prListComplete);
  const { commits } = lane;
  const checkable = headConfirmed && lane.checkable;
  // A commit whose SHA is malformed cannot be named safely, so it counts as
  // unverified and is reported as `<invalid-sha>`, never echoed.
  const unverified = commits
    .filter(
      (commit) => !SHA.test(commit.sha ?? "") || commit.commit?.verification?.verified !== true,
    )
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

// Adds the escalation label (only if the repository already has it) and posts
// one fixed comment.
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

// Returns the process exit code: 0 once the check ran (whatever it found) and
// any escalation was posted, 1 otherwise. The outputs are written before the
// escalation, so a failed escalation write still leaves all-verified=false.
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
        log(`::error::check-signed-commits: escalation failed (${errorDetail(error)})`);
        return 1;
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
