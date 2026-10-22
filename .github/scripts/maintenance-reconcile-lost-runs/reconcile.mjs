#!/usr/bin/env node
// reconcile.mjs: re-runs PR CI and lane runs a GitHub outage ended without a
// result. A run that ended cancelled, timed_out or startup_failure, on its
// first attempt, is re-run once with the job's own token. Its attempt number is
// the record: a run at attempt 2 or later was already re-run, by this script
// or a person, and is never touched again. No model.
//
// Three kinds are re-run:
// - CI: a CI workflow's newest run on an open PR's current head. These
//   workflows check no re-runner.
// - Infra: the same run when it ended failure and every failure is one an
//   outside outage explains (infra-failure.mjs). Only its failed jobs are
//   re-run, through rerun-failed-jobs, at attempts 1 and 2 only, each
//   INFRA_BACKOFF_MINUTES after the attempt ended, and only while npm's and
//   GitHub's status pages show indicator none.
// - Lane: a pr-verify run. Its trigger check trusts a re-run github-actions[bot]
//   starts only through this workflow's record of it, the artifact
//   rerunRecordName(run id, head SHA) (check-trusted-trigger's README). The
//   plan step names each record, the workflow uploads them, and only then does
//   the act step re-run the run, so the record exists before the re-run.
// Other lost lane runs (the review lanes, refine) are listed in the summary for
// a person: their gates or the lanes token broker refuse a re-run
// github-actions[bot] starts. A merge-group run is not covered: a re-run puts
// no PR back in the queue, and pr-merge re-enqueues its own PRs once their
// checks pass.
//
// Nothing is read from GitHub while githubstatus.com shows Actions as anything
// but operational, or the status cannot be read, so a re-run never adds load
// mid-incident. At most MAX_IN_FLIGHT re-runs are in flight at once (PR CI
// sets and pr-verify runs, counting those already running): merge-critical PRs
// (auto-merge set) first, then oldest PR, then the oldest pr-verify runs.
// Writes are at least WRITE_GAP_MS apart. The first rate-limit error stops the
// run.
//
// Environment:
//   MODE                 `plan` (read, choose, name records) or `act` (re-run the plan)
//   PLAN_PATH            the plan file plan writes and act reads
//   RECORD_PATH          the file plan writes for the record uploads
//   GH_TOKEN             the job's GITHUB_TOKEN (actions: write, pull-requests: read)
//   GITHUB_REPOSITORY    owner/repo
//   KILL_SWITCH          `proceed` from the kill-switch step; anything else stops
//   STATUS_URL           the status page's components endpoint (default githubstatus.com)
//   GITHUB_OUTPUT        plan writes record-1 to record-3 there (empty when unused)
//   GITHUB_STEP_SUMMARY  the outcome is listed there when set
//   GITHUB_API_URL
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { createGitHub, paginate, rerunRecordName } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { INFRA_BACKOFF_MINUTES, infraOnly, LOOKBACK_HOURS, reconcilerRetries, testedRun } from "./infra-failure.mjs";

const STATUS_URL = "https://www.githubstatus.com/api/v2/components.json";
// A failed run's failed jobs are re-run only while both pages show indicator none.
export const NPM_STATUS_URL = "https://status.npmjs.org/api/v2/status.json";
export const GITHUB_STATUS_URL = "https://www.githubstatus.com/api/v2/status.json";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RECORD = /^reconcile-rerun-[1-9][0-9]{0,19}-2-[0-9a-f]{40}$/;
export const LOST = new Set(["cancelled", "timed_out", "startup_failure"]);
// Workflows with no trigger-actor check, which a github-actions[bot] re-run passes.
export const CI_WORKFLOWS = new Set([
  ".github/workflows/pr-require-checks.yml",
  ".github/workflows/pr-test-windows.yml",
  ".github/workflows/pr-check-managed-files-hosted.yml",
]);
// Lane workflows whose trigger check takes this workflow's record
// (reconciler-workflow) and that mint no broker token. Each starts on
// workflow_run from main, so its runs are listed by workflow, not by PR head.
export const RECORDED_LANES = [".github/workflows/pr-verify.yml"];
// The lane step that judges the head. A run that reached it may have judged,
// and whoever can cancel it (actions: write) can stop or delete the verdict
// before it lands, so a re-run would let them have the same head judged again:
// it is left alone. So is a run none of whose jobs started: GitHub cancels a
// pending run when a newer one for the same PR head queues behind it, and that
// newer run judges the head.
export const JUDGE_STEP = "Judge the pull request";
export const MAX_IN_FLIGHT = 3;
export const WRITE_GAP_MS = 1000;
// Pages of 100 read per status query of a lane's run listing; a listing that
// does not fit is a failure, never a partial read.
export const LANE_RUN_PAGES = 5;
// The lane listing is read once per status, so the many succeeded runs are
// never listed: the lost conclusions, and every status short of completed (the
// runs a re-run may have put in flight). Earlier statuses are read first, so a
// run that starts between two queries is still listed by the later one.
export const LANE_LIST_STATUSES = [...LOST, "requested", "pending", "waiting", "queued", "in_progress"];

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

const newerFirst = (a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || b.id - a.id;

// The newest run of each workflow on one head.
function newestByWorkflow(runs) {
  const newest = new Map();
  for (const r of runs) {
    const seen = newest.get(r.path);
    if (!seen || newerFirst(r, seen) < 0) {
      newest.set(r.path, r);
    }
  }
  return [...newest.values()];
}

// Each CI workflow's pull_request runs on one head, newest first.
function ciRunsByWorkflow(runs) {
  const byPath = new Map();
  for (const r of runs.filter((run) => CI_WORKFLOWS.has(run.path) && run.event === "pull_request")) {
    byPath.set(r.path, [...(byPath.get(r.path) ?? []), r]);
  }
  return [...byPath.values()].map((list) => list.sort(newerFirst));
}

const isLost = (r, since) => r.status === "completed" && LOST.has(r.conclusion) && r.run_attempt === 1 && Date.parse(r.created_at) >= since;
const isLostLane = (r, since) => r.event === "workflow_run" && r.head_branch === "main" && SHA.test(r.head_sha ?? "") && isLost(r, since);
// A failed run whose failed jobs may be re-run now, if its failures are infra only.
const isRetryable = (r, now) => reconcilerRetries(r, now) && now - Date.parse(r.updated_at) >= INFRA_BACKOFF_MINUTES[r.run_attempt - 1] * 60_000;
const lostNow = (item, r, since) => {
  if (r?.head_sha !== item.head) {
    return false;
  }
  if (item.kind === "infra") {
    return r.status === "completed" && r.conclusion === "failure" && r.run_attempt === item.attempt;
  }
  return item.kind === "lane" ? isLostLane(r, since) : isLost(r, since);
};

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
const byAge = (a, b) => Date.parse(a.created_at) - Date.parse(b.created_at) || a.id - b.id;

// Why the run's first attempt must not be re-run, or undefined when it may be:
// a job started JUDGE_STEP, or no job started any step. Step data, unlike an
// artifact, cannot be deleted. An unreadable listing throws.
async function holdReason(call, repo, runId) {
  const listing = await call("GET", `/repos/${repo}/actions/runs/${runId}/attempts/1/jobs?per_page=100`);
  if (!Array.isArray(listing?.jobs) || listing.total_count > 100) {
    throw new Error("its job listing is not one complete page");
  }
  const started = listing.jobs
    .flatMap((job) => (Array.isArray(job?.steps) ? job.steps : []))
    .filter((s) => s?.conclusion != null && s.conclusion !== "skipped");
  if (started.some((s) => s.name === JUDGE_STEP)) {
    return "after its judge step started";
  }
  return started.length === 0 ? "before any of its jobs started" : undefined;
}

// Reads every open PR's head and the recorded lanes' runs, and returns the
// re-runs to make in order, with a record name on each lane re-run.
async function plan({ repo, call, say, since, now, readStatus }) {
  const pulls = (await paginate(call, `/repos/${repo}/pulls?state=open&base=main`, 5))
    .filter((p) => p.state === "open" && p.draft !== true && p.base?.ref === "main" && p.head?.repo?.full_name === repo && SHA.test(p.head?.sha ?? ""))
    .sort(byMergeCriticality);
  let failed = 0;
  let inFlight = 0;
  const ready = [];
  // Read once, on the first infra-only run: why its re-run waits, or "" when npm and GitHub are clear.
  let upstream;
  const upstreamHold = async () =>
    (upstream ??= (async () => {
      for (const url of [NPM_STATUS_URL, GITHUB_STATUS_URL]) {
        const indicator = await readStatus(url).then(
          (page) => page?.status?.indicator,
          () => "unreadable",
        );
        if (indicator !== "none") {
          return `${new URL(url).host} shows ${indicator ?? "no indicator"}`;
        }
      }
      return "";
    })());
  const noteFailure = (what, error) => {
    if (error instanceof RateLimited) {
      throw error;
    }
    failed += 1;
    console.log(`::error title=reconcile::${what}: ${escapeCommand(error?.message ?? error)}`);
  };
  for (const pull of pulls) {
    try {
      const listing = await call("GET", `/repos/${repo}/actions/runs?head_sha=${pull.head.sha}&per_page=100`);
      if (!Array.isArray(listing?.workflow_runs) || listing.total_count > 100) {
        throw new Error("its run listing is not one complete page");
      }
      const { rerun, lane, inFlight: busy } = classify(listing.workflow_runs, since);
      inFlight += busy ? 1 : 0;
      for (const r of lane) {
        say(`#${pull.number}: lane run ${r.id} (${r.path}) ended ${r.conclusion}; a re-run of this lane needs a person`);
      }
      if (busy) {
        continue;
      }
      const set = rerun.map((r) => ({ kind: "ci", pr: pull.number, id: r.id, path: r.path, conclusion: r.conclusion, head: pull.head.sha }));
      const tested = [];
      for (const runs of ciRunsByWorkflow(listing.workflow_runs)) {
        tested.push(
          await testedRun(runs, async (r) => {
            const listed = await call("GET", `/repos/${repo}/actions/runs/${r.id}/jobs?filter=latest&per_page=100`);
            if (!Array.isArray(listed?.jobs) || listed.total_count > 100) {
              throw new Error(`run ${r.id}'s job listing is not one complete page`);
            }
            return listed.jobs;
          }),
        );
      }
      // A re-run still going under a newer failed contract-only run is in
      // flight too, though classify sees only the newest run.
      if (tested.some((t) => t?.run?.status !== "completed" && t?.run?.run_attempt > 1)) {
        inFlight += 1;
        continue;
      }
      for (const { run: r, jobs } of tested.filter(Boolean)) {
        if (!jobs || !isRetryable(r, now) || !infraOnly(jobs)) {
          continue;
        }
        const hold = await upstreamHold();
        if (hold) {
          say(`#${pull.number}: run ${r.id} (${r.path}) failed on infra only; waiting, ${hold}`);
          continue;
        }
        set.push({ kind: "infra", pr: pull.number, id: r.id, path: r.path, conclusion: "failure (infra only)", attempt: r.run_attempt, head: pull.head.sha });
      }
      if (set.length > 0) {
        ready.push(set);
      }
    } catch (error) {
      noteFailure(`#${pull.number}`, error);
    }
  }
  const created = encodeURIComponent(`>=${new Date(since).toISOString().replace(/\.\d{3}Z$/, "Z")}`);
  const lanes = [];
  for (const lanePath of RECORDED_LANES) {
    try {
      const file = lanePath.slice(lanePath.lastIndexOf("/") + 1);
      const byId = new Map();
      for (const status of LANE_LIST_STATUSES) {
        const listed = await paginate(
          async (...args) => {
            const page = await call(...args);
            if (!Array.isArray(page?.workflow_runs)) {
              throw new Error("its run listing is not a page of runs");
            }
            return page.workflow_runs;
          },
          `/repos/${repo}/actions/workflows/${file}/runs?created=${created}&status=${status}`,
          LANE_RUN_PAGES,
        );
        for (const r of listed) {
          byId.set(r.id, r);
        }
      }
      const listed = [...byId.values()];
      const runs = listed.filter((r) => r.path === lanePath);
      inFlight += runs.filter((r) => r.status !== "completed" && r.run_attempt > 1).length;
      const unpublished = [];
      for (const r of runs.filter((run) => isLostLane(run, since))) {
        try {
          const held = await holdReason(call, repo, r.id);
          if (held) {
            say(`lane run ${r.id} (${r.path}) ended ${r.conclusion} ${held}; a re-run needs a person`);
          } else {
            unpublished.push(r);
          }
        } catch (error) {
          noteFailure(`lane run ${r.id}`, error);
        }
      }
      // The record's head is the pr-verify run's own head_sha (main's tip), not
      // the pull request's head: the PR binding is the live gate's job
      // (check-trusted-trigger and resolve-pr), never this record's.
      lanes.push(
        ...unpublished
          .sort(byAge)
          .map((r) => ({ kind: "lane", id: r.id, path: r.path, conclusion: r.conclusion, head: r.head_sha, created_at: r.created_at, record: rerunRecordName(r.id, r.head_sha) })),
      );
    } catch (error) {
      noteFailure(lanePath, error);
    }
  }

  // Every item takes one place: a PR's CI set, or one lane run.
  let room = Math.max(0, MAX_IN_FLIGHT - inFlight);
  const items = [];
  for (const set of ready) {
    if (room > 0) {
      items.push(...set);
      room -= 1;
    } else {
      say(`#${set[0].pr}: deferred, ${MAX_IN_FLIGHT} re-runs in flight`);
    }
  }
  for (const lane of lanes) {
    if (room > 0) {
      items.push(lane);
      room -= 1;
    } else {
      say(`lane run ${lane.id} (${lane.path}): deferred, ${MAX_IN_FLIGHT} re-runs in flight`);
    }
  }
  return { items, failed };
}

// Re-runs each planned item still lost on a fresh read.
async function act({ repo, call, say, since, sleep, items }) {
  let failed = 0;
  let wrote = false;
  for (const item of items) {
    const where = item.kind === "lane" ? "lane" : `#${item.pr}`;
    try {
      if (item.kind === "lane" && item.record !== rerunRecordName(item.id, item.head)) {
        throw new Error("the plan names no record for it");
      }
      const r = await call("GET", `/repos/${repo}/actions/runs/${item.id}`);
      if (!lostNow(item, r, since)) {
        say(`${where}: run ${item.id} changed since the listing; left alone`);
        continue;
      }
      if (item.kind !== "lane") {
        // A push since the listing makes this run obsolete, and re-running it
        // would cancel the new head's CI in the PR's concurrency group.
        const current = await call("GET", `/repos/${repo}/pulls/${item.pr}`);
        if (current?.state !== "open" || current.draft === true || current.head?.sha !== item.head) {
          say(`${where}: the PR changed since the listing; run ${item.id} left alone`);
          continue;
        }
      }
      if (wrote) {
        await sleep(WRITE_GAP_MS);
      }
      wrote = true;
      if (item.kind === "infra") {
        await call("POST", `/repos/${repo}/actions/runs/${item.id}/rerun-failed-jobs`);
        say(`${where}: re-ran the failed jobs of run ${item.id} (${item.path}) attempt ${item.attempt}, which failed on infra only`);
        continue;
      }
      await call("POST", `/repos/${repo}/actions/runs/${item.id}/rerun`);
      say(`${where}: re-ran run ${item.id} (${item.path}), which ended ${item.conclusion}`);
    } catch (error) {
      if (error instanceof RateLimited) {
        throw error;
      }
      failed += 1;
      console.log(`::error title=reconcile::${where} run ${item.id}: ${escapeCommand(error?.message ?? error)}`);
    }
  }
  return failed;
}

// The plan's record-N outputs, each a record name or empty.
function recordOutputs(items) {
  const names = items.filter((item) => item.kind === "lane").map((item) => item.record);
  if (names.length > MAX_IN_FLIGHT || !names.every((name) => RECORD.test(name))) {
    throw new Error("the plan's record names are malformed");
  }
  return Object.fromEntries(Array.from({ length: MAX_IN_FLIGHT }, (_, i) => [`record-${i + 1}`, names[i] ?? ""]));
}

export async function main({ env = process.env, github, fetchStatus: readStatus = fetchStatus, sleep = delay, now = Date.now() } = {}) {
  const lines = [];
  const say = (line) => {
    console.log(`reconcile: ${line}`);
    lines.push(`- ${line}`);
  };
  const finish = (code) => {
    if (env.GITHUB_STEP_SUMMARY && lines.length > 0) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, `### Lost-run reconciler (${env.MODE})\n\n${lines.join("\n")}\n`);
    }
    return code;
  };
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.MODE !== "plan" && env.MODE !== "act") {
      throw new Error("MODE is neither plan nor act");
    }
    if (!env.PLAN_PATH) {
      throw new Error("PLAN_PATH is not set");
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

    if (env.MODE === "act") {
      const planned = JSON.parse(readFileSync(env.PLAN_PATH, "utf8"));
      if (!Array.isArray(planned?.items) || !Number.isInteger(planned.failed)) {
        throw new Error("the plan file does not hold a plan");
      }
      const failed = await act({ repo, call, say, since, sleep, items: planned.items });
      if (planned.failed + failed > 0) {
        console.log(`::error title=reconcile::the plan step recorded ${planned.failed} listing failures and ${failed} re-runs failed; see the Find lost runs step`);
        return finish(1);
      }
      return finish(0);
    }

    let result = { items: [], failed: 0 };
    const write = () => {
      writeFileSync(env.PLAN_PATH, JSON.stringify(result));
      const outputs = recordOutputs(result.items);
      if (outputs["record-1"] !== "") {
        writeFileSync(env.RECORD_PATH, JSON.stringify(result.items.filter((item) => item.kind === "lane")));
      }
      if (env.GITHUB_OUTPUT) {
        writeOutputs(outputs, env.GITHUB_OUTPUT);
      }
    };
    if (env.KILL_SWITCH !== "proceed") {
      say("the lanes kill switch stops this run; nothing read or re-run");
      write();
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
      write();
      return finish(0);
    }
    result = await plan({ repo, call, say, since, now, readStatus });
    if (result.items.some((item) => item.kind === "lane") && !env.RECORD_PATH) {
      throw new Error("RECORD_PATH is not set");
    }
    write();
    if (lines.length === 0 && result.items.length === 0) {
      say(result.failed > 0 ? `${result.failed} listings failed; what was lost is unknown` : "nothing lost");
    }
    return finish(0);
  } catch (error) {
    console.log(`::error title=reconcile::${escapeCommand(error?.message ?? error)}; the run stops`);
    return finish(1);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
