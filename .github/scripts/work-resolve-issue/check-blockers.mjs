#!/usr/bin/env node
// check-blockers.mjs: the issue lane's blocker gate, in the admit job before
// any model run. An issue a blocker still blocks does not run (owner decision
// Q95): `proceed` is false, agent-ready stays on, and a notice names those
// blockers. A blocker stops blocking only as admission and work-unblock judge
// it (admit.mjs blockerDone): a merged pull request, or an issue here closed
// as completed with a trusted close. work-unblock's sweep re-fires the issue
// once none blocks. A blocker list or close it cannot read also skips, with a
// warning, so the sweep retries it; neither case fails the job or hands the
// issue to a person. No model, no write.
//
// Environment:
//   GH_TOKEN             the job's GITHUB_TOKEN (issues: read)
//   GITHUB_REPOSITORY    owner/repo
//   ISSUE_NUMBER         the issue agent-ready was added to
//   TRUSTED_ACTORS_PATH  the default branch's trusted-actor list
//   GITHUB_OUTPUT        receives proceed=true|false
//   GITHUB_API_URL
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, isTrustedClose, loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { blockersOf, stillBlocking } from "../intake-triage/admit.mjs";

const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

// `#n` for a blocker in this repository, `owner/repo#n` for one elsewhere.
const named = (blocker, repository) => {
  const repo = String(blocker?.repository_url ?? "").match(/\/repos\/([^/]+\/[^/]+)$/)?.[1] ?? "?";
  return `${repo.toLowerCase() === repository.toLowerCase() ? "" : repo}#${blocker?.number}`;
};

export async function main({ env = process.env, github, log = console.log, write = (outputs) => writeOutputs(outputs, env.GITHUB_OUTPUT) } = {}) {
  const repository = env.GITHUB_REPOSITORY ?? "";
  const number = env.ISSUE_NUMBER ?? "";
  let pending;
  try {
    if (!REPO.test(repository) || !NUMBER.test(number)) {
      throw new Error("GITHUB_REPOSITORY or ISSUE_NUMBER is not set to a repository and issue number");
    }
    const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    const client = github ?? createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const trusted = async (blocker) => isTrustedClose(client, repository, await client("GET", `/repos/${repository}/issues/${blocker}`), humans);
    pending = await stillBlocking(await blockersOf(client, `/repos/${repository}/issues/${number}`), repository, trusted);
  } catch (error) {
    log(`::warning title=blockers unread::the run is skipped and agent-ready kept: its blockers could not be read (${String(error?.message ?? error).replace(/[\r\n%]/g, " ")}); work-unblock's sweep re-fires it`);
    write({ proceed: "false" });
    return 0;
  }
  if (pending.length > 0) {
    log(`::notice title=blocked::the run is skipped and agent-ready kept while ${pending.map((blocker) => named(blocker, repository)).join(", ")} still blocks it (not a merged pull request or an issue here closed as completed by a listed human or a merge); work-unblock's sweep re-fires it once none does`);
    write({ proceed: "false" });
    return 0;
  }
  write({ proceed: "true" });
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
