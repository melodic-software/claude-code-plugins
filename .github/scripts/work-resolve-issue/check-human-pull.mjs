import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { humanPullsFor } from "../intake-triage/admit.mjs";

const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

export async function main({ env = process.env, github, log = console.log, write = (outputs) => writeOutputs(outputs, env.GITHUB_OUTPUT) } = {}) {
  const repository = env.GITHUB_REPOSITORY ?? "";
  const number = env.ISSUE_NUMBER ?? "";
  if (!REPO.test(repository) || !NUMBER.test(number)) {
    throw new Error("GITHUB_REPOSITORY or ISSUE_NUMBER is not set to a repository and issue number");
  }
  const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
  const client = github ?? createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
  const [pull] = await humanPullsFor(client, repository, Number(number), humans);
  if (pull) {
    log(`::notice title=human pull request::a listed human's open pull request #${pull.number} names issue #${number}, so the run pushes no branch and opens no pull request`);
  }
  write({ pull: pull ? String(pull.number) : "" });
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
