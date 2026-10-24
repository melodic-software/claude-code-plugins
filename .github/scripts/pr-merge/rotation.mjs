#!/usr/bin/env node
// rotation.mjs: orders a pr-merge `merge` job's candidates so its gate loop
// starts after the last candidate the previous gate loop reached, wrapping
// round to the lowest PR number. Under merge.gate-budget-minutes a loop can
// stop before the end of the list; starting where the last one stopped means
// every candidate is reached across runs.
//
// The previous position is the `pr-merge-gate-cursor` artifact each gate loop
// uploads, `{"last": <PR number>}`, with `"deferred": <PR number>` when its
// read limit (merge.gate-candidate-minutes) stopped a candidate. A deferred
// candidate is gated first, marked `deferred` so its gate runs under the
// longer merge.gate-deferred-minutes: one that always passes the limit still
// gets a longer gate the next run. Only a scheduled or hand-started run of
// pr-merge.yml on main counts; a pull_request_target run runs the PR base
// branch's copy, so its cursor is not read. The newest such run holding a
// cursor wins, found from the workflow's own run list, never the repository's
// artifact list. The cursor sets only the order, never a verdict. Any failure
// leaves the listing order (ascending PR number) and warns.
//
// Environment:
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN (actions: read)
//   GITHUB_REPOSITORY    owner/repo
//   GITHUB_RUN_ID        this run, which has no cursor yet
//   CANDIDATES_PATH      candidates.json, rewritten in rotated order
//   RUNNER_TEMP          where the cursor artifact is downloaded
//   PR_MERGE_READS_PATH  the job's shared GET answers (sharedReads), if set
//   GITHUB_API_URL
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const CURSOR_ARTIFACT = "pr-merge-gate-cursor";
const WORKFLOW_PATH = ".github/workflows/pr-merge.yml";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
// Pages of main's runs listed, and trusted runs asked for a cursor, before
// giving up on finding one.
const MAX_PAGES = 2;
const MAX_RUNS = 10;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// Ascending by PR number, starting at the first number above `last`.
export function rotate(candidates, last) {
  const sorted = [...candidates].sort((a, b) => a.number - b.number);
  const start = Number.isInteger(last) ? sorted.findIndex((c) => c.number > last) : -1;
  return start <= 0 ? sorted : [...sorted.slice(start), ...sorted.slice(0, start)];
}

// A scheduled or hand-started run of main's copy of pr-merge.yml.
export function trustedRun(run) {
  return (
    run?.path === WORKFLOW_PATH &&
    (run.event === "schedule" || run.event === "workflow_dispatch") &&
    run.head_branch === "main"
  );
}

// `gh run download` of the artifact `name`'s file `file` from a run.
export function ghDownload({ repo, token, dir, name = CURSOR_ARTIFACT, file = "cursor.json" }) {
  return (runId) => {
    const target = mkdtempSync(join(dir, `${name}-`));
    execFileSync("gh", ["run", "download", String(runId), "-R", repo, "-n", name, "-D", target], {
      env: { ...process.env, GH_TOKEN: token },
      stdio: ["ignore", "ignore", "inherit"],
    });
    return readFileSync(join(target, file), "utf8");
  };
}

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

// `actions` with its GET answers shared through the file at `path`
// (PR_MERGE_READS_PATH, in the job's own RUNNER_TEMP, which only this job's
// steps write), so the readers of one job (the cursor, the head-ref map, the
// lane records) list main's runs, each run's artifacts and each compare once
// between them. An unreadable file shares nothing, and one that cannot be
// written only leaves the next reader to read GitHub; the answers never
// outlive the job.
export function sharedReads(actions, path) {
  if (!path) return actions;
  return async (method, url, ...rest) => {
    if (method !== "GET") return actions(method, url, ...rest);
    let saved = {};
    try {
      const data = JSON.parse(readFileSync(path, "utf8"));
      if (isObject(data)) saved = data;
    } catch {}
    if (Object.hasOwn(saved, url)) return saved[url];
    const value = await actions(method, url, ...rest);
    try {
      writeFileSync(`${path}.tmp`, JSON.stringify({ ...saved, [url]: value }));
      renameSync(`${path}.tmp`, path);
    } catch {}
    return value;
  };
}

// The run's artifacts named `name`, from one listing of all its artifacts
// that every reader shares, or by the name filter when that listing holds
// less than all of them.
async function artifactsNamed({ repo, actions, runId, name }) {
  const all = await actions("GET", `/repos/${repo}/actions/runs/${runId}/artifacts?per_page=100`);
  if (Array.isArray(all?.artifacts) && Number.isInteger(all.total_count) && all.total_count <= all.artifacts.length) {
    return all.artifacts.filter((a) => a?.name === name);
  }
  const found = await actions("GET", `/repos/${repo}/actions/runs/${runId}/artifacts?name=${name}`);
  return Array.isArray(found?.artifacts) ? found.artifacts : [];
}

// The id of the newest trusted run, this one aside, holding an unexpired
// artifact named `name` and passing `accept`, or undefined when there is none.
export async function newestTrustedRun({ repo, runId, actions, name, accept = async () => true }) {
  let asked = 0;
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const listing = await actions(
      "GET",
      `/repos/${repo}/actions/workflows/pr-merge.yml/runs?branch=main&exclude_pull_requests=true&per_page=100&page=${page}`,
    );
    if (!Array.isArray(listing?.workflow_runs)) {
      throw new Error("the pr-merge run listing has an unexpected shape");
    }
    // The API lists runs newest first.
    for (const run of listing.workflow_runs) {
      if (!trustedRun(run) || String(run.id) === runId) {
        continue;
      }
      if (asked === MAX_RUNS) {
        return undefined;
      }
      asked += 1;
      const found = await artifactsNamed({ repo, actions, runId: run.id, name });
      if (found.some((a) => a?.expired === false) && (await accept(run))) {
        return run.id;
      }
    }
    if (listing.workflow_runs.length < 100) {
      return undefined;
    }
  }
  return undefined;
}

// The newest trusted cursor, {last, deferred}, or undefined when there is none.
export async function readCursor({ repo, runId, actions, download, shared }) {
  const id = await newestTrustedRun({ repo, runId, actions: sharedReads(actions, shared), name: CURSOR_ARTIFACT });
  if (id === undefined) {
    return undefined;
  }
  const cursor = JSON.parse(download(id));
  const pr = (value) => Number.isInteger(value) && value >= 1;
  if (!pr(cursor?.last) || (cursor.deferred !== undefined && !pr(cursor.deferred))) {
    throw new Error(`the cursor of run ${id} is not a PR number`);
  }
  return { last: cursor.last, deferred: cursor.deferred };
}

export async function main({ env = process.env, actions, download } = {}) {
  try {
    const repo = env.GITHUB_REPOSITORY ?? "";
    if (!REPO.test(repo)) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const path = env.CANDIDATES_PATH;
    const candidates = JSON.parse(readFileSync(path, "utf8"));
    if (!Array.isArray(candidates) || !candidates.every((c) => Number.isInteger(c?.number))) {
      throw new Error("candidates.json is not a list of PRs");
    }
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP });
    const cursor = await readCursor({ repo, runId: String(env.GITHUB_RUN_ID), actions, download, shared: env.PR_MERGE_READS_PATH });
    const deferred = cursor?.deferred;
    const ordered = rotate(candidates, deferred === undefined ? cursor?.last : deferred - 1).map((c) =>
      c.number === deferred ? { ...c, deferred: true } : c,
    );
    writeFileSync(`${path}.tmp`, JSON.stringify(ordered));
    renameSync(`${path}.tmp`, path);
    const first = ordered[0]?.number;
    console.log(
      cursor === undefined
        ? "no earlier gate cursor; the gate starts at the lowest PR number"
        : `the last run's gate reached #${cursor.last}${deferred === undefined ? "" : ` and deferred #${deferred}`}; ` +
            `this run starts at ${first === undefined ? "no candidate" : `#${first}`}`,
    );
  } catch (error) {
    console.log(`::warning title=rotation::${escapeCommand(error?.message ?? error)}; the gate runs in listing order`);
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
