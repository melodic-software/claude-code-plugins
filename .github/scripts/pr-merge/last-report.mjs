#!/usr/bin/env node
import { renameSync, rmSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { onMain } from "./head-ref-map.mjs";
import { countedGh, escapeCommand, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const REPORT_ARTIFACT = "pr-merge-post-merge-report";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

export async function main({ env = process.env, actions, download } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  const dir = env.LAST_REPORT_DIR;
  try {
    if (!dir) throw new Error("LAST_REPORT_DIR is not set");
    rmSync(dir, { recursive: true, force: true });
    if (!REPO.test(repo)) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    actions = sharedReads(
      actions ?? createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined }),
      env.PR_MERGE_READS_PATH,
    );
    download ??= (id, target) => countedGh(["run", "download", String(id), "-R", repo, "-n", REPORT_ARTIFACT, "-D", target], { token: env.ACTIONS_TOKEN, env });
    const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
    const id = await newestTrustedRun({ repo, runId: String(env.GITHUB_RUN_ID), actions, name: REPORT_ARTIFACT, accept });
    if (id === undefined) {
      console.log("no earlier post-merge report; the post-merge check runs");
      return 0;
    }
    const part = `${dir}.part`;
    rmSync(part, { recursive: true, force: true });
    download(id, part);
    renameSync(part, dir);
    console.log(`the post-merge report of run ${id}`);
  } catch (error) {
    console.log(`::warning title=last post-merge report::${escapeCommand(error?.message ?? error)}; the post-merge check runs`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
