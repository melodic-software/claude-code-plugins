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
// A pending run's job does the work only when its "Check who started the
// run" step lets it on, and this check counts a run by that step's rule, by
// id, since a login can be released and registered by someone else: a
// scheduled run's first attempt, a later attempt of one that a listed human
// started (a re-run keeps the event, and a scheduled run's actor is often a
// bot), or any other run whose actor and triggering actor are each a listed
// human. A scheduled or
// hand-started run counts only on main, since another branch runs its own
// copy. A pull_request_target run reads only its own pull request, so it
// supersedes no run. And its
// event must rank at least as high as this run's (RANKS). For `merge`, only a
// scheduled run re-fires refused lane runs, and a pull_request_target run
// starts no full CI run: pull_request_target, then workflow_dispatch, then
// schedule. For `enable-auto-merge`, a scheduled or hand-started run reads
// every lane pull request and disarms one on a hold, and only it arms:
// pull_request_target, then workflow_dispatch and schedule.
//
// A PR-scoped dispatch (pr-merge.yml inputs.pr, its run name rotation.mjs
// WAKE_TITLE) arms only its one pull request, so, like pull_request_target,
// it supersedes no sweep. Its own run (DISPATCH_PR set) is superseded by a
// sweep as any run is, and by a pending PR-scoped dispatch for the same pull
// request that the who step lets on: github-actions[bot]'s first attempt
// (who.mjs verdictWake), or one a listed human started.
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
//   DISPATCH_PR          this run's pull request when it is PR-scoped
//   TRUSTED_ACTORS_PATH  trusted-actors.json from the default branch tip
//   GITHUB_OUTPUT        receives superseded=true or superseded=false
//   GITHUB_STEP_SUMMARY  the skip is listed there when set
//   GITHUB_API_URL
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList, REPOSITORY } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { WAKE_TITLE } from "./rotation.mjs";
import { GITHUB_ACTIONS_BOT_ID } from "./who.mjs";

export const RANKS = Object.freeze({
  merge: Object.freeze({ pull_request_target: 0, workflow_dispatch: 1, schedule: 2 }),
  "enable-auto-merge": Object.freeze({ pull_request_target: 0, workflow_dispatch: 1, schedule: 1 }),
});
const WAITING = new Set(["queued", "pending", "waiting", "requested"]);
export const MAX_JOB_READS = 5;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// The run's actor and its triggering actor (who last re-ran it) are each a
// listed human, by id.
const startedByHuman = ({ humans }, run) =>
  [run.actor?.id, run.triggering_actor?.id].every((id) => Number.isInteger(id) && humans.has(id));

const NUMBER = /^[1-9][0-9]{0,15}$/;

// A PR-scoped dispatch's pull request as its run name gives it, or null for
// a run that is not one (an unreadable number reads as no pull request).
const scopeOf = (run) => {
  if (run?.event !== "workflow_dispatch") return null;
  const found = WAKE_TITLE.exec(String(run.display_title ?? ""));
  return found === null ? null : NUMBER.test(found[1]) ? found[1] : "";
};

// The pending runs whose job, if still waiting, does all this run's job does.
// `scope`: this run's pull request when it is PR-scoped, else null.
export function eligible(runs, { runId, event, trusted, ranks, scope = null }) {
  return runs.filter((run) => {
    if (
      !(
        run?.status === "pending" &&
        String(run.id) !== runId &&
        Object.hasOwn(ranks, run.event) &&
        ranks[run.event] >= ranks[event] &&
        // An event run reads only its own pull request (pr-merge.yml EVENT_PR).
        run.event !== "pull_request_target" &&
        // A dispatch on another branch runs that branch's copy of the workflow.
        run.head_branch === "main"
      )
    ) {
      return false;
    }
    const other = scopeOf(run);
    if (other !== null) {
      // A PR-scoped dispatch does only a PR-scoped run's work for its own pull request.
      const wake = run.actor?.id === Number(GITHUB_ACTIONS_BOT_ID) && run.triggering_actor?.id === run.actor.id && run.run_attempt === 1;
      return scope !== null && other !== "" && other === scope && (wake || startedByHuman(trusted, run));
    }
    return run.event === "schedule" ? run.run_attempt === 1 || trusted.humans.has(run.triggering_actor?.id) : startedByHuman(trusted, run);
  });
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
    const repo = env.GITHUB_REPOSITORY ?? "";
    if (!REPOSITORY.test(repo)) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const trusted = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    // The group holds at most 100 pending runs, so one page lists them all.
    const listing = await actions("GET", `/repos/${repo}/actions/workflows/pr-merge.yml/runs?status=pending&exclude_pull_requests=true&per_page=100`);
    if (!Array.isArray(listing?.workflow_runs)) {
      throw new Error("the pending run listing has an unexpected shape");
    }
    // A PR-scoped run whose input is no pull request number does nothing, so
    // nothing does its work either.
    const scope = event === "workflow_dispatch" && env.DISPATCH_PR ? (NUMBER.test(env.DISPATCH_PR) ? env.DISPATCH_PR : "") : null;
    const runs = eligible(listing.workflow_runs, { runId: String(env.GITHUB_RUN_ID), event, trusted, ranks, scope });
    for (const run of runs.slice(0, MAX_JOB_READS)) {
      const read = await actions("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`);
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
