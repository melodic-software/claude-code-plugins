#!/usr/bin/env node
// superseded.mjs: tells a pr-merge job (SUPERSEDED_JOB: `merge`, the default,
// or `enable-auto-merge`) whether another run of this workflow has the same job
// still waiting, so it does this run's work after this one. Each of those jobs
// takes its own concurrency group with `queue: max`, so a waiting job starts
// after the one holding the group, whatever order the runs were created in.
// When it does every bit of work this run's job would, this job skips its
// work: a backlog then costs one sweep, and no run is cancelled, so no
// CANCELLED check lands on a PR.
//
// A run's status reads `pending` while any of its jobs waits on a concurrency
// group, so a pending run can be one whose job already ran and that waits on
// another group. A pending run counts only after a read of its jobs shows this
// job waiting (queued, pending, waiting or requested); a job a condition
// skipped is completed. Both jobs need post-merge-dispatch and are created
// only once it ends, so a run still in that job has no waiting job and is not
// counted: this job then does its work.
//
// A pending run's job does the work when the run is scheduled, or when a
// listed human started it (the job's "Check who started the run" step stops
// any other run). This check counts a run only when its actor id and its
// triggering actor id are both a listed human's, since a login can be
// released and registered by someone else. The who step still matches the
// triggering actor by login, so the two differ only on a renamed listed human
// (counted here, stopped there: one sweep waits for the next scheduled run) or
// a listed login someone else now holds (skipped here: one extra sweep). A scheduled or
// hand-started run counts only on main, since another branch runs its own
// copy; pull_request_target runs always run main's. And its
// event must rank at least as high as this run's (RANKS). For `merge`, only a
// scheduled run re-fires refused lane runs, and a pull_request_target run
// starts no full CI run: pull_request_target, then workflow_dispatch, then
// schedule. For `enable-auto-merge`, every run lists every lane pull request
// and disarms one on a hold, and only a scheduled or hand-started one arms:
// pull_request_target, then workflow_dispatch and schedule.
//
// Any failure answers `superseded=false`: the job does its work as it would
// without this check. One REST call to list pending runs, then one jobs read
// per eligible run, at most MAX_JOB_READS, with the job's own token
// (actions: read).
//
// Environment:
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN
//   GITHUB_REPOSITORY    owner/repo
//   GITHUB_RUN_ID        this run, never its own successor
//   GITHUB_EVENT_NAME    this run's event
//   SUPERSEDED_JOB       the job asking: merge (default) or enable-auto-merge
//   TRUSTED_ACTORS_PATH  trusted-actors.json from the default branch tip
//   GITHUB_OUTPUT        receives superseded=true or superseded=false
//   GITHUB_STEP_SUMMARY  the skip is listed there when set
//   GITHUB_API_URL
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const RANKS = Object.freeze({
  merge: Object.freeze({ pull_request_target: 0, workflow_dispatch: 1, schedule: 2 }),
  "enable-auto-merge": Object.freeze({ pull_request_target: 0, workflow_dispatch: 1, schedule: 1 }),
});
const WAITING = new Set(["queued", "pending", "waiting", "requested"]);
export const MAX_JOB_READS = 5;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// The run's actor and its triggering actor (who last re-ran it) are each a
// listed human, by id.
const startedByHuman = ({ humans }, run) =>
  [run.actor?.id, run.triggering_actor?.id].every((id) => Number.isInteger(id) && humans.has(id));

// The pending runs whose job, if still waiting, does all this run's job does.
export function eligible(runs, { runId, event, trusted, ranks }) {
  return runs.filter(
    (run) =>
      run?.status === "pending" &&
      String(run.id) !== runId &&
      Object.hasOwn(ranks, run.event) &&
      ranks[run.event] >= ranks[event] &&
      // A dispatch on another branch runs that branch's copy of the workflow.
      (run.event === "pull_request_target" || run.head_branch === "main") &&
      (run.event === "schedule" || startedByHuman(trusted, run)),
  );
}

export async function main({ env = process.env, actions } = {}) {
  let superseded = false;
  try {
    const job = env.SUPERSEDED_JOB || "merge";
    const ranks = Object.hasOwn(RANKS, job) ? RANKS[job] : undefined;
    if (ranks === undefined) {
      throw new Error(`job ${job} has no ranks`);
    }
    const event = env.GITHUB_EVENT_NAME;
    if (!Object.hasOwn(ranks, event)) {
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
    const runs = eligible(listing.workflow_runs, { runId: String(env.GITHUB_RUN_ID), event, trusted, ranks });
    for (const run of runs.slice(0, MAX_JOB_READS)) {
      const read = await actions("GET", `/repos/${env.GITHUB_REPOSITORY}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`);
      if (!Array.isArray(read?.jobs)) {
        throw new Error(`the jobs of run ${run.id} have an unexpected shape`);
      }
      if (!WAITING.has(read.jobs.find((j) => j?.name === job)?.status)) {
        continue;
      }
      superseded = true;
      const msg = `run ${run.id} (${run.event}) has its ${job} job waiting to do every bit of this run's ${job} work after it, so this run skips it`;
      console.log(`::notice::${escapeCommand(msg)}`);
      if (env.GITHUB_STEP_SUMMARY) {
        appendFileSync(env.GITHUB_STEP_SUMMARY, `- ${msg}\n`);
      }
      break;
    }
  } catch (error) {
    superseded = false;
    console.log(`::warning title=superseded::${escapeCommand(error?.message ?? error)}; the job does its work`);
  }
  appendFileSync(env.GITHUB_OUTPUT, `superseded=${superseded}\n`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
