// Starts the pr-unblock lane's review-dependency activity for each open
// Dependabot pull request dependency-classify.mjs sorts `review`, from the
// same dispatcher run as dispatch.mjs (pr-unblock-dispatch.yml), so the
// trigger gate and the broker check it as they check a resolve-conflicts
// dispatch. A head that already carries a pr-unblock / review-dependency check
// run was reviewed; the model job's own selection decides the round cap.
// Logs carry PR numbers, SHAs and run ids only.
//
// Reads are spent only where they can change the decision: none once
// maxDispatch is reached, none for a head the record holds as reviewed, and
// no commits or files for a red ci-status, which is review tier on its own
// (dependency-classify.mjs classify).

import { RED } from "./dependency-classify.mjs";
import { emptyRecord, isHandled, markHandled } from "./dispatch-record.mjs";
import { ciStatusOf, classifyPull, commitFilesReader } from "./review-dependency.mjs";

export const DEFAULTS = Object.freeze({
  base: "main",
  workflow: "pr-unblock.yml",
  checkName: "pr-unblock / review-dependency",
  // The GitHub Actions app, as in dispatch.mjs.
  appId: 15368,
  // Judgment: one model run per PR, a few Dependabot PRs open at a time.
  maxDispatch: 2,
});

const RUN_ID = /^[1-9][0-9]{0,14}$/;

const handles = (run) =>
  !(run.status === "completed" && run.conclusion === "neutral" && String(run.output?.title ?? "").startsWith("Skipped: untrusted-trigger"));

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
  appId = DEFAULTS.appId,
  maxDispatch = DEFAULTS.maxDispatch,
  config = null,
  policy,
  repository,
  provenance,
  listed,
  record = emptyRecord(),
}) {
  const candidates = (listed ?? (await listAll(api, base)))
    .filter((node) => node.isDraft === false && node.isCrossRepository === false && node.baseRefName === base)
    .filter((node) => node.author?.login === "dependabot[bot]")
    .sort((a, b) => a.number - b.number);
  const dispatched = [];
  let failed = 0;
  let sent = 0;
  for (const node of candidates) {
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
      const ci = await api.listCheckRuns({ sha: node.headRefOid, checkName: "ci-status", appId });
      const ciStatus = ciStatusOf(ci);
      // The same reads the model job's select step classifies from.
      tier = RED.has(ciStatus) ? "review" : (
        await classifyPull({
          pull: {
            user: { login: node.author.login },
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
      if (existing.some((run) => run.status === "completed" && handles(run))) {
        markHandled(record, checkName, node.headRefOid);
      }
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: could not read check runs for ${node.headRefOid}: ${error.message}`);
      continue;
    }
    if (existing.some(handles)) {
      log(`skip #${node.number}: head ${node.headRefOid} already has a ${checkName} check run`);
      continue;
    }
    sent += 1;
    try {
      const { workflowRunId } = await api.dispatchWorkflow({
        workflow,
        ref: `refs/heads/${base}`,
        inputs: { "pr-number": String(node.number), activity: "review-dependency", "dispatcher-run-id": String(runId) },
      });
      const id = String(workflowRunId);
      if (!RUN_ID.test(id)) {
        failed += 1;
        log(`::error::#${node.number}: dispatch returned no valid workflow_run_id`);
        continue;
      }
      dispatched.push({ number: node.number, workflowRunId: id });
      log(`dispatched review-dependency #${node.number} head ${node.headRefOid} workflow_run_id=${id}`);
    } catch (error) {
      failed += 1;
      log(`::error::#${node.number}: dispatch failed: ${error.message}`);
    }
  }
  return { dispatched, failed };
}
