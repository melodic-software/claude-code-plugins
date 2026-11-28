import { DEPENDABOT_ID, DEPENDABOT_LOGIN, RED } from "./dependency-classify.mjs";
import { isPrUnblockTitle } from "../lib/run-title.mjs";
import { emptyRecord, isHandled, markHandled, sendDispatch, startOf } from "./dispatch-record.mjs";
import { LIMIT_DEFAULTS } from "../work-resolve-issue/limits.mjs";
import { anyHandles, headLagStop, permanentlyHandles, releasedBy, stopRelease } from "./limit-stop.mjs";
import { postingAttempt } from "../../actions/report-check-run/posting-run.mjs";
import { ciStatusOf, classifyPull, commitFilesReader, GATE_HOLD_SKIP, gateCheckRuns, gateHoldOnly, newestOf, newestRound } from "./review-dependency.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  checkName: "pr-unblock / review-dependency",
  verdictCheckName: "pr-unblock / apply-dependency-verdict",
  appId: 15368,
  maxDispatch: 2,
});

const TERMINAL_SKIPS = new Set(["Skipped: awaiting-human", "Skipped: superseded-sha"]);
const NOT_APPLICABLE = "Skipped: not-applicable";

async function sortedBeforeGateEnd(api, run, gateEnd) {
  if (!(startOf(run) > gateEnd)) {
    return true;
  }
  const [runId, attempt] = String(postingAttempt(run) ?? "").split(":");
  if (!attempt) {
    return false;
  }
  const starts = ((await api.readLatestJobs(runId))?.jobs ?? []).filter((job) => String(job.run_attempt) === attempt).map(startOf);
  return starts.length > 0 && Math.min(...starts) < gateEnd;
}

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
      const gateEnd = RED.has(ciStatus) ? Date.parse(newestOf(ci)?.completed_at ?? "") : Number.NaN;
      if (Number.isFinite(gateEnd)) {
        const kept = [];
        for (const run of existing) {
          if (run.output?.title !== NOT_APPLICABLE || !(await sortedBeforeGateEnd(api, run, gateEnd))) {
            kept.push(run);
          }
        }
        existing = kept;
      }
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
      const newestCheck = Math.max(...existing.map(startOf));
      const last = existing.find((run) => startOf(run) === newestCheck);
      const terminal = last?.status === "completed" && last.conclusion === "neutral" && TERMINAL_SKIPS.has(last.output?.title);
      if (permanentlyHandles(existing, { limits, lagStopsRelease: true }) && (terminal || verdicts.some((run) => startOf(run) > newestCheck))) {
        markHandled(record, checkName, node.headRefOid);
      }
    } catch (error) {
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
