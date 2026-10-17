// Resolves the pull request a pr-require-checks run passed, for pr-verify.yml.
// The only event field it takes is the upstream run id; every other fact is
// read back from the API. It proceeds only when all of these hold, and
// otherwise writes proceed=false with a reason:
// - the run is a completed, successful pull_request run of
//   pr-require-checks.yml, by exact path, in this repository on a head of
//   this repository;
// - exactly one open PR into main has that run's head SHA as its current head
//   and its head in this repository;
// - the PR is not a draft and not a dependency manager's;
// - no counted verdict for that PR and head exists yet: an unexpired
//   pr-verify-<pr>-<head>-<verdict> artifact of a successful pr-verify.yml
//   workflow_run run on main in this repository.
// The head SHA is the run's, never the PR's live head.

import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const UPSTREAM_PATH = ".github/workflows/pr-require-checks.yml";
export const VERIFY_PATH = ".github/workflows/pr-verify.yml";
export const VERDICTS = Object.freeze(["pass", "pass-notes", "fail"]);
// dependabot[bot] (.github/standards/trusted-actors/trusted-actors.json): the
// pr-merge lane refuses its pull requests before reading a verdict.
export const DEPENDABOT_ID = 49699333;

const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;

async function judged({ github, repository, number, head, base }) {
  for (const verdict of VERDICTS) {
    const name = `pr-verify-${number}-${head}-${verdict}`;
    const listing = await github("GET", `/repos/${repository}/actions/artifacts?name=${name}&per_page=100`);
    for (const artifact of listing?.artifacts ?? []) {
      const runId = artifact?.workflow_run?.id;
      if (artifact?.name !== name || artifact.expired !== false || !Number.isSafeInteger(runId)) {
        continue;
      }
      const run = await github("GET", `/repos/${repository}/actions/runs/${runId}`);
      if (
        run?.path === VERIFY_PATH &&
        run.event === "workflow_run" &&
        run.head_branch === base &&
        run.conclusion === "success" &&
        run.repository?.full_name === repository
      ) {
        return true;
      }
    }
  }
  return false;
}

export async function resolvePull({ github, repository, upstreamRunId, base = "main" }) {
  const skip = (reason) => ({ proceed: false, reason });
  if (!RUN_ID.test(String(upstreamRunId))) {
    throw new Error("the upstream run id is not a run id");
  }
  const run = await github("GET", `/repos/${repository}/actions/runs/${upstreamRunId}`);
  if (
    String(run?.id) !== String(upstreamRunId) ||
    run.path !== UPSTREAM_PATH ||
    run.event !== "pull_request" ||
    run.status !== "completed" ||
    run.conclusion !== "success" ||
    run.repository?.full_name !== repository ||
    run.head_repository?.full_name !== repository ||
    !SHA.test(run.head_sha ?? "")
  ) {
    return skip("not-a-passing-run");
  }
  const head = run.head_sha;
  const pulls = (await github("GET", `/repos/${repository}/commits/${head}/pulls`)).filter(
    (pull) =>
      pull?.state === "open" &&
      pull.head?.sha === head &&
      pull.head?.repo?.full_name === repository &&
      pull.base?.ref === base,
  );
  if (pulls.length !== 1) {
    return skip("no-single-pr");
  }
  const [pull] = pulls;
  if (!Number.isSafeInteger(pull.number) || pull.number < 1 || !SHA.test(pull.base?.sha ?? "")) {
    return skip("no-single-pr");
  }
  if (pull.draft !== false) {
    return skip("draft");
  }
  if (pull.user?.id === DEPENDABOT_ID) {
    return skip("dependency-manager");
  }
  if (await judged({ github, repository, number: pull.number, head, base })) {
    return skip("already-judged");
  }
  return { proceed: true, reason: "ok", prNumber: pull.number, headSha: head, baseSha: pull.base.sha };
}

export async function main(env = process.env, { github } = {}) {
  for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "UPSTREAM_RUN_ID"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const result = await resolvePull({
    github: github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
    repository: env.GITHUB_REPOSITORY,
    upstreamRunId: env.UPSTREAM_RUN_ID,
  });
  const lines = [
    `proceed=${result.proceed}`,
    `reason=${result.reason}`,
    `pr-number=${result.prNumber ?? ""}`,
    `head-sha=${result.headSha ?? ""}`,
    `base-sha=${result.baseSha ?? ""}`,
  ];
  appendFileSync(env.GITHUB_OUTPUT, `${lines.join("\n")}\n`);
  console.log(`resolve-pr: proceed=${result.proceed} reason=${result.reason}${result.proceed ? ` pr=${result.prNumber} head=${result.headSha}` : ""}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::error::pr-verify could not resolve the pull request: ${error.message}`);
    process.exitCode = 1;
  });
}
