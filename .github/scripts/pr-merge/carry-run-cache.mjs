#!/usr/bin/env node
// carry-run-cache.mjs: copies the reads in one pr-merge run cache
// (babysit_run_cache.py) that can never change into a file the next run starts
// from. pr-merge.yml runs it three times: after the gate, from this run's
// cache into the file a scheduled or hand-started run uploads as the
// pr-merge-run-cache artifact; before the gate, `read`, which fetches that
// file; and then from it into this run's empty cache. Every entry is checked
// again on each pass.
//
// `read` takes the file from the newest scheduled or hand-started run of
// main's pr-merge.yml, this run aside, holding the artifact, and only when
// that run's head commit is on main, as head-ref-map.mjs reads its map. Only a
// run's own steps can upload its artifacts, so the file was written by main's
// pr-merge.yml; it never goes through actions/cache, which any job in main's
// cache scope can write and whose restore extracts its archive anywhere in
// the workspace. `read` first removes any file at CARRY_TO, so a file left
// there before it is never read, and writes the downloaded file as it is:
// babysit_merge_skip.py reads its skip-unchanged section.
//
// The carried reads stay untrusted all the same: each kept read lands in a
// carried-* section that babysit_verify_evidence.py reads only on a FAIL's
// path and only where the value counts the FAIL; any other answer is read
// from GitHub.
//   run-record        a pr-verify run's record of origin shape (a run of
//                     pr-verify.yml on the branch of this repository), kept
//                     as carried-run-record with each repository trimmed to
//                     its full_name (all either reader reads); used only
//                     when it shows origin
//   fail-head-ref     the head ref an untied FAIL's verdict.json records, by
//                     artifact id, kept as carried-fail-head-ref; used only
//                     when it names the PR's head ref
//   on-branch         a run head found on the branch (main forbids force
//                     pushes), kept as carried-on-branch; a yes counts a
//                     FAIL's run as origin, and a PASS's run never reads it
// Everything else is dropped: a read bounded by MAX_AGE, keyed by
// credentials, or a sweep stamp can change between runs. So is an entry dated
// in the future or more than RETENTION_DAYS ago, past the artifact retention
// that makes it unreachable. Any failure writes nothing and warns, so the run
// reads GitHub as before.
//
// Environment:
//   CARRY_FROM          the run cache file to read (missing: nothing carried)
//   CARRY_TO            the file to write
//   GITHUB_REPOSITORY   owner/repo
//   CARRY_BRANCH        the branch the verdicts are judged on (main)
//   GITHUB_OUTPUT       gets carried=true once CARRY_TO is written
//   ACTIONS_TOKEN       read: the job's GITHUB_TOKEN (actions: read)
//   GITHUB_RUN_ID       read: this run, which has no file yet
//   RUNNER_TEMP         read: where the artifact is downloaded
//   PR_MERGE_READS_PATH read: the job's shared GET answers
//                       (rotation.mjs sharedReads), if set
//   GITHUB_API_URL
import { appendFileSync, existsSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { onMain } from "./head-ref-map.mjs";
import { ghDownload, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const CARRY_ARTIFACT = "pr-merge-run-cache";
export const CARRY_FILE = "pr-merge-carried.json";

// GitHub's default artifact retention; pr-verify.yml sets none.
export const RETENTION_DAYS = 90;
const WORKFLOW_PATH = ".github/workflows/pr-verify.yml";
const SHA = /^[0-9a-f]{40}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const ZONED = /(Z|[+-]\d\d:\d\d)$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

function dated(entry, now) {
  if (!isObject(entry) || typeof entry.at !== "string" || !ZONED.test(entry.at)) return false;
  const age = now - Date.parse(entry.at);
  return age >= 0 && age <= RETENTION_DAYS * 86_400_000;
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

// A run record with each repository kept as its name.
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

// The sections of `data` kept for the next run, each entry as saved.
export function carry(data, { repo, branch, now }) {
  const out = { "carried-run-record": {}, "carried-fail-head-ref": {}, "carried-on-branch": {} };
  if (!isObject(data)) return out;
  const take = (from, to, keep, shape = (value) => value) => {
    if (!isObject(data[from])) return;
    for (const [key, entry] of Object.entries(data[from])) {
      if (dated(entry, now) && keep(key, entry.value)) out[to][key] = { at: entry.at, value: shape(entry.value) };
    }
  };
  // Each section is kept from this run's reads and from what it carried in.
  for (const from of ["carried-run-record", "run-record"]) {
    take(from, "carried-run-record", (k, v) => originRecord(k, v, repo, branch), slimRecord);
  }
  for (const from of ["carried-fail-head-ref", "fail-head-ref"]) {
    take(from, "carried-fail-head-ref", (k, v) => headRef(k, v, repo));
  }
  for (const from of ["carried-on-branch", "on-branch"]) {
    take(from, "carried-on-branch", (k, v) => onBranch(k, v, repo, branch));
  }
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
    writeFileSync(`${to}.tmp`, JSON.stringify(kept));
    renameSync(`${to}.tmp`, to);
    if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, "carried=true\n");
    console.log(Object.entries(kept).map(([section, entries]) => `${section}=${Object.keys(entries).length}`).join(" "));
  } catch (error) {
    console.log(`::warning::the run cache was not carried: ${escapeCommand(error.message)}`);
  }
}

// `read`: the newest trusted run's file, written as it is to CARRY_TO.
export async function read({ env = process.env, actions: client, download } = {}) {
  const { CARRY_TO: to, GITHUB_REPOSITORY: repo = "" } = env;
  try {
    if (to) rmSync(to, { force: true });
    if (!to || !REPO.test(repo)) throw new Error("CARRY_TO and GITHUB_REPOSITORY are required");
    client ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: CARRY_ARTIFACT, file: CARRY_FILE });
    const actions = sharedReads(client, env.PR_MERGE_READS_PATH);
    const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
    const id = await newestTrustedRun({ repo, runId: String(env.GITHUB_RUN_ID), actions, name: CARRY_ARTIFACT, accept });
    if (id === undefined) {
      console.log("no earlier run cache to carry");
      return;
    }
    const text = download(id);
    if (!isObject(JSON.parse(text))) throw new Error(`the run cache of run ${id} is not a JSON object`);
    writeFileSync(`${to}.tmp`, text);
    renameSync(`${to}.tmp`, to);
    console.log(`run cache of run ${id}`);
  } catch (error) {
    console.log(`::warning::the run cache was not carried: ${escapeCommand(error?.message ?? error)}`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  if (process.argv[2] === "read") await read();
  else main();
}
