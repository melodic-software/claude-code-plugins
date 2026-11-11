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
// gets a longer gate the next run. Only a scheduled or hand-started sweep of
// pr-merge.yml on main counts (trustedRun); a pull_request_target run runs the PR base
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
import { closeSync, mkdtempSync, openSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

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

// The run name pr-merge.yml gives a PR-scoped dispatch (`run-name`, from
// inputs.pr); the capture is the input as given.
export const WAKE_TITLE = /^pr-merge: arm #(.*)$/s;

// A scheduled or hand-started run of main's copy of pr-merge.yml, or of the
// workflow at `path`. A PR-scoped dispatch (WAKE_TITLE) reads and arms one
// pull request, so its kept files do not stand for a sweep's.
export function trustedRun(run, path = WORKFLOW_PATH) {
  return (
    run?.path === path &&
    (run.event === "schedule" || (run.event === "workflow_dispatch" && !WAKE_TITLE.test(String(run.display_title ?? "")))) &&
    run.head_branch === "main"
  );
}

const API_BUDGET_LIB = fileURLToPath(new URL("../../actions/log-api-budget/api-budget.bash", import.meta.url));

// `gh <args>` with `token`, through api-budget.bash's gh wrapper: each request
// it sends counts in the job-end api-calls notice under API_BUDGET_TOKEN, and
// the rate guard refuses it while a stop holds. Plain gh when that file cannot
// be read. The wrapper keeps the stderr it starts with as its error copy, so
// only the source line's stderr is silenced.
export function countedGh(args, { token, env = process.env, stdout = "ignore", timeout } = {}) {
  execFileSync("bash", ["-c", '. "$0" 2>/dev/null && api_budget_wrap_gh "${API_BUDGET_TOKEN:-}"; gh "$@"', API_BUDGET_LIB, ...args], {
    env: { ...env, GH_TOKEN: token },
    stdio: ["ignore", stdout, "inherit"],
    ...(timeout !== undefined && { timeout, killSignal: "SIGKILL" }),
  });
}

// A run's artifact `name`, downloaded once per run id, as the text of `file`
// (another file of the same artifact when the caller names one). With
// `shared` (PR_MERGE_READS_PATH), the artifact id comes from the run's whole
// artifact listing a reader already saved there (artifactsNamed), so the
// archive is one request (ghDownloadArtifact); with no such listing, or no
// unexpired artifact named `name` in it, `gh run download` lists and fetches.
export function ghDownload({ repo, token, dir, name = CURSOR_ARTIFACT, file = "cursor.json", env, shared }) {
  const targets = new Map();
  const byId = ghDownloadArtifact({ repo, token, dir, name, file, env });
  return (runId, other = file) => {
    const artifactId = listedArtifactId({ repo, runId, name, shared });
    if (artifactId !== undefined) {
      return byId(artifactId, other);
    }
    if (!targets.has(String(runId))) {
      const target = mkdtempSync(join(dir, `${name}-`));
      countedGh(["run", "download", String(runId), "-R", repo, "-n", name, "-D", target], { token, env });
      targets.set(String(runId), target);
    }
    return readFileSync(join(targets.get(String(runId)), other), "utf8");
  };
}

// The newest (highest id) unexpired artifact named `name` in run `runId`'s
// whole artifact listing as saved in the file at `shared`, or undefined when
// the file holds no complete listing for the run, or none such in it.
function listedArtifactId({ repo, runId, name, shared }) {
  if (!shared) return undefined;
  let saved;
  try {
    saved = JSON.parse(readFileSync(shared, "utf8"));
  } catch {
    return undefined;
  }
  const all = isObject(saved) ? saved[`/repos/${repo}/actions/runs/${runId}/artifacts?per_page=100`] : undefined;
  if (!Array.isArray(all?.artifacts) || !Number.isInteger(all.total_count) || all.total_count > all.artifacts.length) {
    return undefined;
  }
  const ids = all.artifacts.filter((a) => a?.name === name && a.expired === false && Number.isSafeInteger(a.id)).map((a) => a.id);
  return ids.length > 0 ? Math.max(...ids) : undefined;
}

// An artifact's file `file` (another file of it when the caller names one),
// fetched once per artifact id from its archive endpoint. Unlike `gh run
// download -n`, it lists none of the run's artifacts again, so a caller that
// already holds the id spends one request, not two. `timeout` (ms) caps the
// fetch and the unzip each, killing either past it.
export function ghDownloadArtifact({ repo, token, dir, name, file, env, timeout }) {
  const archives = new Map();
  return (artifactId, other = file) => {
    const key = String(artifactId);
    if (!archives.has(key)) {
      const archive = join(mkdtempSync(join(dir, `${name}-`)), "artifact.zip");
      const fd = openSync(archive, "w");
      try {
        countedGh(["api", `repos/${repo}/actions/artifacts/${key}/zip`], { token, env, stdout: fd, timeout });
      } finally {
        closeSync(fd);
      }
      archives.set(key, archive);
    }
    try {
      // Extracted beside the archive and read from disk: a piped `unzip -p`
      // fails with ENOBUFS once the file passes execFileSync's 1 MiB default
      // maxBuffer.
      const out = join(dirname(archives.get(key)), "extracted");
      execFileSync("unzip", ["-q", "-o", "-d", out, archives.get(key), other], { stdio: ["ignore", "ignore", "pipe"], ...(timeout !== undefined && { timeout, killSignal: "SIGKILL" }) });
      return readFileSync(join(out, other), "utf8");
    } catch (error) {
      // unzip's exit 11 is "no matching files": the artifact lacks the file,
      // raised as reading an extracted copy (ghDownload's other path) would.
      if (error?.status === 11) {
        throw Object.assign(new Error(`ENOENT: no such file or directory, open '${other}' (artifact ${key})`), { code: "ENOENT", syscall: "open", path: other });
      }
      throw error;
    }
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

const runOrder = (run) => (Number.isSafeInteger(run?.id) ? run.id : -1);

// The id of the newest trusted run of `workflow` (pr-merge.yml unless named),
// this one aside, holding an unexpired artifact named `name` and passing
// `accept`, or undefined when there is none.
export async function newestTrustedRun(options) {
  return (await newestTrustedArtifact(options))?.runId;
}

// newestTrustedRun's run as {runId, artifactId}: artifactId is the newest
// (highest id) unexpired artifact named `name` from the listing already read,
// undefined when that listing gives it no id. `trusted` picks the runs asked
// (trustedRun by default).
// `event`, when set, lists only that event's runs, so a reader that trusts one
// event does not page past the others.
export async function newestTrustedArtifact({ repo, runId, actions, name, accept = async () => true, workflow = WORKFLOW_PATH, trusted = (run) => trustedRun(run, workflow), event }) {
  const file = workflow.slice(workflow.lastIndexOf("/") + 1);
  const only = event === undefined ? "" : `&event=${event}`;
  let asked = 0;
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const listing = await actions(
      "GET",
      `/repos/${repo}/actions/workflows/${file}/runs?branch=main${only}&exclude_pull_requests=true&per_page=100&page=${page}`,
    );
    if (!Array.isArray(listing?.workflow_runs)) {
      throw new Error(`the ${file.replace(/\.yml$/, "")} run listing has an unexpected shape`);
    }
    // Newest first by id, not the API's order, which follows created_at: on
    // 2026-11-01 runs created 08:00-09:00Z were stamped an hour ahead and
    // listed above later runs, so a carry came from a run an hour older.
    const runs = [...listing.workflow_runs].sort((a, b) => runOrder(b) - runOrder(a));
    for (const run of runs) {
      if (!trusted(run) || String(run.id) === runId) {
        continue;
      }
      if (asked === MAX_RUNS) {
        return undefined;
      }
      asked += 1;
      const live = (await artifactsNamed({ repo, actions, runId: run.id, name })).filter((a) => a?.expired === false);
      if (live.length > 0 && (await accept(run))) {
        const newest = live.reduce((a, b) => (runOrder(b) > runOrder(a) ? b : a));
        return { runId: run.id, artifactId: Number.isSafeInteger(newest?.id) ? newest.id : undefined };
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
    download ??= ghDownload({ repo, token: env.ACTIONS_TOKEN, dir: env.RUNNER_TEMP, shared: env.PR_MERGE_READS_PATH });
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
