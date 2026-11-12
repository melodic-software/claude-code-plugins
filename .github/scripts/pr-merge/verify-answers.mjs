#!/usr/bin/env node
// verify-answers.mjs: hands enable-auto-merge the skip records (SKIP_FILE,
// enable-auto-merge.mjs SKIPPABLE) the last reader run kept, which it checks
// itself; a skip only repeats a refusal.
//
// Before the arm step: the newest scheduled or hand-started run of
// main's pr-merge.yml (rotation.mjs `newestTrustedRun`), this run aside,
// holding the pr-merge-verify-answers artifact, and only when its head commit
// is on main (head-ref-map.mjs `onMain`), as the head-ref map and the carried
// run cache are read. Only a run's own steps can upload its artifacts, so the
// file was written by main's pr-merge.yml; it never goes through
// actions/cache, which any job in main's cache scope can write. Any file
// already at EAM_SKIP_PATH is removed first, so one left there is never read.
//
// Any failure writes nothing and warns: each pull request is then read.
//
// Environment:
//   ACTIONS_TOKEN         the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY     owner/repo
//   GITHUB_RUN_ID         this run, which has no records yet
//   RUNNER_TEMP           where the artifact is downloaded
//   PR_MERGE_READS_PATH   the job's shared GET answers (rotation.mjs
//                         sharedReads), if set
//   EAM_SKIP_PATH         the file to write
//   GITHUB_API_URL
import { renameSync, rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { onMain } from "./head-ref-map.mjs";
import { escapeCommand, ghDownload, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const ANSWERS_ARTIFACT = "pr-merge-verify-answers";
export const SKIP_FILE = "eam-skip.json";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

// The newest trusted run holding the artifact, or undefined.
export async function skipsRun({ repo, runId, actions: client, shared }) {
  const actions = sharedReads(client, shared);
  const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
  return newestTrustedRun({ repo, runId, actions, name: ANSWERS_ARTIFACT, accept });
}

export async function main({ env = process.env, actions, download } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  try {
    if (!REPO.test(repo)) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    if (!env.EAM_SKIP_PATH) throw new Error("EAM_SKIP_PATH is not set");
    rmSync(env.EAM_SKIP_PATH, { force: true });
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: ANSWERS_ARTIFACT, file: SKIP_FILE, shared: env.PR_MERGE_READS_PATH });
    const id = await skipsRun({ repo, runId: String(env.GITHUB_RUN_ID), actions, shared: env.PR_MERGE_READS_PATH });
    if (id === undefined) {
      console.log("no earlier skip records; each pull request is read");
      return 0;
    }
    let text;
    try {
      text = download(id, SKIP_FILE);
    } catch (error) {
      if (error?.code === "ENOENT" && error?.syscall === "open") {
        console.log(`run ${id} kept no skip records; each pull request is read`);
        return 0;
      }
      throw error;
    }
    writeFileSync(`${env.EAM_SKIP_PATH}.tmp`, text);
    renameSync(`${env.EAM_SKIP_PATH}.tmp`, env.EAM_SKIP_PATH);
    console.log(`skip records of run ${id}`);
  } catch (error) {
    console.log(`::warning title=skip records::${escapeCommand(error?.message ?? error)}; each pull request is read`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
