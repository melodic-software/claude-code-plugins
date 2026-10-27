#!/usr/bin/env node
// last-report.mjs: the post-merge report the last pr-merge tick kept (its
// post-merge-dispatch job's pr-merge-post-merge-report artifact), which this
// tick's post-merge-dispatch job reuses in place of its own check while
// nothing the check reads has moved (babysit_verify_evidence.py settle
// --idle-tick). Found as the lane records are (lane-records.mjs): the newest
// scheduled or hand-started run of main's pr-merge.yml, this run aside,
// holding the artifact unexpired (rotation.mjs `newestTrustedRun`), whose head
// commit is on main (`onMain`). Only a run's own steps upload its artifacts,
// so the files were written by main's pr-merge.yml. Any failure leaves no
// report and warns: the check then runs.
//
// Environment:
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY    owner/repo
//   GITHUB_RUN_ID        this run, whose report is not written yet
//   PR_MERGE_READS_PATH  the job's shared GET answers (rotation.mjs sharedReads), if set
//   GITHUB_API_URL
//   LAST_REPORT_DIR      where the report's files are written
import { execFileSync } from "node:child_process";
import { renameSync, rmSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { onMain } from "./head-ref-map.mjs";
import { newestTrustedRun, sharedReads } from "./rotation.mjs";

export const REPORT_ARTIFACT = "pr-merge-post-merge-report";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

export async function main({ env = process.env, actions, download } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  const dir = env.LAST_REPORT_DIR;
  try {
    if (!dir) throw new Error("LAST_REPORT_DIR is not set");
    // A report left in its place before this step is never read as one.
    rmSync(dir, { recursive: true, force: true });
    if (!REPO.test(repo)) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    actions = sharedReads(
      actions ?? createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined }),
      env.PR_MERGE_READS_PATH,
    );
    download ??= (id, target) =>
      execFileSync("gh", ["run", "download", String(id), "-R", repo, "-n", REPORT_ARTIFACT, "-D", target], {
        env: { ...process.env, GH_TOKEN: env.ACTIONS_TOKEN },
        stdio: ["ignore", "ignore", "inherit"],
      });
    const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
    const id = await newestTrustedRun({ repo, runId: String(env.GITHUB_RUN_ID), actions, name: REPORT_ARTIFACT, accept });
    if (id === undefined) {
      console.log("no earlier post-merge report; the post-merge check runs");
      return 0;
    }
    // Downloaded beside its place and moved in whole, so a failed download
    // leaves no report.
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
