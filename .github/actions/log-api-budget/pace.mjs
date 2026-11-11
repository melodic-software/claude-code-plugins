// The burn-rate pacer for timer-driven lanes. A budget trip (the breaker
// share of the header's limit left, rate-limits.json) turns the kill switch
// on and stops every lane; this slows the timer-driven ones first. On a
// schedule tick it reads the workflow's scheduled-run listing, whose headers
// are the GITHUB_TOKEN pool reading, projects the remaining at the window's
// reset from the burn rate the window has shown so far, and writes
// paced=true when that falls under `pace` of the header's limit (limits.api
// github-token pace: pr-pipeline.yaml, which each paced workflow hands over
// as RESOLVED_CONFIG, over rate-limits.json; 0 is off) and the previous
// scheduled run, the one with the highest run id below this run's, shows its
// lane's marker step (PACE_WORK_STEP) concluded success. Each lane runs that
// marker only after a clean pass of its work, and a paced tick skips it, so
// the next scheduled tick always runs: a paced lane runs at half its cadence
// rather than stopping, whatever other events do to the run counter. The
// previous run's jobs are read only when the projection would pace. A paced
// tick skips its work and ends green. Any other event, a reading that cannot
// project, a previous run that is missing or shows no clean pass, or a
// failed read is paced=false: the breaker stays the backstop.
//
//   node pace.mjs   EVENT_NAME, PACE_WORK_STEP, GITHUB_TOKEN, GITHUB_REPOSITORY,
//                   GITHUB_RUN_ID, GITHUB_WORKFLOW_REF and GITHUB_OUTPUT;
//                   RESOLVED_CONFIG optional

import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { apiLimitsOrBuiltIn, countRequests } from "./rate-guard.mjs";

// GitHub's primary rate-limit window.
const WINDOW_SECONDS = 3600;
// Before this much of the window has passed, the burn rate is too short to project.
const MIN_ELAPSED_SECONDS = 60;

const round = (value) => Math.round(value * 100) / 100;

// { paced, projected } for one reading at `now` (epoch seconds): projected is
// the share of the header's limit left at the reset, at the window's burn
// rate so far, clamped to 0..1.
export function paceDecision({ limit, remaining, reset } = {}, share, now) {
  const left = reset - now;
  if (![limit, remaining, reset].every(Number.isFinite) || limit <= 0 || remaining < 0 || remaining > limit || left < 0 || !(share > 0)) {
    return { paced: false, projected: null };
  }
  const elapsed = WINDOW_SECONDS - Math.min(left, WINDOW_SECONDS);
  const used = limit - remaining;
  const atReset = elapsed < MIN_ELAPSED_SECONDS ? remaining : remaining - (used * left) / elapsed;
  const projected = Math.max(0, atReset) / limit;
  return { paced: projected < share, projected: round(projected) };
}

// The scheduled run before `runId`: the highest run id below it. Ids grow
// with each run; created_at does not always (rotation.mjs runOrder: runs
// stamped an hour ahead on 2026-11-01).
export function previousRun(runs, runId) {
  const own = /^[0-9]+$/.test(String(runId ?? "")) ? Number(runId) : Number.NaN;
  if (!Number.isSafeInteger(own)) return undefined;
  return runs.filter((run) => Number.isSafeInteger(run?.id) && run.id < own).reduce((a, b) => (a === undefined || b.id > a.id ? b : a), undefined);
}

// Why the tick must run although the projection would pace it, or null when
// `previous` shows a clean pass and may be followed by a paced tick. `jobs`
// reads that run's jobs.
export async function mustRun({ previous, step, jobs }) {
  if (!step) return "no PACE_WORK_STEP names this lane's work";
  if (!previous) return "no earlier scheduled run";
  const listed = (await jobs(previous.id))?.jobs;
  if (!Array.isArray(listed)) throw new Error(`run ${previous.id}'s job listing has an unexpected shape`);
  const did = listed.some((job) => (job?.steps ?? []).some((s) => s?.name === step && s.conclusion === "success"));
  return did ? null : `run ${previous.id}, the last scheduled one, shows no successful \`${step}\``;
}

export async function main(env = process.env, { fetchImpl = fetch, now = () => Date.now() / 1000 } = {}) {
  let paced = false;
  if (env.EVENT_NAME === "schedule") {
    try {
      const share = apiLimitsOrBuiltIn({ resolvedPath: env.RESOLVED_CONFIG })["github-token"].pace;
      const file = /\/\.github\/workflows\/([^/@]+)@/.exec(env.GITHUB_WORKFLOW_REF ?? "")?.[1];
      if (!file) throw new Error("GITHUB_WORKFLOW_REF names no workflow file");
      const api = env.GITHUB_API_URL ?? "https://api.github.com";
      // Counted for the job-end api-calls notice like any guarded call.
      const get = (path) =>
        countRequests(fetchImpl)(`${api}/repos/${env.GITHUB_REPOSITORY}${path}`, {
          headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${env.GITHUB_TOKEN}`, "X-GitHub-Api-Version": "2022-11-28" },
        });
      // Five, so a run whose created_at is stamped ahead still leaves the
      // previous one in the page.
      const response = await get(`/actions/workflows/${encodeURIComponent(file)}/runs?event=schedule&per_page=5`);
      const header = (name) => (response.headers.has(name) ? Number(response.headers.get(name)) : Number.NaN);
      const reading = { limit: header("x-ratelimit-limit"), remaining: header("x-ratelimit-remaining"), reset: header("x-ratelimit-reset") };
      const decision = response.ok ? paceDecision(reading, share, now()) : { paced: false, projected: null };
      let why = "";
      if (decision.paced) {
        const runs = (await response.json())?.workflow_runs;
        if (!Array.isArray(runs)) throw new Error("the scheduled-run listing has an unexpected shape");
        const previous = previousRun(runs, env.GITHUB_RUN_ID);
        const jobs = async (id) => {
          const answer = await get(`/actions/runs/${id}/jobs?filter=latest&per_page=100`);
          if (!answer.ok) throw new Error(`run ${id}'s jobs: HTTP ${answer.status}`);
          return answer.json();
        };
        const reason = await mustRun({ previous, step: env.PACE_WORK_STEP, jobs });
        paced = reason === null;
        why = paced ? `; this tick skips its work, run ${previous.id} did the last` : `; this tick runs: ${reason}`;
      }
      if (decision.projected !== null) {
        console.log(`::notice title=api-pace::github-token projected=${decision.projected} pace=${share} paced=${paced}${why}`);
      }
    } catch (error) {
      console.log(`::warning::the pacer could not read the GITHUB_TOKEN pool (${error.message}); the tick runs`);
      paced = false;
    }
  }
  appendFileSync(env.GITHUB_OUTPUT, `paced=${paced}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::warning::the pacer failed (${error.message}); the tick runs`);
  });
}
