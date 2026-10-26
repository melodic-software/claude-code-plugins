#!/usr/bin/env node
// who.mjs: the "Check who started the run" step of pr-merge's merge and
// enable-auto-merge jobs. A scheduled run's first attempt proceeds: nobody
// starts it. A re-run keeps its event, so a later attempt of a scheduled run
// proceeds only when the account that started this attempt is a listed human.
// Any other run proceeds only when its actor (ACTOR_ID) and the account that
// started this attempt are each a listed human. Both are matched by id, since
// a login can be released and registered by someone else; the attempt's
// starter is read by id from this run's own record with readRerunner. An
// unreadable record or list, a record for another run or attempt, or a
// missing id stops the run quietly. At most one REST read, with the job's
// token (actions: read).
//
// Environment:
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN
//   ACTOR_ID             the run's actor id
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

import { createGitHub, loadTrustedList, REPOSITORY, readRerunner } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

const NUMBER = /^[1-9][0-9]{0,15}$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

export async function main({ env = process.env, actions } = {}) {
  const schedule = env.GITHUB_EVENT_NAME === "schedule";
  let proceed = schedule && env.GITHUB_RUN_ATTEMPT === "1";
  let rerunner;
  if (!proceed) {
    try {
      if (!REPOSITORY.test(env.GITHUB_REPOSITORY ?? "")) {
        throw new Error("GITHUB_REPOSITORY is not owner/repo");
      }
      const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
      if (schedule || (NUMBER.test(env.ACTOR_ID ?? "") && humans.has(Number(env.ACTOR_ID)))) {
        actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
        rerunner = await readRerunner(actions, env.GITHUB_REPOSITORY, String(env.GITHUB_RUN_ID ?? ""), String(env.GITHUB_RUN_ATTEMPT ?? ""));
        proceed = humans.has(rerunner);
      }
    } catch (error) {
      console.log(`::warning title=who::${escapeCommand(error?.message ?? error)}; read as not a listed human`);
    }
  }
  if (!proceed) {
    const who = [!schedule && `actor id ${env.ACTOR_ID || "unset"}`, rerunner !== undefined && `re-runner id ${rerunner}`].filter(Boolean).join(", ");
    console.log(`::notice::started by an account that is not a listed human${who ? ` (${escapeCommand(who)})` : ""}; ${escapeCommand(env.STOP_NOTICE ?? "")}`);
  }
  appendFileSync(env.GITHUB_OUTPUT, `proceed=${proceed}\n`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
