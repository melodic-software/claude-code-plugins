#!/usr/bin/env node
import { existsSync, readFileSync, rmSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { onMain, writeAtomic } from "./head-ref-map.mjs";
import { escapeCommand, ghDownload, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const RECORDS_ARTIFACT = "pr-merge-lane-records";
export const RECORDS_FILE = "lane-records.json";
const VERSION = 1;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const NAME = /^pr-merge-(?:dispatched-[1-9][0-9]{0,15}|rerun-[1-9][0-9]{0,15}-attempt-2)$/;
const ZONED = /(Z|[+-]\d\d:\d\d)$/;

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const dated = (value) => typeof value === "string" && ZONED.test(value) && !Number.isNaN(Date.parse(value));

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

export async function readRecords({ repo, runId, actions: client, download, shared }) {
  const actions = sharedReads(client, shared);
  const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
  const id = await newestTrustedRun({ repo, runId, actions, name: RECORDS_ARTIFACT, accept });
  return id === undefined ? undefined : { run: id, records: parseRecords(download(id), repo) };
}

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
    if (mode === "read" && env.LANE_RECORDS_PATH) rmSync(env.LANE_RECORDS_PATH, { force: true });
    if (!REPO.test(repo)) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    if (mode === "read") {
      actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
      download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: RECORDS_ARTIFACT, file: RECORDS_FILE, shared: env.PR_MERGE_READS_PATH });
      const found = await readRecords({ repo, runId: String(env.GITHUB_RUN_ID), actions, download, shared: env.PR_MERGE_READS_PATH });
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
