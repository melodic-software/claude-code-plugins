#!/usr/bin/env node
// lane-records.mjs: keeps, from one pr-merge run to the next, the
// pr-merge-dispatched-<id> and pr-merge-rerun-<id>-attempt-2 records the
// post-merge check proved (babysit_postmerge.py `_lane_record`), so it does
// not list each record and read the run that uploaded it on every run. A
// record that is present stays present: the run that uploaded it, its event,
// branch and head commit never change, and main forbids force pushes.
//
// Each record answered from here can let a merge verify (a lane dispatch
// covering it, or the lane's own re-run turning a red attempt 1 into a
// flake), so it is read only the way the head-ref map is (head-ref-map.mjs):
// `read`, before each post-merge check, takes the file from the newest
// scheduled or hand-started run of main's pr-merge.yml, this run aside,
// holding the pr-merge-lane-records artifact (rotation.mjs `trustedRun`),
// and only when that run's head commit is on main (`onMain`). Only a run's
// own steps can upload its artifacts, so the file was written by main's
// pr-merge.yml; it never goes through actions/cache. The check still runs
// its sender rule over the sender fields the file stores for each record
// before using it; only the head commit's ancestry is read live.
//
// `write`, after the gate: the file the checks of this job rewrote (the
// records they read in and the final ones they proved, created at or after
// their floor), each kept while unexpired and, when the run saved an artifact
// listing, while it lists its artifact id unexpired, written to
// LANE_RECORDS_OUT for actions/upload-artifact. With no listing file (no
// candidates, or a listing the run could not read), unexpired records are
// carried as they are and pruned on the next run that saves a listing: the
// listing only prunes, and is no trust check.
//
// The file is `{"version": 1, "repo": "<owner/repo>", "records": {"<record
// name>": {"created_at", "artifact", "expires_at", "sender"}}}`. A file of
// any other shape is no file. Any failure writes nothing and warns: the
// check then reads every record, which costs requests, never a decision.
//
// A listing file that exists but cannot be parsed writes nothing, and the
// next run reads an older file.
//
// Environment:
//   ACTIONS_TOKEN             read: the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY         owner/repo
//   GITHUB_RUN_ID             read: this run, which has no file yet
//   RUNNER_TEMP               read: where the artifact is downloaded
//   GITHUB_API_URL
//   LANE_RECORDS_PATH         the file the checks read and rewrite
//   BABYSIT_VERIFY_LISTING    write: the run's saved artifact listing, if any
//   LANE_RECORDS_OUT          write: the file to upload
import { existsSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { onMain } from "./head-ref-map.mjs";
import { ghDownload, newestTrustedRun } from "./rotation.mjs";

export const RECORDS_ARTIFACT = "pr-merge-lane-records";
export const RECORDS_FILE = "lane-records.json";
const VERSION = 1;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
// babysit_postmerge.py `_LANE_RECORD_NAME`.
const NAME = /^pr-merge-(?:dispatched-[1-9][0-9]{0,15}|rerun-[1-9][0-9]{0,15}-attempt-2)$/;
const ZONED = /(Z|[+-]\d\d:\d\d)$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const dated = (value) => typeof value === "string" && ZONED.test(value) && !Number.isNaN(Date.parse(value));

// The file's records, by name, or an error for any other shape; the check
// (babysit_postmerge.py `load_lane_records`) applies the same rules and more.
export function parseRecords(text, repo) {
  const data = JSON.parse(text);
  if (!isObject(data) || data.version !== VERSION || data.repo !== repo || !isObject(data.records)) {
    throw new Error("the lane records file has an unexpected shape");
  }
  for (const [name, entry] of Object.entries(data.records)) {
    if (
      !NAME.test(name) ||
      !isObject(entry) ||
      !dated(entry.created_at) ||
      !dated(entry.expires_at) ||
      !Number.isSafeInteger(entry.artifact) ||
      entry.artifact <= 0 ||
      !isObject(entry.sender) ||
      !Number.isSafeInteger(entry.sender.id) ||
      entry.sender.status !== "completed"
    ) {
      throw new Error(`the lane records file holds ${name}, an entry of another shape`);
    }
  }
  return data.records;
}

const serialize = (repo, records) => JSON.stringify({ version: VERSION, repo, records });

function writeAtomic(path, text) {
  writeFileSync(`${path}.tmp`, text);
  renameSync(`${path}.tmp`, path);
}

// The newest trusted run's records, by name, or undefined when no run has any.
export async function readRecords({ repo, runId, actions, download }) {
  const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
  const id = await newestTrustedRun({ repo, runId, actions, name: RECORDS_ARTIFACT, accept });
  return id === undefined ? undefined : { run: id, records: parseRecords(download(id), repo) };
}

// The next run's records: those unexpired at `now` whose artifact `listing`
// lists unexpired, under the record's name, uploaded by its sender run. With
// no listing, expiry alone: the check kept each record only once its artifact
// was listed unexpired (babysit_postmerge.py `_prove`).
export function nextRecords({ records, listing, now }) {
  const listed =
    listing &&
    new Map(
      (Array.isArray(listing.artifacts) ? listing.artifacts : [])
        .filter((a) => a?.expired === false && Number.isSafeInteger(a.id))
        .map((a) => [a.id, a]),
    );
  return Object.fromEntries(
    Object.entries(records).filter(([name, entry]) => {
      if (!(Date.parse(entry.expires_at) > now)) return false;
      if (!listed) return true;
      const artifact = listed.get(entry.artifact);
      return artifact?.name === name && artifact.workflow_run?.id === entry.sender.id;
    }),
  );
}

export async function main({ mode = process.argv[2], env = process.env, actions, download, now = Date.now() } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  try {
    // A file left in its place before this step is never read as one.
    if (mode === "read" && env.LANE_RECORDS_PATH) rmSync(env.LANE_RECORDS_PATH, { force: true });
    if (!REPO.test(repo)) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    if (mode === "read") {
      actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
      download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: RECORDS_ARTIFACT, file: RECORDS_FILE });
      const found = await readRecords({ repo, runId: String(env.GITHUB_RUN_ID), actions, download });
      if (found === undefined) {
        console.log("no earlier lane records; the post-merge check reads each record");
        return 0;
      }
      writeAtomic(env.LANE_RECORDS_PATH, serialize(repo, found.records));
      console.log(`lane records of run ${found.run}: ${Object.keys(found.records).length}`);
    } else if (mode === "write") {
      if (!env.LANE_RECORDS_PATH || !existsSync(env.LANE_RECORDS_PATH)) {
        console.log("no lane records to keep");
        return 0;
      }
      const records = parseRecords(readFileSync(env.LANE_RECORDS_PATH, "utf8"), repo);
      let listing;
      if (existsSync(env.BABYSIT_VERIFY_LISTING ?? "")) {
        listing = JSON.parse(readFileSync(env.BABYSIT_VERIFY_LISTING, "utf8"));
        if (!Array.isArray(listing?.artifacts)) throw new Error("the saved artifact listing has an unexpected shape");
      } else {
        console.log("no saved artifact listing; lane records are kept by expiry alone");
      }
      const kept = nextRecords({ records, listing, now });
      writeAtomic(env.LANE_RECORDS_OUT, serialize(repo, kept));
      console.log(`lane records for the next run: ${Object.keys(kept).length}`);
    } else {
      throw new Error("the mode is read or write");
    }
  } catch (error) {
    console.log(`::warning title=lane records::${escapeCommand(error?.message ?? error)}; the post-merge check reads each record`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
