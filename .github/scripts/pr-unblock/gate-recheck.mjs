// Whether a lane escalation still lets the patch-activity push past the
// human-gated label on a pull request, read again right before the write
// runner's apply-patch push (pr-run-activity-write.yml, "Read the hold labels
// from the base"). The caller's select job decided it once, before the model
// turn; anything posted since (a review-lane hold, a person's comment, review
// or label, another escalation) can change the answer. It re-runs the check
// that select ran, on the same reads: prHold for the activity (fix-ci,
// fix-docs, resolve-conflicts and address-feedback on an owner PR), and
// gateSource over the issue comments and label events for address-feedback on
// any other PR (address-feedback.mjs select). Writes to GITHUB_OUTPUT:
// lane-escalation=true|false.
//
// Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_OUTPUT, PR_NUMBER,
// HEAD_SHA, APP_SENDER_ID, LABEL, ACTIVITY; BASE_PATH and TRUSTED_ACTORS as
// address-feedback.mjs ownerAdoption reads them.

import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { createGitHubApi, need, ownerAdoption, ownerAuthored, positive } from "./address-feedback.mjs";
import { commentItems, gateSource, prHold, reviewReader } from "./gate-source.mjs";

const ACTIVITY = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;

export async function main(env, { api, adoption, log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "HEAD_SHA", "APP_SENDER_ID", "LABEL", "ACTIVITY"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!/^[0-9a-f]{40}$/.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit SHA");
  }
  if (!ACTIVITY.test(env.ACTIVITY)) {
    throw new Error("ACTIVITY is not an activity name");
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
  // address-feedback's select reads the issue comments and label events (a
  // pull-requests: read token may), the other selects the REST issue timeline.
  const feedback = env.ACTIVITY === "address-feedback";
  const readTimeline = feedback
    ? async () => [...commentItems(await client.listIssueComments(pr)), ...(await client.listLabelEvents(pr))]
    : () => client.listTimeline(pr);
  let escalated;
  let why;
  if (feedback && !ownerAuthored(await client.getPull(pr), adoption ?? (await ownerAdoption(env, log)))) {
    const { source, reason } = gateSource({ timeline: await readTimeline(), label: env.LABEL, head: env.HEAD_SHA, isLanesApp });
    escalated = source === "lane-escalation";
    why = `${source} (${reason})`;
  } else {
    const hold = await prHold({
      labels: [env.LABEL],
      holdLabels: [],
      gateLabel: env.LABEL,
      head: env.HEAD_SHA,
      activity: env.ACTIVITY,
      appId,
      readTimeline,
      readReviews: reviewReader(client, pr),
    });
    escalated = hold.laneEscalated;
    why = escalated ? "lane-escalation" : hold.why;
  }
  appendFileSync(env.GITHUB_OUTPUT, `lane-escalation=${escalated}\n`);
  log(`#${pr} ${env.LABEL} for ${env.ACTIVITY}: ${why}`);
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
