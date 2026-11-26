#!/usr/bin/env node
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { loadTrustedList, REPOSITORY } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { escapeCommand, WAKE_TITLE } from "./rotation.mjs";
import { GITHUB_ACTIONS_BOT_ID } from "./who.mjs";

export const RANKS = Object.freeze({
  merge: Object.freeze({ pull_request_target: 0, workflow_dispatch: 1, schedule: 2 }),
  "enable-auto-merge": Object.freeze({ pull_request_target: 0, workflow_dispatch: 1, schedule: 1 }),
});
const NAMES = Object.freeze({ merge: "Merge", "enable-auto-merge": "Enable Auto Merge" });
const jobNamed = (jobs, job) => jobs.find((j) => j?.name === NAMES[job]) ?? jobs.find((j) => j?.name === job);
const WAITING = new Set(["queued", "pending", "waiting", "requested"]);
export const MAX_JOB_READS = 5;

const startedByHuman = ({ humans }, run) =>
  [run.actor?.id, run.triggering_actor?.id].every((id) => Number.isInteger(id) && humans.has(id));

const NUMBER = /^[1-9][0-9]{0,15}$/;

const scopeOf = (run) => {
  if (run?.event !== "workflow_dispatch") return null;
  const found = WAKE_TITLE.exec(String(run.display_title ?? ""));
  return found === null ? null : NUMBER.test(found[1]) ? found[1] : "";
};

export function eligible(runs, { runId, event, trusted, ranks, scope = null }) {
  return runs.filter((run) => {
    if (
      !(
        run?.status === "pending" &&
        String(run.id) !== runId &&
        Object.hasOwn(ranks, run.event) &&
        ranks[run.event] >= ranks[event] &&
        run.event !== "pull_request_target" &&
        run.head_branch === "main"
      )
    ) {
      return false;
    }
    const other = scopeOf(run);
    if (other !== null) {
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
    const listing = await actions("GET", `/repos/${repo}/actions/workflows/pr-merge.yml/runs?status=pending&exclude_pull_requests=true&per_page=100`);
    if (!Array.isArray(listing?.workflow_runs)) {
      throw new Error("the pending run listing has an unexpected shape");
    }
    const scope = event === "workflow_dispatch" && env.DISPATCH_PR ? (NUMBER.test(env.DISPATCH_PR) ? env.DISPATCH_PR : "") : null;
    const runs = eligible(listing.workflow_runs, { runId: String(env.GITHUB_RUN_ID), event, trusted, ranks, scope });
    for (const run of runs.slice(0, MAX_JOB_READS)) {
      const read = await actions("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`);
      if (!Array.isArray(read?.jobs)) {
        throw new Error(`the jobs of run ${run.id} have an unexpected shape`);
      }
      if (!WAITING.has(jobNamed(read.jobs, job)?.status)) {
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
