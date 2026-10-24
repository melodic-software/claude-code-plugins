// Whether the human-gated label holds one activity on a pull request, for a
// base-code job before the activity's model turn (pr-unblock.yml's
// resolve-conflicts-select, pr-refine.yml's fix-docs-head). The label holds
// unless another lane's escalation put it on (gate-source.mjs prHold); other
// hold labels stay with the activity's applies-when. Writes to GITHUB_OUTPUT:
// held=true|false, and lane-escalated=true when the label is on and the
// activity works past it, which lets the write runner push past it too.
//
// Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_OUTPUT, PR_NUMBER,
// APP_SENDER_ID, ACTIVITY, TRACKER_CONFIG (default .base/.work-item-tracker.json).

import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { createGitHubApi, humanGatedLabelFrom, need, positive } from "./address-feedback.mjs";
import { prHold } from "./gate-source.mjs";

const ACTIVITY = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;

export async function main(env, { api, log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "APP_SENDER_ID", "ACTIVITY"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!ACTIVITY.test(env.ACTIVITY)) {
    throw new Error("ACTIVITY is not an activity name");
  }
  const gateLabel = humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/.work-item-tracker.json");
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
    });
  const pull = await client.getPull(pr);
  const { held, laneEscalated, why } = await prHold({
    labels: (pull.labels ?? []).map((label) => label?.name),
    holdLabels: [],
    gateLabel,
    head: pull.head?.sha,
    activity: env.ACTIVITY,
    appId,
    readTimeline: () => client.listTimeline(pr),
  });
  appendFileSync(env.GITHUB_OUTPUT, `held=${held}\nlane-escalated=${laneEscalated}\n`);
  log(held ? `#${pr} ${why}` : `#${pr} not held for ${env.ACTIVITY}${laneEscalated ? ` (another lane's escalation put ${gateLabel} on)` : ""}`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::lane-hold failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
