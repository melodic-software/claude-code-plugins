#!/usr/bin/env node
// listing-carry.mjs: hands the verdict reader the repository artifact listing
// the last run saved (babysit_verify_evidence.py BABYSIT_VERIFY_LISTING_CARRY),
// so it lists only the artifacts uploaded since (`Reader._incremental`)
// instead of every page.
//
// The file is the newest scheduled or hand-started run of main's pr-merge.yml
// (rotation.mjs `newestTrustedRun`), this run aside, holding the
// pr-merge-verify-listing artifact, and only when its head commit is on main
// (head-ref-map.mjs `onMain`), as the head-ref map and the carried run cache
// are read. Only a run's own steps can upload its artifacts, so the file was
// written by main's pr-merge.yml; it never goes through actions/cache, which
// any job in main's cache scope can write. Any file already at
// BABYSIT_VERIFY_LISTING_CARRY is removed first, so one left there is never
// read. The reader checks the file itself, and keeps a listing built on it
// only when it holds exactly the live artifact count GitHub reports;
// otherwise it lists every page.
//
// Any failure writes nothing and warns: the reader then lists every page.
//
// Environment:
//   ACTIONS_TOKEN                  the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY              owner/repo
//   GITHUB_RUN_ID                  this run, which has no listing yet
//   RUNNER_TEMP                    where the artifact is downloaded
//   PR_MERGE_READS_PATH            the job's shared GET answers
//                                  (rotation.mjs sharedReads), if set
//   PR_MERGE_MAIN_TIP              main's tip (head-ref-map.mjs onMain), if set
//   BABYSIT_VERIFY_LISTING_CARRY   the file to write
//   GITHUB_API_URL
import { renameSync, rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { onMain } from "./head-ref-map.mjs";
import { ghDownload, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const LISTING_ARTIFACT = "pr-merge-verify-listing";
export const LISTING_FILE = "verify-listing.json";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

// The newest trusted run's saved listing and its run id, or undefined when no
// run has one; an error for a file of another shape.
export async function readListing({ repo, runId, actions: client, download, shared }) {
  const actions = sharedReads(client, shared);
  const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
  const id = await newestTrustedRun({ repo, runId, actions, name: LISTING_ARTIFACT, accept });
  if (id === undefined) {
    return undefined;
  }
  const text = download(id);
  const data = JSON.parse(text);
  if (!isObject(data) || typeof data.fetchedAt !== "string" || !Array.isArray(data.artifacts)) {
    throw new Error(`the artifact listing of run ${id} has an unexpected shape`);
  }
  return { run: id, text, count: data.artifacts.length };
}

export async function main({ env = process.env, actions, download } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  const path = env.BABYSIT_VERIFY_LISTING_CARRY;
  try {
    if (!path) throw new Error("BABYSIT_VERIFY_LISTING_CARRY is not set");
    rmSync(path, { force: true });
    if (!REPO.test(repo)) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: LISTING_ARTIFACT, file: LISTING_FILE });
    const found = await readListing({ repo, runId: String(env.GITHUB_RUN_ID), actions, download, shared: env.PR_MERGE_READS_PATH });
    if (found === undefined) {
      console.log("no earlier artifact listing; the verdict reader lists every page");
      return 0;
    }
    writeFileSync(`${path}.tmp`, found.text);
    renameSync(`${path}.tmp`, path);
    console.log(`artifact listing of run ${found.run}: ${found.count} artifacts`);
  } catch (error) {
    console.log(`::warning title=artifact listing::${escapeCommand(error?.message ?? error)}; the verdict reader lists every page`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
