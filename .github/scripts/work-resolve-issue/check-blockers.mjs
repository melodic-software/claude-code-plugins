#!/usr/bin/env node
// check-blockers.mjs: the issue lane's blocker gate, in the admit job before
// any model run. An issue with an open blocked_by issue or pull request does
// not run (owner decision Q95): `proceed` is false, agent-ready stays on, and a
// notice names the open blockers. work-unblock's sweep re-fires the issue once
// none is open. A blocker list it cannot read also skips, with a warning, so the
// sweep retries it; neither case fails the job or hands the issue to a person.
// No model, no write.
//
// Environment:
//   GH_TOKEN             the job's GITHUB_TOKEN (issues: read)
//   GITHUB_REPOSITORY    owner/repo
//   ISSUE_NUMBER         the issue agent-ready was added to
//   GITHUB_OUTPUT        receives proceed=true|false
//   GITHUB_API_URL
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { blockersOf, openBlockers } from "../intake-triage/admit.mjs";

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
  let open;
  try {
    if (!REPO.test(repository) || !NUMBER.test(number)) {
      throw new Error("GITHUB_REPOSITORY or ISSUE_NUMBER is not set to a repository and issue number");
    }
    const client = github ?? createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    open = openBlockers(await blockersOf(client, `/repos/${repository}/issues/${number}`));
  } catch (error) {
    log(`::warning title=blockers unread::the run is skipped and agent-ready kept: its blocker list could not be read (${String(error?.message ?? error).replace(/[\r\n%]/g, " ")}); work-unblock's sweep re-fires it`);
    write({ proceed: "false" });
    return 0;
  }
  if (open.length > 0) {
    log(`::notice title=blocked::the run is skipped and agent-ready kept while ${open.map((blocker) => named(blocker, repository)).join(", ")} stays open; work-unblock's sweep re-fires it once no blocker is open`);
    write({ proceed: "false" });
    return 0;
  }
  write({ proceed: "true" });
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
