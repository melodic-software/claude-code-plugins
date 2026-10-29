// Whether a lane escalation still put the human-gated label on a pull request,
// read again right before the write runner's apply-patch push
// (pr-run-activity-write.yml, "Read the hold labels from the base"). The
// caller's select job decided it once, before the model turn; a review-lane
// hold posted since, or a person removing and adding the label back, changes
// the answer (gate-source.mjs gateSource). Writes to GITHUB_OUTPUT:
// lane-escalation=true|false.
//
// Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_OUTPUT, PR_NUMBER,
// HEAD_SHA, APP_SENDER_ID, LABEL.

import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { createGitHubApi, need, positive } from "./address-feedback.mjs";
import { gateSource } from "./gate-source.mjs";

export async function main(env, { api, log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "HEAD_SHA", "APP_SENDER_ID", "LABEL"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!/^[0-9a-f]{40}$/.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit SHA");
  }
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      // Each answer's rate-limit reading, for the job-end api-budget notice.
      fetch: rateLimitLatch.guard(globalThis.fetch),
    });
  const isLanesApp = (user) => user?.id === appId && user?.type === "Bot";
  const { source, reason } = gateSource({ timeline: await client.listTimeline(pr), label: env.LABEL, head: env.HEAD_SHA, isLanesApp });
  appendFileSync(env.GITHUB_OUTPUT, `lane-escalation=${source === "lane-escalation"}\n`);
  log(`#${pr} ${env.LABEL}: ${source} (${reason})`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::gate-recheck failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
