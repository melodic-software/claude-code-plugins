// The pr-unblock lane's review-dependency selection, shared by the model job's
// runner step and the verdict job's script (apply-dependency-verdict.mjs). It
// runs no PR head code and hands the model no decision.
//
//   select  run by .github/workflows/pr-run-activity-write.yml around a
//           `prepare: dependency-review` skill, before the head checkout and
//           any model turn, with the job's read-only token: skips a pull
//           request Dependabot did not open or one dependency-classify.mjs
//           sorts `auto` (pr-merge owns those), escalates once the configured
//           number of review rounds ran, and otherwise writes the context
//           file the skill reads.
//
// The PR body holds third-party release notes: it is copied into the context
// file as data and never logged or interpolated into a command.

import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { createGitHubApi, need, positive, SHA } from "./address-feedback.mjs";
import { classify, DEPENDABOT_LOGIN, parseConfig } from "./dependency-classify.mjs";

export const DEFAULT_MAX_ROUNDS = 2;
export const MODEL_CHECK = "pr-unblock / review-dependency";
export const VERDICTS = Object.freeze(["merge", "fix", "close", "escalate"]);
const ROUND_LINE = /^<!-- pr-unblock:review-dependency-round head=([0-9a-f]{40}) verdict=(merge|fix|close|escalate|invalid) run=([1-9][0-9]{0,14}-[1-9][0-9]{0,4}|none) -->$/;
// The pulls files listing stops here
// (docs.github.com/en/rest/pulls/pulls#list-pull-requests-files, as of
// 2026-10-15; recheck when that section changes its limit).
const FILES_CAP = 3000;
// Lockfile patches run long; the model reads the rest from the checkout.
// Judgment, sized to keep the context file well inside one model turn.
const PATCH_CAP = 20_000;
const PATCHES_TOTAL_CAP = 300_000;

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");

export function roundLine({ head, verdict, run }) {
  return `<!-- pr-unblock:review-dependency-round head=${head} verdict=${verdict} run=${run} -->`;
}

// The round markers the lanes App posted, oldest first; any other author's
// copy is ignored.
export function rounds(issueComments, appId) {
  return issueComments
    .filter((comment) => comment.user?.id === appId)
    .map((comment) => ROUND_LINE.exec(firstLine(comment.body)))
    .filter(Boolean)
    .map((match) => ({ head: match[1], verdict: match[2], run: match[3] }));
}

export const countRounds = (issueComments, appId) => rounds(issueComments, appId).length;

// The model job's check run, posted by its report job on the head it gated.
// It counts a round whose verdict job never ran; a forged one only stops the
// lane sooner.
export function countCheckRounds(checkRunsByCommit) {
  return checkRunsByCommit.filter((runs) =>
    runs.some(
      (run) => run.name === MODEL_CHECK && run.app?.slug === "github-actions" && ["success", "failure"].includes(run.conclusion),
    ),
  ).length;
}

// The newest ci-status run GitHub Actions posted on the head: its conclusion
// once completed, else pending.
export function ciStatusOf(checkRuns) {
  const newest = checkRuns
    .filter((run) => run.app?.slug === "github-actions")
    .sort((a, b) => b.id - a.id)[0];
  return newest?.status === "completed" ? String(newest.conclusion) : "pending";
}

// The head commit's message, only when Dependabot authored it and GitHub
// verified its signature; the classifier reads its updated-dependencies block.
export function verifiedMessage(commit, sha) {
  return commit?.sha === sha && commit.author?.login === DEPENDABOT_LOGIN && commit.commit?.verification?.verified === true
    ? String(commit.commit.message ?? "")
    : "";
}

export function classifyPull(pull, ciStatus, commitMessage = "", { files, config = null } = {}) {
  return classify({
    author: pull.user?.login,
    headRef: pull.head?.ref,
    title: pull.title ?? "",
    body: pull.body ?? "",
    labels: (pull.labels ?? []).map((label) => (typeof label === "string" ? label : label.name)),
    ciStatus,
    commitMessage,
    files,
    config,
  });
}

function capPatches(files) {
  let left = PATCHES_TOTAL_CAP;
  return files.map((file) => {
    const patch = String(file.patch ?? "");
    const kept = patch.slice(0, Math.max(0, Math.min(PATCH_CAP, left)));
    left -= kept.length;
    return {
      filename: file.filename,
      previous_filename: file.previous_filename ?? null,
      status: file.status,
      additions: file.additions,
      deletions: file.deletions,
      patch: kept.length < patch.length ? `${kept}\n[patch truncated: read the file]` : kept,
    };
  });
}

export async function select({ api, pr, headSha, appId, dependabotId, config = null, repository = "", maxRounds = DEFAULT_MAX_ROUNDS }) {
  const pull = await api.getPull(pr);
  if (pull.user?.id !== dependabotId || pull.user?.login !== DEPENDABOT_LOGIN) {
    return { decision: "skip", skipReason: "not-applicable" };
  }
  const files = await api.listPullFiles(pr);
  const classification = classifyPull(
    pull,
    ciStatusOf(await api.listCheckRuns(headSha, "ci-status")),
    verifiedMessage(await api.getCommit(headSha), headSha),
    { files, config },
  );
  if (classification.tier !== "review") {
    return { decision: "skip", skipReason: "not-applicable", classification };
  }
  const comments = await api.listIssueComments(pr);
  const commits = await api.listPullCommits(pr);
  const checkRuns = await Promise.all(commits.map((commit) => api.listCheckRuns(commit.sha, MODEL_CHECK)));
  const done = Math.max(countRounds(comments, appId), countCheckRounds(checkRuns));
  if (done >= maxRounds) {
    return { decision: "escalate", escalationReason: "dependency-round-cap", rounds: done, classification };
  }

  return {
    decision: "proceed",
    rounds: done,
    classification,
    file: {
      version: 1,
      repository,
      pr,
      head_sha: headSha,
      head_ref: pull.head.ref,
      title: pull.title ?? "",
      labels: (pull.labels ?? []).map((label) => (typeof label === "string" ? label : label.name)),
      classification,
      rounds: done,
      files_truncated: files.length >= FILES_CAP,
      files: capPatches(files),
      // Dependabot's text, with the upstream release notes it quotes: data.
      body: pull.body ?? "",
    },
  };
}

// Dependabot's id comes from the base's trusted-actors list, by login.
export function dependabotIdFrom(trustedActorsPath) {
  const actors = JSON.parse(readFileSync(trustedActorsPath, "utf8")).actors ?? [];
  const actor = actors.find((row) => row.login === DEPENDABOT_LOGIN && row.kind === "bot");
  return positive(actor?.id, `the ${DEPENDABOT_LOGIN} id in ${trustedActorsPath}`);
}

// The base's .github/dependabot.yml as [ecosystem, directory] pairs; null
// (which covers no path, so every PR is review) when it cannot be read.
export function readConfig(path) {
  try {
    return path ? parseConfig(readFileSync(path, "utf8")) : null;
  } catch {
    return null;
  }
}

export function maxRoundsFrom(value) {
  return value === undefined || value === "" ? DEFAULT_MAX_ROUNDS : positive(value, "DEPENDENCY_REVIEW_ROUNDS");
}

export async function main(argv, env, { api, log = (line) => console.log(line) } = {}) {
  if (argv[0] !== "select") {
    throw new Error("usage: review-dependency.mjs select");
  }
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "HEAD_SHA", "APP_SENDER_ID", "TRUSTED_ACTORS", "DEPENDENCY_FILE", "DEPENDABOT_CONFIG"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
    });
  const result = await select({
    api: client,
    pr,
    headSha: env.HEAD_SHA,
    appId: positive(env.APP_SENDER_ID, "APP_SENDER_ID"),
    dependabotId: dependabotIdFrom(env.TRUSTED_ACTORS),
    repository: env.GITHUB_REPOSITORY,
    maxRounds: maxRoundsFrom(env.DEPENDENCY_REVIEW_ROUNDS),
    config: readConfig(env.DEPENDABOT_CONFIG),
  });
  if (result.file) {
    writeFileSync(env.DEPENDENCY_FILE, `${JSON.stringify(result.file, null, 2)}\n`);
  }
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  output("proceed", String(result.decision === "proceed"));
  output("skip-reason", result.decision === "skip" ? result.skipReason : result.decision === "escalate" ? "awaiting-human" : "");
  output("escalation-reason", result.escalationReason ?? "");
  output("security", String(result.classification?.security === true));
  log(
    `${result.decision}: tier ${result.classification?.tier ?? "-"} (${(result.classification?.reasons ?? []).join(", ") || "none"}), ` +
      `${result.rounds ?? 0} earlier round(s)${result.escalationReason ? `, ${result.escalationReason}` : ""}`,
  );
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::review-dependency failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
