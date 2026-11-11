// Whether the human-gated label holds one activity on a pull request, for a
// base-code job before the activity's model turn (pr-unblock.yml's
// resolve-conflicts-select, pr-refine.yml's fix-docs-head). The label holds
// unless another lane's escalation put it on (gate-source.mjs prHold); other
// hold labels stay with the activity's applies-when. Writes to GITHUB_OUTPUT:
// held=true|false, and lane-escalated=true when the label is on and the
// activity works past it, which lets the write runner push past it too.
//
// A read that meets a GitHub fault (readFault) leaves the hold unknown, so the
// step holds (outage posture element 2): one notice, `unread=true` and neither
// held nor lane-escalated, and exit 0. Each caller proceeds only on
// held=false and posts its skip only on held=true, so nothing after it runs
// and nothing lands on the head: pr-refine.yml's fix-docs-head-held marks the
// run, and the next dispatcher tick sends the PR again. Any other error, a 404
// or a 403 among them, still ends the step red.
//
// Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_OUTPUT, PR_NUMBER,
// APP_SENDER_ID, ACTIVITY, TRACKER_CONFIG (default .base/docs/conventions/work-items.yaml),
// ARTIFACT_READ_TOKEN (actions: read; the review lanes' comment records).

import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { isFault } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { createGitHubApi, humanGatedLabelFrom, laneReader, need, positive, withLaneBinding } from "./address-feedback.mjs";
import { prHold, reviewReader } from "./gate-source.mjs";

const ACTIVITY = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;

// A GitHub fault: isFault, or a 5xx or 429 from createGitHubApi, whose errors
// carry the status on a plain Error. What the read found is unknown, not wrong.
export const readFault = (error) => isFault(error) || error?.status >= 500 || error?.status === 429;

export async function main(env, { api, actions, log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "APP_SENDER_ID", "ACTIVITY"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!ACTIVITY.test(env.ACTIVITY)) {
    throw new Error("ACTIVITY is not an activity name");
  }
  const gateLabel = humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/docs/conventions/work-items.yaml");
  // The review lanes' hold comments count only when bound to their runs,
  // read with ARTIFACT_READ_TOKEN (address-feedback.mjs withLaneBinding).
  const client = withLaneBinding(
    api ??
      createGitHubApi({
        token: env.GITHUB_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
        // Each answer's rate-limit reading, for the job-end api-budget notice.
        fetch: rateLimitLatch.guard(globalThis.fetch),
      }),
    actions ?? laneReader(env),
  );
  // prHold reads a failed review read as a person's hold; a fault there is
  // kept here, so it holds the step instead.
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
