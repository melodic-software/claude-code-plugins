#!/usr/bin/env node
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { loadTrustedList, REPOSITORY, readRerunner } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { ACTIONS_BOT_ID } from "../lib/lane-vocabulary.mjs";

const NUMBER = /^[1-9][0-9]{0,15}$/;
export const GITHUB_ACTIONS_BOT_ID = String(ACTIONS_BOT_ID);

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

export const verdictWake = (env) =>
  env.GITHUB_EVENT_NAME === "workflow_dispatch" &&
  env.GITHUB_RUN_ATTEMPT === "1" &&
  env.GITHUB_REF === "refs/heads/main" &&
  env.ACTOR_ID === GITHUB_ACTIONS_BOT_ID &&
  NUMBER.test(env.DISPATCH_PR ?? "");

export async function main({ env = process.env, actions } = {}) {
  const schedule = env.GITHUB_EVENT_NAME === "schedule";
  let proceed = (schedule && env.GITHUB_RUN_ATTEMPT === "1") || verdictWake(env);
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
