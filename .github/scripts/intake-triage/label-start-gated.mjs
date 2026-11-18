import process from "node:process";
import { pathToFileURL } from "node:url";

import { createRateLimitLatch, RateLimitStop } from "../../actions/log-api-budget/rate-guard.mjs";

export const FLOOR_LABEL = "needs-triage";

/**
 * Adds the floor label to an issue with no label at all after intake's start
 * gate (check-kill-switch) ended its run neutral, since that issues event was
 * the issue's only trigger and the hourly triage sweep looks for the label.
 *
 * Every call goes through the rate guard in its hold posture, so an exhausted
 * pool skips the write and the step stays green. The labels endpoint creates a
 * label it does not know, so the label is read first and a 404 adds nothing.
 *
 * @returns {Promise<"added" | "labeled" | "rate-limited" | "missing-label" | "unread">}
 */
export async function labelStartGated({ api = "https://api.github.com", repository, number, token, label = FLOOR_LABEL, latch, fetchImpl = fetch, log = (line) => console.log(line) }) {
  const send = latch.guard(fetchImpl);
  const headers = { accept: "application/vnd.github+json", authorization: `Bearer ${token}`, "x-github-api-version": "2022-11-28" };
  const base = `${api}/repos/${repository}`;
  const limited = (url) => latch.until(url) !== null;
  const skip = (url, what, response) => {
    if (limited(url)) {
      log(`::notice::#${number}: ${what} hit the rate guard, so '${label}' was not added; the triage sweep still finds the issue`);
      return "rate-limited";
    }
    log(`::warning::#${number}: ${what} answered HTTP ${response.status}, so '${label}' was not added`);
    return "unread";
  };
  try {
    const issueUrl = `${base}/issues/${number}`;
    const issue = await send(issueUrl, { headers });
    if (!issue.ok) {
      return skip(issueUrl, "reading the issue", issue);
    }
    const names = ((await issue.json())?.labels ?? []).map((entry) => (typeof entry === "string" ? entry : entry?.name));
    if (names.length > 0) {
      log(`::notice::#${number} already carries a label (${names.join(", ")}), so the start-gate stop adds no '${label}'`);
      return "labeled";
    }
    const labelUrl = `${base}/labels/${encodeURIComponent(label)}`;
    const known = await send(labelUrl, { headers });
    if (known.status === 404) {
      log(`::error::label '${label}' does not exist in ${repository}; this step applies an existing label and never creates one`);
      return "missing-label";
    }
    if (!known.ok) {
      return skip(labelUrl, `reading label '${label}'`, known);
    }
    const addUrl = `${base}/issues/${number}/labels`;
    const added = await send(addUrl, { method: "POST", headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify({ labels: [label] }) });
    if (!added.ok) {
      return skip(addUrl, `adding '${label}'`, added);
    }
    log(`::notice::#${number} had no label when the start gate stopped intake, so it now carries '${label}' for the triage sweep`);
    return "added";
  } catch (error) {
    if (error instanceof RateLimitStop) {
      log(`::notice::#${number}: ${error.message}, so '${label}' was not added; the triage sweep still finds the issue`);
      return "rate-limited";
    }
    throw error;
  }
}

async function main(env = process.env) {
  const { GITHUB_API_URL, GITHUB_TOKEN, REPOSITORY, ISSUE_NUMBER } = env;
  if (!/^[1-9][0-9]*$/.test(ISSUE_NUMBER ?? "") || !/^[\w.-]+\/[\w.-]+$/.test(REPOSITORY ?? "")) {
    console.log("::error::ISSUE_NUMBER or REPOSITORY is missing or malformed");
    return 1;
  }
  const outcome = await labelStartGated({
    api: GITHUB_API_URL || undefined,
    repository: REPOSITORY,
    number: ISSUE_NUMBER,
    token: GITHUB_TOKEN,
    latch: createRateLimitLatch({ hold: true }),
  });
  console.log(`label-start-gated: #${ISSUE_NUMBER} ${outcome}`);
  return outcome === "missing-label" ? 1 : 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
