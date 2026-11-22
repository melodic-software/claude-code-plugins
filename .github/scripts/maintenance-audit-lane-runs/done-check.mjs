// Lists the open issues at Work status confirmed that a pull request merged
// here names on a `Refs:` line after their newest decision or refinement
// (admit.mjs mergedRefsAfter), which admission parks for a done-check nothing
// else starts, in one job token digest issue a session reads; it closes the
// digest when the list is empty, and closing it as not planned mutes it
// (https://github.com/melodic-software/claude-code-plugins/issues/18251). It
// reads TRUSTED_ACTORS_PATH, LANES_APP_ID and BASE_PATH (default `.base`).
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { loadTrustedActors } from "../../actions/resolve-config/read-status.mjs";
import { DONE_BATCH, mergedRefsPulls } from "../intake-triage/admit.mjs";

export const DIGEST_MARKER = "<!-- intake-done-check-digest -->";
export const DIGEST_TITLE = "Run the done-check on issues a merged Refs pull request parked";
const FILER = "github-actions[bot]";
const PAGE = 100;
const MAX_PAGES = 10;

export async function parkedForDoneCheck({ github, repository, config, trustedActors, issuesByStatus, humans, appId }) {
  const listed = await issuesByStatus(github, repository, ["confirmed"], { config, trustedActors });
  const numbers = [...new Set(listed.map((issue) => issue.number))].sort((a, b) => a - b);
  const parked = [];
  for (let at = 0; at < numbers.length; at += DONE_BATCH) {
    let failure = null;
    const found = await mergedRefsPulls({ github, repository, numbers: numbers.slice(at, at + DONE_BATCH), humans, appId, log: (line) => (failure = line) });
    if (failure !== null) {
      throw new Error(`the merged Refs pull requests were not read: ${failure}`);
    }
    parked.push(...[...found].sort(([a], [b]) => a - b));
  }
  return { parked, held: (listed.held ?? []).map((issue) => issue.number) };
}

export function renderDigest(parked) {
  const lines = parked.map(([number, pulls]) => `- #${number}: merged ${pulls.map((n) => `#${n}`).join(", ")}`);
  return [
    DIGEST_MARKER,
    "Open issues admission parked at Work status confirmed because a pull request merged here names them on a `Refs:` line after their newest decision or refinement, so their work may be done. For each one: close it if the work is done, or post a comment whose first line is `**Decision recorded.**` saying what is left, which sends it back through intake.",
    "",
    "The daily lane sweep rewrites this list, closes this issue when the list is empty and reopens it when it fills again. Closing it as not planned mutes it.",
    "",
    ...(lines.length > 0 ? lines : ["None."]),
  ].join("\n");
}

export function planDigest({ parked, digest }) {
  const body = renderDigest(parked);
  if (!digest) {
    return parked.length > 0 ? { action: "create", body } : { action: "none" };
  }
  if (digest.state === "closed") {
    return parked.length > 0 && digest.state_reason !== "not_planned" ? { action: "reopen", body } : { action: "none" };
  }
  if (parked.length === 0) {
    return { action: "close", body };
  }
  return digest.body === body ? { action: "none" } : { action: "edit", body };
}

export async function findDigest(github, repository) {
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const issues = await github("GET", `/repos/${repository}/issues?creator=${encodeURIComponent(FILER)}&state=all&per_page=${PAGE}&page=${page}`);
    if (!Array.isArray(issues)) {
      throw new Error("the issue list is not a list");
    }
    const digest = issues.find((issue) => !issue.pull_request && String(issue.body ?? "").split("\n", 1)[0] === DIGEST_MARKER);
    if (digest) {
      return digest;
    }
    if (issues.length < PAGE) {
      return null;
    }
  }
  throw new Error(`${FILER} has filed more than ${PAGE * MAX_PAGES} issues, so the digest was not found`);
}

export async function applyPlan(github, repository, digest, plan) {
  switch (plan.action) {
    case "create":
      return (await github("POST", `/repos/${repository}/issues`, { title: DIGEST_TITLE, body: plan.body })).number;
    case "edit":
      await github("PATCH", `/repos/${repository}/issues/${digest.number}`, { body: plan.body });
      return digest.number;
    case "close":
      await github("PATCH", `/repos/${repository}/issues/${digest.number}`, { body: plan.body, state: "closed", state_reason: "completed" });
      return digest.number;
    case "reopen":
      await github("PATCH", `/repos/${repository}/issues/${digest.number}`, { body: plan.body, state: "open" });
      return digest.number;
    default:
      return digest?.number ?? null;
  }
}

async function main(env = process.env) {
  const repository = env.GITHUB_REPOSITORY;
  const github = createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
  const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
  const appId = /^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "") ? Number(env.LANES_APP_ID) : undefined;
  const { issueStatusFromBase, issuesByStatus } = await import("../../actions/resolve-config/resolve-config.mjs");
  const config = issueStatusFromBase(env);
  if (!config) {
    throw new Error("models.issue-status is not set, so the confirmed issues cannot be listed");
  }
  const { parked, held } = await parkedForDoneCheck({ github, repository, config, trustedActors: loadTrustedActors(env), issuesByStatus, humans, appId });
  const digest = await findDigest(github, repository);
  const plan = planDigest({ parked, digest });
  const number = await applyPlan(github, repository, digest, plan);
  const run = `${env.GITHUB_SERVER_URL}/${repository}/actions/runs/${env.GITHUB_RUN_ID}`;
  const lines = [
    "### Done-check list",
    "",
    `Parked for a done-check: ${parked.map(([n]) => `#${n}`).join(", ") || "none"}. Digest issue: ${number === null ? "none" : `#${number}`} (${plan.action}). Left out of the listing mid-write: ${held.map((n) => `#${n}`).join(", ") || "none"}. Run: ${run}.`,
  ];
  if (env.GITHUB_STEP_SUMMARY) {
    appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  }
  console.log(`done-check: parked ${parked.length}, digest ${number ?? "none"}, action ${plan.action}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    await main();
  } catch (error) {
    console.log(`::error title=done-check::${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    process.exitCode = 1;
  }
}
