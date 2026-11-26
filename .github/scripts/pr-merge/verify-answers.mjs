#!/usr/bin/env node
import { renameSync, rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { onMain } from "./head-ref-map.mjs";
import { escapeCommand, ghDownload, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const ANSWERS_ARTIFACT = "pr-merge-verify-answers";
export const SKIP_FILE = "eam-skip.json";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

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
