// Starts pr-refine's fix-docs for the one pull request a pull_request_target
// run of pr-unblock-dispatch.yml names (its refine job, ADR 0090), the only
// start fix-docs has: dispatchDocsFixes (fix-docs-dispatch.mjs) reads this PR
// alone, in the listing's shape, and decides once per PR. The dispatch record
// is not read or saved, so each event reads the PR's history afresh. A PR this
// run skips waits for its next event: a push, a reopen or a ready flip.
//
// It also starts each pr-refine activity the base config's
// refine-dispatch.activities lists, once per event, with no PR read: an id
// outside REFINE_ACTIVITIES fails the run and dispatches nothing. Only a
// listed human's event starts one, never the lanes App's: the App's push of
// an activity's patch would start that activity again.
//
// The trusted-trigger gate refuses a Refine run whose dispatcher run was
// started by anyone but the lanes App or a listed human, and a refused run
// counts toward fix-docs's per-PR cap, so an event from anyone else
// dispatches nothing. A re-run keeps the original event's sender while
// anyone with write access may have started it, so only a first attempt
// (RUN_ATTEMPT exactly 1) dispatches.
//
// Reads only PR_NUMBER and SENDER_ID from the event, as numbers. Logs carry PR numbers,
// SHAs, run ids and counts only. Each dispatched run id is appended to
// RUN_IDS_FILE as soon as its dispatch returns, for the job's record steps,
// which hold one record per line: fix-docs's and one per REFINE_ACTIVITIES id.
import { runAsScript } from "../lib/run-main.mjs";
import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { baseHumanGatedLabel, createGitHubApi, loadBaseLimits, loadBaseRefineActivities, loadBaseTidyCutoffs, TRUSTED_ACTORS_PATH, wrapRunIds } from "./dispatch.mjs";
import { RUN_ID } from "./dispatch-record.mjs";
import { DEFAULTS, dispatchDocsFixes } from "./fix-docs-dispatch.mjs";
import { budgetedFetch } from "./request-budget.mjs";

const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
const userId = (value) => (/^[1-9][0-9]*$/.test(value ?? "") ? Number(value) : undefined);

// The pr-refine activities refine-dispatch.activities may name. Each adds one
// line to RUN_IDS_FILE, so pr-unblock-dispatch.yml's refine job holds a
// record slot for fix-docs and one per id here (workflow-gates.test.mjs).
export const REFINE_ACTIVITIES = Object.freeze(["fix-marker"]);

export async function main(
  env,
  {
    api,
    log = (line) => console.log(line),
    loadLimits = loadBaseLimits,
    loadTidyCutoffs = loadBaseTidyCutoffs,
    loadActivities = loadBaseRefineActivities,
    readGateLabel = baseHumanGatedLabel,
    readHumans = () => loadTrustedList(`${env.BASE_PATH || ".base"}/${TRUSTED_ACTORS_PATH}`).humans,
  } = {},
) {
  for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_RUN_ID", "RUN_IDS_FILE"]) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
  if (!PR_NUMBER.test(env.PR_NUMBER ?? "")) {
    throw new Error("PR_NUMBER is not a pull request number");
  }
  const number = Number(env.PR_NUMBER);
  if (env.RUN_ATTEMPT !== "1") {
    log(`::notice::skip fix-docs #${number}: this run is not its event's first attempt, and a re-run keeps the event's sender whoever started it; the PR's next event decides`);
    return 0;
  }
  const appSenderId = userId(env.APP_SENDER_ID);
  const sender = userId(env.SENDER_ID);
  const fromApp = sender !== undefined && sender === appSenderId;
  const fromHuman = sender !== undefined && !fromApp && readHumans().has(sender);
  if (!fromApp && !fromHuman) {
    log(`skip fix-docs #${number}: its event's sender is neither the lanes App nor a listed human; only an event one of them sends starts it`);
    return 0;
  }
  const budget = api ? null : budgetedFetch({ log });
  const base =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      fetch: budget.fetch,
    });
  const client = { ...wrapRunIds(base, env), listDocsFixCandidates: () => base.readDocsFixCandidate(number) };
  try {
    const limits = await loadLimits(env);
    const tidyCutoffs = await loadTidyCutoffs(env);
    const activities = [...new Set(await loadActivities(env))];
    const unknown = activities.filter((activity) => !REFINE_ACTIVITIES.includes(activity));
    if (unknown.length > 0) {
      log(`::error::refine-dispatch.activities names ${unknown.length} id(s) outside ${REFINE_ACTIVITIES.join(", ")}; nothing dispatched for #${number}`);
      return 1;
    }
    let gateLabel = null;
    try {
      gateLabel = readGateLabel(env);
    } catch (error) {
      log(`::warning::cannot read the human-gated label from the base tracker binding (${error.message}); it holds every PR it is on`);
    }
    let failed = 0;
    try {
      const result = await dispatchDocsFixes({
        api: client,
        runId: env.GITHUB_RUN_ID,
        log,
        maxDispatch: limits["fix-docs-per-run"] ?? 2,
        maxRunsPerHead: limits["limit-stops-per-head"] ?? DEFAULTS.maxRunsPerHead,
        tidyCutoffs,
        gateLabel,
        appSenderId,
      });
      failed += result.failed;
      log(`dispatched ${result.dispatched.length} fix-docs run(s), ${result.failed} failure(s)`);
    } catch (error) {
      log(`::warning::#${number} could not be read (${error.message}); no fix-docs dispatched, the PR's next event retries`);
    }
    if (activities.length > 0 && fromApp) {
      log(`skip ${activities.join(", ")} #${number}: the lanes App sent this event, and its push of a patch would start the activity again`);
    }
    for (const activity of fromHuman ? activities : []) {
      try {
        const { workflowRunId } = await client.dispatchWorkflow({
          workflow: DEFAULTS.workflow,
          ref: `refs/heads/${DEFAULTS.base}`,
          inputs: { "pr-number": String(number), activity, "dispatcher-run-id": String(env.GITHUB_RUN_ID) },
        });
        if (!RUN_ID.test(String(workflowRunId))) {
          failed += 1;
          log(`::error::#${number}: ${activity} dispatch returned no valid workflow_run_id`);
          continue;
        }
        log(`dispatched ${activity} #${number} workflow_run_id=${workflowRunId}`);
      } catch (error) {
        failed += 1;
        log(`::error::#${number}: ${activity} dispatch failed: ${error.message}`);
      }
    }
    return failed === 0 ? 0 : 1;
  } finally {
    if (budget) {
      log(budget.summary());
    }
  }
}

runAsScript(import.meta.url, "refine event dispatch", () => main(process.env));
