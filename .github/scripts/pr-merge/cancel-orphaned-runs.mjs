#!/usr/bin/env node
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";

const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
export const QUEUE_PREFIX = "gh-readonly-queue/";
const BASE = "main";
const CANDIDATE_PREFIX = `${QUEUE_PREFIX}${BASE}/`;
export const MIN_AGE_MS = 60_000;
export const MAX_CANCELS = 20;
export const MAX_PAGES = 3;
const STATUSES = ["queued", "in_progress"];

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

export function orphans(runs, branches, nowMs, { minAgeMs = MIN_AGE_MS, max = MAX_CANCELS, merged = null } = {}) {
  const live = new Set(branches);
  return runs
    .filter(
      (run) =>
        run?.event === "merge_group" &&
        Number.isSafeInteger(run.id) &&
        run.id > 0 &&
        typeof run.head_branch === "string" &&
        run.head_branch.startsWith(CANDIDATE_PREFIX) &&
        !live.has(run.head_branch) &&
        nowMs - Date.parse(run.created_at) > minAgeMs &&
        (merged === null || (SHA.test(run.head_sha ?? "") && !merged.has(run.head_sha))),
    )
    .sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at))
    .slice(0, max)
    .map((run) => run.id);
}

export async function listRuns(github, repo) {
  const byId = new Map();
  for (const status of STATUSES) {
    let seen = 0;
    for (let page = 1; page <= MAX_PAGES; page += 1) {
      const answer = await github("GET", `/repos/${repo}/actions/runs?event=merge_group&status=${status}&per_page=100&page=${page}`);
      const batch = answer?.workflow_runs;
      if (!Array.isArray(batch)) {
        throw new Error(`the ${status} merge_group listing has no workflow_runs array`);
      }
      for (const run of batch) {
        byId.set(run?.id, run);
      }
      seen += batch.length;
      if (batch.length < 100 || seen >= (answer.total_count ?? 0)) {
        break;
      }
    }
  }
  return [...byId.values()];
}

export async function listQueueBranches(github, repo) {
  const refs = await github("GET", `/repos/${repo}/git/matching-refs/heads/${QUEUE_PREFIX}`);
  if (!Array.isArray(refs)) {
    throw new Error("the queue ref listing is not an array");
  }
  if (/rel="next"/.test(refs[Symbol.for("github.link")] ?? "")) {
    throw new Error("the queue ref listing is paged");
  }
  return refs.map((ref) => String(ref?.ref ?? "").replace(/^refs\/heads\//, ""));
}

export async function mainShas(github, repo) {
  const commits = await github("GET", `/repos/${repo}/commits?sha=${BASE}&per_page=100`);
  if (!Array.isArray(commits)) {
    throw new Error("main's commit listing is not an array");
  }
  return new Set(commits.map((commit) => commit?.sha));
}

export async function main({ env = process.env, github, now = Date.now } = {}) {
  let calls = 0;
  let listed = 0;
  const cancelled = [];
  const report = () =>
    console.log(`::notice title=cancel-orphaned-runs::listed=${listed} cancelled=[${cancelled.join(",")}] calls=${calls}`);
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const repo = env.GITHUB_REPOSITORY;
    const client = github ?? createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const call = (...args) => {
      calls += 1;
      return client(...args);
    };
    const runs = await listRuns(call, repo);
    listed = runs.length;
    if (listed === 0) {
      return 0;
    }
    const branches = await listQueueBranches(call, repo);
    const at = now();
    if (orphans(runs, branches, at).length === 0) {
      return 0;
    }
    const merged = await mainShas(call, repo);
    for (const id of orphans(runs, branches, at, { merged })) {
      try {
        await call("POST", `/repos/${repo}/actions/runs/${id}/cancel`);
        cancelled.push(id);
      } catch (error) {
        console.log(`::warning title=cancel-orphaned-runs::run ${id} not cancelled: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    return 0;
  } catch (error) {
    console.log(`::warning title=cancel-orphaned-runs::nothing more cancelled: ${escapeCommand(error?.message ?? error)}`);
    return 0;
  } finally {
    report();
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
