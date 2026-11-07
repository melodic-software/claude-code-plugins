// Starts pr-refine's fix-docs for the one pull request a pull_request_target
// run of pr-unblock-dispatch.yml names (its refine job, ADR 0090), the only
// start fix-docs has: dispatchDocsFixes (fix-docs-dispatch.mjs) reads this PR
// alone, in the listing's shape, and decides once per PR. The dispatch record
// is not read or saved, so each event reads the PR's history afresh. A PR this
// run skips waits for its next event: a push, a reopen or a ready flip.
//
// The trusted-trigger gate refuses a Refine run whose dispatcher run was
// started by anyone but the lanes App or a listed human, and a refused run
// counts toward fix-docs's per-PR cap, so an event from anyone else
// dispatches nothing. A re-run keeps the original event's sender while
// anyone with write access may have started it, so only a first attempt
// (RUN_ATTEMPT exactly 1) dispatches.
//
// Reads only PR_NUMBER and SENDER_ID from the event, as numbers. Logs carry PR numbers,
// SHAs, run ids and counts only. The dispatched run id is appended to
// RUN_IDS_FILE as soon as the dispatch returns, for the job's record step.

import { pathToFileURL } from "node:url";

import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { baseHumanGatedLabel, createGitHubApi, loadBaseLimits, loadBaseTidyCutoffs, TRUSTED_ACTORS_PATH, wrapRunIds } from "./dispatch.mjs";
import { DEFAULTS, dispatchDocsFixes } from "./fix-docs-dispatch.mjs";
import { budgetedFetch } from "./request-budget.mjs";

const PR_NUMBER = /^[1-9][0-9]{0,9}$/;

export async function main(
  env,
  {
    api,
    log = (line) => console.log(line),
    loadLimits = loadBaseLimits,
    loadTidyCutoffs = loadBaseTidyCutoffs,
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
  const appSenderId = /^[1-9][0-9]*$/.test(env.APP_SENDER_ID ?? "") ? Number(env.APP_SENDER_ID) : undefined;
  const sender = /^[1-9][0-9]*$/.test(env.SENDER_ID ?? "") ? Number(env.SENDER_ID) : null;
  if (sender === null || (sender !== appSenderId && !readHumans().has(sender))) {
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
    let gateLabel = null;
    try {
      gateLabel = readGateLabel(env);
    } catch (error) {
      log(`::warning::cannot read the human-gated label from the base tracker binding (${error.message}); it holds every PR it is on`);
    }
    let result;
    try {
      result = await dispatchDocsFixes({
        api: client,
        runId: env.GITHUB_RUN_ID,
        log,
        maxDispatch: limits["fix-docs-per-run"] ?? 2,
        maxRunsPerHead: limits["limit-stops-per-head"] ?? DEFAULTS.maxRunsPerHead,
        tidyCutoffs,
        gateLabel,
        appSenderId,
      });
    } catch (error) {
      log(`::warning::#${number} could not be read (${error.message}); nothing dispatched, the PR's next event retries`);
      return 0;
    }
    log(`dispatched ${result.dispatched.length} run(s), ${result.failed} failure(s)`);
    return result.failed === 0 ? 0 : 1;
  } finally {
    if (budget) {
      log(budget.summary());
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::refine event dispatch failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
