// Resolves the pull request a pr-require-checks run passed, for pr-verify.yml.
// The only event field it takes is the upstream run id; every other fact is
// read back from the API. It proceeds only when all of these hold, and
// otherwise writes proceed=false with a reason:
// - the run is a completed, successful pull_request run of
//   pr-require-checks.yml, by exact path, in this repository on a head of
//   this repository;
// - exactly one open PR into main has that run's head SHA as its current head
//   and its head in this repository;
// - the PR is not a draft and not a dependency manager's (a Bot account with
//   one of DEPENDENCY_MANAGERS' logins);
// - under merge.verify-authors `lane` (the default) the lanes App opened it:
//   a Bot account whose login is merge.agent-identity, compared as the
//   pr-merge lane does (babysit_merge_policy._lane_authored); under `any`
//   anyone may have; any other value judges nothing;
// - the head has no counted verdict yet: a FAIL at it under this PR's number
//   or another the commit's pull requests carry, or a PASS or PASS-NOTES for
//   this PR, each looked up by exact artifact name, uploaded by a completed
//   run that the pr-merge lane's reader would count (countedBy, the same checks as
//   babysit_verify_evidence.py). A run still going or one that uploaded
//   nothing does not stop a new judgment.
// The babysit-prs test test_verify_rules_sync.py runs this file to keep
// DEPENDENCY_MANAGERS, isDependencyManager and countedBy in step with the gate.
// It also writes the PR's closing issues with their authors and last body
// editors to SPEC_FILE, and the spec text trusted humans wrote to
// SPEC_TEXT_FILE (linkedIssues).
// The head SHA is the run's, never the PR's live head.

import { appendFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const UPSTREAM_PATH = ".github/workflows/pr-require-checks.yml";
export const VERIFY_PATH = ".github/workflows/pr-verify.yml";
// babysit_classify.DEPENDENCY_MANAGER_LOGINS: the pr-merge lane refuses these
// Bot accounts' pull requests before reading a verdict.
export const DEPENDENCY_MANAGERS = Object.freeze(["dependabot", "dependabot-preview", "renovate", "renovate-bot"]);

const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const NAME = /^pr-verify-([1-9][0-9]*)-([0-9a-f]{40})-(pass|pass-notes|fail)$/;
const MAX_PAGES = 100;

const SPEC_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      closingIssuesReferences(first: 10) {
        totalCount
        nodes {
          number repository { nameWithOwner } body lastEditedAt
          author { ...actor } editor { ...actor }
          comments(first: 100) { totalCount nodes { databaseId updatedAt body lastEditedAt author { ...actor } editor { ...actor } } }
        }
      }
    }
  }
}
fragment actor on Actor { __typename login ... on User { databaseId } ... on Bot { databaseId } }`;

const actorFields = (actor, role) => ({
  [`${role}_login`]: typeof actor?.login === "string" ? actor.login : null,
  [`${role}_id`]: Number.isSafeInteger(actor?.databaseId) ? actor.databaseId : null,
  [`${role}_type`]: typeof actor?.__typename === "string" ? actor.__typename : null,
});

// A Bot account with a dependency manager's login; a User named like one is not.
export const isDependencyManager = (user) =>
  user?.type === "Bot" &&
  DEPENDENCY_MANAGERS.includes(String(user.login ?? "").toLowerCase().replace(/^app\//, "").replace(/\[bot\]$/, ""));

// babysit_merge_policy._login_key: REST spells an App `app[bot]`, GraphQL `app`.
const loginKey = (login) => String(login ?? "").trim().toLowerCase().replace(/\[bot\]$/, "");
const laneAuthored = (user, laneIdentity) =>
  loginKey(laneIdentity) !== "" && user?.type === "Bot" && loginKey(user.login) === loginKey(laneIdentity);

// Every artifact with exactly this name; a read that fails throws.
async function artifactsNamed(github, repository, name) {
  const artifacts = [];
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const path = `/repos/${repository}/actions/artifacts?name=${encodeURIComponent(name)}&per_page=100&page=${page}`;
    const batch = (await github("GET", path))?.artifacts ?? [];
    artifacts.push(...batch);
    if (batch.length < 100) {
      return artifacts;
    }
  }
  throw new Error(`the ${name} artifacts have more than ${MAX_PAGES} pages`);
}

// Whether the pr-merge lane would count this artifact's run, and the run is
// complete: of verifier origin (path, event, branch, repository, head
// repository, a head SHA on the branch), completed, and for a pass concluded
// success. A read that fails counts nothing.
export async function countedBy({ github, repository, runId, verdict, base }) {
  let run;
  try {
    run = await github("GET", `/repos/${repository}/actions/runs/${runId}`);
  } catch {
    return false;
  }
  if (
    run?.id !== runId ||
    run.path !== VERIFY_PATH ||
    run.event !== "workflow_run" ||
    run.head_branch !== base ||
    run.repository?.full_name !== repository ||
    run.head_repository?.full_name !== repository ||
    run.status !== "completed" ||
    (verdict !== "fail" && run.conclusion !== "success") ||
    !SHA.test(run.head_sha ?? "")
  ) {
    return false;
  }
  try {
    const compare = await github("GET", `/repos/${repository}/compare/${run.head_sha}...${base}`);
    return compare?.status === "ahead" || compare?.status === "identical";
  } catch {
    return false;
  }
}

// The names that hold a counted verdict at the head: this PR's PASS,
// PASS-NOTES and FAIL, and a FAIL under each other number the commit's pull
// requests carry.
async function judged({ github, repository, number, head, base, numbers }) {
  const names = [
    ...["pass", "pass-notes", "fail"].map((verdict) => `pr-verify-${number}-${head}-${verdict}`),
    ...[...new Set(numbers)].filter((other) => other !== number).map((other) => `pr-verify-${other}-${head}-fail`),
  ];
  for (const name of names) {
    const [, , , verdict] = NAME.exec(name);
    for (const artifact of await artifactsNamed(github, repository, name)) {
      if (artifact?.name !== name || artifact.expired !== false) {
        continue;
      }
      const runId = artifact.workflow_run?.id;
      if (Number.isSafeInteger(runId) && (await countedBy({ github, repository, runId, verdict, base }))) {
        return true;
      }
    }
  }
  return false;
}

// The closing issues in this repository with their authors and last body
// editors (`linkedIssues`), and the spec text: each body and comment written,
// and last edited if ever, by a User on the trusted list's humans other than
// the PR author (`specText`). Bots, the lanes App and the PR author are left
// out even where select-trusted-text keeps them.
async function linkedIssues(github, repository, number, humans, prAuthor) {
  const [owner, name] = repository.split("/");
  const data = await github("POST", "/graphql", { query: SPEC_QUERY, variables: { owner, name, number } });
  const refs = data?.data?.repository?.pullRequest?.closingIssuesReferences;
  if (!refs || !Array.isArray(refs.nodes) || refs.totalCount !== refs.nodes.length) {
    throw new Error(`#${number}: the closing issues could not be read`);
  }
  const author = String(prAuthor ?? "").toLowerCase();
  const trusted = (actor) =>
    actor?.__typename === "User" &&
    humans.has(actor.databaseId) &&
    author !== "" &&
    String(actor.login ?? "").toLowerCase() !== author;
  const written = (item) => trusted(item?.author) && (item.lastEditedAt == null || trusted(item.editor));
  const issues = refs.nodes.filter(
    (issue) => issue?.repository?.nameWithOwner === repository && Number.isSafeInteger(issue.number),
  );
  for (const issue of issues) {
    const comments = issue.comments;
    if (!Array.isArray(comments?.nodes) || comments.totalCount !== comments.nodes.length) {
      throw new Error(`#${issue.number}: the issue's comments could not be read`);
    }
  }
  return {
    linkedIssues: issues.map((issue) => ({
      number: issue.number,
      ...actorFields(issue.author, "author"),
      last_edited_at: typeof issue.lastEditedAt === "string" ? issue.lastEditedAt : null,
      ...actorFields(issue.editor, "editor"),
      // The spec comments the model gets, which the gate recomputes with the
      // same filter (babysit_verify_evidence._spec_comments).
      spec_comments: issue.comments.nodes
        .filter(written)
        .map((comment) => ({ id: comment.databaseId, updated_at: comment.updatedAt })),
    })),
    specText: issues.map((issue) => ({
      number: issue.number,
      body: written(issue) && typeof issue.body === "string" ? issue.body : null,
      comments: issue.comments.nodes.filter(written).map((comment) => String(comment.body ?? "")),
    })),
  };
}

export async function resolvePull({ github, repository, upstreamRunId, humans, base = "main", verifyAuthors = "lane", laneIdentity }) {
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
  const associated = await github("GET", `/repos/${repository}/commits/${head}/pulls`);
  const pulls = associated.filter(
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
  if (isDependencyManager(pull.user)) {
    return skip("dependency-manager");
  }
  if (verifyAuthors !== "lane" && verifyAuthors !== "any") {
    return skip("verify-authors-invalid");
  }
  if (verifyAuthors === "lane" && !laneAuthored(pull.user, laneIdentity)) {
    return skip("author-not-lane");
  }
  const numbers = associated.map((item) => item?.number).filter((n) => Number.isSafeInteger(n) && n > 0);
  if (await judged({ github, repository, number: pull.number, head, base, numbers })) {
    return skip("already-judged");
  }
  return {
    proceed: true,
    reason: "ok",
    prNumber: pull.number,
    headSha: head,
    baseSha: pull.base.sha,
    headRef: String(pull.head.ref ?? ""),
    ...(await linkedIssues(github, repository, pull.number, humans, pull.user?.login)),
  };
}

export async function main(env = process.env, { github } = {}) {
  for (const key of [
    "GITHUB_TOKEN",
    "GITHUB_REPOSITORY",
    "GITHUB_OUTPUT",
    "UPSTREAM_RUN_ID",
    "SPEC_FILE",
    "SPEC_TEXT_FILE",
    "TRUSTED_ACTORS_PATH",
  ]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  const result = await resolvePull({
    github: github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
    repository: env.GITHUB_REPOSITORY,
    upstreamRunId: env.UPSTREAM_RUN_ID,
    humans: loadTrustedList(env.TRUSTED_ACTORS_PATH).humans,
    // pr-verify.yml reads both from main's pr-pipeline.yaml; unset is `lane`.
    verifyAuthors: env.VERIFY_AUTHORS ?? "lane",
    laneIdentity: env.LANE_IDENTITY,
  });
  if (result.proceed && !/^[A-Za-z0-9._/-]+$/.test(result.headRef)) {
    throw new Error("the head branch has a name the outputs cannot carry");
  }
  if (result.proceed) {
    writeFileSync(env.SPEC_FILE, `${JSON.stringify(result.linkedIssues, null, 2)}\n`);
    writeFileSync(env.SPEC_TEXT_FILE, `${JSON.stringify(result.specText, null, 2)}\n`);
  }
  const lines = [
    `proceed=${result.proceed}`,
    `reason=${result.reason}`,
    `pr-number=${result.prNumber ?? ""}`,
    `head-sha=${result.headSha ?? ""}`,
    `base-sha=${result.baseSha ?? ""}`,
    `head-ref=${result.headRef ?? ""}`,
  ];
  appendFileSync(env.GITHUB_OUTPUT, `${lines.join("\n")}\n`);
  const summary = {
    "author-not-lane": "skipped: author not the lanes App",
    "verify-authors-invalid": "skipped: verify-authors value is invalid",
  }[result.reason];
  if (summary && env.GITHUB_STEP_SUMMARY) {
    appendFileSync(env.GITHUB_STEP_SUMMARY, `${summary}\n`);
  }
  console.log(`resolve-pr: proceed=${result.proceed} reason=${result.reason}${result.proceed ? ` pr=${result.prNumber} head=${result.headSha}` : ""}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::error::pr-verify could not resolve the pull request: ${error.message}`);
    process.exitCode = 1;
  });
}
