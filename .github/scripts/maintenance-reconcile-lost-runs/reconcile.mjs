#!/usr/bin/env node
// reconcile.mjs: re-runs PR CI runs a GitHub outage ended without a result.
// A CI workflow's newest run on an open PR's current head that ended
// cancelled, timed_out or startup_failure, on its first attempt, is re-run
// once with the job's own token. Its attempt number is the record: a run at
// attempt 2 or later was already re-run, by this script or a person, and is
// never touched again. No model.
//
// Nothing is read from GitHub while githubstatus.com shows Actions as anything
// but operational, or the status cannot be read, so a re-run never adds load
// mid-incident. At most MAX_IN_FLIGHT PRs have a re-run in flight at once
// (re-runs already running count), merge-critical PRs (auto-merge set) first,
// then oldest first; writes are at least WRITE_GAP_MS apart. The first
// rate-limit error stops the run.
//
// Only the CI workflows below are re-run. A lane workflow's trigger check
// refuses a re-run github-actions[bot] starts, so a lost lane run is listed in
// the summary for a person instead. A merge-group run is not covered: a re-run
// puts no PR back in the queue, and pr-merge re-enqueues its own PRs once
// their checks pass.
//
// Environment:
//   GH_TOKEN             the job's GITHUB_TOKEN (actions: write, pull-requests: read)
//   GITHUB_REPOSITORY    owner/repo
//   KILL_SWITCH          `proceed` from the kill-switch step; anything else stops
//   STATUS_URL           the status page's components endpoint (default githubstatus.com)
//   GITHUB_STEP_SUMMARY  the outcome is listed there when set
//   GITHUB_API_URL
import { appendFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { createGitHub, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

const STATUS_URL = "https://www.githubstatus.com/api/v2/components.json";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
export const LOST = new Set(["cancelled", "timed_out", "startup_failure"]);
// Workflows with no trigger-actor check, which a github-actions[bot] re-run passes.
export const CI_WORKFLOWS = new Set([
  ".github/workflows/pr-require-checks.yml",
  ".github/workflows/pr-test-windows.yml",
  ".github/workflows/pr-check-managed-files-hosted.yml",
]);
export const MAX_IN_FLIGHT = 3;
export const WRITE_GAP_MS = 1000;
// An outage loss is re-run within a day; an older one is left to a person (judgment).
export const LOOKBACK_HOURS = 24;

class RateLimited extends Error {}

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

async function fetchStatus(url) {
  const response = await fetch(url, { headers: { Accept: "application/json" }, signal: AbortSignal.timeout(15_000) });
  if (!response.ok) {
    throw new Error(`the status page answered ${response.status}`);
  }
  return response.json();
}

// The Actions component's status, or undefined when the page has none.
export const actionsStatus = (page) =>
  Array.isArray(page?.components) ? page.components.find((c) => c?.name === "Actions" && c.group !== true)?.status : undefined;

// The newest run of each workflow on one head.
function newestByWorkflow(runs) {
  const newest = new Map();
  for (const r of runs) {
    const seen = newest.get(r.path);
    if (!seen || Date.parse(r.created_at) > Date.parse(seen.created_at) || (r.created_at === seen.created_at && r.id > seen.id)) {
      newest.set(r.path, r);
    }
  }
  return [...newest.values()];
}

const isLost = (r, since) => r.status === "completed" && LOST.has(r.conclusion) && r.run_attempt === 1 && Date.parse(r.created_at) >= since;

// What one PR's head holds: CI runs to re-run, lost lane runs, and whether a
// CI re-run is already in flight.
export function classify(runs, since) {
  const newest = newestByWorkflow(runs);
  const ci = newest.filter((r) => CI_WORKFLOWS.has(r.path));
  return {
    rerun: ci.filter((r) => r.event === "pull_request" && isLost(r, since)),
    lane: newest.filter((r) => !CI_WORKFLOWS.has(r.path) && isLost(r, since)),
    inFlight: ci.some((r) => r.status !== "completed" && r.run_attempt > 1),
  };
}

const byMergeCriticality = (a, b) => Number(b.auto_merge != null) - Number(a.auto_merge != null) || a.number - b.number;

export async function main({ env = process.env, github, fetchStatus: readStatus = fetchStatus, sleep = delay, now = Date.now() } = {}) {
  const lines = [];
  const say = (line) => {
    console.log(`reconcile: ${line}`);
    lines.push(`- ${line}`);
  };
  const finish = (code) => {
    if (env.GITHUB_STEP_SUMMARY && lines.length > 0) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, `### Lost-run reconciler\n\n${lines.join("\n")}\n`);
    }
    return code;
  };
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.KILL_SWITCH !== "proceed") {
      say("the lanes kill switch stops this run; nothing read or re-run");
      return finish(0);
    }
    let status;
    try {
      status = actionsStatus(await readStatus(env.STATUS_URL || STATUS_URL));
    } catch (error) {
      status = `unreadable (${error?.message ?? error})`;
    }
    if (status !== "operational") {
      say(`Actions is ${status ?? "missing from the status page"}; idle until it is operational`);
      return finish(0);
    }

    const repo = env.GITHUB_REPOSITORY;
    let last;
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, onResponse: (r) => (last = r) });
    const call = async (...args) => {
      try {
        return await github(...args);
      } catch (error) {
        const limited =
          error?.status === 429 ||
          (error?.status === 403 && (last?.headers?.get("x-ratelimit-remaining") === "0" || last?.headers?.has("retry-after")));
        throw limited ? new RateLimited(`rate limited at ${args[0]} ${args[1]}`) : error;
      }
    };

    const since = now - LOOKBACK_HOURS * 3_600_000;
    const pulls = (await paginate(call, `/repos/${repo}/pulls?state=open&base=main`, 5))
      .filter((p) => p.state === "open" && p.draft !== true && p.base?.ref === "main" && p.head?.repo?.full_name === repo && SHA.test(p.head?.sha ?? ""))
      .sort(byMergeCriticality);
    let failed = 0;
    let inFlight = 0;
    const ready = [];
    for (const pull of pulls) {
      try {
        const listing = await call("GET", `/repos/${repo}/actions/runs?head_sha=${pull.head.sha}&per_page=100`);
        if (!Array.isArray(listing?.workflow_runs) || listing.total_count > 100) {
          throw new Error("its run listing is not one complete page");
        }
        const { rerun, lane, inFlight: busy } = classify(listing.workflow_runs, since);
        inFlight += busy ? 1 : 0;
        for (const r of lane) {
          say(`#${pull.number}: lane run ${r.id} (${r.path}) ended ${r.conclusion}; a lane re-run needs a person`);
        }
        if (rerun.length > 0 && !busy) {
          ready.push({ pull, rerun });
        }
      } catch (error) {
        if (error instanceof RateLimited) {
          throw error;
        }
        failed += 1;
        console.log(`::error title=reconcile::#${pull.number}: ${escapeCommand(error?.message ?? error)}`);
      }
    }

    const room = Math.max(0, MAX_IN_FLIGHT - inFlight);
    for (const { pull } of ready.slice(room)) {
      say(`#${pull.number}: deferred, ${MAX_IN_FLIGHT} PR CI sets in flight`);
    }
    let wrote = false;
    for (const { pull, rerun } of ready.slice(0, room)) {
      for (const listed of rerun) {
        try {
          // A fresh read, so a run re-run since the listing is left alone.
          const r = await call("GET", `/repos/${repo}/actions/runs/${listed.id}`);
          if (r?.head_sha !== pull.head.sha || !isLost(r, since)) {
            say(`#${pull.number}: run ${listed.id} changed since the listing; left alone`);
            continue;
          }
          if (wrote) {
            await sleep(WRITE_GAP_MS);
          }
          wrote = true;
          await call("POST", `/repos/${repo}/actions/runs/${listed.id}/rerun`);
          say(`#${pull.number}: re-ran run ${listed.id} (${listed.path}), which ended ${listed.conclusion}`);
        } catch (error) {
          if (error instanceof RateLimited) {
            throw error;
          }
          failed += 1;
          console.log(`::error title=reconcile::#${pull.number} run ${listed.id}: ${escapeCommand(error?.message ?? error)}`);
        }
      }
    }
    if (lines.length === 0) {
      say("nothing lost");
    }
    return finish(failed === 0 ? 0 : 1);
  } catch (error) {
    console.log(`::error title=reconcile::${escapeCommand(error?.message ?? error)}; the run stops`);
    return finish(1);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
