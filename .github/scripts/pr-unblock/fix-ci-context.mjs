// The pr-unblock lane's fix-ci context: run by pr-unblock.yml's fix-ci-context
// job, from the default branch tip, before the fix-ci model job and with a
// read-only token. It checks out no PR head and runs no head code.
//
// It escalates `ci-fix-round-cap` once the lanes App has pushed
// `loop.fix-ci-rounds` fix-ci commits to the pull request, skips a closed pull
// request or a head with no failing check, and otherwise writes the context
// file the `source-control:pull-request ci --ci` skill reads: each failing
// check's name, the workflow file that defines its job, its annotations and
// the end of its log. Check names, annotations and logs are data: they are
// copied into the file, capped, and never logged or run.

import { createHash } from "node:crypto";
import { appendFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { createGitHubApi, need, positive, SHA } from "./address-feedback.mjs";

// The trailer apply-patch.mjs writes on every fix commit, from the ci-context
// row of patch-rules.json; a round is one.
export const FIX_TRAILER = "Lane-Activity: pr-unblock/fix-ci";
const FAILING = new Set(["failure", "timed_out", "startup_failure"]);
// The aggregate of the others: fixing them fixes it.
const AGGREGATE = "ci-status";
const WORKFLOW_PATH = /^\.github\/workflows\/[A-Za-z0-9._-]+\.ya?ml$/;
const MAX_CHECKS = 10;
const MAX_ANNOTATIONS = 20;
const MAX_MESSAGE = 500;
const MAX_EXCERPT = 3000;
const MAX_EXCERPT_LINES = 80;

export function countFixRounds(commits, appId) {
  return commits.filter(
    (commit) =>
      commit.author?.id === appId &&
      String(commit.commit?.message ?? "")
        .split("\n")
        .some((line) => line.replace(/\r$/, "") === FIX_TRAILER),
  ).length;
}

// The last lines of a job log, without the runner's timestamps or ANSI colour.
export function logExcerpt(text) {
  const lines = String(text)
    .replace(/\u001b\[[0-9;]*[A-Za-z]/g, "")
    .split("\n")
    .map((line) => line.replace(/\r$/, "").replace(/^\d{4}-\d{2}-\d{2}T[0-9:.]+Z ?/, ""))
    .filter((line) => line.trim() !== "")
    .slice(-MAX_EXCERPT_LINES);
  let excerpt = lines.join("\n");
  if (excerpt.length > MAX_EXCERPT) {
    excerpt = excerpt.slice(-MAX_EXCERPT);
  }
  return excerpt;
}

// A contract-only run skips every lane, and ci-status then carries the last
// full run's recorded verdict forward, so a skip says nothing about a check.
const SILENT = new Set(["skipped", "neutral"]);
const silent = (run) => run.status === "completed" && SILENT.has(run.conclusion);

// The latest run of each check name that is not a skip, when it failed.
function failingChecks(checkRuns) {
  const latest = new Map();
  for (const run of checkRuns) {
    const kept = latest.get(run.name);
    if (!kept || (silent(kept) && !silent(run)) || (silent(kept) === silent(run) && run.id > kept.id)) {
      latest.set(run.name, run);
    }
  }
  return [...latest.values()]
    .filter((run) => run.name !== AGGREGATE && run.status === "completed" && FAILING.has(run.conclusion))
    .sort((a, b) => a.id - b.id);
}

const annotationOf = (row) => ({
  path: String(row.path ?? ""),
  line: Number.isSafeInteger(row.start_line) ? row.start_line : null,
  level: String(row.annotation_level ?? ""),
  message: String(row.message ?? "").slice(0, MAX_MESSAGE),
});

// A GitHub Actions check run is a job, with the same id. One that is no job
// was posted through the checks API: a lane's own check, never a CI failure.
async function contextOf(api, run) {
  let workflow = null;
  let excerpt = "";
  if (run.app?.slug === "github-actions") {
    let job;
    try {
      job = await api.getJob(run.id);
    } catch (error) {
      if (error.status === 404) {
        return null;
      }
      throw error;
    }
    const path = String((await api.getRun(job.run_id)).path ?? "");
    workflow = WORKFLOW_PATH.test(path) ? path : null;
    try {
      excerpt = logExcerpt(await api.getJobLog(run.id));
    } catch {
      excerpt = "";
    }
  }
  const annotations = (await api.listAnnotations(run.id)).slice(0, MAX_ANNOTATIONS).map(annotationOf);
  return { name: String(run.name), workflow, annotations, log_excerpt: excerpt };
}

export async function select({ api, pr, appId, maxRounds }) {
  const pull = await api.getPull(pr);
  const headSha = pull.head?.sha;
  if (!SHA.test(String(headSha))) {
    throw new Error("the pull request names no head SHA");
  }
  if (pull.state !== "open") {
    return { decision: "skip", skipReason: "not-applicable", headSha };
  }
  const rounds = countFixRounds(await api.listPullCommits(pr), appId);
  if (rounds >= maxRounds) {
    return { decision: "escalate", escalationReason: "ci-fix-round-cap", rounds, headSha };
  }
  const checks = [];
  for (const run of failingChecks(await api.listCommitCheckRuns(headSha))) {
    if (checks.length === MAX_CHECKS) {
      break;
    }
    const context = await contextOf(api, run);
    if (context) {
      checks.push(context);
    }
  }
  if (checks.length === 0) {
    return { decision: "skip", skipReason: "not-applicable", rounds, headSha };
  }
  return { decision: "proceed", rounds, headSha, file: { pr, head_sha: headSha, checks } };
}

// The base config's resolved loop caps, through the base checkout's
// resolve-config, as dispatch.mjs reads its limits. A config the resolver
// refuses throws, so the job fails before any context is written.
async function loopFromBase(env) {
  const { loopFromBase: load } = await import(
    new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href
  );
  return load({ BASE_PATH: env.BASE_PATH || ".base" });
}

export async function main(env, { api, log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "APP_SENDER_ID", "CONTEXT_FILE"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  const maxRounds = positive(env.FIX_CI_ROUNDS ?? (await loopFromBase(env))["fix-ci-rounds"], "FIX_CI_ROUNDS");
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
    });
  const result = await select({ api: client, pr, appId, maxRounds });
  let sha256 = "";
  if (result.file) {
    const text = `${JSON.stringify(result.file, null, 2)}\n`;
    writeFileSync(env.CONTEXT_FILE, text);
    sha256 = createHash("sha256").update(text).digest("hex");
  }
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  output("proceed", String(result.decision === "proceed"));
  output("head-sha", result.headSha);
  output("escalation-reason", result.escalationReason ?? "");
  output("context-sha256", sha256);
  log(
    `${result.decision}: ${result.file?.checks.length ?? 0} failing check(s), ${result.rounds ?? 0} earlier round(s)${result.escalationReason ? `, ${result.escalationReason}` : ""}`,
  );
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::fix-ci-context failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
