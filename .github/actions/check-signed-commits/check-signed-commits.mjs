// Post-model check for CI lanes: every commit added to the PR after the
// recorded head must be GitHub-verified. On any unverified commit it adds the
// escalation label (only if the repository already has it) and posts one
// fixed comment listing the SHAs. It never rewrites or force-pushes.
import process from "node:process";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../check-kill-switch/check-kill-switch.mjs";
import { createGitHub, paginate } from "../check-trusted-trigger/check-trusted-trigger.mjs";

const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
const REPOSITORY = /^[A-Za-z0-9-]+\/(?!\.\.?$)[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const LISTED_COMMITS_CAP = 250;

// The PR commits that are new since `sinceSha`. When `sinceSha` is not a
// known ancestor of the head, every PR commit counts as new.
async function newCommits(github, base, prCommits, sinceSha, headSha) {
  if (!SHA.test(sinceSha ?? "")) {
    return { commits: prCommits, sinceIsAncestor: false };
  }
  let comparison;
  try {
    comparison = await github("GET", `${base}/compare/${sinceSha}...${headSha}`);
  } catch (error) {
    if (error?.status === 404) {
      return { commits: prCommits, sinceIsAncestor: false };
    }
    throw error;
  }
  const ancestor = comparison.status === "ahead" || comparison.status === "identical";
  if (!ancestor) {
    return { commits: prCommits, sinceIsAncestor: false };
  }
  if (comparison.total_commits > comparison.commits.length) {
    return { commits: prCommits, sinceIsAncestor: true };
  }
  // The comparison's own commit objects carry the verification read; the PR
  // list only decides which of them belong to the PR (not merged-in base).
  const inPr = new Set(prCommits.map((commit) => commit.sha));
  return {
    commits: comparison.commits.filter((commit) => inPr.has(commit.sha)),
    sinceIsAncestor: true,
  };
}

function escalationComment(unverified, sinceIsAncestor, complete) {
  const lines = [
    "Lane commit check: these commits on this pull request are not GitHub-verified, so no lane " +
      "continues on it until a human reviews them.",
  ];
  if (!complete) {
    lines.push(
      "",
      `This pull request has more commits than GitHub lists (${LISTED_COMMITS_CAP}), so its ` +
        "commits cannot all be checked.",
    );
  }
  if (!sinceIsAncestor) {
    lines.push(
      "",
      "The head recorded before the lane ran is not an ancestor of the current head, so every " +
        "commit on the pull request was checked.",
    );
  }
  if (unverified.length > 0) {
    lines.push("", ...unverified.map((sha) => `- \`${sha}\``));
  }
  return lines.join("\n");
}

export async function checkSignedCommits({ github, repository, prNumber, sinceSha, label }) {
  const base = `/repos/${repository}`;
  const pull = await github("GET", `${base}/pulls/${prNumber}`);
  const prCommits = await paginate(github, `${base}/pulls/${prNumber}/commits`);
  const { commits, sinceIsAncestor } = await newCommits(
    github,
    base,
    prCommits,
    sinceSha,
    pull.head.sha,
  );
  // A commit whose SHA is malformed cannot be named safely, so it counts as
  // unverified and is reported as `<invalid-sha>`, never echoed.
  const unverified = commits
    .filter(
      (commit) => !SHA.test(commit.sha ?? "") || commit.commit?.verification?.verified !== true,
    )
    .map((commit) => (SHA.test(commit.sha ?? "") ? commit.sha : "<invalid-sha>"));
  // The PR commit list stops at LISTED_COMMITS_CAP; a PR with more (or with
  // no count) cannot be checked whole, which fails closed.
  const complete = Number.isInteger(pull.commits) && pull.commits <= prCommits.length;
  const allVerified = complete && unverified.length === 0;
  if (!allVerified) {
    const labels = await paginate(github, `${base}/labels`);
    if (labels.some((existing) => existing.name === label)) {
      await github("POST", `${base}/issues/${prNumber}/labels`, { labels: [label] });
    }
    await github("POST", `${base}/issues/${prNumber}/comments`, {
      body: escalationComment(unverified, sinceIsAncestor, complete),
    });
  }
  return { allVerified, unverified, sinceIsAncestor };
}

// Returns the process exit code: 0 once the check ran (whatever it found),
// 1 when it could not run, with no outputs written.
export async function main({ env = process.env, github, log = console.log } = {}) {
  try {
    if (!PR_NUMBER.test(env.PR_NUMBER ?? "") || !REPOSITORY.test(env.REPOSITORY ?? "")) {
      throw new Error("pr-number or repository is malformed");
    }
    const result = await checkSignedCommits({
      github: github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
      repository: env.REPOSITORY,
      prNumber: env.PR_NUMBER,
      sinceSha: env.SINCE_SHA,
      label: env.ESCALATION_LABEL || "needs-human",
    });
    writeOutputs(
      {
        "all-verified": String(result.allVerified),
        unverified: result.unverified.join(" "),
        "since-is-ancestor": String(result.sinceIsAncestor),
      },
      env.GITHUB_OUTPUT,
    );
    if (!result.sinceIsAncestor) {
      log("check-signed-commits: the recorded head is not an ancestor; checked every PR commit");
    }
    log(
      result.allVerified
        ? "check-signed-commits: every new commit is verified"
        : `::warning::check-signed-commits: unverified commits ${result.unverified.join(" ")}`,
    );
    return 0;
  } catch (error) {
    const detail = error?.name === "GitHubError" ? error.message : (error?.name ?? "error");
    log(`::error::check-signed-commits: could not run (${detail})`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
