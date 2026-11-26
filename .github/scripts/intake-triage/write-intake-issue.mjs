#!/usr/bin/env node
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { pathToFileURL } from "node:url";

import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { createGitHub, paginate } from "../lib/github-client.mjs";

export const MARKER = "<!-- claude-lane intake-triage -->";
export const OPEN_LIMIT = 200;
export const MERGED_LIMIT = 100;
export const MERGED_PAGES = 3;
const ISSUE_TYPES_QUERY = "query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { issueTypes(first: 25) { nodes { name isEnabled } } } }";

const labelName = (label) => (typeof label === "string" ? label : label?.name);

export function trustedComments(comments, humans, bots) {
  return comments.filter((comment) => {
    const user = comment.user;
    if (!Number.isInteger(user?.id)) return false;
    if (user.login === "github-actions[bot]" && String(comment.body ?? "").startsWith(MARKER)) return false;
    return (user.type === "User" && humans.has(user.id)) || (user.type === "Bot" && bots.has(user.id));
  });
}

export async function openIssues(github, repository, number) {
  const open = [];
  for (let page = 1; open.length < OPEN_LIMIT; page += 1) {
    const batch = await github("GET", `/repos/${repository}/issues?state=open&sort=created&direction=desc&per_page=100&page=${page}`);
    for (const other of batch) {
      if (!other.pull_request && other.number !== number) open.push({ number: other.number, title: other.title });
    }
    if (batch.length < 100) break;
  }
  return open.slice(0, OPEN_LIMIT);
}

export async function mergedPulls(github, repository) {
  const merged = [];
  for (let page = 1; page <= MERGED_PAGES && merged.length < MERGED_LIMIT; page += 1) {
    const batch = await github("GET", `/repos/${repository}/issues?state=closed&sort=updated&direction=desc&per_page=100&page=${page}`);
    for (const other of batch) {
      const at = other.pull_request?.merged_at;
      if (typeof at === "string" && at) merged.push({ number: other.number, title: other.title, merged_at: at });
    }
    if (batch.length < 100) break;
  }
  return merged.sort((a, b) => b.merged_at.localeCompare(a.merged_at)).slice(0, MERGED_LIMIT);
}

export async function issueTypes(github, repository) {
  const [owner, name] = repository.split("/");
  const data = (await github("POST", "/graphql", { query: ISSUE_TYPES_QUERY, variables: { owner, name } }))?.data;
  return (data?.repository?.issueTypes?.nodes ?? [])
    .filter((type) => type?.isEnabled === true && typeof type.name === "string" && type.name.trim() !== "" && !type.name.includes("'") && type.name.trim().toLowerCase() !== "none")
    .map((type) => type.name);
}

export function narrowType(schema, types) {
  const next = structuredClone(schema);
  if (types.length > 0) next.properties.type = { type: "string", enum: types };
  else delete next.properties.type;
  return next;
}

const parseIds = (text) => {
  const tokens = String(text ?? "").split(/[\s,]+/).filter(Boolean);
  if (!tokens.every((token) => /^[1-9][0-9]{0,15}$/.test(token))) throw new Error("BOT_SENDER_IDS must hold positive integer ids");
  return new Set(tokens.map(Number));
};

export async function main({ env = process.env, github, log = console.log } = {}) {
  const file = env.ISSUE_FILE;
  try {
    if (!file) throw new Error("ISSUE_FILE is empty");
    rmSync(file, { force: true });
    if (!/^[1-9][0-9]{0,9}$/.test(env.ISSUE_NUMBER ?? "") || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("ISSUE_NUMBER or GITHUB_REPOSITORY is malformed");
    }
    const number = Number(env.ISSUE_NUMBER);
    const repository = env.GITHUB_REPOSITORY;
    const bots = parseIds(env.BOT_SENDER_IDS);
    const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    const schema = JSON.parse(readFileSync(env.SCHEMA_FILE, "utf8"));
    const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const issue = await client("GET", `/repos/${repository}/issues/${number}`);
    if (issue?.pull_request) throw new Error(`#${number} is a pull request`);
    if (issue?.number !== number) throw new Error(`the API returned no issue #${number}`);
    const all = await paginate(client, `/repos/${repository}/issues/${number}/comments`);
    const comments = trustedComments(all, humans, bots);
    log(`write-intake-issue: ${comments.length} of ${all.length} comments go to the model; the rest are from untrusted authors or the lane`);
    let types = [];
    try {
      types = await issueTypes(client, repository);
    } catch (error) {
      log(`::warning::Issue Types unreadable, so the verdict names none: ${error.message}`);
    }
    const record = {
      number,
      title: issue.title ?? "",
      author: issue.user?.login ?? "",
      labels: (issue.labels ?? []).map(labelName).filter((name) => typeof name === "string"),
      body: issue.body ?? "",
      comments: comments.map((comment) => ({ author: comment.user.login ?? "", url: comment.html_url ?? "", body: comment.body ?? "" })),
      open_issues: await openIssues(client, repository, number),
      merged_pulls: await mergedPulls(client, repository),
    };
    writeFileSync(env.SCHEMA_FILE, `${JSON.stringify(narrowType(schema, types))}\n`);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, `${JSON.stringify(record, null, 2)}\n`);
    log(`write-intake-issue: #${number} written with ${record.open_issues.length} open issues, ${record.merged_pulls.length} merged pull requests and ${types.length} Issue Types`);
    return 0;
  } catch (error) {
    if (file) rmSync(file, { force: true });
    log(`::error::write-intake-issue: ${error.message}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
