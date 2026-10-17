// The pr-unblock lane's review-dependency selection, shared by the model job's
// runner step and the verdict job's script (apply-dependency-verdict.mjs). It
// runs no PR head code and hands the model no decision.
//
//   select  run by .github/workflows/pr-run-activity-write.yml around a
//           `prepare: dependency-review` skill, before the head checkout and
//           any model turn, with the job's read-only token: skips a pull
//           request Dependabot did not open, one whose head is no longer the
//           gated head (superseded-sha), or one dependency-classify.mjs
//           sorts `auto` (pr-merge owns those), escalates once the configured
//           number of review rounds ran, and otherwise writes the context
//           file the skill reads.
//
// The PR body holds third-party release notes: it is copied into the context
// file as data and never logged or interpolated into a command.

import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { createGitHubApi, need, positive, SHA } from "./address-feedback.mjs";
import {
  classifierGaps,
  classify,
  COMMIT_FILES_LIMIT,
  DEPENDABOT_LOGIN,
  isDependabotCommit,
  parseConfig,
  provenanceReasons,
  withProvenance,
} from "./dependency-classify.mjs";

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

// A commit's changed paths, or null when unreadable or at the listing limit,
// as the pr-merge lane's _commit_files reads them.
export function commitFilesReader(api) {
  const cache = new Map();
  return async (sha) => {
    if (!cache.has(sha)) {
      let paths = null;
      try {
        const listing = (await api.getCommit(sha)).files;
        paths = Array.isArray(listing) && listing.length < COMMIT_FILES_LIMIT ? listing.map((f) => String(f.filename ?? "")) : null;
      } catch {
        paths = null;
      }
      cache.set(sha, paths);
    }
    return cache.get(sha);
  };
}

// The classifier's input from REST reads: the pull request, its commits and
// files, the files of each non-Dependabot commit, the base config, and the
// base Dependabot policy (readPolicy) with this repository's name; then the
// provenance gate, which reads the package registry (`provenance`, the live
// one unless a test passes its own).
export async function classifyPull({ pull, ciStatus, commits, files, config, policy, repository, readCommitFiles, provenance = provenanceReasons }) {
  const touched = new Map();
  for (const item of commits) {
    if (!isDependabotCommit(item)) {
      touched.set(String(item.sha ?? ""), await readCommitFiles(String(item.sha ?? "")));
    }
  }
  const classification = classify({
    author: pull.user?.login,
    headRef: pull.head?.ref,
    title: pull.title ?? "",
    body: pull.body ?? "",
    labels: (pull.labels ?? []).map((label) => (typeof label === "string" ? label : label.name)),
    ciStatus,
    commits,
    totalCommits: pull.commits,
    files,
    config,
    policy,
    repository,
    changedFiles: pull.changed_files,
    commitFiles: (sha) => touched.get(sha) ?? null,
  });
  return withProvenance(classification, provenance);
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

export async function select({ api, pr, headSha, appId, dependabotId, config = null, policy, repository = "", maxRounds = DEFAULT_MAX_ROUNDS, provenance }) {
  const pull = await api.getPull(pr);
  if (pull.user?.id !== dependabotId || pull.user?.login !== DEPENDABOT_LOGIN) {
    return { decision: "skip", skipReason: "not-applicable" };
  }
  // The head moved since the gate: the next dispatcher run reviews the new one.
  if (pull.head?.sha !== headSha) {
    return { decision: "skip", skipReason: "superseded-sha" };
  }
  const files = await api.listPullFiles(pr);
  const commits = await api.listPullCommits(pr);
  const classification = await classifyPull({
    pull,
    ciStatus: ciStatusOf(await api.listCheckRuns(headSha, "ci-status")),
    commits,
    files,
    config,
    policy,
    repository,
    readCommitFiles: commitFilesReader(api),
    provenance,
  });
  if (classification.tier !== "review") {
    return { decision: "skip", skipReason: "not-applicable", classification };
  }
  const comments = await api.listIssueComments(pr);
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

// The base's .github/dependabot.yml as [ecosystem, directory] pairs. A file
// it cannot read, or one with no entry that reads, is null, which the
// classifier reports as dependabot-config-unreadable as the pr-merge lane
// does (review tier, and no merge verdict); each case logs its own warning so
// the cause is visible.
export function readConfig(path, log = (line) => console.log(line)) {
  let text;
  try {
    text = readFileSync(String(path ?? ""), "utf8");
  } catch (error) {
    log(`::warning::cannot read the Dependabot config ${path || "(no path)"} (${error.code ?? error.name}); every Dependabot PR is review tier until it reads`);
    return null;
  }
  const pairs = parseConfig(text);
  if (pairs === null) {
    log(`::warning::the Dependabot config ${path} has no updates entry that reads; every Dependabot PR is review tier until one does`);
  }
  return pairs;
}

// The base's standards Dependabot policy as parsed JSON. A file it cannot
// read or parse is null, which the classifier reports as
// dependabot-policy-unreadable (review tier for every Dependabot PR).
export function readPolicy(path, log = (line) => console.log(line)) {
  try {
    return JSON.parse(readFileSync(String(path ?? ""), "utf8"));
  } catch (error) {
    log(`::warning::cannot read the Dependabot policy ${path || "(no path)"} (${error.code ?? error.name}); every Dependabot PR is review tier until it reads`);
    return null;
  }
}

// The distinct `control` strings of the review-only entries the
// classification matched, in entry order.
export const reviewControls = (classification) => [...new Set((classification?.reviewOnly ?? []).map((entry) => entry.control))];

export function maxRoundsFrom(value) {
  return value === undefined || value === "" ? DEFAULT_MAX_ROUNDS : positive(value, "DEPENDENCY_REVIEW_ROUNDS");
}

export async function main(argv, env, { api, log = (line) => console.log(line), provenance } = {}) {
  if (argv[0] !== "select") {
    throw new Error("usage: review-dependency.mjs select");
  }
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "HEAD_SHA", "APP_SENDER_ID", "TRUSTED_ACTORS", "DEPENDENCY_FILE", "DEPENDABOT_CONFIG", "DEPENDABOT_POLICY"]);
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
    config: readConfig(env.DEPENDABOT_CONFIG, log),
    policy: readPolicy(env.DEPENDABOT_POLICY, log),
    provenance,
  });
  if (result.file) {
    writeFileSync(env.DEPENDENCY_FILE, `${JSON.stringify(result.file, null, 2)}\n`);
  }
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  output("proceed", String(result.decision === "proceed"));
  output("skip-reason", result.decision === "skip" ? result.skipReason : result.decision === "escalate" ? "awaiting-human" : "");
  output("escalation-reason", result.escalationReason ?? "");
  output("security", String(result.classification?.security === true));
  output("config-unreadable", String((result.classification?.reasons ?? []).includes("dependabot-config-unreadable")));
  output("files-truncated", String(result.file?.files_truncated === true));
  // Each matched review-only entry's control, which a merge verdict must
  // quote (apply-dependency-verdict.mjs); JSON keeps it on one line.
  output("controls", JSON.stringify(reviewControls(result.classification)));
  const gaps = classifierGaps(result.classification?.tier === "review" ? result.classification.reasons : []);
  if (gaps.length) {
    log(`::warning::classifier gap: #${pr} goes to review only because the classifier could not read it (${gaps.join(", ")}); fix the classifier, not the pull request`);
  }
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
