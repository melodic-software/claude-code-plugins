#!/usr/bin/env node
// who.mjs: the "Check who started the run" step of pr-merge's merge and
// enable-auto-merge jobs. A scheduled run proceeds: nobody starts it. Any
// other run proceeds only when this run attempt's record shows its actor and
// its triggering actor (who last re-ran it) are each a listed human, by id,
// since a login can be released and registered by someone else. An
// unreadable record, a record for another run or attempt, or a missing id
// stops the run quietly. One REST read with the job's token (actions: read).
//
// Environment:
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN
//   GITHUB_REPOSITORY    owner/repo
//   GITHUB_RUN_ID        this run
//   GITHUB_RUN_ATTEMPT   this run attempt
//   GITHUB_EVENT_NAME    this run's event
//   TRUSTED_ACTORS_PATH  trusted-actors.json from the default branch tip
//   STOP_NOTICE          what the notice says happens instead when it stops
//   GITHUB_OUTPUT        receives proceed=true or proceed=false
//   GITHUB_API_URL
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const RUN_ATTEMPT = /^[1-9][0-9]{0,4}$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

export async function main({ env = process.env, actions } = {}) {
  let proceed = env.GITHUB_EVENT_NAME === "schedule";
  let who = "an unknown account";
  if (!proceed) {
    try {
      const { GITHUB_REPOSITORY: repo, GITHUB_RUN_ID: runId, GITHUB_RUN_ATTEMPT: attempt } = env;
      if (!REPO.test(repo ?? "") || !RUN_ID.test(runId ?? "") || !RUN_ATTEMPT.test(attempt ?? "")) {
        throw new Error("the run is not named");
      }
      const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
      actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
      const run = await actions("GET", `/repos/${repo}/actions/runs/${runId}`);
      if (String(run?.id) !== runId || run?.run_attempt !== Number(attempt)) {
        throw new Error("the run record is not this run attempt's");
      }
      if (typeof run.triggering_actor?.login === "string") {
        who = run.triggering_actor.login;
      }
      proceed = [run.actor?.id, run.triggering_actor?.id].every((id) => Number.isInteger(id) && humans.has(id));
    } catch (error) {
      console.log(`::warning title=who::${escapeCommand(error?.message ?? error)}; read as not a listed human`);
    }
  }
  if (!proceed) {
    console.log(`::notice::started by ${escapeCommand(who)}, who is not a listed human; ${escapeCommand(env.STOP_NOTICE ?? "")}`);
  }
  appendFileSync(env.GITHUB_OUTPUT, `proceed=${proceed}\n`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
