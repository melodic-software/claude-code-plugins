import { runAsScript } from "../lib/run-main.mjs";
import { loadTrustedList, trustedListPath } from "../lib/trusted-actors.mjs";
import { baseHumanGatedLabel, createGitHubApi, loadBaseLimits, loadBaseRefineActivities, loadBaseTidyCutoffs, wrapRunIds } from "./dispatch.mjs";
import { RUN_ID } from "./dispatch-record.mjs";
import { DEFAULTS, dispatchDocsFixes } from "./fix-docs-dispatch.mjs";
import { budgetedFetch } from "./request-budget.mjs";

const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
const userId = (value) => (/^[1-9][0-9]*$/.test(value ?? "") ? Number(value) : undefined);

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
    readHumans = () => loadTrustedList(trustedListPath(env)).humans,
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
