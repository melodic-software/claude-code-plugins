// Starts the pr-unblock lane's review-dependency activity for each open
// Dependabot pull request dependency-classify.mjs sorts `review`, from the
// same dispatcher run as dispatch.mjs (pr-unblock-dispatch.yml), so the
// trigger gate and the broker check it as they check a resolve-conflicts
// dispatch. A head that already carries a pr-unblock / review-dependency check
// run was reviewed, unless the head's newest pr-unblock /
// apply-dependency-verdict check run skipped no-model-turn: the
// review-dependency check runs that started before it handled nothing, so the
// head is dispatched again. A verdict check that is a lane stop (a reason
// escalation-routes.json routes to a failing status) or a kill-switch stop
// releases them the same way, until `limits.limit-stops-per-head` such stops stand on the head, as
// in dispatch.mjs. The model job's own selection decides the round
// cap, and every such round posts its round marker. A limit stop holds the
// head only until its limit resets, at most `limits.limit-stops-per-head`
// times (limit-stop.mjs), as in dispatch.mjs. Logs carry PR numbers, SHAs and
// run ids only.
//
// Reads are spent only where they can change the decision: none once
// maxDispatch is reached, none for a head the record holds as reviewed, and
// no commits or files for a red ci-status, which is review tier on its own
// (dependency-classify.mjs classify). A head is recorded only once a verdict
// check started after its newest review-dependency check, or that check is a
// select job skip no verdict follows, so a no-model-turn verdict still to come
// can release it.

import { DEPENDABOT_ID, DEPENDABOT_LOGIN, RED } from "./dependency-classify.mjs";
import { isPrUnblockTitle } from "../lib/run-title.mjs";
import { emptyRecord, isHandled, markHandled, sendDispatch, startOf } from "./dispatch-record.mjs";
import { LIMIT_DEFAULTS } from "../work-resolve-issue/limits.mjs";
import { anyHandles, headLagStop, permanentlyHandles, releasedBy, stopRelease } from "./limit-stop.mjs";
import { ciStatusOf, classifyPull, commitFilesReader, GATE_HOLD_SKIP, gateCheckRuns, gateHoldOnly, newestOf, newestRound } from "./review-dependency.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  checkName: "pr-unblock / review-dependency",
  // The verdict job's check: its no-model-turn skip releases the round's
  // review-dependency check runs.
  verdictCheckName: "pr-unblock / apply-dependency-verdict",
  // The GitHub Actions app, as in dispatch.mjs.
  appId: 15368,
  // Judgment: one model run per PR, a few Dependabot PRs open at a time.
  maxDispatch: 2,
});

// The neutral titles review-dependency-not-run posts from the select job's
// skip reasons (review-dependency.mjs select): no verdict job follows them,
// so no no-model-turn verdict can release the head. The select job's
// superseded-sha lands on the head it was sent for, which the PR has left;
// the same title on the head read here, the PR's current one, is the gate's
// head-lag stop, which did no work, so lagStopsRelease sends it again
// (limit-stop.mjs) and it is not recorded.
const NOT_APPLICABLE = "Skipped: not-applicable";
const TERMINAL_SKIPS = new Set(["Skipped: awaiting-human", NOT_APPLICABLE, "Skipped: superseded-sha"]);
const sortedBeforeGateEnd = (run, gateEnd) => run.output?.title === NOT_APPLICABLE && !(startOf(run) > gateEnd);

const GATE_JOB = /\/actions\/runs\/([1-9][0-9]*)\/job\/([1-9][0-9]*)$/;

const gateFailedInRollup = (node, appId) =>
  (node.commits?.nodes?.[0]?.commit?.statusCheckRollup?.contexts?.nodes ?? []).some(
    (context) => context?.__typename === "CheckRun" && context.name === "CI Status" && context.conclusion === "FAILURE" && context.checkSuite?.app?.databaseId === appId,
  );

export async function rerunVerdictHold({ api, node, appId, laneAppId }) {
  const gate = newestOf(await api.listCheckRuns({ sha: node.headRefOid, checkName: "CI Status", appId }));
  if (gate?.status !== "completed" || gate.conclusion !== "failure" || gateHoldOnly(await api.listAnnotations(gate.id), node.number) !== "verdict") {
    return null;
  }
  const round = newestRound(await api.listIssueComments(node.number), laneAppId);
  if (round?.head !== node.headRefOid || round.verdict !== "merge" || !(Date.parse(round.createdAt) > Date.parse(gate.started_at))) {
    return null;
  }
  const [, runId, jobId] = GATE_JOB.exec(String(gate.details_url ?? "")) ?? [];
  const jobs = runId ? ((await api.readLatestJobs(runId))?.jobs ?? []) : [];
  const job = jobs.find((entry) => String(entry.id) === jobId && String(entry.check_run_url ?? "").endsWith(`/check-runs/${gate.id}`));
  if (!job) {
    throw new Error(`CI Status check run ${gate.id} names no job of its run`);
  }
  await api.rerunJob(job.id);
  return job.id;
}

async function listAll(api, base) {
  const nodes = [];
  let after;
  for (;;) {
    const page = await api.listOpenPulls({ base, after });
    nodes.push(...page.nodes);
    if (!page.pageInfo.hasNextPage) {
      return nodes;
    }
    after = page.pageInfo.endCursor;
  }
}

export async function dispatchDependencyReviews({
  api,
  runId,
  log,
  base = DEFAULTS.base,
  workflow = DEFAULTS.workflow,
  checkName = DEFAULTS.checkName,
  verdictCheckName = DEFAULTS.verdictCheckName,
  appId = DEFAULTS.appId,
  laneAppId,
  maxDispatch = DEFAULTS.maxDispatch,
  config = null,
  policy,
  repository,
  provenance,
  listed,
  record = emptyRecord(),
  now = Date.now(),
  limits,
}) {
  const candidates = (listed ?? (await listAll(api, base)))
    .filter((node) => node.isDraft === false && node.isCrossRepository === false && node.baseRefName === base && node.author?.databaseId === DEPENDABOT_ID)
    .sort((a, b) => a.number - b.number);
  const dispatched = [];
  let failed = 0;
  let sent = 0;
  let active = null;
  for (const node of candidates) {
    if (laneAppId !== undefined && gateFailedInRollup(node, appId)) {
      try {
        const job = await rerunVerdictHold({ api, node, appId, laneAppId });
        if (job !== null) {
          log(`rerun: #${node.number}: CI Status at ${node.headRefOid} holds only for a merge verdict the lanes App posted after it started; re-ran its job ${job}`);
          continue;
        }
      } catch (error) {
        log(`::warning::#${node.number}: could not re-run CI Status at ${node.headRefOid} for its merge verdict: ${error.message}; a later run retries`);
      }
    }
    if (sent >= maxDispatch) {
      log(`defer #${node.number}: ${maxDispatch} review dispatches this run; left for a later run unread`);
      continue;
    }
    if (isHandled(record, checkName, node.headRefOid)) {
      log(`skip #${node.number}: head ${node.headRefOid} already has a ${checkName} check run (recorded)`);
      continue;
    }
    let tier;
    let existing;
    try {
      const ci = await gateCheckRuns((name) => api.listCheckRuns({ sha: node.headRefOid, checkName: name, appId }));
      const ciStatus = ciStatusOf(ci);
      // The same reads the model job's select step classifies from.
      tier = RED.has(ciStatus) ? "review" : (
        await classifyPull({
          pull: {
            user: { login: DEPENDABOT_LOGIN },
            head: { ref: node.headRefName },
            title: node.title,
            body: node.body,
            labels: node.labels?.nodes ?? [],
            changed_files: node.changedFiles,
            commits: node.commits?.totalCount,
          },
          ciStatus,
          commits: await api.listPullCommits(node.number),
          files: await api.listPullFiles(node.number),
          config,
          policy,
          repository,
          readCommitFiles: commitFilesReader(api),
          provenance,
        })
      ).tier;
      if (tier !== "review") {
        continue;
      }
      existing = await api.listCheckRuns({ sha: node.headRefOid, checkName, appId });
      if (ciStatus === "success") {
        existing = existing.filter((run) => !(run.status === "completed" && run.conclusion === "neutral" && run.output?.title === `Skipped: ${GATE_HOLD_SKIP}`));
      }
      const gate = newestOf(ci);
      const gateEnd = gate?.status === "completed" ? Date.parse(gate.completed_at ?? "") : Number.NaN;
      existing = existing.filter((run) => !(sortedBeforeGateEnd(run, gateEnd) && Number.isFinite(gateEnd)));
      // A round whose verdict job skipped no-model-turn handled nothing, and
      // one whose verdict job stopped on a reason routed to a failing status,
      // or that the kill switch stopped (limit-stop.mjs releasesHead), is
      // retried on the same head, a fresh model session, until
      // limit-stops-per-head such stops stand on it: either way the
      // review-dependency check runs that started before that verdict job
      // stop counting, so this run dispatches the head again. A limit stop is
      // not released that way, though its round's verdict also finds no model
      // turn: it holds the head until its limit resets.
      let verdicts = [];
      if (anyHandles(existing, { now, limits, lagStopsRelease: true })) {
        verdicts = await api.listCheckRuns({ sha: node.headRefOid, checkName: verdictCheckName, appId });
        const newest = verdicts.reduce((a, b) => (startOf(b) > startOf(a) ? b : a), verdicts[0]);
        if (newest?.status === "completed" && newest.conclusion === "neutral" && newest.output?.title === "Skipped: no-model-turn") {
          existing = releasedBy(existing, startOf(newest), limits);
        } else {
          const cap = (limits ?? LIMIT_DEFAULTS)["limit-stops-per-head"];
          const { cut, stops } = stopRelease(verdicts, cap);
          existing = releasedBy(existing, cut, limits);
          if (cut === null && stops >= cap) {
            log(`::warning::#${node.number}: head ${node.headRefOid}'s ${verdictCheckName} stopped ${stops} time(s), the most one head gets; no review-dependency retry until a new push`);
          }
        }
      }
      // Until a verdict check started after the newest review-dependency
      // check, a no-model-turn verdict may still release the head, so it is
      // not recorded yet; a newest check that is a select job skip no verdict
      // job follows records at once. A limit stop never records the head, or
      // its reset could not release it. An unreadable start records nothing.
      const newestCheck = Math.max(...existing.map(startOf));
      const last = existing.find((run) => startOf(run) === newestCheck);
      const terminal = last?.status === "completed" && last.conclusion === "neutral" && TERMINAL_SKIPS.has(last.output?.title) && !sortedBeforeGateEnd(last, gateEnd);
      if (permanentlyHandles(existing, { limits, lagStopsRelease: true }) && (terminal || verdicts.some((run) => startOf(run) > newestCheck))) {
        markHandled(record, checkName, node.headRefOid);
      }
    } catch (error) {
      // A read that fails, whatever GitHub answered, holds the PR for a later run.
      log(`::warning::#${node.number}: could not read check runs for ${node.headRefOid}: ${error.message}; skipped, a later run retries`);
      continue;
    }
    if (anyHandles(existing, { now, limits, lagStopsRelease: true })) {
      log(`skip #${node.number}: head ${node.headRefOid} already has a ${checkName} check run`);
      continue;
    }
    try {
      active ??= (await api.listWorkflowRuns(workflow)).filter((run) => run.status !== "completed");
    } catch (error) {
      log(`::warning::#${node.number}: ${workflow} run listing ${error.rateLimited ? "is rate limited" : "could not be read"} (${error.message}); skipped, a later run retries`);
      continue;
    }
    const inFlight = active.find((run) => isPrUnblockTitle(run.display_title, "review-dependency", node.number));
    if (inFlight) {
      log(`skip #${node.number}: ${workflow} run ${inFlight.id} for review-dependency is not done yet`);
      continue;
    }
    if (existing.some(headLagStop)) {
      log(`refire: #${node.number}: head ${node.headRefOid}'s ${checkName} was stopped head-lag; sending it again`);
    }
    sent += 1;
    const id = await sendDispatch(api, log, {
      workflow,
      base,
      node,
      label: "review-dependency ",
      inputs: { "pr-number": String(node.number), activity: "review-dependency", "dispatcher-run-id": String(runId) },
    });
    if (id === null) {
      failed += 1;
    } else {
      dispatched.push({ number: node.number, workflowRunId: id });
    }
  }
  return { dispatched, failed };
}
