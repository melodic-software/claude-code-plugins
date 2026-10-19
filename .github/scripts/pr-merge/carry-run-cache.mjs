#!/usr/bin/env node
// carry-run-cache.mjs: copies the reads in one pr-merge run cache
// (babysit_run_cache.py) that can never change into a file the next run starts
// from. pr-merge.yml runs it twice: after the gate, from this run's cache into
// the file it saves with actions/cache; and before the gate, from the restored
// file into this run's empty cache. Every entry is checked again on each pass.
//
// Kept, each read only on a FAIL's path, where a value can only count the
// FAIL (babysit_verify_evidence.py):
//   run-record        a pr-verify run's record, only when it names a run of
//                     pr-verify.yml on the branch of this repository (origin);
//                     these fields never change for a run id, and a record
//                     that would turn a FAIL away is never carried
//   fail-head-ref     the head ref an untied FAIL's verdict.json records, by
//                     artifact id; an id names contents that never change
//   on-branch         a run head found on the branch (main forbids force
//                     pushes), carried as carried-on-branch, which a PASS's
//                     run never reads
// Everything else is dropped: a read bounded by MAX_AGE, keyed by
// credentials, or a sweep stamp can change between runs. So is an entry dated
// in the future or more than RETENTION_DAYS ago, past the artifact retention
// that makes it unreachable. Any failure writes nothing and warns, so the run
// reads GitHub as before.
//
// Environment:
//   CARRY_FROM          the cache file to read (missing: nothing carried)
//   CARRY_TO            the file to write
//   GITHUB_REPOSITORY   owner/repo
//   CARRY_BRANCH        the branch the verdicts are judged on (main)
//   GITHUB_OUTPUT       gets carried=true once CARRY_TO is written
import { appendFileSync, existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

// GitHub's default artifact retention; pr-verify.yml sets none.
export const RETENTION_DAYS = 90;
const WORKFLOW_PATH = ".github/workflows/pr-verify.yml";
const SHA = /^[0-9a-f]{40}$/;
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
  const out = { "run-record": {}, "fail-head-ref": {}, "carried-on-branch": {} };
  if (!isObject(data)) return out;
  const take = (from, to, keep) => {
    if (!isObject(data[from])) return;
    for (const [key, entry] of Object.entries(data[from])) {
      if (dated(entry, now) && keep(key, entry.value)) out[to][key] = { at: entry.at, value: entry.value };
    }
  };
  take("run-record", "run-record", (k, v) => originRecord(k, v, repo, branch));
  take("fail-head-ref", "fail-head-ref", (k, v) => headRef(k, v, repo));
  for (const from of ["carried-on-branch", "on-branch"]) {
    take(from, "carried-on-branch", (k, v) => onBranch(k, v, repo, branch));
  }
  return out;
}

export function main(env = process.env, now = Date.now()) {
  const { CARRY_FROM: from, CARRY_TO: to, GITHUB_REPOSITORY: repo, CARRY_BRANCH: branch = "main" } = env;
  try {
    if (!from || !to || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? "")) {
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

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) main();
