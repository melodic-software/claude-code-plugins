import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { budgetPolicy } from "../check-kill-switch/budget-policy.mjs";
import { countRequests } from "./rate-guard.mjs";

export { paceDecision, paceShare } from "../check-kill-switch/budget-policy.mjs";

export function previousRun(runs, runId) {
  const own = /^[0-9]+$/.test(String(runId ?? "")) ? Number(runId) : Number.NaN;
  if (!Number.isSafeInteger(own)) return undefined;
  return runs.filter((run) => Number.isSafeInteger(run?.id) && run.id < own).reduce((a, b) => (a === undefined || b.id > a.id ? b : a), undefined);
}

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
      const file = /\/\.github\/workflows\/([^/@]+)@/.exec(env.GITHUB_WORKFLOW_REF ?? "")?.[1];
      if (!file) throw new Error("GITHUB_WORKFLOW_REF names no workflow file");
      const policy = budgetPolicy({ resolvedPath: env.RESOLVED_CONFIG });
      await policy.ready("pace");
      const api = env.GITHUB_API_URL ?? "https://api.github.com";
      const get = (path) =>
        countRequests(fetchImpl)(`${api}/repos/${env.GITHUB_REPOSITORY}${path}`, {
          headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${env.GITHUB_TOKEN}`, "X-GitHub-Api-Version": "2022-11-28" },
        });
      const response = await get(`/actions/workflows/${encodeURIComponent(file)}/runs?event=schedule&per_page=5`);
      const header = (name) => (response.headers.has(name) ? Number(response.headers.get(name)) : Number.NaN);
      const reading = { limit: header("x-ratelimit-limit"), remaining: header("x-ratelimit-remaining"), reset: header("x-ratelimit-reset") };
      const decision = response.ok ? policy.decide("pace", reading, now(), { workflow: file }) : { stop: false, projected: null };
      let why = "";
      if (decision.stop) {
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
        console.log(`::notice title=api-pace::github-token projected=${decision.projected} pace=${decision.share} paced=${paced}${why}`);
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
