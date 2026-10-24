#!/usr/bin/env node
// head-ref-map.mjs: keeps, from one pr-merge run to the next, the head ref each
// untied pr-verify FAIL's verdict.json records, by artifact id, so the gate
// ties or unties those FAILs without downloading them again
// (babysit_verify_evidence.py `_head_ref`). An id names contents that never
// change: an overwrite uploads a new id.
//
// `read`, before the gate: the newest scheduled or hand-started run of main's
// pr-merge.yml (rotation.mjs `trustedRun`), this run aside, holding the
// pr-merge-head-refs artifact; its map is checked and written to
// HEAD_REFS_PATH. Only a run's own steps can upload its artifacts, so that
// map was written by main's pr-merge.yml. A run's head_branch is a tag's name
// for a run on a tag, so a run counts only when its head commit is on main
// (`onMain`); a run that is not is passed over. The map never goes through
// actions/cache, which any job in main's cache scope can write.
//
// `write`, after the gate: that map's entries and the head refs this run
// downloaded (the run cache's fail-head-ref section, which only this run's
// gate writes: carry-run-cache.mjs restores carried-* sections alone), each
// kept only while the run's saved artifact listing lists its id unexpired,
// written to HEAD_REFS_OUT for actions/upload-artifact. With no listing file
// (no candidates, or a listing the run could not read) the map read before
// the gate is written as it is, and the next run that saves a listing prunes
// it; a listing file that cannot be parsed writes nothing, and the next run
// reads an older map.
//
// The map holds no verdict, only `{"version": 1, "repo": "<owner/repo>",
// "head_refs": {"<artifact id>": "<head ref>"}}`, "" for a verdict that records
// none. Any failure writes nothing and warns: the gate then downloads every
// untied FAIL, which costs requests, never a decision.
//
// Environment:
//   ACTIONS_TOKEN             read: the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY         owner/repo
//   GITHUB_RUN_ID             read: this run, which has no map yet
//   RUNNER_TEMP               read: where the artifact is downloaded
//   GITHUB_API_URL
//   HEAD_REFS_PATH            the map read before the gate
//   BABYSIT_RUN_CACHE         write: this run's cache (babysit_run_cache.py)
//   BABYSIT_VERIFY_LISTING    write: the run's saved artifact listing
//   HEAD_REFS_OUT             write: the map to upload
import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { ghDownload, newestTrustedRun } from "./rotation.mjs";

export const MAP_ARTIFACT = "pr-merge-head-refs";
export const MAP_FILE = "head-refs.json";
const VERSION = 1;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const ID = /^[1-9][0-9]{0,15}$/;
const SHA = /^[0-9a-f]{40}$/;
// babysit_verify_evidence.py RECORD_SECTION.
const RECORD_SECTION = "fail-head-ref";

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

// The map's head refs, by id, or an error for any other shape; the reader
// (babysit_verify_evidence.py `load_head_refs`) applies the same rules.
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

function writeAtomic(path, text) {
  writeFileSync(`${path}.tmp`, text);
  renameSync(`${path}.tmp`, path);
}

// Whether commit `sha` is main's head or an ancestor of it. The branch is
// named in full: a bare `main` would also match a tag named main.
export async function onMain({ repo, actions, sha }) {
  if (!SHA.test(sha ?? "")) return false;
  const compare = await actions("GET", `/repos/${repo}/compare/${sha}...refs/heads/main?per_page=1`);
  return compare?.status === "identical" || compare?.status === "ahead";
}

// The newest trusted run's map, by id, or undefined when no run has one.
export async function readMap({ repo, runId, actions, download }) {
  const accept = (run) => onMain({ repo, actions, sha: run.head_sha });
  const id = await newestTrustedRun({ repo, runId, actions, name: MAP_ARTIFACT, accept });
  return id === undefined ? undefined : { run: id, refs: parseMap(download(id), repo) };
}

// The next run's map: `previous` and this run's downloads (`runCache`), for
// ids `listing` lists unexpired.
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
      download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, name: MAP_ARTIFACT, file: MAP_FILE });
      const found = await readMap({ repo, runId: String(env.GITHUB_RUN_ID), actions, download });
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
      let refs = previous;
      if (listing !== undefined) {
        const runCache = existsSync(env.BABYSIT_RUN_CACHE ?? "") ? JSON.parse(readFileSync(env.BABYSIT_RUN_CACHE, "utf8")) : {};
        refs = nextMap({ previous, runCache, listing, repo });
      }
      writeAtomic(env.HEAD_REFS_OUT, serialize(repo, refs));
      const count = Object.keys(refs).length;
      console.log(listing === undefined ? `no saved artifact listing; the head-ref map is carried as it is: ${count} artifacts` : `head-ref map for the next run: ${count} artifacts`);
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
