#!/usr/bin/env node
// label-unblocked.mjs: when an issue closes, labels `agent-ready` each issue
// it blocked that is now ready for the resolve-issue lane (the label starts
// that lane once resolve-issue accepts App-added labels, a follow-up by
// Automation Lanes): open, every blocker closed as completed, no hold label,
// not already agent-ready, ratified by the owner's admission marker, and
// admitted by resolve-issue's own admission rule (no work class outside its
// classes). Every fact is read from the API now, never from the event
// payload. No model.
//
// On `schedule` it sweeps instead: every issue closed in the last
// LOOKBACK_HOURS goes through the same rules, so an issue a bot closed (a
// pull request merge), which starts no close run, is still picked up. A
// swept close counts only when a listed human or a bot made it. Overlapping
// windows are harmless: an issue already labeled is left alone, and one whose
// label a person removed is never labeled again.
//
// Environment:
//   GH_TOKEN               the lane App token (issues: write)
//   GITHUB_REPOSITORY      owner/repo
//   GITHUB_EVENT_NAME      `issues` (a close) or `schedule` (the sweep)
//   GITHUB_EVENT_PATH      the event payload; on `issues` only its action,
//                          issue number and sender are read; on `schedule`
//                          it is not read
//   KILL_SWITCH            `proceed` from the kill-switch step; anything else stops
//   TRUSTED_ACTORS_PATH    trusted-actors.json from the default branch tip
//   ACTOR_ID               who closed the issue; must be a listed human
//                          (`issues` only)
//   TRIGGERING_ACTOR       who started this run (a re-runner may differ);
//                          must be a listed human (`issues` only)
//   BASE_PATH              the default branch checkout (default `.base`), whose
//                          pr-pipeline.yaml holds resolve-issue's admission
//   GITHUB_API_URL
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { admits } from "../../actions/resolve-config/predicate.mjs";
import { findRatification } from "../../actions/resolve-config/ratification.mjs";

const LABEL = "agent-ready";
// A person decides these; the lane never starts on them.
const HOLDS = new Set(["needs-owner-decision", "status: needs-decision", "needs-human"]);
const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
// The sweep's window: three hourly runs overlap, so a missed run loses nothing.
export const LOOKBACK_HOURS = 3;

// Whether the account that closed the issue (ACTOR_ID, by id) and the one
// that started this run (TRIGGERING_ACTOR, by login; a re-runner may be
// another account) are each a listed human. The broker mints only then.
export function checkCloser(env) {
  if (!NUMBER.test(env.ACTOR_ID ?? "")) {
    return false;
  }
  const { humans, logins } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
  const rerunner = logins.get(String(env.TRIGGERING_ACTOR ?? "").toLowerCase());
  return humans.has(Number(env.ACTOR_ID)) && rerunner !== undefined && humans.has(rerunner);
}

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const reportError = (number, error) =>
  console.log(`::error title=label-unblocked::#${number}: ${escapeCommand(error?.message ?? error)}`);

// Why `number` is not promoted, or null when it is ready.
async function refusal({ github, repo, number, ratifiers, admission }) {
  const base = `/repos/${repo}/issues/${number}`;
  const current = await github("GET", base);
  if (current.state !== "open") {
    return "not open";
  }
  const labels = (current.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
  const lower = labels.map((label) => String(label).toLowerCase());
  const held = lower.find((label) => HOLDS.has(label));
  if (held) {
    return `held by ${held}`;
  }
  if (lower.includes(LABEL)) {
    return `already ${LABEL}`;
  }
  // A blocker closed as not planned or duplicate never did the work, and its
  // author can close it, so only a completed close counts; a pull request
  // counts only once merged.
  const done = (blocker) =>
    blocker.state === "closed" &&
    (blocker.pull_request ? Boolean(blocker.pull_request.merged_at) : blocker.state_reason === "completed");
  const blockers = await paginate(github, `${base}/dependencies/blocked_by`);
  const pending = blockers.filter((blocker) => !done(blocker)).length;
  if (pending > 0) {
    return `${pending} blocker(s) not closed as completed`;
  }
  // Removing the label by hand stops the lane; a person adds it to restart.
  const events = await paginate(github, `${base}/events`);
  if (events.some((event) => event.event === "unlabeled" && String(event.label?.name).toLowerCase() === LABEL)) {
    return `${LABEL} was removed before`;
  }
  const ratifying = findRatification(await paginate(github, `${base}/comments`), ratifiers);
  if (ratifying === undefined) {
    return "no admission marker from a listed human";
  }
  return admits(admission, labels, { ratified: true }) ? null : "a work class resolve-issue does not admit";
}

// resolve-issue's admission, from the validated config on the default branch.
// Imported here, not at the top: the resolver's dependencies are installed by
// the resolve-config step that runs before this one.
async function loadAdmission(env) {
  const { readAdmission } = await import("../../actions/resolve-config/resolve-config.mjs");
  return readAdmission({ basePath: env.BASE_PATH || ".base", activity: "resolve-issue" });
}

// The issues closed at or after `since`. The listing's `since` filters on the
// last update, so the close time is checked here; pull requests, which the
// listing also returns, are left out.
async function closedSince(github, repo, since) {
  const path = `/repos/${repo}/issues?state=closed&since=${encodeURIComponent(since.toISOString())}&sort=updated&direction=desc`;
  return (await paginate(github, path))
    .filter((item) => !item.pull_request && NUMBER.test(String(item.number)) && Date.parse(item.closed_at) >= since.getTime())
    .map((item) => Number(item.number));
}

// Whether a swept close counts: the close path takes only a listed human's
// close, and the sweep adds a bot's (a pull request merge, the lanes App). An
// outside author closing their own blocking issue counts for nothing.
async function sweptCloser(github, repo, number, ratifiers) {
  const closer = (await github("GET", `/repos/${repo}/issues/${number}`)).closed_by;
  return closer?.type === "Bot" || ratifiers.has(closer?.id);
}

// Labels each issue `closed` blocked that is ready, each at most once per run.
// Returns how many reads or writes failed.
async function labelUnblocked({ github, repo, closed, sweep, ratifiers, admission }) {
  const seen = new Set();
  let failed = 0;
  for (const source of closed) {
    let blocked;
    try {
      if (sweep && !(await sweptCloser(github, repo, source, ratifiers))) {
        console.log(`label-unblocked: #${source} was closed by neither a listed human nor a bot; skipped`);
        continue;
      }
      blocked = await paginate(github, `/repos/${repo}/issues/${source}/dependencies/blocking`);
    } catch (error) {
      failed += 1;
      reportError(source, error);
      continue;
    }
    for (const item of blocked) {
      const number = Number(item.number);
      // A label write here can land only in this repository.
      if (!String(item.repository_url ?? "").toLowerCase().endsWith(`/repos/${repo}`.toLowerCase()) || item.pull_request) {
        console.log(`label-unblocked: skipped a blocked item outside this repository's issues`);
        continue;
      }
      if (seen.has(number)) {
        continue;
      }
      seen.add(number);
      try {
        const reason = await refusal({ github, repo, number, ratifiers, admission });
        if (reason !== null) {
          console.log(`label-unblocked: #${number} not labeled: ${reason}`);
          continue;
        }
        await github("POST", `/repos/${repo}/issues/${number}/labels`, { labels: [LABEL] });
        console.log(`label-unblocked: #${number} labeled ${LABEL}`);
      } catch (error) {
        failed += 1;
        reportError(number, error);
      }
    }
  }
  return failed;
}

export async function main({ env = process.env, github, admission, now = Date.now() } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const sweep = env.GITHUB_EVENT_NAME === "schedule";
    const event = sweep ? {} : JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8"));
    if (!sweep && (env.GITHUB_EVENT_NAME !== "issues" || event.action !== "closed" || !NUMBER.test(String(event.issue?.number)))) {
      throw new Error("this runs only on an issue closing or on the schedule");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("label-unblocked: the lanes kill switch stops this run; nothing read or labeled");
      return 0;
    }
    if (!sweep) {
      // A bot's close (the lanes App's, or a PR merge a bot ran) is skipped
      // cleanly: the broker refuses it, and the hourly sweep picks it up.
      if (event.sender?.type === "Bot") {
        console.log("label-unblocked: a bot closed this issue; nothing read or labeled");
        return 0;
      }
      if (!checkCloser(env)) {
        console.log("label-unblocked: the closer or the re-runner is not a listed human; nothing read or labeled");
        return 0;
      }
    }
    const repo = env.GITHUB_REPOSITORY;
    const ratifiers = loadTrustedList(env.TRUSTED_ACTORS_PATH).humans;
    admission ??= await loadAdmission(env);
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const closed = sweep
      ? await closedSince(github, repo, new Date(now - LOOKBACK_HOURS * 3_600_000))
      : [Number(event.issue.number)];
    if (sweep) {
      console.log(`label-unblocked: ${closed.length} issue(s) closed in the last ${LOOKBACK_HOURS} hours`);
    }
    const failed = await labelUnblocked({ github, repo, closed, sweep, ratifiers, admission });
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=label-unblocked::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

// `--check-closer` writes only the closer check, as the `proceed` step
// output, so the workflow can stop before it requests a token.
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  if (process.argv[2] === "--check-closer") {
    const proceed = checkCloser(process.env);
    writeOutputs({ proceed: String(proceed) });
    console.log(`label-unblocked: closer and re-runner ${proceed ? "are" : "are not both"} listed humans`);
  } else {
    process.exitCode = await main();
  }
}
