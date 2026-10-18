#!/usr/bin/env node
// superseded.mjs: tells a pr-merge `merge` job whether another run of this
// workflow is pending in the `pr-merge` concurrency group and will do the same
// work after this one. Runs there start one at a time, so a run still pending
// while this job holds the group starts after it, whatever order they were
// created in. When that run sweeps every candidate and does every follow-up
// this run would, this run skips the gate: a backlog then costs one sweep, and
// no run is cancelled, so no CANCELLED `merge` check lands on a PR.
//
// A pending run sweeps when it is scheduled, or when its actor id and its
// triggering actor's login are both a listed human's (the job's "Check who
// started the run" step stops any other run). A scheduled or hand-started run
// counts only on main, since another branch runs its own copy. Only a
// scheduled run re-fires refused lane runs, and a pull_request_target run
// starts no full CI run, so a run counts only when its event ranks at least as
// high as this run's: pull_request_target, then workflow_dispatch, then
// schedule.
//
// Any failure answers `superseded=false`: the gate runs as it would without
// this check. One REST call, with the job's own token (actions: read).
//
// Environment:
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN
//   GITHUB_REPOSITORY    owner/repo
//   GITHUB_RUN_ID        this run, never its own successor
//   GITHUB_EVENT_NAME    this run's event
//   TRUSTED_ACTORS_PATH  trusted-actors.json from the default branch tip
//   GITHUB_OUTPUT        receives superseded=true or superseded=false
//   GITHUB_STEP_SUMMARY  the skip is listed there when set
//   GITHUB_API_URL
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

const RANK = Object.freeze({ pull_request_target: 0, workflow_dispatch: 1, schedule: 2 });
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// The who step's test: the run's actor id and its triggering actor's login
// (case-insensitive) each belong to a listed human.
function startedByHuman({ humans, logins }, run) {
  const login = run.triggering_actor?.login;
  return (
    Number.isInteger(run.actor?.id) &&
    humans.has(run.actor.id) &&
    typeof login === "string" &&
    humans.has(logins.get(login.toLowerCase()))
  );
}

// The first pending run that sweeps every candidate and does all this run does.
export function successor(runs, { runId, event, trusted }) {
  return runs.find(
    (run) =>
      run?.status === "pending" &&
      String(run.id) !== runId &&
      Object.hasOwn(RANK, run.event) &&
      RANK[run.event] >= RANK[event] &&
      // A dispatch on another branch runs that branch's copy of the workflow.
      (run.event === "pull_request_target" || run.head_branch === "main") &&
      (run.event === "schedule" || startedByHuman(trusted, run)),
  );
}

export async function main({ env = process.env, actions } = {}) {
  let superseded = false;
  try {
    const event = env.GITHUB_EVENT_NAME;
    if (!Object.hasOwn(RANK, event)) {
      throw new Error(`event ${event} has no rank`);
    }
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const trusted = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    // The group holds at most 100 pending runs, so one page lists them all.
    const listing = await actions(
      "GET",
      `/repos/${env.GITHUB_REPOSITORY}/actions/workflows/pr-merge.yml/runs?status=pending&exclude_pull_requests=true&per_page=100`,
    );
    if (!Array.isArray(listing?.workflow_runs)) {
      throw new Error("the pending run listing has an unexpected shape");
    }
    const next = successor(listing.workflow_runs, { runId: String(env.GITHUB_RUN_ID), event, trusted });
    if (next !== undefined) {
      superseded = true;
      const msg = `run ${next.id} (${next.event}) is pending in the pr-merge group and checks every candidate after this run, so this run skips the gate`;
      console.log(`::notice::${escapeCommand(msg)}`);
      if (env.GITHUB_STEP_SUMMARY) {
        appendFileSync(env.GITHUB_STEP_SUMMARY, `- ${msg}\n`);
      }
    }
  } catch (error) {
    console.log(`::warning title=superseded::${escapeCommand(error?.message ?? error)}; the gate runs`);
  }
  appendFileSync(env.GITHUB_OUTPUT, `superseded=${superseded}\n`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
