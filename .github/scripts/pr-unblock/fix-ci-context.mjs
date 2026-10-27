// The pr-unblock lane's fix-ci context: run by pr-unblock.yml's fix-ci-context
// job, from the default branch tip, before the fix-ci model job and with a
// read-only token. It checks out no PR head and runs no head code.
//
// It skips a pull request the human-gated label holds (awaiting-human) unless
// another lane's escalation put the label on (gate-source.mjs prHold),
// escalates `ci-fix-round-cap` once the lanes App has pushed
// `loop.fix-ci-rounds` fix-ci commits to the pull request, skips a closed pull
// request or a head with no failing check (one cancelled past its time limit
// counts), and otherwise writes the context
// file the `source-control:pull-request ci --ci` skill reads: each failing
// check's name, the workflow file that defines its job, its annotations and
// the end of its log, and the review findings address-feedback would work
// (keepThreads with no trusted person's direction: unresolved threads the
// reviewer bot or a verifier note opened on a reviewed head and only it
// wrote), so a fix the reviewer already named is not escalated. Check names,
// annotations, logs and findings are data: they are copied into the file,
// capped, and never logged or run.

import { createHash } from "node:crypto";
import { appendFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { timeLimitNoted } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { createGitHubApi, humanGatedLabelFrom, keepThreads, need, positive, reviewedHeads, reviewerIdFrom, SHA } from "./address-feedback.mjs";
import { prHold } from "./gate-source.mjs";

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
const MAX_FINDINGS = 10;
const MAX_FINDING = 2000;

export function countFixRounds(commits, appId) {
  return commits.filter(
    (commit) =>
      commit.author?.id === appId &&
      String(commit.commit?.message ?? "")
        .split("\n")
        .some((line) => line.replace(/\r$/, "") === FIX_TRAILER),
  ).length;
}

// The last lines of a job log, without the runner's timestamps or ANSI color.
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

// The latest run of each check name that is not a skip, when it failed or was
// cancelled; select keeps a cancelled one only past its time limit. The fix-ci
// dispatcher reads a cancelled head through it too, so the two agree.
export function failingChecks(checkRuns) {
  const latest = new Map();
  for (const run of checkRuns) {
    const kept = latest.get(run.name);
    if (!kept || (silent(kept) && !silent(run)) || (silent(kept) === silent(run) && run.id > kept.id)) {
      latest.set(run.name, run);
    }
  }
  return [...latest.values()]
    .filter((run) => run.name !== AGGREGATE && run.status === "completed" && (FAILING.has(run.conclusion) || run.conclusion === "cancelled"))
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
// notes are the run's annotations when select already read them.
async function contextOf(api, run, notes) {
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
  const annotations = (notes ?? (await api.listAnnotations(run.id))).slice(0, MAX_ANNOTATIONS).map(annotationOf);
  return { name: String(run.name), workflow, annotations, log_excerpt: excerpt };
}

// Each kept thread's opening comment: where it points and what it says.
async function reviewFindings(api, pr, { appId, reviewerId }) {
  const [issueComments, reviews, reviewComments, threads] = await Promise.all([
    api.listIssueComments(pr),
    api.listReviews(pr),
    api.listReviewComments(pr),
    api.listThreads(pr),
  ]);
  return keepThreads({ threads, reviewComments, reviews, heads: reviewedHeads(issueComments), reviewerId, appId })
    .slice(0, MAX_FINDINGS)
    .map((thread) => ({ path: String(thread.path ?? ""), line: thread.line, body: String(thread.comments[0].body).slice(0, MAX_FINDING) }));
}

export async function select({ api, pr, appId, reviewerId, maxRounds, humanGatedLabel = "needs-human", log = (line) => console.log(line) }) {
  const pull = await api.getPull(pr);
  const headSha = pull.head?.sha;
  if (!SHA.test(String(headSha))) {
    throw new Error("the pull request names no head SHA");
  }
  if (pull.state !== "open") {
    return { decision: "skip", skipReason: "not-applicable", headSha };
  }
  // The human-gated label holds fix-ci unless another lane's escalation put
  // it on; the label stays on, and laneEscalated lets the push past it.
  const { held, laneEscalated } = await prHold({
    labels: (pull.labels ?? []).map((label) => label?.name),
    holdLabels: [],
    gateLabel: humanGatedLabel,
    head: headSha,
    activity: "fix-ci",
    appId,
    readTimeline: () => api.listTimeline(pr),
  });
  if (held) {
    return { decision: "skip", skipReason: "awaiting-human", headSha };
  }
  const rounds = countFixRounds(await api.listPullCommits(pr), appId);
  if (rounds >= maxRounds) {
    return { decision: "escalate", escalationReason: "ci-fix-round-cap", rounds, headSha, laneEscalated };
  }
  const checks = [];
  for (const run of failingChecks(await api.listCommitCheckRuns(headSha))) {
    if (checks.length === MAX_CHECKS) {
      break;
    }
    // A job past its timeout-minutes ends cancelled; its time-limit note is
    // the cause the model reads (#9828). Any other cancel has nothing to fix.
    let notes;
    if (run.conclusion === "cancelled") {
      notes = await api.listAnnotations(run.id);
      if (!timeLimitNoted(notes)) {
        continue;
      }
    }
    const context = await contextOf(api, run, notes);
    if (context) {
      checks.push(context);
    }
  }
  if (checks.length === 0) {
    return { decision: "skip", skipReason: "not-applicable", rounds, headSha, laneEscalated };
  }
  // The findings are a lead, so a failed read costs them, not the run.
  let review_findings = [];
  try {
    review_findings = await reviewFindings(api, pr, { appId, reviewerId });
  } catch (error) {
    log(`::warning::the review findings could not be read (${error.message}); the context holds none`);
  }
  return { decision: "proceed", rounds, headSha, laneEscalated, file: { pr, head_sha: headSha, checks, review_findings } };
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
  // The base checkout's list, the one address-feedback reads.
  const reviewerId = reviewerIdFrom(env.TRUSTED_ACTORS || `${env.BASE_PATH || ".base"}/.github/standards/trusted-actors/trusted-actors.json`);
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
    });
  const humanGatedLabel = humanGatedLabelFrom(env.TRACKER_CONFIG || `${env.BASE_PATH || ".base"}/.work-item-tracker.json`);
  const result = await select({ api: client, pr, appId, reviewerId, maxRounds, humanGatedLabel, log });
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
  // fix-ci-not-run's check, and whether apply-patch may push past the
  // human-gated label a lane escalation put on.
  output("skip-reason", result.decision === "skip" ? result.skipReason : "");
  output("lane-escalated", String(result.laneEscalated === true));
  log(
    `${result.decision}: ${result.file?.checks.length ?? 0} failing check(s), ${result.file?.review_findings.length ?? 0} review finding(s), ${result.rounds ?? 0} earlier round(s)${result.escalationReason ? `, ${result.escalationReason}` : ""}`,
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
