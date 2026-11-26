#!/usr/bin/env node
import { createHash } from "node:crypto";
import { appendFileSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { escapeCommand, ghDownloadArtifact, newestTrustedArtifact } from "../pr-merge/rotation.mjs";

export const CARRY_ARTIFACT = "work-unblock-verdicts";
export const CARRY_FILE = "work-unblock-verdicts.json";
const WORKFLOW_PATH = ".github/workflows/work-unblock.yml";
export const CARRY_DAYS = 14;
export const JOBS_MAX = 300;
export const REFUSALS_MAX = 2000;
export const DECIDED_MAX = 1000;
export const WAIT_MAX_HOURS = 24;
const WAIT_KEY = /^[0-9a-f]{40}-[0-9a-f]{40}$/;
const RUN_KEY = /^[1-9][0-9]{0,14}\|[1-9][0-9]{0,3}$/;
const REFUSAL_KEY = /^[1-9][0-9]{0,14}\|(?:check|token|stop|limit|floor)$/;
const ISSUE_KEY = /^[1-9][0-9]{0,9}$/;
const REASON = /^(?:[a-z]+(?:-[a-z]+)*|\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ(?: server-5\d\d)?)$/;
const ZONED = /(Z|[+-]\d\d:\d\d)$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const DAY_MS = 86_400_000;

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const warn = (what, error) => console.log(`::warning title=verdict-carry::${what}: ${escapeCommand(error?.message ?? error)}`);
const writeWhole = (to, text) => {
  writeFileSync(`${to}.tmp`, text);
  renameSync(`${to}.tmp`, to);
};

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

function slimJob(job) {
  const out = { id: job.id, name: job.name, conclusion: job.conclusion ?? null, runner_id: job.runner_id ?? null, started_at: job.started_at ?? null };
  if (Array.isArray(job.steps)) out.steps = job.steps.map((step) => ({ name: String(step?.name ?? ""), conclusion: step?.conclusion ?? null }));
  return out;
}

const runKey = (run) => (RUN_KEY.test(`${run?.id}|${run?.run_attempt}`) ? `${run.id}|${run.run_attempt}` : null);
const refusalKey = (jobId, mode) => (REFUSAL_KEY.test(`${jobId}|${mode}`) ? `${jobId}|${mode}` : null);

export function codeDigest(dir = dirname(fileURLToPath(import.meta.url))) {
  const digest = createHash("sha256");
  for (const name of readdirSync(dir).filter((file) => file.endsWith(".mjs") && !file.endsWith(".test.mjs")).sort()) {
    digest.update(`${name}\0`).update(readFileSync(join(dir, name))).update("\0");
  }
  return digest.digest("hex");
}

export function loadCarry(path, now = Date.now(), code = codeDigest()) {
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
  if (data?.code !== code) data = null;
  const jobs = section(data, "jobs", RUN_KEY, validJobs);
  const refusals = section(data, "refusals", REFUSAL_KEY, validRefusal);
  const validWait = (wait) =>
    isObject(wait) &&
    typeof wait.reason === "string" &&
    wait.reason.length > 0 &&
    typeof wait.updated === "string" &&
    ZONED.test(wait.updated) &&
    typeof wait.key === "string" &&
    WAIT_KEY.test(wait.key) &&
    Number.isFinite(wait.due) &&
    wait.due <= now + WAIT_MAX_HOURS * 3_600_000;
  const decided = section(data, "decided", ISSUE_KEY, () => true);
  for (const [key, entry] of decided) {
    if (entry.wait !== undefined && !validWait(entry.wait)) decided.set(key, { at: entry.at });
  }
  const at = new Date(now).toISOString();
  const counts = { jobsHit: 0, jobsRead: 0, refusalsHit: 0, refusalsRead: 0 };
  const use = (map, key, entry) => map.set(key, { ...entry, at });
  return {
    counts,
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
    refusal(jobId, mode) {
      const key = refusalKey(jobId, mode);
      const entry = key ? refusals.get(key) : undefined;
      if (!entry) return undefined;
      use(refusals, key, entry);
      counts.refusalsHit += 1;
      return { value: entry.value };
    },
    keepRefusal(jobId, mode, value) {
      const key = refusalKey(jobId, mode);
      if (!key || !validRefusal({ value })) return;
      counts.refusalsRead += 1;
      refusals.set(key, { at, value });
    },
    decidedAt(number) {
      const entry = decided.get(String(number));
      return entry && Date.parse(entry.at);
    },
    carriedWait(number) {
      return decided.get(String(number))?.wait;
    },
    keepDecided(number, wait) {
      if (!ISSUE_KEY.test(String(number))) return;
      decided.set(String(number), wait && validWait(wait) ? { at, wait: { reason: wait.reason, due: wait.due, updated: wait.updated, key: wait.key } } : { at });
    },
    save(to) {
      const newest = (map, max) => Object.fromEntries([...map].sort(([, a], [, b]) => Date.parse(b.at) - Date.parse(a.at)).slice(0, max));
      try {
        writeWhole(to, JSON.stringify({ code, jobs: newest(jobs, JOBS_MAX), refusals: newest(refusals, REFUSALS_MAX), decided: newest(decided, DECIDED_MAX) }));
        return true;
      } catch (error) {
        warn("the verdicts were not kept for the next sweep", error);
        return false;
      }
    },
  };
}

const SWEEP_EVENTS = new Set(["schedule", "workflow_dispatch", "workflow_run"]);
export const anySweepRun = (repo) => (run) =>
  run?.path === WORKFLOW_PATH &&
  SWEEP_EVENTS.has(run.event) &&
  run.head_branch === "main" &&
  run.head_repository?.full_name === repo;

export const sweepRun = (repo) => {
  const sweep = anySweepRun(repo);
  return (run) => sweep(run) && run.conclusion === "success";
};

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
    writeWhole(to, text);
    console.log(`${CARRY_ARTIFACT} of run ${found.runId}`);
  } catch (error) {
    warn("the verdicts were not carried", error);
  }
}

export function markSaved(env = process.env) {
  if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, "verdicts=true\n");
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href && process.argv[2] === "read") {
  await read();
}
