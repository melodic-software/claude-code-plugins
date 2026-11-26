import { appendFileSync } from "node:fs";

import { runAsScript } from "../lib/run-main.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { createGitHubApi, laneReader, need, ownerAdoption, ownerAuthored, positive, SHA, withLaneBinding } from "./address-feedback.mjs";
import { commentItems, gateSource, prHold, reviewReader } from "./gate-source.mjs";

const ACTIVITY = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;

export async function main(env, { api, actions, adoption, log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "HEAD_SHA", "APP_SENDER_ID", "LABEL", "ACTIVITY"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit SHA");
  }
  if (!ACTIVITY.test(env.ACTIVITY)) {
    throw new Error("ACTIVITY is not an activity name");
  }
  const client = withLaneBinding(
    api ??
      createGitHubApi({
        token: env.GITHUB_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
        fetch: rateLimitLatch.guard(globalThis.fetch),
      }),
    actions ?? laneReader(env),
  );
  const isLanesApp = (user) => user?.id === appId && user?.type === "Bot";
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

runAsScript(import.meta.url, "gate-recheck", () => main(process.env));
