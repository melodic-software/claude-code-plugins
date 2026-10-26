#!/usr/bin/env node
// post-unarmed-status.mjs: posts the `pr-merge/unarmed` commit statuses that
// enable-auto-merge.mjs hands on (UNARMED_OUTPUT): `failure` on a lanes App
// pull request's head whose refusal the lanes clear has stood
// merge.risk-escalation-minutes unchanged, `success` on a head it armed. No
// model.
//
// The status shows a hold the lanes own on the pull request, in place of the
// human-gated label (owner rule 2026-10-26: a person only for an intent or
// design change or a HIGH or CRITICAL security issue). It is informational:
// its context is not `ci-status`, the only check the main ruleset requires,
// so it neither holds nor passes a merge. Each head's newest status in the
// context is read first: one already in that state with that description
// gets no write, and a `success` is written only over a status already
// there, so an unchanged run writes nothing.
//
// Environment:
//   GH_TOKEN            the job's own token, with statuses: write
//   GITHUB_REPOSITORY   owner/repo
//   STATUSES            enable-auto-merge's UNARMED_OUTPUT, a JSON array
//   GITHUB_RUN_ID, GITHUB_SERVER_URL, GITHUB_API_URL
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { UNARMED_CONTEXT } from "./enable-auto-merge.mjs";

const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const STATES = new Set(["failure", "success"]);
// GitHub's limit on a status description.
const DESCRIPTION_CHARS = 140;
// Statuses read and written in one run at most (judgment: more open lane
// pull requests than this is a run to look at).
export const MAX_STATUSES = 100;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// The statuses `text` hands on, well-formed only, one per head (its last).
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

// Whether `status` changes what its head shows, given the head's newest
// status in the context (`current`, undefined for none).
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
        // Newest first, so the first in the context is the one shown.
        const listed = await github("GET", `/repos/${repo}/commits/${status.sha}/statuses?per_page=100`);
        const current = (Array.isArray(listed) ? listed : []).find((item) => item?.context === UNARMED_CONTEXT);
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
