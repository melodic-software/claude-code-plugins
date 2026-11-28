#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { closeSync, mkdtempSync, openSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { PR_MERGE_TITLE } from "../lib/run-title.mjs";

export const CURSOR_ARTIFACT = "pr-merge-gate-cursor";
const WORKFLOW_PATH = ".github/workflows/pr-merge.yml";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const MAX_PAGES = 2;
const MAX_RUNS = 10;

export const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

export function rotate(candidates, last) {
  const sorted = [...candidates].sort((a, b) => a.number - b.number);
  const start = Number.isInteger(last) ? sorted.findIndex((c) => c.number > last) : -1;
  return start <= 0 ? sorted : [...sorted.slice(start), ...sorted.slice(0, start)];
}

export const WAKE_TITLE = PR_MERGE_TITLE;

export function trustedRun(run, path = WORKFLOW_PATH) {
  return (
    run?.path === path &&
    (run.event === "schedule" || (run.event === "workflow_dispatch" && !WAKE_TITLE.test(String(run.display_title ?? "")))) &&
    run.head_branch === "main"
  );
}

const API_BUDGET_LIB = fileURLToPath(new URL("../../actions/log-api-budget/api-budget.bash", import.meta.url));

export function countedGh(args, { token, env = process.env, stdout = "ignore", timeout } = {}) {
  execFileSync("bash", ["-c", '. "$0" 2>/dev/null && api_budget_wrap_gh "${API_BUDGET_TOKEN:-}"; gh "$@"', API_BUDGET_LIB, ...args], {
    env: { ...env, GH_TOKEN: token },
    stdio: ["ignore", stdout, "inherit"],
    ...(timeout !== undefined && { timeout, killSignal: "SIGKILL" }),
  });
}

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
      const out = join(dirname(archives.get(key)), "extracted");
      execFileSync("unzip", ["-q", "-o", "-d", out, archives.get(key), other], { stdio: ["ignore", "ignore", "pipe"], ...(timeout !== undefined && { timeout, killSignal: "SIGKILL" }) });
      return readFileSync(join(out, other), "utf8");
    } catch (error) {
      if (error?.status === 11) {
        throw Object.assign(new Error(`ENOENT: no such file or directory, open '${other}' (artifact ${key})`), { code: "ENOENT", syscall: "open", path: other });
      }
      throw error;
    }
  };
}

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

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

async function artifactsNamed({ repo, actions, runId, name }) {
  const all = await actions("GET", `/repos/${repo}/actions/runs/${runId}/artifacts?per_page=100`);
  if (Array.isArray(all?.artifacts) && Number.isInteger(all.total_count) && all.total_count <= all.artifacts.length) {
    return all.artifacts.filter((a) => a?.name === name);
  }
  const found = await actions("GET", `/repos/${repo}/actions/runs/${runId}/artifacts?name=${name}`);
  return Array.isArray(found?.artifacts) ? found.artifacts : [];
}

const runOrder = (run) => (Number.isSafeInteger(run?.id) ? run.id : -1);

export async function newestTrustedRun(options) {
  return (await newestTrustedArtifact(options))?.runId;
}

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
