// The pr-unblock lane's fix-ci context: run by pr-unblock.yml's fix-ci-context
// job, from the default branch tip, before the fix-ci model job and with a
// read-only token. It checks out no PR head and runs no head code.
//
// It skips a pull request the human-gated label holds (awaiting-human) unless
// another lane's escalation put the label on (gate-source.mjs prHold), skips
// one from a head branch a workflow owns and rebuilds (owned-branch, the base
// config's merge.refire-skip-branches: the rebuild is its fix and moves the
// branch under any push), skips a closed pull request or a head with no failing check (one cancelled
// past its time limit counts), escalates `ci-fix-round-cap` once the lanes App
// has pushed `loop.fix-ci-rounds` fix-ci commits to the pull request, and
// otherwise writes the context
// file the `source-control:pull-request ci --ci` skill reads: each failing
// check's name, the workflow file that defines its job, its annotations and
// the end of its log, and the review findings address-feedback would work
// (keepThreads with no trusted person's direction: unresolved threads the
// reviewer bot or a verifier note opened on a reviewed head and only it
// wrote), so a fix the reviewer already named is not escalated. It also
// carries the linked issues' trusted spec text (`spec`, pr-verify's
// linkedIssues) and the lines the pull request's last address-feedback commit
// added (`feedback_lines`), so a fix does not cut a line a criterion needs
// just to pass another check. Check names, annotations, logs, findings, spec and
// feedback lines are data: they are copied into the file, capped, and never
// logged or run. After a weaken retry stop on the head (WEAKEN_RETRY) the file
// also carries the runner's fixed `retry` brief.

import { createHash } from "node:crypto";
import { appendFileSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

import { loadRules, webHostsFrom } from "../intake-triage/admit.mjs";
import { timeLimitNoted } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
import { linkedIssues } from "../pr-verify/resolve-pr.mjs";
import { anyListed, countedFetch, createGitHubApi, humanGatedLabelFrom, keepThreads, need, positive, readTriggers, reviewedHeads, reviewerIdFrom, reviewerIdsFrom, SHA, trustedHumansFrom } from "./address-feedback.mjs";
import { failingChecks, prHold, reviewReader } from "./gate-source.mjs";
import { FIX_TRAILER as FEEDBACK_TRAILER } from "./publish-feedback.mjs";

// clear-escalations reads the head the same way, so the reader lives on the
// merge path floor in gate-source.mjs.
export { failingChecks };
import { ACTIONS_APP_ID, retryRung, stopSkip } from "./escalation-routes.mjs";

// The trailer apply-patch.mjs writes on every fix commit, from the ci-context
// row of patch-rules.json; a round is one.
export const FIX_TRAILER = "Lane-Activity: pr-unblock/fix-ci";
const WORKFLOW_PATH = /^\.github\/workflows\/[A-Za-z0-9._-]+\.ya?ml$/;
const MAX_CHECKS = 10;
const MAX_ANNOTATIONS = 20;
const MAX_MESSAGE = 500;
const MAX_EXCERPT = 3000;
const MAX_EXCERPT_LINES = 80;
const MAX_FINDINGS = 10;
const MAX_FINDING = 2000;
// The read job refuses a context file over 1 MiB (pr-run-activity-read.yml,
// "Check the CI context"). Spec and feedback lines each get a byte budget;
// select drops both when the whole file would still pass the limit.
export const CONTEXT_MAX_BYTES = 1048576;
export const MAX_SPEC_BYTES = 196608;
export const MAX_FEEDBACK_BYTES = 65536;

// The fail-routed stop apply-patch.mjs gives a head's first weaken-required
// escalation, as report-escalation.sh status describes it on the head's
// pr-unblock/fix-ci status, and the runner's brief for the fresh fixer round
// that follows: fixed text, never anything a head or a model wrote.
export const WEAKEN_RETRY = "ci-fix-weaken-retry";
// The skip on a head branch a workflow owns and rebuilds.
export const OWNED_BRANCH = "owned-branch";
const WEAKEN_STOPPED = `Lane stopped: ${WEAKEN_RETRY};`;
export const WEAKEN_BRIEF =
  "An earlier fix-ci run on this head could fix a failing check only by weakening a test, and the lane refuses that fix. " +
  "Find a fix in the code under test that keeps every test's assertions and expected values unchanged. " +
  "If the only way to green still weakens a check, escalate weaken-required: this round is the last before a person.";

// A finished fix-ci check by the GitHub Actions app: an earlier attempt on the head.
const earlierAttempt = (run) => run?.status === "completed" && run.app?.id === ACTIONS_APP_ID;

// Whether the head carries the pr-unblock/fix-ci status a weaken retry stop
// posted, by the GitHub Actions bot. Statuses are never removed, so a stop a
// later run cleared still counts.
export const weakenStopped = (statuses) =>
  statuses.some(
    (row) => row?.context === "pr-unblock/fix-ci" && row.creator?.login === "github-actions[bot]" && String(row.description ?? "").startsWith(WEAKEN_STOPPED),
  );

// A commit the lanes App pushed for the activity whose trailer it carries.
const laneCommit = (commit, appId, trailer) =>
  commit.author?.id === appId &&
  String(commit.commit?.message ?? "")
    .split("\n")
    .some((line) => line.replace(/\r$/, "") === trailer);

export function countFixRounds(commits, appId) {
  return commits.filter((commit) => laneCommit(commit, appId, FIX_TRAILER)).length;
}

// The pull request's last address-feedback commit, or undefined.
export const lastFeedbackCommit = (commits, appId) => commits.findLast((commit) => laneCommit(commit, appId, FEEDBACK_TRAILER));

// The context file's text, as main writes it.
export const contextText = (file) => `${JSON.stringify(file, null, 2)}\n`;

// A field's value when the bytes it adds to the file, pretty-printed at its
// depth, fit max; otherwise null. A cut list would read as whole, so a field
// that does not fit is unknown, never partial.
const withinBytes = (value, max) => (Buffer.byteLength(JSON.stringify({ value }, null, 2)) <= max ? value : null);

// The linked issues' spec text, as linkedIssues returns it: each issue's
// number, how it is linked (`refs`: the pull request is one slice of it),
// any Scope line's targets, its body and its counted comments.
export function specField(specText, max = MAX_SPEC_BYTES) {
  const spec = specText.map((issue) => ({
    number: issue.number,
    spec_kind: issue.spec_kind,
    ...(issue.scope !== undefined && { scope: issue.scope }),
    body: typeof issue.body === "string" ? issue.body : null,
    comments: (issue.comments ?? []).map(String),
  }));
  return withinBytes(spec, max);
}

// The non-blank lines a commit's diff adds, by file, from the commits API's
// `patch` (which carries no file header lines). A file that adds lines but
// comes with no patch leaves the lines unknown: null.
export function feedbackLines(files, max = MAX_FEEDBACK_BYTES) {
  const kept = [];
  for (const file of files ?? []) {
    if (typeof file.patch !== "string") {
      if (file.additions > 0) {
        return null;
      }
      continue;
    }
    const lines = file.patch
      .split("\n")
      .filter((line) => line.startsWith("+"))
      .map((line) => line.slice(1).replace(/\r$/, ""))
      .filter((line) => line.trim() !== "");
    if (lines.length > 0) {
      kept.push({ path: String(file.filename ?? ""), lines });
    }
  }
  return withinBytes(kept, max);
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
async function reviewFindings(api, pr, { appId, reviewerId, reviewerIds, trustedHumans, pull }) {
  const [issueComments, reviews, reviewComments, threads] = await Promise.all([
    api.listIssueComments(pr),
    api.listReviews(pr),
    api.listReviewComments(pr),
    api.listThreads(pr),
  ]);
  const triggers = anyListed(reviewComments.map((row) => row.user?.id), reviewerIds) ? await readTriggers({ api, pr, pull }) : null;
  return keepThreads({ threads, reviewComments, reviews, heads: reviewedHeads(issueComments), reviewerId, reviewerIds, appId, trustedHumans, issueComments, triggers })
    .slice(0, MAX_FINDINGS)
    .map((thread) => ({ path: String(thread.path ?? ""), line: thread.line, body: String(thread.comments[0].body).slice(0, MAX_FINDING) }));
}

// readSpec returns linkedIssues' specText for the pull request; ownedBranches
// is merge.refire-skip-branches.
export async function select({ api, pr, repository, appId, reviewerId, reviewerIds = [], trustedHumans = new Set(), maxRounds, humanGatedLabel = "needs-human", ownedBranches = [], readSpec = async () => [], log = (line) => console.log(line) }) {
  const pull = await api.getPull(pr);
  const headSha = pull.head?.sha;
  if (!SHA.test(String(headSha))) {
    throw new Error("the pull request names no head SHA");
  }
  if (pull.head?.repo?.full_name !== repository) {
    throw new Error("the pull request's head is not in this repository");
  }
  if (pull.state !== "open") {
    return { decision: "skip", skipReason: "not-applicable", headSha };
  }
  if (ownedBranches.includes(pull.head?.ref)) {
    return { decision: "skip", skipReason: OWNED_BRANCH, headSha };
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
    readReviews: reviewReader(api, pr),
  });
  if (held) {
    return { decision: "skip", skipReason: "awaiting-human", headSha };
  }
  // A whole listing of settled checks with none failing: every fix-ci stop
  // is gone on this head, round cap included, and `resolved` lets
  // report-stop-status clear its status. A cut-short or unsettled listing
  // decides nothing.
  const runs = await api.listCommitCheckRuns(headSha);
  const failing = failingChecks(runs);
  if (failing.length === 0) {
    const settled = runs.complete === true && runs.every((run) => run.status === "completed");
    return { decision: "skip", ...(settled ? { skipReason: "stop-resolved", resolved: true } : { skipReason: "not-applicable" }), headSha, laneEscalated };
  }
  const commits = await api.listPullCommits(pr);
  const rounds = countFixRounds(commits, appId);
  if (rounds >= maxRounds) {
    return { decision: "escalate", escalationReason: "ci-fix-round-cap", rounds, headSha, laneEscalated };
  }
  const checks = [];
  for (const run of failing) {
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
    review_findings = await reviewFindings(api, pr, { appId, reviewerId, reviewerIds, trustedHumans, pull });
  } catch (error) {
    log(`::warning::the review findings could not be read (${error.message}); the context holds none`);
  }
  // A failed read leaves null: ci-ci.md then escalates any fix that passes
  // only by removing prose.
  let spec = null;
  try {
    spec = specField(await readSpec());
  } catch (error) {
    log(`::warning::the linked issues' spec text could not be read (${error.message}); the context holds null`);
  }
  let feedback_lines = [];
  const feedback = lastFeedbackCommit(commits, appId);
  if (feedback !== undefined) {
    try {
      feedback_lines = feedbackLines((await api.getCommit(feedback.sha)).files);
    } catch (error) {
      feedback_lines = null;
      log(`::warning::the last address-feedback commit could not be read (${error.message}); the context holds null`);
    }
  }
  // A retry after the push job stopped on this head runs one rung up. A
  // weaken-required stop takes its fresh fixer round only on the head's first
  // fix-ci attempt: the dispatcher retries a stopped head once per base tip
  // (fix-ci-restarts), so a stop after an earlier attempt could leave the head
  // red with no retry and no person.
  const modelRung = retryRung(await api.listCheckRuns(headSha, "pr-unblock / apply-patch"));
  const file = { pr, head_sha: headSha, checks, review_findings, spec, feedback_lines };
  if (modelRung === "1" && weakenStopped(await api.listCommitStatuses(headSha))) {
    file.retry = { after: WEAKEN_RETRY, brief: WEAKEN_BRIEF };
  }
  // Some fields are capped by count and length, not bytes, and text that
  // escapes long in JSON (control characters) can push them past the limit.
  if (Buffer.byteLength(contextText(file)) > CONTEXT_MAX_BYTES) {
    file.spec = null;
    file.feedback_lines = null;
    log("::warning::the context file would pass 1 MiB; it holds no spec or feedback lines");
  }
  const weakenRetry = modelRung === "" && !(await api.listCheckRuns(headSha, "pr-unblock / fix-ci")).some(earlierAttempt);
  return { decision: "proceed", rounds, headSha, laneEscalated, modelRung, weakenRetry, file };
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

// merge.refire-skip-branches: OWNED_BRANCHES (a JSON list) when set, else the
// base config's.
async function ownedBranchesOf(env) {
  if (env.OWNED_BRANCHES !== undefined) {
    const list = JSON.parse(env.OWNED_BRANCHES);
    if (!Array.isArray(list) || !list.every((ref) => typeof ref === "string" && ref !== "")) {
      throw new Error("OWNED_BRANCHES is not a JSON list of branch names");
    }
    return list;
  }
  const { ownedBranchesFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
  return ownedBranchesFromBase({ BASE_PATH: env.BASE_PATH || ".base" });
}

// The issue lane's web hosts, which pr-verify.yml hands linkedIssues as
// ISSUE_LANE_WEB_HOSTS: that value when set, else the base config's.
async function webHostsOf(env) {
  if (env.ISSUE_LANE_WEB_HOSTS !== undefined) {
    return webHostsFrom(env.ISSUE_LANE_WEB_HOSTS);
  }
  const { issueLaneWebHostsFromBase } = await import(new URL("../../actions/resolve-config/resolve-config.mjs", import.meta.url).href);
  return issueLaneWebHostsFromBase({ BASE_PATH: env.BASE_PATH || ".base" });
}

export async function main(env, { api, log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "APP_SENDER_ID", "CONTEXT_FILE"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  const maxRounds = positive(env.FIX_CI_ROUNDS ?? (await loopFromBase(env))["fix-ci-rounds"], "FIX_CI_ROUNDS");
  const ownedBranches = await ownedBranchesOf(env);
  // The base checkout's list, the one address-feedback reads.
  const trustedActors = env.TRUSTED_ACTORS || `${env.BASE_PATH || ".base"}/.github/standards/trusted-actors/trusted-actors.json`;
  const reviewerId = reviewerIdFrom(trustedActors);
  const reviewerIds = reviewerIdsFrom(env.REVIEWER_IDS);
  const trustedHumans = trustedHumansFrom(trustedActors);
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      fetch: await countedFetch(),
    });
  const humanGatedLabel = humanGatedLabelFrom(env.TRACKER_CONFIG || `${env.BASE_PATH || ".base"}/.work-item-tracker.json`);
  // linkedIssues takes check-trusted-trigger's github(method, path, body)
  // client: one that throws on GraphQL errors, and one that keeps them for
  // its Refs read.
  const graphql = (keepErrors) => async (_method, _path, body) => {
    const answer = await client.graphqlAnswer(body);
    if (!keepErrors && Array.isArray(answer?.errors) && answer.errors.length > 0) {
      throw new Error("the spec read answered with GraphQL errors");
    }
    return answer;
  };
  // linkedIssues' inputs as pr-verify's resolve-pr.mjs main builds them, the
  // lanes App's bot id as laneAppId. Read here, so a failure leaves null.
  const readSpec = async () => {
    const humans = trustedHumansFrom(trustedActors);
    const taskList = loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url)))["task-list"];
    const webHosts = await webHostsOf(env);
    return (await linkedIssues(graphql(false), graphql(true), env.GITHUB_REPOSITORY, pr, humans, appId, taskList, webHosts)).specText;
  };
  const result = await select({ api: client, pr, repository: env.GITHUB_REPOSITORY, appId, reviewerId, reviewerIds, trustedHumans, maxRounds, humanGatedLabel, ownedBranches, readSpec, log });
  let sha256 = "";
  if (result.file) {
    const text = contextText(result.file);
    writeFileSync(env.CONTEXT_FILE, text);
    sha256 = createHash("sha256").update(text).digest("hex");
  }
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  output("proceed", String(result.decision === "proceed"));
  output("head-sha", result.headSha);
  output("escalation-reason", result.escalationReason ?? "");
  output("context-sha256", sha256);
  // fix-ci-not-run's check (a stop's own skip, so the head's fix-ci runs
  // record it), and whether apply-patch may push past the human-gated label
  // a lane escalation put on.
  output("skip-reason", result.decision === "skip" ? result.skipReason : result.decision === "escalate" ? stopSkip(result.escalationReason) : "");
  output("lane-escalated", String(result.laneEscalated === true));
  output("model-rung", result.modelRung ?? "");
  output("weaken-retry", String(result.weakenRetry === true));
  output("stop-resolved", String(result.resolved === true));
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
