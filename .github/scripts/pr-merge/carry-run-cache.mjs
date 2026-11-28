#!/usr/bin/env node
import { appendFileSync, existsSync, readFileSync, rmSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { onMain, writeAtomic } from "./head-ref-map.mjs";
import { escapeCommand, ghDownload, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const CARRY_ARTIFACT = "pr-merge-run-cache";
export const VERIFY_ARTIFACT = "pr-merge-verify-run-cache";
const CARRIED = ["carried-run-record", "carried-fail-head-ref", "carried-on-branch", "carried-lane-run"];
export const CARRY_FILE = "pr-merge-carried.json";

export const RETENTION_DAYS = 90;
export const LANE_RUN_DAYS = 30;
export const LANE_RUN_MAX = 400;
const LANE_RUN_BYTES = 65_536;
const LANE_RUN_FORMAT = "v2";
const WORKFLOW_PATH = ".github/workflows/pr-verify.yml";
const SHA = /^[0-9a-f]{40}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const ZONED = /(Z|[+-]\d\d:\d\d)$/;

const warn = (what, error) => console.log(`::warning::${what}: ${escapeCommand(error?.message ?? error)}`);

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

function dated(entry, now, days) {
  if (!isObject(entry) || typeof entry.at !== "string" || !ZONED.test(entry.at)) return false;
  const age = now - Date.parse(entry.at);
  return age >= 0 && age <= days * 86_400_000;
}

function originRecord(key, value, repo, branch) {
  const id = Number(key.slice(repo.length + 1));
  return (
    key.startsWith(`${repo}|`) &&
    isObject(value) &&
    Number.isSafeInteger(value.id) &&
    value.id > 0 &&
    value.id === id &&
    value.path === WORKFLOW_PATH &&
    value.event === "workflow_run" &&
    value.head_branch === branch &&
    value.repository?.full_name === repo &&
    value.head_repository?.full_name === repo &&
    SHA.test(value.head_sha ?? "")
  );
}

function slimRecord(value) {
  const out = { ...value };
  for (const k of ["repository", "head_repository"]) out[k] = { full_name: value[k].full_name };
  return out;
}

function headRef(key, value, repo) {
  return (
    /^[1-9][0-9]{0,15}$/.test(key.slice(repo.length + 1)) &&
    key.startsWith(`${repo}|`) &&
    isObject(value) &&
    typeof value.head_ref === "string" &&
    value.head_ref !== ""
  );
}

function onBranch(key, value, repo, branch) {
  const match = /^(.*)\|([0-9a-f]{40})\.\.\.(.*)$/.exec(key);
  return match !== null && match[1] === repo && match[3] === branch && value === true;
}

function laneRun(key, value, repo) {
  const match = /^([1-9][0-9]{0,15})\|([1-9][0-9]{0,3})\|([A-Za-z0-9_.-]+)\|([a-z0-9]+)$/.exec(key.slice(repo.length + 1));
  if (!key.startsWith(`${repo}|`) || match === null || match[4] !== LANE_RUN_FORMAT) return false;
  const [id, count] = [Number(match[1]), Number(match[2])];
  return (
    isObject(value) &&
    typeof value.updated_at === "string" &&
    Array.isArray(value.attempts) &&
    value.attempts.length === count &&
    value.attempts.every(
      (attempt, i) =>
        isObject(attempt) &&
        attempt.id === id &&
        attempt.run_attempt === i + 1 &&
        Array.isArray(attempt.jobs) &&
        attempt.jobs.every(isObject),
    ) &&
    JSON.stringify(value).length <= LANE_RUN_BYTES
  );
}

export function carry(data, { repo, branch, now }) {
  const out = Object.fromEntries(CARRIED.map((section) => [section, {}]));
  if (!isObject(data)) return out;
  const take = (section, keep, { shape = (value) => value, days = RETENTION_DAYS } = {}) => {
    const to = `carried-${section}`;
    for (const from of [to, section]) {
      if (!isObject(data[from])) continue;
      for (const [key, entry] of Object.entries(data[from])) {
        if (dated(entry, now, days) && keep(key, entry.value)) out[to][key] = { at: entry.at, value: shape(entry.value) };
      }
    }
  };
  take("run-record", (k, v) => originRecord(k, v, repo, branch), { shape: (value) => slimRecord(value) });
  take("fail-head-ref", (k, v) => headRef(k, v, repo));
  take("on-branch", (k, v) => onBranch(k, v, repo, branch));
  take("lane-run", (k, v) => laneRun(k, v, repo), { days: LANE_RUN_DAYS });
  const newest = Object.entries(out["carried-lane-run"])
    .sort(([, a], [, b]) => Date.parse(b.at) - Date.parse(a.at))
    .slice(0, LANE_RUN_MAX);
  out["carried-lane-run"] = Object.fromEntries(newest);
  return out;
}

export function main(env = process.env, now = Date.now()) {
  const { CARRY_FROM: from, CARRY_TO: to, GITHUB_REPOSITORY: repo, CARRY_BRANCH: branch = "main" } = env;
  try {
    if (!from || !to || !REPO.test(repo ?? "")) {
      throw new Error("CARRY_FROM, CARRY_TO and GITHUB_REPOSITORY are required");
    }
    if (!existsSync(from)) {
      console.log("no run cache to carry");
      return;
    }
    const kept = carry(JSON.parse(readFileSync(from, "utf8")), { repo, branch, now });
    writeAtomic(to, JSON.stringify(kept));
    const any = Object.values(kept).some((entries) => Object.keys(entries).length > 0);
    if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, `carried=true\n${any ? "kept=true\n" : ""}`);
    console.log(Object.entries(kept).map(([section, entries]) => `${section}=${Object.keys(entries).length}`).join(" "));
  } catch (error) {
    warn("the run cache was not carried", error);
  }
}

export function withCarried(base, extra) {
  const out = { ...base };
  for (const section of CARRIED) {
    if (isObject(extra[section])) out[section] = { ...extra[section], ...(isObject(base[section]) ? base[section] : {}) };
  }
  return out;
}

export async function read({ env = process.env, actions: client, download } = {}) {
  const { CARRY_TO: to, GITHUB_REPOSITORY: repo = "" } = env;
  try {
    if (to) rmSync(to, { force: true });
    if (!to || !REPO.test(repo)) throw new Error("CARRY_TO and GITHUB_REPOSITORY are required");
    client ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    download ??= (id, name) => ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name, file: CARRY_FILE, shared: env.PR_MERGE_READS_PATH })(id);
    const actions = sharedReads(client, env.PR_MERGE_READS_PATH);
    const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
    const find = (name) => newestTrustedRun({ repo, runId: String(env.GITHUB_RUN_ID), actions, name, accept });
    const load = (name, id) => {
      const text = download(id, name);
      if (!isObject(JSON.parse(text))) throw new Error(`the ${name} file of run ${id} is not a JSON object`);
      console.log(`${name} of run ${id}`);
      return text;
    };
    const mergeId = await find(CARRY_ARTIFACT);
    let kept;
    if (mergeId !== undefined) {
      try {
        kept = load(CARRY_ARTIFACT, mergeId);
      } catch (error) {
        warn(`the ${CARRY_ARTIFACT} file was not carried`, error);
      }
    }
    let verify;
    try {
      const verifyId = await find(VERIFY_ARTIFACT);
      if (verifyId !== undefined) verify = load(VERIFY_ARTIFACT, verifyId);
    } catch (error) {
      warn("the verifier reads were not carried", error);
    }
    if (kept === undefined && verify === undefined) {
      console.log("no earlier run cache to carry");
      return;
    }
    const text = verify === undefined ? kept : JSON.stringify(withCarried(JSON.parse(kept ?? "{}"), JSON.parse(verify)));
    writeAtomic(to, text);
  } catch (error) {
    warn("the run cache was not carried", error);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  if (process.argv[2] === "read") await read();
  else main();
}
