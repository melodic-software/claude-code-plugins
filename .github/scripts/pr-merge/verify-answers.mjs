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
// The same artifact holds enable-auto-merge's skip records (SKIP_FILE), read
// from the one download into EAM_SKIP_PATH; the arm step checks them itself,
// and a skip only repeats a refusal. A run without them writes none.
//
// Environment:
//   ACTIONS_TOKEN         the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY     owner/repo
//   GITHUB_RUN_ID         this run, which has no answers yet
//   RUNNER_TEMP           where the artifact is downloaded
//   PR_MERGE_READS_PATH   the job's shared GET answers (rotation.mjs
//                         sharedReads), if set
//   VERIFY_ANSWERS_PATH   the file to write
//   EAM_SKIP_PATH         where the skip records go, if set
//   GITHUB_API_URL
import { renameSync, rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { onMain } from "./head-ref-map.mjs";
import { ghDownload, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const ANSWERS_ARTIFACT = "pr-merge-verify-answers";
export const ANSWERS_FILE = "verify-answers.json";
export const SKIP_FILE = "eam-skip.json";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

// The newest trusted run holding the answers artifact, or undefined.
export async function answersRun({ repo, runId, actions: client, shared }) {
  const actions = sharedReads(client, shared);
  const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
  return newestTrustedRun({ repo, runId, actions, name: ANSWERS_ARTIFACT, accept });
}

// Run `id`'s answers file, as `{ run, text, count }`; undefined when the
// artifact holds none (a run whose reader read nothing), an error for a file
// that is not this repository's.
export function readAnswers({ repo, id, download }) {
  let text;
  try {
    text = download(id);
  } catch {
    return undefined;
  }
  const data = JSON.parse(text);
  if (!isObject(data) || data.repo !== repo || !isObject(data.entries)) {
    throw new Error(`the answers of run ${id} are not this repository's`);
  }
  return { run: id, text, count: Object.keys(data.entries).length };
}

const keep = (path, text) => {
  writeFileSync(`${path}.tmp`, text);
  renameSync(`${path}.tmp`, path);
};

export async function main({ env = process.env, actions, download } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  try {
    if (!REPO.test(repo)) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    if (!env.VERIFY_ANSWERS_PATH) throw new Error("VERIFY_ANSWERS_PATH is not set");
    rmSync(env.VERIFY_ANSWERS_PATH, { force: true });
    if (env.EAM_SKIP_PATH) rmSync(env.EAM_SKIP_PATH, { force: true });
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: ANSWERS_ARTIFACT, file: ANSWERS_FILE });
    const id = await answersRun({ repo, runId: String(env.GITHUB_RUN_ID), actions, shared: env.PR_MERGE_READS_PATH });
    if (id === undefined) {
      console.log("no earlier verifier answers; each pull request is read in full");
      return 0;
    }
    // The skip records first: a malformed answers file stops only the answers.
    if (env.EAM_SKIP_PATH) {
      try {
        keep(env.EAM_SKIP_PATH, download(id, SKIP_FILE));
      } catch {
        console.log(`run ${id} kept no skip records; each pull request is read`);
      }
    }
    const found = readAnswers({ repo, id, download });
    if (found === undefined) {
      console.log(`run ${id} kept no verifier answers; each pull request is read in full`);
      return 0;
    }
    keep(env.VERIFY_ANSWERS_PATH, found.text);
    console.log(`verifier answers of run ${found.run}: ${found.count} pull requests`);
  } catch (error) {
    console.log(`::warning title=verifier answers::${escapeCommand(error?.message ?? error)}; each pull request is read in full`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
