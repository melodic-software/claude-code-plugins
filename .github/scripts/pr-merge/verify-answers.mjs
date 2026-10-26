#!/usr/bin/env node
// verify-answers.mjs: hands enable-auto-merge's verifier reader the answers
// the last run kept (babysit_verify_evidence.py --answers-in), so a refusal
// whose inputs have not moved can be compared with, or under
// merge.verify-cache serve stand in for, a full read.
//
// Before the arm step: the newest scheduled or hand-started run of
// main's pr-merge.yml (rotation.mjs `newestTrustedRun`), this run aside,
// holding the pr-merge-verify-answers artifact, and only when its head commit
// is on main (head-ref-map.mjs `onMain`), as the head-ref map and the carried
// run cache are read. Only a run's own steps can upload its artifacts, so the
// file was written by main's pr-merge.yml; it never goes through
// actions/cache, which any job in main's cache scope can write. Any file
// already at VERIFY_ANSWERS_PATH is removed first, so one left there is never
// read. The reader checks the file's version, repository and code itself and
// keeps an entry only for a refusal, so no file can make it allow.
//
// Any failure writes nothing and warns: the reader then reads in full.
//
// Environment:
//   ACTIONS_TOKEN         the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY     owner/repo
//   GITHUB_RUN_ID         this run, which has no answers yet
//   RUNNER_TEMP           where the artifact is downloaded
//   PR_MERGE_READS_PATH   the job's shared GET answers (rotation.mjs
//                         sharedReads), if set
//   VERIFY_ANSWERS_PATH   the file to write
//   GITHUB_API_URL
import { renameSync, rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { onMain } from "./head-ref-map.mjs";
import { ghDownload, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const ANSWERS_ARTIFACT = "pr-merge-verify-answers";
export const ANSWERS_FILE = "verify-answers.json";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

// The newest trusted run's answers file and its run id, or undefined when no
// run has one; an error for a file that is not this repository's.
export async function readAnswers({ repo, runId, actions: client, download, shared }) {
  const actions = sharedReads(client, shared);
  const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
  const id = await newestTrustedRun({ repo, runId, actions, name: ANSWERS_ARTIFACT, accept });
  if (id === undefined) {
    return undefined;
  }
  const text = download(id);
  const data = JSON.parse(text);
  if (!isObject(data) || data.repo !== repo || !isObject(data.entries)) {
    throw new Error(`the answers of run ${id} are not this repository's`);
  }
  return { run: id, text, count: Object.keys(data.entries).length };
}

export async function main({ env = process.env, actions, download } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  try {
    if (!REPO.test(repo)) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    if (!env.VERIFY_ANSWERS_PATH) throw new Error("VERIFY_ANSWERS_PATH is not set");
    rmSync(env.VERIFY_ANSWERS_PATH, { force: true });
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: ANSWERS_ARTIFACT, file: ANSWERS_FILE });
    const found = await readAnswers({ repo, runId: String(env.GITHUB_RUN_ID), actions, download, shared: env.PR_MERGE_READS_PATH });
    if (found === undefined) {
      console.log("no earlier verifier answers; each pull request is read in full");
      return 0;
    }
    writeFileSync(`${env.VERIFY_ANSWERS_PATH}.tmp`, found.text);
    renameSync(`${env.VERIFY_ANSWERS_PATH}.tmp`, env.VERIFY_ANSWERS_PATH);
    console.log(`verifier answers of run ${found.run}: ${found.count} pull requests`);
  } catch (error) {
    console.log(`::warning title=verifier answers::${escapeCommand(error?.message ?? error)}; each pull request is read in full`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
