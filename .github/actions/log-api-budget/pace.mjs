// The burn-rate pacer for timer-driven lanes. A budget trip (the breaker
// share of the header's limit left, rate-limits.json) turns the kill switch
// on and stops every lane; this slows the timer-driven ones first. On a
// schedule tick it reads the GITHUB_TOKEN pool once, projects the remaining
// at the window's reset from the burn rate the window has shown so far, and
// writes paced=true when that falls under `pace` of the header's limit
// (limits.api github-token pace: pr-pipeline.yaml, which each paced workflow
// hands over as RESOLVED_CONFIG, over rate-limits.json; 0 is off). A tick is
// paced only when the previous scheduled run of the same workflow shows its
// work step (PACE_WORK_STEP) concluded success, and, with
// PACE_MAX_GAP_MINUTES, was created no longer ago than that. A paced tick
// skips that step, so the next scheduled tick always runs: a paced lane runs
// at half its cadence rather than stopping, whatever other events do to the
// run counter. The read is the workflow's scheduled-run listing, whose
// headers are the pool reading; the previous run's jobs are read only when
// the projection would pace. A paced tick skips its work and ends green. Any
// other event, a reading that cannot project, a previous run that is missing,
// unfinished or did not do its work, or a failed read is paced=false: the
// breaker stays the backstop.
//
//   node pace.mjs   EVENT_NAME, PACE_WORK_STEP, GITHUB_TOKEN, GITHUB_REPOSITORY,
//                   GITHUB_RUN_ID, GITHUB_WORKFLOW_REF and GITHUB_OUTPUT;
//                   RESOLVED_CONFIG and PACE_MAX_GAP_MINUTES optional

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

// Why the tick must run although the projection would pace it, or null when
// `previous` (the last scheduled run but this one, from the listing) did its
// work and may be followed by a paced tick. `jobs` reads that run's jobs.
export async function mustRun({ previous, step, maxGapMinutes, jobs, now }) {
  if (!step) return "no PACE_WORK_STEP names this lane's work";
  if (!previous || !/^[0-9]+$/.test(String(previous.id))) return "no earlier scheduled run";
  const created = Date.parse(previous.created_at) / 1000;
  if (!Number.isFinite(created)) return `run ${previous.id} has no creation time`;
  if (maxGapMinutes > 0 && now - created > maxGapMinutes * 60) return `run ${previous.id}, the last scheduled one, was created over ${maxGapMinutes} minutes ago`;
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
      const response = await get(`/actions/workflows/${encodeURIComponent(file)}/runs?event=schedule&per_page=3`);
      const header = (name) => (response.headers.has(name) ? Number(response.headers.get(name)) : Number.NaN);
      const reading = { limit: header("x-ratelimit-limit"), remaining: header("x-ratelimit-remaining"), reset: header("x-ratelimit-reset") };
      const decision = response.ok ? paceDecision(reading, share, now()) : { paced: false, projected: null };
      let why = "";
      if (decision.paced) {
        const runs = (await response.json())?.workflow_runs;
        if (!Array.isArray(runs)) throw new Error("the scheduled-run listing has an unexpected shape");
        // The newest run created before this one, whatever order the listing has.
        const own = runs.find((run) => String(run?.id) === String(env.GITHUB_RUN_ID ?? ""));
        const before = (run) => run !== own && (!own || Date.parse(run?.created_at) < Date.parse(own.created_at));
        const previous = runs.filter(before).sort((a, b) => Date.parse(b?.created_at) - Date.parse(a?.created_at))[0];
        const jobs = async (id) => {
          const answer = await get(`/actions/runs/${id}/jobs?filter=latest&per_page=100`);
          if (!answer.ok) throw new Error(`run ${id}'s jobs: HTTP ${answer.status}`);
          return answer.json();
        };
        const reason = await mustRun({ previous, step: env.PACE_WORK_STEP, maxGapMinutes: Number(env.PACE_MAX_GAP_MINUTES), jobs, now: now() });
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
