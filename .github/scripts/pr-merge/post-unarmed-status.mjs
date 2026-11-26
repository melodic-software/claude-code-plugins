#!/usr/bin/env node
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { ACTIONS_BOT_ID } from "../lib/lane-vocabulary.mjs";
import { UNARMED_CONTEXT } from "./enable-auto-merge.mjs";

const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const STATES = new Set(["failure", "success"]);
const DESCRIPTION_CHARS = 140;
export const MAX_STATUSES = 100;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

export function parse(text) {
  let list;
  try {
    list = JSON.parse(text);
  } catch {
    return [];
  }
  const byHead = new Map();
  for (const item of Array.isArray(list) ? list : []) {
    if (SHA.test(String(item?.sha)) && STATES.has(item?.state) && typeof item.description === "string") {
      byHead.set(item.sha, { sha: item.sha, state: item.state, description: Array.from(item.description).slice(0, DESCRIPTION_CHARS).join("") });
    }
  }
  return [...byHead.values()].slice(0, MAX_STATUSES);
}

export const changes = (status, current) =>
  current === undefined ? status.state === "failure" : current.state !== status.state || current.description !== status.description;

export async function main({ env = process.env, github } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const repo = env.GITHUB_REPOSITORY;
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const target = /^[1-9][0-9]*$/.test(env.GITHUB_RUN_ID ?? "") ? `${env.GITHUB_SERVER_URL || "https://github.com"}/${repo}/actions/runs/${env.GITHUB_RUN_ID}` : null;
    let failed = 0;
    let written = 0;
    for (const status of parse(env.STATUSES ?? "")) {
      try {
        const listed = await github("GET", `/repos/${repo}/commits/${status.sha}/statuses?per_page=100`);
        const newest = (Array.isArray(listed) ? listed : []).find((item) => item?.context === UNARMED_CONTEXT);
        const current = newest?.creator?.id === ACTIONS_BOT_ID ? newest : undefined;
        if (!changes(status, current)) {
          continue;
        }
        await github("POST", `/repos/${repo}/statuses/${status.sha}`, {
          state: status.state,
          context: UNARMED_CONTEXT,
          description: status.description,
          ...(target ? { target_url: target } : {}),
        });
        written += 1;
      } catch (error) {
        failed += 1;
        console.log(`::error title=post-unarmed-status::${status.sha}: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    console.log(`post-unarmed-status: ${written} written, ${failed} failed`);
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=post-unarmed-status::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
