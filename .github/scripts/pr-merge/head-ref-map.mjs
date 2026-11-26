#!/usr/bin/env node
import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { readDefaultBranchTip, requireBehindTip } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { escapeCommand, ghDownload, newestTrustedRun, sharedReads } from "./rotation.mjs";

export const MAP_ARTIFACT = "pr-merge-head-refs";
export const MAP_FILE = "head-refs.json";
const VERSION = 1;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const ID = /^[1-9][0-9]{0,15}$/;
const SHA = /^[0-9a-f]{40}$/;
const RECORD_SECTION = "fail-head-ref";

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

export function parseMap(text, repo) {
  const data = JSON.parse(text);
  if (!isObject(data) || data.version !== VERSION || data.repo !== repo || !isObject(data.head_refs)) {
    throw new Error("the head-ref map has an unexpected shape");
  }
  for (const [id, ref] of Object.entries(data.head_refs)) {
    if (!ID.test(id) || typeof ref !== "string") {
      throw new Error("the head-ref map holds an entry of another shape");
    }
  }
  return data.head_refs;
}

const serialize = (repo, refs) => JSON.stringify({ version: VERSION, repo, head_refs: refs });

export function writeAtomic(path, text) {
  writeFileSync(`${path}.tmp`, text);
  renameSync(`${path}.tmp`, path);
}

let mainTip;
export function forgetMainTip() {
  mainTip = undefined;
}

export async function onMain({ repo, actions, sha, env = process.env }) {
  if (!SHA.test(sha ?? "")) return false;
  const listed = env.PR_MERGE_MAIN_TIP ?? "";
  mainTip ??= SHA.test(listed) ? Promise.resolve(listed) : readDefaultBranchTip(actions, repo, "main", "off-main");
  try {
    await requireBehindTip(actions, repo, sha, await mainTip, "off-main");
    return true;
  } catch {
    return false;
  }
}

export async function readMap({ repo, runId, actions: client, download, shared }) {
  const actions = sharedReads(client, shared);
  const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
  const id = await newestTrustedRun({ repo, runId, actions, name: MAP_ARTIFACT, accept });
  return id === undefined ? undefined : { run: id, refs: parseMap(download(id), repo) };
}

export function nextMap({ previous = {}, runCache, listing, repo }) {
  const listed = new Set(
    (Array.isArray(listing?.artifacts) ? listing.artifacts : [])
      .filter((a) => a?.expired === false && Number.isSafeInteger(a.id) && a.id > 0)
      .map((a) => String(a.id)),
  );
  const refs = {};
  for (const [id, ref] of Object.entries(previous)) {
    if (listed.has(id)) refs[id] = ref;
  }
  const downloaded = isObject(runCache?.[RECORD_SECTION]) ? runCache[RECORD_SECTION] : {};
  for (const [key, entry] of Object.entries(downloaded)) {
    const id = key.slice(repo.length + 1);
    if (!key.startsWith(`${repo}|`) || !ID.test(id) || !listed.has(id) || !isObject(entry?.value)) continue;
    const ref = entry.value.head_ref;
    refs[id] = typeof ref === "string" ? ref : "";
  }
  return refs;
}

export async function main({ mode = process.argv[2], env = process.env, actions, download } = {}) {
  const repo = env.GITHUB_REPOSITORY ?? "";
  try {
    if (!REPO.test(repo)) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    if (mode === "read") {
      actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
      download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: MAP_ARTIFACT, file: MAP_FILE, shared: env.PR_MERGE_READS_PATH });
      const found = await readMap({ repo, runId: String(env.GITHUB_RUN_ID), actions, download, shared: env.PR_MERGE_READS_PATH });
      if (found === undefined) {
        console.log("no earlier head-ref map; the gate downloads each untied FAIL");
        return 0;
      }
      writeAtomic(env.HEAD_REFS_PATH, serialize(repo, found.refs));
      console.log(`head-ref map of run ${found.run}: ${Object.keys(found.refs).length} artifacts`);
    } else if (mode === "write") {
      let listing;
      if (existsSync(env.BABYSIT_VERIFY_LISTING ?? "")) {
        listing = JSON.parse(readFileSync(env.BABYSIT_VERIFY_LISTING, "utf8"));
        if (!Array.isArray(listing?.artifacts)) throw new Error("the saved artifact listing has an unexpected shape");
      }
      let previous;
      if (env.HEAD_REFS_PATH && existsSync(env.HEAD_REFS_PATH)) {
        try {
          previous = parseMap(readFileSync(env.HEAD_REFS_PATH, "utf8"), repo);
        } catch (error) {
          console.log(`::warning title=head-ref map::the map read before the gate is dropped: ${escapeCommand(error?.message ?? error)}`);
        }
      }
      if (listing === undefined && previous === undefined) {
        console.log("no saved artifact listing and no head-ref map to carry");
        return 0;
      }
      if (listing === undefined) {
        writeAtomic(env.HEAD_REFS_OUT, serialize(repo, previous));
        console.log(`no saved artifact listing; the head-ref map is carried as it is: ${Object.keys(previous).length} artifacts`);
        return 0;
      }
      const runCache = existsSync(env.BABYSIT_RUN_CACHE ?? "") ? JSON.parse(readFileSync(env.BABYSIT_RUN_CACHE, "utf8")) : {};
      const refs = nextMap({ previous, runCache, listing, repo });
      writeAtomic(env.HEAD_REFS_OUT, serialize(repo, refs));
      console.log(`head-ref map for the next run: ${Object.keys(refs).length} artifacts`);
    } else {
      throw new Error("the mode is read or write");
    }
  } catch (error) {
    console.log(`::warning title=head-ref map::${escapeCommand(error?.message ?? error)}; the gate downloads each untied FAIL`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
