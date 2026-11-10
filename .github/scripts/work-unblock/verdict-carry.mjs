#!/usr/bin/env node
// verdict-carry.mjs: the reads of a work-unblock sweep that never change,
// carried to the next sweep so it does not read them again. A sweep reads,
// for each agent-ready issue, the latest-attempt job listing of each of its
// completed work-resolve-issue runs and the log of a refused job
// (label-unblocked.mjs jobLister and refusalReader); on 2026-11-10 that was
// about 44 job listings and 31 logs a sweep, every sweep, for the same runs.
//
//   jobs      a completed run's latest-attempt jobs, by `<run id>|<attempt>`,
//             each job kept as the fields the sweep reads; used only while
//             this sweep's run listing shows the run completed with the same
//             attempt and updated_at (a re-run starts a new attempt)
//   refusals  the refusal reason read from a completed job's log, by
//             `<job id>|<mode>` (a job log never changes once it ends); only
//             a log that was read is kept, never a failed read
//
// `read` takes the file from the newest successful sweep of main's
// work-unblock.yml (a scheduled run or one a finished work-resolve-issue run
// started), this run aside, holding the work-unblock-verdicts artifact. Only
// that run's own steps could upload it, and every work-unblock event runs
// main's copy of the workflow; it never goes through actions/cache, which any
// job in main's cache scope can write (pr-merge/carry-run-cache.mjs). `read`
// first removes any file at VERDICTS_IN, so a file left there is never read.
//
// Any failure, or an entry of the wrong shape, carries nothing for it and the
// sweep reads GitHub as before. An entry unused for CARRY_DAYS is dropped, and
// at most JOBS_MAX and REFUSALS_MAX entries are kept, the newest used first.
//
// Environment (`read`):
//   VERDICTS_IN         the file to write
//   ACTIONS_TOKEN       the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY   owner/repo
//   GITHUB_RUN_ID       this run, which has no file yet
//   RUNNER_TEMP         where the artifact is downloaded
//   GITHUB_API_URL
import { appendFileSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { ghDownloadArtifact, newestTrustedArtifact } from "../pr-merge/rotation.mjs";

export const CARRY_ARTIFACT = "work-unblock-verdicts";
export const CARRY_FILE = "work-unblock-verdicts.json";
const WORKFLOW_PATH = ".github/workflows/work-unblock.yml";
// Judgment: an agent-ready issue's runs stay in the sweep for days, and an
// entry each sweep uses is kept fresh; 14 days outlasts a stalled issue's
// backoff (24 hours at most) many times over.
export const CARRY_DAYS = 14;
// Judgment: a sweep read about 44 runs and 31 logs on 2026-11-10.
export const JOBS_MAX = 300;
export const REFUSALS_MAX = 2000;
const RUN_KEY = /^[1-9][0-9]{0,14}\|[1-9][0-9]{0,3}$/;
const REFUSAL_KEY = /^[1-9][0-9]{0,14}\|(?:check|token|stop)$/;
// A refusal reason as label-unblocked.mjs reads it (DENIAL, BREAKER), or null.
const REASON = /^[a-z]+(?:-[a-z]+)*$/;
const ZONED = /(Z|[+-]\d\d:\d\d)$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const DAY_MS = 86_400_000;

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const warn = (what, error) => console.log(`::warning title=verdict-carry::${what}: ${escapeCommand(error?.message ?? error)}`);

const fresh = (entry, now) => {
  if (!isObject(entry) || typeof entry.at !== "string" || !ZONED.test(entry.at)) return false;
  const age = now - Date.parse(entry.at);
  return age >= 0 && age <= CARRY_DAYS * DAY_MS;
};
const isStep = (step) => isObject(step) && typeof step.name === "string" && (step.conclusion === null || typeof step.conclusion === "string");
const isJob = (job) =>
  isObject(job) &&
  (job.id === undefined || Number.isSafeInteger(job.id)) &&
  typeof job.name === "string" &&
  (job.steps === undefined || (Array.isArray(job.steps) && job.steps.every(isStep)));
const validJobs = (entry) => typeof entry.updated_at === "string" && Array.isArray(entry.jobs) && entry.jobs.every(isJob);
const validRefusal = (entry) => entry.value === null || (typeof entry.value === "string" && REASON.test(entry.value));

// A job as the sweep reads it: no log text, URL or runner name is kept.
function slimJob(job) {
  const out = { id: job.id, name: job.name, conclusion: job.conclusion ?? null, runner_id: job.runner_id ?? null, started_at: job.started_at ?? null };
  if (Array.isArray(job.steps)) out.steps = job.steps.map((step) => ({ name: String(step?.name ?? ""), conclusion: step?.conclusion ?? null }));
  return out;
}

const runKey = (run) => (RUN_KEY.test(`${run?.id}|${run?.run_attempt}`) ? `${run.id}|${run.run_attempt}` : null);

// The carry from the file at `path` (missing or unreadable: empty), with the
// lookups and records label-unblocked.mjs makes and the file the next sweep
// reads. `now` dates each entry used or added.
export function loadCarry(path, now = Date.now()) {
  const section = (data, name, keyPattern, valid) => {
    const out = new Map();
    if (!isObject(data?.[name])) return out;
    for (const [key, entry] of Object.entries(data[name])) {
      if (keyPattern.test(key) && fresh(entry, now) && valid(entry)) out.set(key, entry);
    }
    return out;
  };
  let data = null;
  if (path) {
    try {
      data = JSON.parse(readFileSync(path, "utf8"));
    } catch (error) {
      if (error?.code !== "ENOENT") warn("the carried verdicts were not read", error);
    }
  }
  const jobs = section(data, "jobs", RUN_KEY, validJobs);
  const refusals = section(data, "refusals", REFUSAL_KEY, validRefusal);
  const at = new Date(now).toISOString();
  const counts = { jobsHit: 0, jobsRead: 0, refusalsHit: 0, refusalsRead: 0 };
  const use = (map, key, entry) => map.set(key, { ...entry, at });
  return {
    counts,
    // A completed run's carried jobs while its listing still matches, else undefined.
    jobsOf(run) {
      const key = runKey(run);
      const entry = key && run.status === "completed" ? jobs.get(key) : undefined;
      if (!entry || entry.updated_at !== run.updated_at) return undefined;
      use(jobs, key, entry);
      counts.jobsHit += 1;
      return entry.jobs.map((job) => ({ ...job, steps: job.steps?.map((step) => ({ ...step })) }));
    },
    keepJobs(run, listed) {
      const key = runKey(run);
      if (!key || run.status !== "completed" || typeof run.updated_at !== "string" || !Array.isArray(listed) || !listed.every(isJob)) return;
      counts.jobsRead += 1;
      jobs.set(key, { at, updated_at: run.updated_at, jobs: listed.map(slimJob) });
    },
    // { value } for a carried refusal, else undefined.
    refusal(jobId, mode) {
      const key = `${jobId}|${mode}`;
      const entry = REFUSAL_KEY.test(key) ? refusals.get(key) : undefined;
      if (!entry) return undefined;
      use(refusals, key, entry);
      counts.refusalsHit += 1;
      return { value: entry.value };
    },
    keepRefusal(jobId, mode, value) {
      const key = `${jobId}|${mode}`;
      if (!REFUSAL_KEY.test(key) || !validRefusal({ value })) return;
      counts.refusalsRead += 1;
      refusals.set(key, { at, value });
    },
    // Writes the file the next sweep reads; true once written.
    save(to) {
      const newest = (map, max) => Object.fromEntries([...map].sort(([, a], [, b]) => Date.parse(b.at) - Date.parse(a.at)).slice(0, max));
      try {
        writeFileSync(`${to}.tmp`, JSON.stringify({ jobs: newest(jobs, JOBS_MAX), refusals: newest(refusals, REFUSALS_MAX) }));
        renameSync(`${to}.tmp`, to);
        return true;
      } catch (error) {
        warn("the verdicts were not kept for the next sweep", error);
        return false;
      }
    },
  };
}

// A successful sweep of main's work-unblock.yml: only a sweep uploads the file.
export const sweepRun = (repo) => (run) =>
  run?.path === WORKFLOW_PATH &&
  (run.event === "schedule" || run.event === "workflow_run") &&
  run.head_branch === "main" &&
  run.conclusion === "success" &&
  run.head_repository?.full_name === repo;

// `read`: the newest successful sweep's file, written to VERDICTS_IN.
export async function read({ env = process.env, actions, download } = {}) {
  const { VERDICTS_IN: to, GITHUB_REPOSITORY: repo = "" } = env;
  try {
    if (to) rmSync(to, { force: true });
    if (!to || !REPO.test(repo)) throw new Error("VERDICTS_IN and GITHUB_REPOSITORY are required");
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    download ??= ghDownloadArtifact({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: CARRY_ARTIFACT, file: CARRY_FILE });
    const found = await newestTrustedArtifact({ repo, runId: String(env.GITHUB_RUN_ID), actions, name: CARRY_ARTIFACT, workflow: WORKFLOW_PATH, trusted: sweepRun(repo) });
    if (found?.artifactId === undefined) {
      console.log("no earlier sweep's verdicts to carry");
      return;
    }
    const text = download(found.artifactId);
    if (!isObject(JSON.parse(text))) throw new Error(`the ${CARRY_ARTIFACT} file of run ${found.runId} is not a JSON object`);
    writeFileSync(`${to}.tmp`, text);
    renameSync(`${to}.tmp`, to);
    console.log(`${CARRY_ARTIFACT} of run ${found.runId}`);
  } catch (error) {
    warn("the verdicts were not carried", error);
  }
}

// Sets `verdicts=true` for the upload steps once the file is written.
export function markSaved(env = process.env) {
  if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, "verdicts=true\n");
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href && process.argv[2] === "read") {
  await read();
}
