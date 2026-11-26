import { appendFileSync } from "node:fs";

import { runAsScript } from "../lib/run-main.mjs";
import { isFault } from "../lib/github-client.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { createGitHubApi, humanGatedLabelFrom, laneReader, need, positive, withLaneBinding } from "./address-feedback.mjs";
import { prHold, reviewReader } from "./gate-source.mjs";

const ACTIVITY = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;

export const readFault = (error) => isFault(error) || error?.status >= 500 || error?.status === 429;

export async function main(env, { api, actions, log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "APP_SENDER_ID", "ACTIVITY"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!ACTIVITY.test(env.ACTIVITY)) {
    throw new Error("ACTIVITY is not an activity name");
  }
  const gateLabel = humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/docs/conventions/work-items.yaml");
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
  let fault = false;
  const readReviews = reviewReader(client, pr);
  let result;
  try {
    const pull = await client.getPull(pr);
    result = await prHold({
      labels: (pull.labels ?? []).map((label) => label?.name),
      holdLabels: [],
      gateLabel,
      head: pull.head?.sha,
      activity: env.ACTIVITY,
      appId,
      readTimeline: () => client.listTimeline(pr),
      readReviews: async (since) => {
        try {
          return await readReviews(since);
        } catch (error) {
          fault = readFault(error);
          throw error;
        }
      },
    });
  } catch (error) {
    if (!readFault(error)) {
      throw error;
    }
    fault = true;
  }
  if (fault) {
    appendFileSync(env.GITHUB_OUTPUT, "unread=true\n");
    log(`::notice::#${pr}: the human-gated hold for ${env.ACTIVITY} could not be read (a GitHub fault); ${env.ACTIVITY} does not run, and the next dispatcher tick sends the PR again`);
    return 0;
  }
  const { held, laneEscalated, why } = result;
  appendFileSync(env.GITHUB_OUTPUT, `held=${held}\nlane-escalated=${laneEscalated}\n`);
  log(held ? `#${pr} ${why}` : `#${pr} not held for ${env.ACTIVITY}${laneEscalated ? ` (another lane's escalation put ${gateLabel} on)` : ""}`);
  return 0;
}

runAsScript(import.meta.url, "lane-hold", () => main(process.env));
