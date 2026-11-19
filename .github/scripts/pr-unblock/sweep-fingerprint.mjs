import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";

import { zipEntry } from "../lib/lane-binding.mjs";
import { PR_UNBLOCK_TITLE } from "../lib/run-title.mjs";

export const FINGERPRINT_ARTIFACT = "pr-feedback-sweep-fingerprint";
export const FINGERPRINT_FILE = "pr-feedback-sweep-fingerprint.json";
export const FINGERPRINT_SCHEMA = 1;
export const FULL_REFRESH_MS = 2 * 3_600_000;
export const COMMENT_SKEW_MS = 60_000;
export const SWEEP_STATES_PAGE = 10;
export const SWEEP_STATES_QUERY = `query($owner: String!, $name: String!, $base: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: OPEN, baseRefName: $base, first: ${SWEEP_STATES_PAGE}, after: $after) {
      nodes {
        number headRefOid
        comments { totalCount }
        reviewThreads(first: 100) { totalCount nodes { isResolved } }
        commits(last: 1) {
          nodes {
            commit {
              oid
              status { contexts { context state createdAt } }
              checkSuites(first: 50) {
                totalCount
                nodes { checkRuns(first: 100, filterBy: { checkType: ALL }) { totalCount nodes { databaseId status conclusion completedAt title } } }
              }
            }
          }
        }
      }
      pageInfo { hasNextPage endCursor }
    }
  }
}`;
const UPLOADER = ".github/workflows/pr-dispatch-feedback.yml";
const KEY = /^[0-9a-f]{64}$/;

const sha256 = (text) => createHash("sha256").update(text).digest("hex");
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const finite = (value) => typeof value === "number" && Number.isFinite(value);

export function parseFingerprint(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isObject(data) || data.schema !== FINGERPRINT_SCHEMA || typeof data.digest !== "string" || !finite(data.takenAt) || !isObject(data.entries)) {
    return null;
  }
  const entries = new Map();
  for (const [number, entry] of Object.entries(data.entries)) {
    if (/^[1-9][0-9]{0,9}$/.test(number) && isObject(entry) && KEY.test(String(entry.key)) && finite(entry.decidedAt) && (entry.dueAt === null || finite(entry.dueAt))) {
      entries.set(Number(number), entry);
    }
  }
  return { run: String(data.run ?? ""), takenAt: data.takenAt, digest: data.digest, entries };
}

// The newest unexpired fingerprint artifact another run uploaded, read and
// parsed, when a pr-dispatch-feedback.yml workflow_run run on main of this
// repository uploaded it; otherwise null, with the reason logged. Any
// workflow can upload an artifact by this name, so the uploader is read back.
// https://docs.github.com/en/rest/actions/artifacts#list-artifacts-for-a-repository
export async function readPreviousFingerprint({ api, repository, runId, log }) {
  const fallBack = (why) => {
    log(`sweep fingerprint: ${why}; every PR is read in full this tick`);
    return null;
  };
  try {
    const [artifact] = (await api.listArtifactsNamed(FINGERPRINT_ARTIFACT))
      .filter((row) => row?.name === FINGERPRINT_ARTIFACT && row.expired === false && String(row.workflow_run?.id) !== String(runId))
      .sort((a, b) => Date.parse(b.created_at ?? "") - Date.parse(a.created_at ?? ""));
    if (!artifact) {
      return fallBack(`no unexpired ${FINGERPRINT_ARTIFACT} artifact from an earlier run`);
    }
    const run = await api.getWorkflowRun(artifact.workflow_run?.id);
    if (run?.path !== UPLOADER || run.event !== "workflow_run" || run.head_branch !== "main" || run.repository?.full_name !== repository) {
      return fallBack(`artifact ${artifact.id} was uploaded by run ${run?.id}, not a workflow_run run of ${UPLOADER} on main`);
    }
    const bytes = zipEntry(await api.downloadArtifact(artifact.id), FINGERPRINT_FILE);
    const previous = bytes === null ? null : parseFingerprint(bytes.toString("utf8"));
    if (previous === null) {
      return fallBack(`artifact ${artifact.id} holds no ${FINGERPRINT_FILE} of schema ${FINGERPRINT_SCHEMA}`);
    }
    return previous;
  } catch (error) {
    return fallBack(`the previous fingerprint could not be read (${error.message})`);
  }
}

const RELATIVE_IMPORT = /(?:\bfrom|\bimport)\s*\(?\s*["'](\.\.?\/[^"']+)["']/g;
export function configDigest({ base, roots = [], files = [], extra = null }) {
  const hash = createHash("sha256");
  const seen = new Set();
  const read = (path) => {
    try {
      return readFileSync(path, "utf8");
    } catch {
      return null;
    }
  };
  const add = (path) => {
    const text = read(path);
    hash.update(`${relative(base, path)}\0${text ?? "\u0000missing"}\0`);
    return text;
  };
  const walk = (path) => {
    if (seen.has(path)) {
      return;
    }
    seen.add(path);
    const text = add(path);
    if (text !== null && path.endsWith(".mjs")) {
      for (const match of text.matchAll(RELATIVE_IMPORT)) {
        walk(resolve(dirname(path), match[1]));
      }
    }
  };
  roots.forEach((path) => walk(resolve(path)));
  files.forEach((path) => add(resolve(path)));
  hash.update(JSON.stringify(extra));
  return hash.digest("hex");
}

export function stateKey({ pull, state, runs }) {
  const commit = state?.commits?.nodes?.[0]?.commit;
  const suites = commit?.checkSuites;
  const threads = state?.reviewThreads;
  if (
    !state ||
    !Array.isArray(runs) ||
    state.headRefOid !== pull.head.sha ||
    commit?.oid !== pull.head.sha ||
    !Number.isSafeInteger(state.comments?.totalCount) ||
    !Array.isArray(threads?.nodes) ||
    threads.totalCount !== threads.nodes.length ||
    !Array.isArray(suites?.nodes) ||
    suites.totalCount !== suites.nodes.length ||
    suites.nodes.some((suite) => !Array.isArray(suite?.checkRuns?.nodes) || suite.checkRuns.totalCount !== suite.checkRuns.nodes.length)
  ) {
    return null;
  }
  const checks = suites.nodes.flatMap((suite) => suite.checkRuns.nodes).sort((a, b) => a.databaseId - b.databaseId);
  const parts = {
    head: pull.head.sha,
    updatedAt: pull.updated_at ?? null,
    draft: pull.draft,
    labels: (pull.labels ?? []).map((label) => label.name).sort(),
    autoMerge: pull.auto_merge != null,
    checks: checks.map((run) => [run.databaseId, run.status, run.conclusion, run.completedAt, run.title]),
    statuses: (commit.status?.contexts ?? []).map((row) => [row.context, row.state, row.createdAt]).sort((a, b) => String(a).localeCompare(String(b))),
    threads: [threads.totalCount, threads.nodes.filter((thread) => thread.isResolved === false).length],
    comments: state.comments.totalCount,
    runs: runs
      .filter((run) => PR_UNBLOCK_TITLE.exec(String(run.display_title ?? ""))?.[2] === String(pull.number))
      .map((run) => [run.id, run.status, run.conclusion, run.updated_at])
      .sort((a, b) => Number(a[0]) - Number(b[0])),
  };
  const newest = checks.at(-1)?.databaseId ?? null;
  return { key: sha256(JSON.stringify(parts)), newestCheckRun: newest };
}

export function sweepFingerprint({ api, repository, runId, settings, digest, now, log, readPrevious = readPreviousFingerprint }) {
  const current = new Map();
  const skipped = new Set();
  const dues = new Map();
  const revisit = new Set();
  let previous = null;
  return {
    async observe(pulls) {
      let states = new Map();
      let runs = null;
      try {
        states = new Map((await api.listSweepStates(settings.base)).map((state) => [state.number, state]));
      } catch (error) {
        log(`::warning::sweep fingerprint: the open PRs' state could not be read (${error.message}); no PR is skipped or recorded`);
      }
      try {
        runs = await api.listWorkflowRuns(settings.workflow);
      } catch (error) {
        log(`sweep fingerprint: the ${settings.workflow} run listing could not be read (${error.message}); no PR is skipped or recorded`);
      }
      for (const pull of pulls) {
        const state = stateKey({ pull, state: states.get(pull.number), runs });
        if (state !== null) {
          current.set(pull.number, { ...state, head: pull.head.sha, updatedAt: pull.updated_at ?? null });
        }
      }
      previous = await readPrevious({ api, repository, runId, log });
      if (previous !== null && previous.digest !== digest) {
        log("sweep fingerprint: the decision's code or configuration changed since the previous fingerprint; every PR is read in full this tick");
        previous = null;
      }
      const candidates = [...current].filter(([number, { key }]) => {
        const entry = previous?.entries.get(number);
        return entry !== undefined && entry.key === key && now - entry.decidedAt < FULL_REFRESH_MS && (entry.dueAt === null || entry.dueAt > now);
      });
      if (candidates.length === 0) {
        return;
      }
      let commented;
      try {
        commented = new Set(await api.listCommentsSince(new Date(previous.takenAt - COMMENT_SKEW_MS).toISOString().replace(/\.\d{3}Z$/, "Z")));
      } catch (error) {
        log(`sweep fingerprint: the comments since the previous tick could not be read (${error.message}); every PR is read in full this tick`);
        return;
      }
      for (const [number] of candidates) {
        if (!commented.has(number)) {
          skipped.add(number);
          log(`sweep: #${number} is unchanged since run ${previous.run}'s fingerprint; its reads are skipped this tick`);
        }
      }
      log(`sweep fingerprint: ${skipped.size} of ${pulls.length} lanes App PRs unchanged`);
    },
    unchanged: (number) => skipped.has(number),
    due(number, at) {
      if (!(at > now)) {
        revisit.add(number);
      } else {
        dues.set(number, Math.min(dues.get(number) ?? Infinity, at));
      }
    },
    settle(quiet) {
      const entries = {};
      const record = (number, decidedAt, dueAt) => {
        const { key, head, updatedAt, newestCheckRun } = current.get(number);
        entries[number] = { key, head, updatedAt, newestCheckRun, decidedAt, dueAt };
      };
      for (const number of skipped) {
        const entry = previous.entries.get(number);
        record(number, entry.decidedAt, entry.dueAt);
      }
      for (const number of quiet) {
        if (current.has(number) && !skipped.has(number) && !revisit.has(number)) {
          record(number, now, dues.get(number) ?? null);
        }
      }
      return { schema: FINGERPRINT_SCHEMA, run: String(runId), takenAt: now, digest, entries };
    },
  };
}
