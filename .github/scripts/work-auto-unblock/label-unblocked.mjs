#!/usr/bin/env node
// label-unblocked.mjs: when an issue closes, labels `agent-ready` each issue
// it blocked that is now ready for the resolve-issue lane: open, every
// blocker closed, no hold label, not already agent-ready, and ratified by the
// owner's admission marker (the resolve-issue lane's own check). Every fact
// is read from the API now, never from the event payload. No model.
//
// Environment:
//   GH_TOKEN               the lane App token (issues: write)
//   GITHUB_REPOSITORY      owner/repo
//   GITHUB_EVENT_NAME      must be `issues`
//   GITHUB_EVENT_PATH      the event payload; only its action, issue number
//                          and sender are read
//   KILL_SWITCH            `proceed` from the kill-switch step; anything else stops
//   TRUSTED_ACTORS_PATH    trusted-actors.json from the default branch tip
//   GITHUB_API_URL
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { findRatification } from "../../actions/resolve-config/ratification.mjs";

const LABEL = "agent-ready";
// A person decides these; the lane never starts on them.
const HOLDS = new Set(["needs-owner-decision", "status: needs-decision", "needs-human"]);
const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// Why `number` is not promoted, or null when it is ready.
async function refusal({ github, repo, number, ratifiers }) {
  const base = `/repos/${repo}/issues/${number}`;
  const current = await github("GET", base);
  if (current.state !== "open") {
    return "not open";
  }
  const labels = (current.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
  const held = labels.find((label) => HOLDS.has(label));
  if (held) {
    return `held by ${held}`;
  }
  if (labels.includes(LABEL)) {
    return `already ${LABEL}`;
  }
  const blockers = await paginate(github, `${base}/dependencies/blocked_by`);
  const open = blockers.filter((blocker) => blocker.state !== "closed").length;
  if (open > 0) {
    return `${open} blocker(s) still open`;
  }
  const ratifying = findRatification(await paginate(github, `${base}/comments`), ratifiers);
  return ratifying === undefined ? "no admission marker from a listed human" : null;
}

export async function main({ env = process.env, github } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8"));
    if (env.GITHUB_EVENT_NAME !== "issues" || event.action !== "closed" || !NUMBER.test(String(event.issue?.number))) {
      throw new Error("this runs only on an issue closing");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("label-unblocked: the lanes kill switch stops this run; nothing read or labeled");
      return 0;
    }
    // A bot's close (the lanes App's, or a PR merge a bot ran) is skipped
    // cleanly: the broker refuses it, and a lane close must not loop.
    if (event.sender?.type === "Bot") {
      console.log("label-unblocked: a bot closed this issue; nothing read or labeled");
      return 0;
    }
    const repo = env.GITHUB_REPOSITORY;
    const closed = Number(event.issue.number);
    const ratifiers = loadTrustedList(env.TRUSTED_ACTORS_PATH).humans;
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const blocked = await paginate(github, `/repos/${repo}/issues/${closed}/dependencies/blocking`);
    let failed = 0;
    for (const item of blocked) {
      const number = Number(item.number);
      // A label write here can land only in this repository.
      if (!String(item.repository_url ?? "").toLowerCase().endsWith(`/repos/${repo}`.toLowerCase()) || item.pull_request) {
        console.log(`label-unblocked: skipped a blocked item outside this repository's issues`);
        continue;
      }
      try {
        const reason = await refusal({ github, repo, number, ratifiers });
        if (reason !== null) {
          console.log(`label-unblocked: #${number} not labeled: ${reason}`);
          continue;
        }
        await github("POST", `/repos/${repo}/issues/${number}/labels`, { labels: [LABEL] });
        console.log(`label-unblocked: #${number} labeled ${LABEL}`);
      } catch (error) {
        failed += 1;
        console.log(`::error title=label-unblocked::#${number}: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=label-unblocked::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
