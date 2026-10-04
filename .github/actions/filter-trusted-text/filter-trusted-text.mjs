// Builds a lane's prompt context from a PR: its title and body, issue
// comments, reviews, review comments, and the issues it closes with their
// comments, keeping only items whose own author is on the trusted-actor list.
// Dropped items are counted and never written or logged.
import { rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  createGitHub,
  isListed,
  loadTrustedActors,
  paginate,
} from "../check-trusted-trigger/check-trusted-trigger.mjs";

const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const APP_SLUG = /^[a-z0-9][a-z0-9-]*$/;

const CLOSING_ISSUES = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      closingIssuesReferences(first: 100) {
        nodes { number repository { nameWithOwner } }
      }
    }
  }
}`;

// An item is trusted when its author's id is listed and, if it was posted
// through a GitHub App, that App's bot account is listed too.
function createTrustCheck(github, ids) {
  const appBots = new Map();
  async function appBotListed(app) {
    const slug = app?.slug;
    if (typeof slug !== "string" || !APP_SLUG.test(slug)) {
      return false;
    }
    if (!appBots.has(slug)) {
      appBots.set(
        slug,
        github("GET", `/users/${encodeURIComponent(`${slug}[bot]`)}`).then(
          (bot) => isListed(ids, bot),
          () => false,
        ),
      );
    }
    return appBots.get(slug);
  }
  return async (item) => {
    if (!isListed(ids, item.user)) {
      return false;
    }
    const app = item.performed_via_github_app;
    return app === null || app === undefined || (await appBotListed(app));
  };
}

export async function buildTrustedContext({ github, repository, prNumber, ids }) {
  const trusted = createTrustCheck(github, ids);
  const dropped = {
    pr: 0,
    "issue-comment": 0,
    review: 0,
    "review-comment": 0,
    "linked-issue": 0,
    "linked-issue-comment": 0,
  };
  const items = [];
  async function keep(kind, list) {
    for (const item of list) {
      if (!(await trusted(item))) {
        dropped[kind] += 1;
        continue;
      }
      items.push({
        kind,
        id: item.id,
        author_id: item.user.id,
        author_login: item.user.login,
        created_at: item.created_at ?? item.submitted_at ?? "",
        url: item.html_url,
        body: item.body ?? "",
      });
    }
  }

  const base = `/repos/${repository}`;
  const pull = await github("GET", `${base}/pulls/${prNumber}`);
  const prTrusted = await trusted(pull);
  if (!prTrusted) {
    dropped.pr += 1;
  }
  await keep("issue-comment", await paginate(github, `${base}/issues/${prNumber}/comments`));
  await keep("review", await paginate(github, `${base}/pulls/${prNumber}/reviews`));
  await keep("review-comment", await paginate(github, `${base}/pulls/${prNumber}/comments`));

  const [owner, name] = repository.split("/");
  const closing = await github("POST", "/graphql", {
    query: CLOSING_ISSUES,
    variables: { owner, name, number: Number(prNumber) },
  });
  const references = closing?.data?.repository?.pullRequest?.closingIssuesReferences?.nodes ?? [];
  for (const reference of references) {
    const issueRepository = reference?.repository?.nameWithOwner;
    if (!REPOSITORY.test(issueRepository ?? "") || !Number.isInteger(reference.number)) {
      throw new Error("closing issue reference has an unexpected shape");
    }
    const issuePath = `/repos/${issueRepository}/issues/${reference.number}`;
    await keep("linked-issue", [await github("GET", issuePath)]);
    await keep("linked-issue-comment", await paginate(github, `${issuePath}/comments`));
  }

  return {
    pr: {
      number: pull.number,
      head_sha: pull.head.sha,
      base_sha: pull.base.sha,
      author_id: pull.user?.id ?? 0,
      title: prTrusted ? pull.title : "",
      body: prTrusted ? pull.body : null,
    },
    items,
    dropped,
  };
}

// Returns the process exit code. On any failure nothing is written, so a lane
// never reads a partial context.
export async function main({ env = process.env, github, log = console.log } = {}) {
  const outputPath = env.OUTPUT_PATH;
  try {
    if (!outputPath) {
      throw new Error("output-path is empty");
    }
    rmSync(outputPath, { force: true });
    if (!PR_NUMBER.test(env.PR_NUMBER ?? "") || !REPOSITORY.test(env.REPOSITORY ?? "")) {
      throw new Error("pr-number or repository is malformed");
    }
    const ids = loadTrustedActors(env.TRUSTED_ACTORS_PATH);
    const context = await buildTrustedContext({
      github: github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
      repository: env.REPOSITORY,
      prNumber: env.PR_NUMBER,
      ids,
    });
    writeFileSync(outputPath, `${JSON.stringify(context, null, 2)}\n`);
    const total = Object.values(context.dropped).reduce((sum, count) => sum + count, 0);
    log(`filter-trusted-text: dropped total=${total} ${JSON.stringify(context.dropped)}`);
    return 0;
  } catch (error) {
    if (outputPath) {
      rmSync(outputPath, { force: true });
    }
    const detail = error?.name === "GitHubError" ? error.message : (error?.name ?? "error");
    log(`filter-trusted-text: failed (${detail}); no context written`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
