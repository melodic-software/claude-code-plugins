#!/usr/bin/env node
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, paginate, retryServerErrors } from "../lib/github-client.mjs";
import { loadTrustedList, trustedListPath } from "../lib/trusted-actors.mjs";
import { laneChecker, laneFooter, withoutBinding, withoutLaneFooters } from "../lib/lane-binding.mjs";
import { humanGatedLabelFrom, isVerifierRoot } from "../pr-unblock/address-feedback.mjs";
import {
  CLEARED,
  ESCALATION,
  escalationsSince,
  escalationActivity,
  escalationRoute,
  failingChecks,
  foreignMarker,
  holdText,
  HOLD_LINE,
  isApp,
  labelHistory,
  LANE_STOPPED,
  laneHold,
  lines,
  MODEL_RUN,
  openCredentialHold,
  openReviewHold,
  openSignedCommitsHold,
  PAIRED_MS,
  personSince,
  RESUME_KEY,
  reviewEntries,
  ROUND_MARKER,
  ROUTES,
  same,
  sinceParam,
  spoken,
} from "../pr-unblock/gate-source.mjs";
import { isProtectedPath } from "../pr-unblock/thread-scope.mjs";
import { branchActivity, LANES_APP_LOGIN as DEFAULT_BOT, laneChange, OUTSIDE_ACTOR_LABEL as OUTSIDE_ACTOR, readStatuses, REVIEW_LANES } from "./merge-holds.mjs";
import { pythonVerify, READER_HOLDS, REFUSAL_MARKER, refusalReasons, rotated, verifyHold } from "./enable-auto-merge.mjs";

const REASON = /^- Reason: `([a-z-]+)`$/m;
const outsideActorHeld = (labels) => (labels ?? []).some((item) => same(item?.name, OUTSIDE_ACTOR));
const OUTSIDE_ACTOR_KEPT = `it carries ${OUTSIDE_ACTOR}, which a person lifts`;
const CREDENTIAL_KEPT = "pr-verify holds it for a credential, which a person lifts";
const clearedMarker = (reason, head) => `<!-- pr-pipeline needs-human-cleared reason=${reason} head=${head} -->`;
const PR_MERGE_MARKERS = Object.freeze([
  "<!-- babysit-merge-verify-escalation -->",
  "<!-- babysit-merge-risk -->",
  "<!-- babysit-merge-shared-copy-escalation -->",
  "<!-- babysit-merge-dependabot-major -->",
]);
const PR_MERGE_ESCALATION = "<!-- work-items:escalation lane=pr-merge kind=escalated -->";
const prMergeLine = (line) => PR_MERGE_MARKERS.includes(line) || line === PR_MERGE_ESCALATION;
const AT_HEAD = / at head `([^`]*)`/g;
const HEAD_MOVED = "head-moved";
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const CI_FIX = Object.freeze(["ci-fix-round-cap", "ci-fix-empty", "ci-fix-invalid", "ci-fix-not-applied", "ci-fix-escalated"]);
const PASSING = new Set(["success", "neutral", "skipped"]);
const AGGREGATE = "CI Status";
const AGGREGATE_JOBS = new Set([AGGREGATE, "ci-status"]);
const CHECK_PAGES = 3;
const SHA = /^[0-9a-f]{40}$/;
// Compare lists at most 300 files, only on page 1; a longer list is incomplete.
// https://docs.github.com/en/rest/commits/commits#compare-two-commits
const COMPARE_CAP = 300;
const FILES_CAP = 3000;
export const CLEARS_PER_RUN = 5;
export const NATIVE_READS_PER_RUN = 3;
export const SESSION_CHECKS_PER_RUN = 5;
const REFUSAL_CLEARED = "refusal-cleared";
export const LANE_CAUSES = Object.freeze({
  link: Object.freeze([]),
  verdict: Object.freeze(["verify:fail", "verify:earlier-fail", "verify:spec-changed", "verify:repeated-fail", "verify:too-old"]),
  risk: Object.freeze(["files-incomplete", "evidence-unbound:", "manifest-review-required"]),
});

function laneCause(kind, reason) {
  const codes = reason.slice(READER_HOLDS[kind].length, -1).split("; ").map((part) => part.split(": ")[0]);
  return codes.every((code) => LANE_CAUSES[kind].some((entry) => (entry.endsWith(":") ? code.startsWith(entry) : code === entry)));
}

async function checkRuns(reader, repo, head) {
  const all = [];
  for (let page = 1; page <= CHECK_PAGES; page += 1) {
    const batch = (await reader("GET", `/repos/${repo}/commits/${head}/check-runs?filter=all&per_page=100&page=${page}`))?.check_runs;
    if (!Array.isArray(batch)) {
      return null;
    }
    all.push(...batch);
    if (batch.length < 100) {
      return all;
    }
  }
  return null;
}

const REQUIRED_WORKFLOW = "pr-require-checks.yml";

async function headFailing({ checks, repo, pull }) {
  try {
    const required = (await checks("GET", `/repos/${repo}/actions/workflows/${REQUIRED_WORKFLOW}/runs?head_sha=${pull.head.sha}&per_page=100`))?.workflow_runs;
    if (!Array.isArray(required) || required.length >= 100) {
      return false;
    }
    const suites = new Set(required.map((run) => run.check_suite_id));
    const runs = await checkRuns(checks, repo, pull.head.sha);
    if (runs === null) {
      return false;
    }
    return failingChecks(runs.filter((run) => run.app?.slug === "github-actions" && suites.has(run.check_suite?.id))).length > 0;
  } catch {
    return false;
  }
}

const reasonOf = ({ body }) => REASON.exec(body.join("\n"))?.[1];
const lastWrite = (item) => Math.max(Date.parse(item.created_at), Date.parse(item.updated_at ?? item.created_at));
const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const reportError = (number, error) =>
  console.log(`::error title=clear-escalations::#${number}: ${escapeCommand(error?.message ?? error)}`);

export const LANE_ONLY = Object.freeze(["feedback-not-landed"]);
const ANY_ESCALATION = "<!-- work-items:escalation";

function personEscalation({ appComments, lifted }) {
  return appComments
    .filter((item) => !(lastWrite(item) < lifted))
    .flatMap((item) => {
      const body = lines(item.body);
      const unblock = body[0] === ESCALATION ? [reasonOf({ body }) ?? "an escalation whose reason does not parse"] : [];
      return [...unblock, ...body.filter((line) => PR_MERGE_MARKERS.includes(line) || (line.startsWith(ANY_ESCALATION) && line !== ESCALATION))];
    })
    .find((reason) => !LANE_ONLY.includes(reason));
}

const CHECKS = Object.freeze({
  "workflow-staged": async (context) => {
    const { github, repo, pull, mainSha } = context;
    const files = (await github("GET", `/repos/${repo}/compare/${pull.head.sha}...${mainSha}`))?.files;
    const workflow = (path) => /^\.github\/workflows\//.test(String(path ?? ""));
    const listed = Array.isArray(files) && files.length < COMPARE_CAP;
    const changed = listed ? files.flatMap((file) => [file.filename, file.previous_filename]).find(workflow) : undefined;
    if (listed && changed === undefined) {
      return `main changes nothing under .github/workflows/ since its merge base with ${pull.head.sha}`;
    }
    const moved = await context.moved();
    const merged = moved === null ? null : await context.mainMerged("workflow-staged");
    if (merged !== null) {
      return `${moved}, and it contains main as of the escalation (${merged})`;
    }
    return { held: listed ? `main ${mainSha} changes ${changed}` : `main ${mainSha}'s file listing against it may be cut short` };
  },
  "unresolved-conflict": async ({ pull }) => mergeable(pull),
  "protected-path-conflict": async ({ pull }) => mergeable(pull),
  ...Object.fromEntries(CI_FIX.map((reason) => [reason, ciPasses])),
  "feedback-protected-path": async ({ github, repo, pull }) => {
    const files = await paginate(github, `/repos/${repo}/pulls/${pull.number}/files`);
    return files.length >= FILES_CAP || files.some((file) => isProtectedPath(file.filename) || isProtectedPath(file.previous_filename ?? ""))
      ? { held: "the pull request changes a protected path, or its file listing may be cut short" }
      : "the pull request changes nothing under .github/workflows/";
  },
  "feedback-not-landed": async (context) => {
    const head = context.pull.head.sha;
    if (context.keysOf("feedback-not-landed").includes(head)) {
      return { held: "the head is still the one the lane's fix did not reach" };
    }
    const open = await openLaneThreads(context);
    if (open === null) {
      return { held: "its review thread listing may be cut short" };
    }
    if (open > 0) {
      return { held: `${open} unresolved review thread(s) carry a lanes App comment` };
    }
    const speaker = await context.speaker();
    if (speaker !== undefined) {
      return { spoke: speaker };
    }
    const moved = await context.moved();
    if (moved !== null) {
      return `${moved}, and no review thread the lane replied to is unresolved`;
    }
    const recorded = personEscalation(context);
    if (recorded !== undefined) {
      return { held: `a push no trusted person made moved the head, and ${recorded} is recorded against the label: clean review lanes lift only ${LANE_ONLY.join(", ")}` };
    }
    const clean = await reviewLanesClean(context);
    return clean === null
      ? { held: `a push no trusted person made moved the head; waiting for clean review lanes at ${head}` }
      : `the head moved off the resume key to ${head}, no review thread the lane replied to is unresolved, and ${clean}`;
  },
  ...Object.fromEntries(
    Object.keys(ROUTES)
      .filter((reason) => escalationRoute(reason) === "fail" && escalationActivity(reason) === "fix-ci")
      .map((reason) => [
        reason,
        async (context) => {
          if (await context.failing()) {
            return "the lane now ends it in a failing status, not a person, and the head's own checks read failed";
          }
          return CI_FIX.includes(reason) ? ciPasses(context) : { held: "the head's own checks do not read failed" };
        },
      ]),
  ),
});

async function ciPasses(context) {
  const moved = await context.moved();
  if (moved === null) {
    return { held: "no trusted push alone moved the head off the resume key" };
  }
  const held = await checksHeld(context.read, context.repo, context.pull.head.sha);
  return held === null ? `${moved}, and no check other than ${AGGREGATE} fails, runs or was cancelled at it` : { held };
}

async function checksHeld(read, repo, head) {
  const runs = await read((reader) => checkRuns(reader, repo, head));
  const others = (runs ?? []).filter((run) => !AGGREGATE_JOBS.has(run?.name));
  const latest = new Map();
  for (const run of others) {
    if (!(latest.get(run.name)?.id > run.id)) {
      latest.set(run.name, run);
    }
  }
  if (
    runs === null ||
    failingChecks(others).length > 0 ||
    others.some((run) => run.status !== "completed") ||
    [...latest.values()].some((run) => !PASSING.has(run.conclusion)) ||
    !others.some((run) => run.conclusion === "success")
  ) {
    return `a check other than ${AGGREGATE} fails, runs, was cancelled or did not pass at ${head}, or its runs did not read`;
  }
  return null;
}

const STATUS_JOBS = new Map(REVIEW_LANES);
export const LANE_RECORDS = Object.freeze([
  { file: "pr-review-hosted.yml", lane: "claude-review", jobs: STATUS_JOBS.get("pr-review-hosted.yml"), whole: false },
  { file: "pr-review-security-hosted.yml", lane: "claude-security-review", jobs: STATUS_JOBS.get("pr-review-security-hosted.yml"), whole: true },
]);
const RECORD_TITLE = "claude-lane-review-complete";
const REVIEW_RECORD =
  /^claude-lane-review-complete lane=([\w-]+) sha=([0-9a-f]{40}) findings=\d{1,6} inline=\d{1,6} scope=(whole|incremental since=[0-9a-f]{40})(?: account=fallback)?$/;
const SECURITY_REVIEWED_HEAD = /^<!-- claude-lane-reviewed-head lane=claude-security-review sha=([0-9a-f]{40}) -->$/;
const MARKER_AUTHOR = "github-actions[bot]";
const CRITICAL_FINDINGS = /^\s*`?critical-findings: (\d{1,6})`?\s*$/gm;
const newestById = (items) => items.reduce((newest, item) => (newest === undefined || item.id > newest.id ? item : newest), undefined);
const newestNamed = (jobs, names) => names.map((name) => newestById(jobs.filter((item) => item?.name === name))).find((job) => job !== undefined);

async function reviewLanesClean(context) {
  const { read, repo, pull, timeline } = context;
  const head = pull.head.sha;
  for (const { file, lane, jobs: names, whole } of LANE_RECORDS) {
    const scope = await read(async (reader) => {
      const runs = (await reader("GET", `/repos/${repo}/actions/workflows/${file}/runs?head_sha=${head}&event=pull_request&per_page=100`))?.workflow_runs;
      if (!Array.isArray(runs) || runs.length >= 100) {
        return null;
      }
      const run = newestById(
        runs.filter((item) => item?.path === `.github/workflows/${file}` && item.head_sha === head && item.event === "pull_request" && item.head_repository?.full_name === repo),
      );
      if (run?.status !== "completed" || run.conclusion !== "success") {
        return null;
      }
      const jobs = (await reader("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
      if (!Array.isArray(jobs) || jobs.length >= 100) {
        return null;
      }
      const status = newestNamed(jobs, names);
      if (status?.status !== "completed" || status.conclusion !== "success") {
        return null;
      }
      const notes = await reader("GET", `/repos/${repo}/check-runs/${status.id}/annotations?per_page=100`);
      if (!Array.isArray(notes) || notes.length >= 100) {
        return null;
      }
      const records = notes.filter((note) => note?.title === RECORD_TITLE);
      const record = records.length === 1 && records[0].annotation_level === "notice" ? REVIEW_RECORD.exec(String(records[0].message ?? "")) : null;
      return record !== null && record[1] === lane && record[2] === head ? record[3] : null;
    });
    if (scope === null || (whole && scope !== "whole")) {
      return null;
    }
  }
  const marker = timeline
    .filter((item) => item.event === "commented" && isApp(item.user, MARKER_AUTHOR) && SECURITY_REVIEWED_HEAD.test(lines(item.body)[0]))
    .at(-1);
  if (
    marker === undefined ||
    SECURITY_REVIEWED_HEAD.exec(lines(marker.body)[0])[1] !== head ||
    !(Date.parse(marker.updated_at ?? marker.created_at) <= Date.parse(marker.created_at))
  ) {
    return null;
  }
  const counts = [...String(marker.body).matchAll(CRITICAL_FINDINGS)];
  if (counts.length !== 1 || Number(counts[0][1]) !== 0) {
    return null;
  }
  const open = await context.threads();
  const severe = (thread) => {
    const found = [...String(thread?.opening?.nodes?.[0]?.body ?? "").matchAll(SEVERITY)];
    return found.length !== 1 || found[0][1] === "CRITICAL";
  };
  if (open === null || open.some(severe)) {
    return null;
  }
  return "both review lanes completed a review of it, the security review whole with critical-findings: 0, and no unresolved review thread carries a CRITICAL or unreadable severity";
}

async function mainMergedAt({ read, repo, pull, escalations }, reason) {
  const times = escalations.filter((item) => reasonOf(item) === reason).map((item) => item.at);
  if (times.length === 0 || !times.every(Number.isFinite)) {
    return null;
  }
  const until = new Date(Math.max(...times)).toISOString();
  return read(async (reader) => {
    const then = (await reader("GET", `/repos/${repo}/commits?sha=main&until=${encodeURIComponent(until)}&per_page=1`))?.[0]?.sha;
    if (!SHA.test(String(then))) {
      return null;
    }
    const compare = await reader("GET", `/repos/${repo}/compare/${then}...${pull.head.sha}`);
    return compare?.behind_by === 0 && ["ahead", "identical"].includes(compare?.status) ? then : null;
  });
}

function mergeable(pull) {
  return pull.mergeable === true && pull.mergeable_state !== "dirty"
    ? "GitHub reports no conflict with main"
    : { held: `GitHub reports mergeable ${pull.mergeable ?? "unknown"} (${pull.mergeable_state ?? "unknown"})` };
}

const THREAD_PAGES = 10;
const LANE_THREADS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          isResolved
          opening: comments(first: 1) { nodes { body } }
          comments(first: 100) { totalCount nodes { author { __typename login } } }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

async function openLaneThreads({ threads, bot }) {
  const open = await threads();
  const lane = (author) => author?.__typename === "Bot" && (author.login === bot || `${author.login}[bot]` === bot);
  return open === null ? null : open.filter((thread) => thread.comments.nodes.some((comment) => lane(comment?.author))).length;
}

async function unresolvedThreads({ github, repo, pull }) {
  const [owner, name] = repo.split("/");
  const open = [];
  let after = null;
  for (let page = 0; page < THREAD_PAGES; page += 1) {
    const variables = { owner, name, number: pull.number, after };
    const threads = (await github("POST", "/graphql", { query: LANE_THREADS_QUERY, variables }))?.data?.repository?.pullRequest?.reviewThreads;
    if (!Array.isArray(threads?.nodes)) {
      return null;
    }
    for (const thread of threads.nodes) {
      if (thread?.isResolved === true) {
        continue;
      }
      const comments = thread?.comments;
      if (thread?.isResolved !== false || !Array.isArray(comments?.nodes) || !(comments.totalCount <= comments.nodes.length)) {
        return null;
      }
      open.push(thread);
    }
    if (!threads.pageInfo?.hasNextPage) {
      return open;
    }
    after = threads.pageInfo.endCursor;
  }
  return null;
}

const keepNote = (label) => `To keep a person on it, add \`${label}\` back: a label a person adds is never removed.`;

export const clearedComment = (reason, head, why, label) =>
  reason === STALE_HOLD
    ? `${clearedMarker(reason, head)}\nA review lane held this pull request at an earlier head, and that hold no longer stands at \`${head}\` (\`${STALE_HOLD}\`): ${why}. pr-merge removed \`${label}\`; a review lane that still finds the cause holds the head again. ${keepNote(label)}`
    : reason === REFUSAL_CLEARED
    ? `${clearedMarker(reason, head)}\nThe pr-merge lane left this pull request for a person, and at \`${head}\` that no longer holds (\`${REFUSAL_CLEARED}\`): ${why}. pr-merge removed \`${label}\`, so the next scheduled run judges it again. ${keepNote(label)}`
    : reason === HEAD_MOVED
    ? `${clearedMarker(reason, head)}\nThe pr-merge lane escalated this pull request, and its head has moved (\`${HEAD_MOVED}\`): ${why}. pr-merge removed \`${label}\` so it judges \`${head}\` afresh, and escalates again if its refusal still holds. ${keepNote(label)}`
    : `${clearedMarker(reason, head)}\nThe pr-unblock lane escalated this pull request as \`${reason.replaceAll(",", "`, `")}\`, and that no longer holds at \`${head}\`: ${why}. pr-merge removed \`${label}\`, so the lanes run on it again. ${keepNote(label)}`;

function prMergeEscalations(appComments) {
  return PR_MERGE_MARKERS.flatMap((marker) => {
    const newest = appComments.filter((item) => lines(item.body).slice(0, 2).includes(marker)).at(-1);
    if (newest === undefined) {
      return [];
    }
    const body = lines(newest.body);
    const named = [...String(body[body.indexOf(marker) + 1] ?? "").matchAll(AT_HEAD)].map((match) => match[1]);
    return [{ marker, head: named.length === 1 && SHA.test(named[0]) ? named[0] : null }];
  });
}

function nativeRefusal(appComments, merged, label, head) {
  if (merged.length !== 1 || merged[0].marker !== REFUSAL_MARKER || merged[0].head !== head) {
    return null;
  }
  const newest = appComments.filter((item) => lines(item.body).slice(0, 2).includes(REFUSAL_MARKER)).at(-1);
  if (!(Date.parse(newest.updated_at) <= Date.parse(newest.created_at))) {
    return null;
  }
  const reason = refusalReasons(newest.body, true, head, label)?.join("\n");
  const kind = reason === undefined ? undefined : Object.keys(READER_HOLDS).find((key) => reason.startsWith(READER_HOLDS[key]));
  return kind !== undefined ? { kind, reason } : null;
}

function liftsRefusal(kind, evidence, head) {
  const held = verifyHold(evidence, head);
  if (held === null) {
    return true;
  }
  const order = Object.keys(READER_HOLDS);
  const now = order.find((key) => held.startsWith(READER_HOLDS[key]));
  return order.indexOf(now) >= order.indexOf(kind) && laneCause(now, held);
}

function pairedWithPrMerge(appComments, since) {
  let newest = -Infinity;
  let ours = false;
  let escalated = false;
  for (const item of appComments) {
    const markers = lines(item.body).filter((line) => line.includes("<!--") && !CLEARED.test(line) && !LANE_STOPPED.test(line));
    const at = Math.max(...[item.created_at, item.updated_at].map(Date.parse).filter((time) => time <= since));
    if (markers.length === 0 || at < newest) {
      continue;
    }
    const mine = markers.some((line) => PR_MERGE_MARKERS.includes(line)) && markers.every(prMergeLine);
    ours = at > newest ? mine : ours && mine;
    escalated = at > newest ? markers.includes(PR_MERGE_ESCALATION) : escalated && markers.includes(PR_MERGE_ESCALATION);
    newest = at;
  }
  return ours && (since - newest <= PAIRED_MS || escalated);
}

export const STALE_HOLD = "stale-review-hold";
const LANE_OF = Object.freeze(Object.fromEntries(LANE_RECORDS.map(({ file, lane }) => [file, lane])));
const SECURITY_LANE = "claude-security-review";
const SEVERITY = /^\s*`?severity: (CRITICAL|IMPORTANT|SUGGESTION)`?\s*$/gm;
const HOLD_LANE = /^<!-- claude-lane-hold lane=([a-z-]+) /;
const HOLD_CRITERIA = / criteria=([a-z,-]+) -->$/;
const COMPARE_FILES = 300;
const FIX_COMMITS = 20;
const LANE_TAG = /^\s*`?claude-lane: ([\w-]+)`?\s*$/m;
const REVIEW_THREAD_PAGES = 10;
const REVIEW_THREADS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes { isResolved path comments(first: 1) { nodes { author { __typename login } databaseId body createdAt updatedAt lastEditedAt originalCommit { oid } originalLine originalStartLine } } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

const ANY_LANE = "*";
function commentLane(author, body) {
  if (author?.__typename !== "Bot") {
    return null;
  }
  const text = String(body ?? "");
  if (["claude", "claude[bot]"].includes(author.login)) {
    return LANE_TAG.exec(text)?.[1] ?? ANY_LANE;
  }
  const last = lines(text).filter((line) => line.trim() !== "").at(-1) ?? "";
  return ["github-actions", "github-actions[bot]"].includes(author.login) ? (LANE_TAG.exec(last)?.[1] ?? null) : null;
}

const ARTIFACT_PAGES = 10;

export function restLaneChecker({ read, download, repo, pr, laneReads }) {
  return laneChecker({
    pr,
    getPull: (number) => read("GET", `/repos/${repo}/pulls/${number}`),
    getRun: (id) => read("GET", `/repos/${repo}/actions/runs/${id}`),
    listArtifacts: async (id) => {
      const all = [];
      for (let page = 1; page <= ARTIFACT_PAGES; page += 1) {
        const listing = await read("GET", `/repos/${repo}/actions/runs/${id}/artifacts?per_page=100&page=${page}`);
        if (!Array.isArray(listing?.artifacts)) {
          throw new Error(`run ${id}'s artifact listing did not read`);
        }
        all.push(...listing.artifacts);
        if (listing.artifacts.length < 100) {
          return all;
        }
      }
      throw new Error(`run ${id} lists more than ${ARTIFACT_PAGES * 100} artifacts`);
    },
    download,
    ...laneReads,
  });
}

export function artifactDownload({ token, repo, apiUrl = "https://api.github.com", fetchImpl = fetch, log }) {
  const send = retryServerErrors(fetchImpl, { log });
  return async (id) => {
    const response = await send(`${apiUrl}/repos/${repo}/actions/artifacts/${id}/zip`, {
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" },
    });
    if (!response.ok) {
      throw new Error(`artifact ${id} did not download: HTTP ${response.status}`);
    }
    return Buffer.from(await response.arrayBuffer());
  };
}

const stdinText = async () => {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
};

const LANE_HOLD_LINE = /(^|\n)<!-- claude-lane-hold lane=/;
const footedHold = (comment) =>
  comment?.user?.login === "github-actions[bot]" && LANE_HOLD_LINE.test(String(comment.body ?? "")) && laneFooter(comment.body) !== null;

export async function laneHoldComments(comments, check) {
  const out = [];
  for (const comment of comments) {
    if (!footedHold(comment)) {
      out.push(comment);
      continue;
    }
    const own = await check({ kind: "issue_comment", id: comment.id, body: comment.body, createdAt: comment.created_at, updatedAt: comment.updated_at });
    out.push({ ...comment, body: own ? withoutBinding(comment.body) : withoutLaneFooters(comment.body) });
  }
  return out;
}

export async function laneTimeline(github, repo, number, check) {
  const timeline = await paginate(github, `/repos/${repo}/issues/${number}/timeline`);
  const comments = await laneHoldComments(timeline.filter((item) => item.event === "commented"), check);
  let next = 0;
  return timeline.map((item) => (item.event === "commented" ? comments[next++] : item));
}

export async function filterLaneHolds({ env = process.env, input, write = (text) => process.stdout.write(text), laneReads } = {}) {
  try {
    const repo = env.GITHUB_REPOSITORY ?? "";
    const pr = Number(env.PR_NUMBER);
    if (!REPO.test(repo) || !Number.isSafeInteger(pr) || pr < 1) {
      throw new Error("GITHUB_REPOSITORY or PR_NUMBER is not set");
    }
    const comments = JSON.parse(input ?? (await stdinText()));
    if (!Array.isArray(comments)) {
      throw new Error("the comments are not one JSON array");
    }
    const log = (line) => console.error(line);
    const apiUrl = env.GITHUB_API_URL || undefined;
    const read = createGitHub({ token: env.GH_TOKEN, apiUrl, log });
    const download = artifactDownload({ token: env.GH_TOKEN, repo, apiUrl, log });
    write(`${JSON.stringify(await laneHoldComments(comments, restLaneChecker({ read, download, repo, pr, laneReads })))}\n`);
    return 0;
  } catch (error) {
    console.error(`lane-holds: did not read: ${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

async function laneThreads({ github, repo, number, check }) {
  const [owner, name] = repo.split("/");
  const open = [];
  let after = null;
  for (let page = 0; page < REVIEW_THREAD_PAGES; page += 1) {
    const threads = (await github("POST", "/graphql", { query: REVIEW_THREADS_QUERY, variables: { owner, name, number, after } }))?.data?.repository?.pullRequest
      ?.reviewThreads;
    if (!Array.isArray(threads?.nodes)) {
      return null;
    }
    for (const thread of threads.nodes) {
      const root = thread?.comments?.nodes?.[0];
      if (thread?.isResolved === true && root === undefined) {
        continue;
      }
      if (typeof thread?.isResolved !== "boolean" || root === undefined) {
        return null;
      }
      const lane = commentLane(root.author, root.body);
      const app = ["claude", "claude[bot]"].includes(root.author?.login);
      const own =
        lane !== null &&
        (app ||
          (await check({ kind: "review_comment", id: root.databaseId, body: root.body, createdAt: root.createdAt, updatedAt: root.updatedAt, lastEditedAt: root.lastEditedAt })));
      if (own) {
        open.push({
          lane,
          severity: [...String(app ? (root.body ?? "") : withoutBinding(root.body)).matchAll(SEVERITY)].map((match) => match[1]),
          resolved: thread.isResolved,
          path: thread.path ?? null,
          commit: root.originalCommit?.oid ?? null,
          lines: Number.isInteger(root.originalLine) ? [root.originalStartLine ?? root.originalLine, root.originalLine] : null,
        });
      }
    }
    if (!threads.pageInfo?.hasNextPage) {
      return open;
    }
    after = threads.pageInfo.endCursor;
  }
  return null;
}

async function laneReview({ checks, repo, head }, [file, names]) {
  const lane = LANE_OF[file];
  try {
    const runs = (await checks("GET", `/repos/${repo}/actions/workflows/${file}/runs?event=pull_request&head_sha=${head}&per_page=100`))?.workflow_runs;
    if (!Array.isArray(runs) || runs.length >= 100) {
      return { held: `${lane}'s runs on ${head} did not read whole` };
    }
    const run = runs.filter((item) => item?.head_sha === head && item.head_repository?.full_name === repo).sort((a, b) => b.id - a.id)[0];
    if (run === undefined) {
      return { held: `${lane} has not run on ${head}` };
    }
    const jobs = (await checks("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
    const job = newestNamed(Array.isArray(jobs) ? jobs : [], names);
    if (job?.status !== "completed" || job.conclusion !== "success") {
      return { held: `${lane} has not passed on ${head}` };
    }
    const notes = await checks("GET", `/repos/${repo}/check-runs/${job.id}/annotations?per_page=100`);
    if (!Array.isArray(notes) || notes.length >= 100) {
      return { held: `${lane}'s notices on ${head} did not read whole` };
    }
    const messages = notes.filter((note) => note?.annotation_level === "notice").map((note) => String(note.message ?? ""));
    if (messages.some((message) => message.startsWith("claude-lane-hold ") && message.includes(` sha=${head} `))) {
      return { held: `${lane} holds ${head}` };
    }
    const done = new RegExp(
      `^claude-lane-review-complete lane=${lane} sha=${head} findings=(\\d{1,6}) inline=(\\d{1,6}) scope=(whole|incremental since=[0-9a-f]{40})(?: account=fallback)?$`,
    );
    const reviewed = messages.map((message) => done.exec(message)).filter((match) => match !== null);
    if (reviewed.length !== 1) {
      return { held: `${lane} recorded no one review of ${head}` };
    }
    return { lane, findings: Number(reviewed[0][1]), inline: Number(reviewed[0][2]), whole: reviewed[0][3] === "whole" };
  } catch (error) {
    return { held: `${lane}'s run on ${head} did not read: ${escapeCommand(error?.message ?? error)}` };
  }
}

function findingsHeld({ head, timeline, threads }, reviews, heldLanes) {
  for (const review of reviews) {
    if (!review.whole) {
      return `${review.lane} reviewed only part of ${head}`;
    }
    if ((review.lane === SECURITY_LANE || heldLanes.has(review.lane)) && review.findings > review.inline) {
      return `${review.lane} reported ${review.findings - review.inline} finding(s) at ${head} with no inline severity`;
    }
  }
  const marker = `<!-- claude-lane-reviewed-head lane=${SECURITY_LANE} sha=${head} -->`;
  const summary = timeline.filter((item) => item.event === "commented" && isApp(item.user, "github-actions[bot]") && lines(item.body)[0] === marker);
  const counts = summary.length === 1 ? [...String(summary[0].body).matchAll(CRITICAL_FINDINGS)].map((match) => match[1]) : [];
  if (counts.length !== 1 || counts[0] !== "0") {
    return `the security lane's summary of ${head} does not read critical-findings: 0`;
  }
  const open = threads.filter((thread) => !thread.resolved);
  for (const { lane } of reviews) {
    const strict = lane === SECURITY_LANE || heldLanes.has(lane);
    const blocking = open.filter(
      (thread) =>
        (thread.lane === lane || thread.lane === ANY_LANE) &&
        (thread.severity.length === 1 ? thread.severity[0] === "CRITICAL" : strict || thread.severity.includes("CRITICAL")),
    ).length;
    if (blocking > 0) {
      return `${blocking} unresolved ${lane} finding(s) at CRITICAL or with no one readable severity`;
    }
  }
  return null;
}

export async function trustedMove({ read, repo, pull, keys, since, trusted }) {
  const head = pull.head.sha;
  const ref = String(pull.head?.ref ?? "");
  if (trusted === null || keys.includes(head) || pull.head?.repo?.full_name !== repo || ref === "") {
    return null;
  }
  const activity = await read((reader) => branchActivity(reader, repo, ref));
  if (!Array.isArray(activity)) {
    return null;
  }
  const at = (item) => Date.parse(String(item?.timestamp));
  const recent = activity.filter((item) => !(at(item) <= since)).sort((a, b) => at(b) - at(a));
  if (recent.length === 0 || recent.length === activity.length || recent[0].after !== head) {
    return null;
  }
  if (recent.some((item) => !trusted.has(item?.actor?.id))) {
    return null;
  }
  const by = [...new Set(recent.map((item) => item.actor.login))].join(", ");
  return `${by} moved the head from the resume key to ${head}`;
}

export function holdsSince(timeline, lifted) {
  const holds = timeline
    .filter((item) => laneHold(item) !== undefined && !(lastWrite(item) < lifted))
    .map((item) => {
      const marker = laneHold(item);
      return { sha: HOLD_LINE.exec(marker)?.[1], lane: HOLD_LANE.exec(marker)?.[1], criteria: (HOLD_CRITERIA.exec(marker)?.[1] ?? "").split(",") };
    });
  return {
    shas: holds.map((hold) => hold.sha),
    lanes: new Set(holds.map((hold) => hold.lane)),
    critical: holds.filter((hold) => hold.criteria.includes("critical-security")).map(({ sha, lane }) => ({ sha, lane })),
  };
}

async function compareCommits(github, repo, from, to) {
  const compare = await github("GET", `/repos/${repo}/compare/${from}...${to}`);
  const commits = compare?.commits;
  return Array.isArray(commits) && commits.length === compare.total_commits && commits.every((commit) => SHA.test(String(commit?.sha)))
    ? { commits, files: Array.isArray(compare.files) ? compare.files : [] }
    : null;
}

export function patchTouches(patch, [first, last]) {
  let old = 0;
  for (const line of String(patch).split("\n")) {
    const hunk = /^@@ -(\d+)/.exec(line);
    if (hunk !== null) {
      old = Number(hunk[1]);
    } else if (line.startsWith("-")) {
      if (old >= first && old <= last) {
        return true;
      }
      old += 1;
    } else if (line.startsWith("+")) {
      if (old >= first && old - 1 <= last) {
        return true;
      }
    } else if (!line.startsWith("\\")) {
      old += 1;
    }
  }
  return false;
}

async function heldCauseUnchanged({ github, repo, base, head, threads }, held, critical) {
  const since = await compareCommits(github, repo, held, head);
  const own = await compareCommits(github, repo, base, head);
  if (since === null || own === null) {
    return `the commits from ${held} or ${base} to ${head} did not read whole`;
  }
  const mine = new Set(own.commits.map((commit) => commit.sha));
  const fixes = since.commits.filter((commit) => mine.has(commit.sha) && Array.isArray(commit.parents) && commit.parents.length === 1);
  if (fixes.length === 0) {
    return `no commit of the pull request's own but merges moved the head off ${held}`;
  }
  const holds = critical.filter((hold) => hold.sha === held);
  if (holds.length === 0) {
    return null;
  }
  if (fixes.length > FIX_COMMITS) {
    return `more than ${FIX_COMMITS} commits moved the head off ${held}`;
  }
  const changed = new Set();
  for (const { sha } of fixes) {
    const files = (await github("GET", `/repos/${repo}/commits/${sha}`))?.files;
    if (!Array.isArray(files) || files.length >= COMPARE_FILES) {
      return `the files of ${sha} did not read whole`;
    }
    for (const file of files) {
      changed.add(file?.filename);
    }
  }
  for (const { lane } of holds) {
    const findings = threads.filter((thread) => thread.lane === lane && thread.commit === held && thread.severity.includes("CRITICAL"));
    if (findings.length === 0) {
      return `the critical-security hold at ${held} has no CRITICAL inline ${lane} finding there`;
    }
    const unchanged = findings.find((thread) => !changed.has(thread.path));
    if (unchanged !== undefined) {
      return `${unchanged.path}, which holds a CRITICAL finding at ${held}, is unchanged since then`;
    }
    const untouched = findings.find((thread) => {
      const patch = since.files.find((file) => file?.filename === thread.path)?.patch;
      return thread.lines === null || typeof patch !== "string" || !patchTouches(patch, thread.lines);
    });
    if (untouched !== undefined) {
      return `the lines of ${untouched.path} that hold a CRITICAL finding at ${held} are unchanged since then`;
    }
  }
  return null;
}

export async function staleHoldEvidence({ github, checks, reader, repo, number, pull, timeline, lifted, trusted, check, head = pull.head.sha, until = Infinity }) {
  const { shas, lanes, critical } = holdsSince(timeline, lifted);
  if (shas.length === 0) {
    return { reason: "no review-lane hold comment stands since the label went on" };
  }
  if (shas.includes(undefined)) {
    return { reason: "a review-lane hold names no head this can read" };
  }
  for (const sha of new Set([head, pull.head.sha])) {
    if (shas.includes(sha)) {
      return { reason: `a review lane holds the current head ${sha}` };
    }
  }
  const changed = laneChange(await github("GET", `/repos/${repo}/compare/${pull.base.sha}...${head}`));
  if (changed !== null) {
    return { reason: `the head's lane runs prove nothing: it changes ${changed}` };
  }
  const ref = String(pull.head?.ref ?? "");
  let activity = null;
  if (reader !== null && ref !== "") {
    try {
      activity = await branchActivity(reader, repo, ref);
    } catch {
      activity = null;
    }
  }
  activity = Array.isArray(activity) ? activity.filter((item) => !(Date.parse(String(item?.timestamp)) > until)) : null;
  const landed = (activity ?? []).filter((item) => shas.includes(item?.after)).map((item) => Date.parse(String(item.timestamp)));
  if (landed.length === 0 || !landed.every(Number.isFinite)) {
    return { reason: "the push that landed the held head is not in the branch's activity" };
  }
  const judged = { ...pull, head: { ...pull.head, sha: head } };
  const moved = await trustedMove({ read: async () => activity, repo, pull: judged, keys: shas, since: Math.max(...landed), trusted });
  if (moved === null) {
    return { reason: "no trusted push alone moved the head off the held head" };
  }
  const reviews = [];
  for (const lane of REVIEW_LANES) {
    const review = await laneReview({ checks, repo, head }, lane);
    if (review.held !== undefined) {
      return { reason: review.held };
    }
    reviews.push(review);
  }
  const threads = await laneThreads({ github, repo, number, check });
  if (threads === null) {
    return { reason: "the review thread listing may be cut short" };
  }
  const findings = findingsHeld({ head, timeline, threads }, reviews, lanes);
  if (findings !== null) {
    return { reason: findings };
  }
  for (const held of new Set(shas)) {
    const unchanged = await heldCauseUnchanged({ github, repo, base: pull.base.ref, head, threads }, held, critical);
    if (unchanged !== null) {
      return { reason: unchanged };
    }
  }
  return { held: [...new Set(shas)], holds: shas.length, moved };
}

export async function recheckStaleHold({ env = process.env, github, laneReads } = {}) {
  try {
    const repo = env.GITHUB_REPOSITORY ?? "";
    const number = Number(env.PR_NUMBER);
    const label = env.HUMAN_GATED ?? "";
    const cleared = env.CLEARED_SHA ?? "";
    if (!REPO.test(repo) || !Number.isSafeInteger(number) || number < 1 || !SHA.test(env.HEAD_SHA ?? "") || !SHA.test(cleared) || label === "") {
      throw new Error("GITHUB_REPOSITORY, PR_NUMBER, HEAD_SHA, CLEARED_SHA or HUMAN_GATED is not set");
    }
    const apiUrl = env.GITHUB_API_URL || undefined;
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl });
    const check = restLaneChecker({ read: github, download: artifactDownload({ token: env.GH_TOKEN, repo, apiUrl }), repo, pr: number, laneReads });
    const trusted = new Set(loadTrustedList(env.TRUSTED_ACTORS_PATH).humans);
    const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
    if (pull?.head?.sha !== env.HEAD_SHA || pull.head?.repo?.full_name !== repo) {
      console.log(`stale-review-hold: #${number}'s head is no longer ${env.HEAD_SHA}`);
      return 1;
    }
    const timeline = await laneTimeline(github, repo, number, check);
    const { since, lifted } = labelHistory(timeline, label);
    const removed = timeline
      .filter((item) => item.event === "unlabeled" && same(item.label?.name, label))
      .map((item) => Date.parse(item.created_at))
      .filter((time) => time >= since);
    if (removed.length === 0) {
      console.log(`stale-review-hold: no removal of ${label} since it went on is recorded`);
      return 1;
    }
    const until = Math.min(...removed);
    const removal = timeline.find((item) => item.event === "unlabeled" && same(item.label?.name, label) && Date.parse(item.created_at) === until);
    const written = (item) => !(Date.parse(item?.created_at ?? item?.submitted_at ?? "") > until);
    const seen = timeline.filter(written);
    let stop = standingStop({ timeline: seen, lifted, since, bot: removal?.actor?.login ?? "", label });
    if (stop === null) {
      const { comments, reviews } = await reviewActivity(github, repo, number, since);
      const speaker = personSince(reviewEntries({ comments: comments.filter(written), reviews: reviews.filter(written) }), since);
      stop = speaker === undefined ? null : spokeReason(speaker, label);
    }
    if (stop !== null) {
      console.log(`stale-review-hold: the hold stands at ${cleared}: ${stop}`);
      return 1;
    }
    const evidence = await staleHoldEvidence({ github, checks: github, reader: github, repo, number, pull, timeline: seen, lifted, trusted, check, head: cleared, until });
    if (evidence.reason !== undefined) {
      console.log(`stale-review-hold: the hold stands at ${cleared}: ${evidence.reason}`);
      return 1;
    }
    console.log(`stale-review-hold: the hold at ${evidence.held.join(", ")} no longer stands at ${cleared}: ${evidence.moved}`);
    return 0;
  } catch (error) {
    console.log(`stale-review-hold: did not read: ${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

const LANE_LABELERS = Object.freeze(["github-actions[bot]", "claude[bot]"]);

function commitHold(timeline, lifted) {
  if (openSignedCommitsHold(timeline, lifted) !== undefined) {
    return "check-signed-commits holds it: a lane commit could not be verified";
  }
  return openCredentialHold(timeline, lifted) !== undefined ? CREDENTIAL_KEPT : null;
}

function notOpenHeld(pull, label) {
  if (pull?.state !== "open" || pull.base?.ref !== "main" || !SHA.test(String(pull.head?.sha))) {
    return "not an open pull request into main";
  }
  if (!(pull.labels ?? []).some((item) => same(item.name, label))) {
    return `${label} is no longer on it`;
  }
  return outsideActorHeld(pull.labels) ? OUTSIDE_ACTOR_KEPT : null;
}

function standingStop({ timeline, lifted, since, bot, label }) {
  const hold = commitHold(timeline, lifted);
  if (hold !== null) {
    return hold;
  }
  const appComments = timeline.filter((item) => item.event === "commented" && isApp(item.user, bot));
  const foreign = foreignMarker(appComments, since, (line) => line === ROUND_MARKER);
  if (foreign !== undefined) {
    return `a lanes App comment since ${label} went on carries a marker: ${foreign.slice(0, 120)}`;
  }
  const speaker = personSince(timeline.flatMap(spoken), since);
  return speaker === undefined ? null : spokeReason(speaker, label);
}

async function staleReviewHold({ github, checks, repo, number, label, bot, timeline, since, lifted, reader, trusted, checkerFor }) {
  const stop = standingStop({ timeline, lifted, since, bot, label });
  if (stop !== null) {
    return { reason: stop };
  }
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  const closed = notOpenHeld(pull, label);
  if (closed !== null) {
    return { reason: closed };
  }
  const evidence = await staleHoldEvidence({ github, checks, reader, repo, number, pull, timeline, lifted, trusted, check: checkerFor(number) });
  if (evidence.reason !== undefined) {
    return evidence;
  }
  const head = pull.head.sha;
  return {
    ...cleared(timeline, bot, since, [STALE_HOLD], head, [
      `it held \`${evidence.held.join("`, `")}\``,
      evidence.moved,
      "both review lanes passed on it with a whole review and no open CRITICAL finding",
    ]),
    holds: evidence.holds,
  };
}

async function staleHoldMoved({ github, repo, number, label, result, check }) {
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  if (pull?.head?.sha !== result.head) {
    return `its head moved to ${pull?.head?.sha ?? "an unread head"} since it was judged`;
  }
  const timeline = await laneTimeline(github, repo, number, check);
  const { lifted } = labelHistory(timeline, label);
  if (openCredentialHold(timeline, lifted) !== undefined) {
    return CREDENTIAL_KEPT;
  }
  const holds = holdsSince(timeline, lifted).shas;
  return holds.length !== result.holds || holds.some((sha) => sha === undefined || sha === result.head) ? "a review lane wrote a hold since it was judged" : null;
}

async function verdict({ github, checks, repo, number, label, bot, mainSha, lanePrs, verify, reads, reader, trusted, checkerFor }) {
  const timeline = await laneTimeline(github, repo, number, checkerFor(number));
  const { labeled, since, lifted, reviewLabeled } = labelHistory(timeline, label, trusted ?? new Set());
  if (LANE_LABELERS.some((login) => isApp(labeled?.actor, login))) {
    return staleReviewHold({ github, checks, repo, number, label, bot, timeline, since, lifted, reader, trusted, checkerFor });
  }
  if (!isApp(labeled?.actor, bot)) {
    return { reason: `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App` };
  }
  const held = openReviewHold(timeline, lifted, reviewLabeled);
  if (held !== undefined) {
    return { reason: `a review lane holds it: ${holdText(held).slice(0, 120)}` };
  }
  const hold = commitHold(timeline, lifted);
  if (hold !== null) {
    return { reason: hold };
  }
  const appComments = timeline.filter((item) => item.event === "commented" && isApp(item.user, bot));
  const escalations = escalationsSince(appComments, since);
  const merged = escalations.length === 0 && pairedWithPrMerge(appComments, since) ? prMergeEscalations(appComments) : [];
  let reasons = [];
  if (merged.length === 0) {
    if (escalations.length === 0 || !(escalations[0].at - since <= PAIRED_MS)) {
      return { reason: `no pr-unblock escalation by the lanes App right after it added ${label}` };
    }
    reasons = [...new Set(escalations.map(reasonOf))];
    const decided = reasons.find((reason) => !Object.hasOwn(CHECKS, reason ?? ""));
    if (reasons.length === 0 || decided !== undefined || reasons.includes(undefined)) {
      return { reason: `an escalation reason since the label (${decided ?? "none"}) is one a person decides` };
    }
  }
  const known =
    merged.length > 0
      ? prMergeLine
      : (line) => line === ESCALATION || RESUME_KEY.test(line) || LANE_STOPPED.test(line) || line === ROUND_MARKER || MODEL_RUN.test(line);
  const foreign = foreignMarker(appComments, since, known);
  if (foreign !== undefined) {
    return { reason: `a lanes App comment since ${label} went on carries another marker: ${foreign.slice(0, 120)}` };
  }
  const speaker = personSince(timeline.flatMap(spoken), since);
  if (speaker !== undefined) {
    return { reason: spokeReason(speaker, label) };
  }
  const pull = await github("GET", `/repos/${repo}/pulls/${number}`);
  const closed = notOpenHeld(pull, label);
  if (closed !== null) {
    return { reason: closed };
  }
  const why = [];
  if (merged.length > 0) {
    const unread = merged.find(({ head }) => head === null);
    if (unread !== undefined) {
      return { reason: `the pr-merge comment carrying ${unread.marker} names no head this script can read` };
    }
    const native = lanePrs === "native" && isApp(pull.user, bot) ? nativeRefusal(appComments, merged, label, pull.head.sha) : null;
    if (native !== null && !laneCause(native.kind, native.reason)) {
      return { reason: `enable-auto-merge's refusal at ${pull.head.sha} is one a person clears (${native.reason})` };
    }
    if (native !== null) {
      const speaker = await threadSpeaker(github, repo, number, since);
      if (speaker !== undefined) {
        return { reason: spokeReason(speaker, label) };
      }
      if (reads.left <= 0) {
        return { reason: `enable-auto-merge's refusal waits: ${NATIVE_READS_PER_RUN} reader runs this run` };
      }
      reads.left -= 1;
      let evidence;
      try {
        evidence = await verify({ number, headRefOid: pull.head.sha, baseRefOid: pull.base?.sha }, "C3");
      } catch (error) {
        return { reason: `the gate's reader did not answer: ${escapeCommand(error?.message ?? error)}` };
      }
      const held = verifyHold(evidence, pull.head.sha);
      if (!liftsRefusal(native.kind, evidence, pull.head.sha)) {
        return { reason: `enable-auto-merge's refusal still needs a person at ${pull.head.sha}: ${held}` };
      }
      return cleared(timeline, bot, since, [REFUSAL_CLEARED], pull.head.sha, [
        `it refused this head (${native.reason})`,
        held === null ? "the gate now takes its issue link, verifier verdict and risk score" : `what refuses now is one the lanes clear: ${held}`,
      ]);
    }
    if (merged.some(({ head }) => head === pull.head.sha)) {
      return { reason: `a pr-merge escalation names the current head ${pull.head.sha}` };
    }
    reasons = [HEAD_MOVED];
    why.push(`its escalation names head \`${[...new Set(merged.map(({ head }) => head))].join("`, `")}\`, and the head is now \`${pull.head.sha}\``);
  } else {
    let red;
    const failing = () => (red ??= headFailing({ checks, repo, pull }));
    const read = async (fn) => {
      if (reader === null) {
        return null;
      }
      try {
        return await fn(reader);
      } catch (error) {
        console.log(`::warning title=clear-escalations::#${number}: ${escapeCommand(error?.message ?? error)}`);
        return null;
      }
    };
    const keys = escalations.map(({ body }) => RESUME_KEY.exec(body[1])?.[1]);
    let movedOnce;
    let threadsOnce;
    let speakerOnce;
    const context = { github, repo, pull, mainSha, read, escalations, bot, timeline, appComments, lifted };
    context.keysOf = (reason) => keys.filter((_, i) => reasonOf(escalations[i]) === reason);
    context.moved = () => (movedOnce ??= trustedMove({ read, repo, pull, keys, since, trusted }));
    context.threads = () => (threadsOnce ??= unresolvedThreads(context));
    context.mainMerged = (reason) => mainMergedAt(context, reason);
    context.failing = failing;
    context.speaker = () => (speakerOnce ??= threadSpeaker(github, repo, number, since));
    for (const reason of reasons) {
      const cleared = await CHECKS[reason](context);
      if (cleared?.spoke !== undefined) {
        return { reason: spokeReason(cleared.spoke, label) };
      }
      if (typeof cleared !== "string") {
        return { reason: `${reason} still holds at ${pull.head.sha}: ${cleared?.held ?? "unknown"}` };
      }
      why.push(cleared);
    }
  }
  return cleared(timeline, bot, since, reasons, pull.head.sha, why);
}

function cleared(timeline, bot, since, reasons, head, why) {
  const recorded = reasons.join(",");
  const marker = clearedMarker(recorded, head);
  const explained = timeline.some(
    (item) => item.event === "commented" && isApp(item.user, bot) && Date.parse(item.created_at) >= since && lines(item.body)[0] === marker,
  );
  return { reason: null, recorded, head, why: why.join("; "), explained, since };
}

const spokeReason = (speaker, label) => `${speaker.user?.login ?? "an account"} commented or reviewed after ${label} went on`;

async function reviewActivity(github, repo, number, since) {
  const comments = await paginate(github, `/repos/${repo}/pulls/${number}/comments?since=${sinceParam(since - 1000)}`);
  const reviews = await paginate(github, `/repos/${repo}/pulls/${number}/reviews`);
  return { comments, reviews };
}

async function threadSpeaker(github, repo, number, since) {
  return personSince(reviewEntries(await reviewActivity(github, repo, number, since)), since);
}

async function threadsSettled(github, repo, number, since, readAt, label) {
  const activity = await reviewActivity(github, repo, number, since);
  const speaker = personSince(reviewEntries(activity), since);
  if (speaker !== undefined) {
    return spokeReason(speaker, label);
  }
  const opened = activity.comments.find((comment) => comment?.in_reply_to_id == null && !(Date.parse(comment?.created_at) < readAt - 1000));
  return opened === undefined ? undefined : `a review thread was opened by ${opened.user?.login ?? "an account"} while its reads ran`;
}

export const SESSION_LABELS = Object.freeze([...new Set(Object.values(ROUTES).map((entry) => entry?.label).filter((label) => typeof label === "string"))]);
const STOP_ACTIVITY = /^<!-- pr-unblock:lane-stopped activity=([a-z]+(?:-[a-z]+)*) -->$/;
const STOP_HEAD = /^- Head: `([0-9a-f]{40})`$/m;
const stopContext = (activity) => (activity === "resolve-conflicts" ? "pr-unblock/conflict" : `pr-unblock/${activity}`);

const SAME_HEAD_ONLY = Object.freeze(["dependency-workflow-unpinned"]);
const laneStatus = (statuses, context) => statuses.find((status) => status?.context === context && status?.creator?.login === "github-actions[bot]");

/**
 * The step output naming, space-separated, each head whose stop verifierMend
 * settled. pr-merge.yml's report-unarmed-status job clears its
 * pr-unblock/address-feedback failure with report-escalation.sh clear. The
 * label stays until a later run finds that success newer than the stop (the
 * same-head lift), so a clear that failed is requested again on the next run
 * while every mend condition still holds.
 */
export const MENDED_OUTPUT = "mended-heads";
const VERIFIER_MENDS = Object.freeze(["feedback-disputed", "feedback-untaken-threads", "feedback-uncertain"]);
const PASS_VERDICTS = Object.freeze(["pass", "pass-notes"]);
const SESSION_THREADS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          isResolved
          root: comments(first: 1) { nodes { author { ... on User { databaseId } ... on Bot { databaseId } } body createdAt originalCommit { oid } } }
          comments(first: 100) { totalCount nodes { createdAt author { __typename login } } }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

async function allThreads(github, repo, number) {
  const [owner, name] = repo.split("/");
  const all = [];
  let after = null;
  for (let page = 0; page < THREAD_PAGES; page += 1) {
    const threads = (await github("POST", "/graphql", { query: SESSION_THREADS_QUERY, variables: { owner, name, number, after } }))?.data?.repository?.pullRequest?.reviewThreads;
    if (!Array.isArray(threads?.nodes)) {
      return null;
    }
    for (const thread of threads.nodes) {
      const root = thread?.root?.nodes?.[0];
      const comments = thread?.comments;
      if (typeof thread?.isResolved !== "boolean" || root === undefined || !Array.isArray(comments?.nodes) || !(comments.totalCount <= comments.nodes.length)) {
        return null;
      }
      all.push({ resolved: thread.isResolved, root, comments: comments.nodes });
    }
    if (!threads.pageInfo?.hasNextPage) {
      return all;
    }
    after = threads.pageInfo.endCursor;
  }
  return null;
}

/**
 * Whether pr-verify settled the address-feedback `stops` routed to a session
 * label at `pull`'s head: { why } when every one of these holds, else
 * { reason } naming the first that does not.
 * - Every stop is at the current head with a VERIFIER_MENDS reason.
 * - The review threads read whole, none is unresolved, at least one opens
 *   with a pr-verify fail note (isVerifierRoot), and no other thread carries
 *   a lanes App comment written from the first fail note to the stop.
 * - From the first fail note's creation on, at least one body edit, and every
 *   body edit and issue connect or disconnect, is by a User whose id
 *   trusted-actors.json lists as a `human` (resolve-pr.mjs editedByPeople):
 *   no bot's or untrusted person's edit counts. resolve-pr.mjs loads here,
 *   not at the top, since ci-status's sparse checkout of this module holds
 *   none of its imports and only pr-merge reaches this.
 * - The gate's reader (one of the run's NATIVE_READS_PER_RUN) answers at the
 *   head with no verdict refusal and a pass or pass-notes there, and, when a
 *   fail note sits on that head, `supersededAtHead`: a counted pass after
 *   that FAIL gave way to it.
 */
async function verifierMend({ github, repo, pull, stops, bot, trusted, verify, reads }) {
  const head = pull.head.sha;
  const other = stops.find((stop) => stop.head !== head || !VERIFIER_MENDS.includes(stop.reason));
  if (other !== undefined) {
    return { reason: `${other.reason} at ${other.head} is not a stop pr-verify settles at this head` };
  }
  if (trusted === null) {
    return { reason: "the trusted-actor list did not read" };
  }
  const threads = await allThreads(github, repo, pull.number);
  if (threads === null) {
    return { reason: "the review threads did not read whole" };
  }
  const open = threads.filter((thread) => !thread.resolved).length;
  if (open > 0) {
    return { reason: `${open} review thread(s) are unresolved` };
  }
  const note = (thread) => isVerifierRoot({ authorId: thread.root.author?.databaseId, body: thread.root.body });
  const failAt = Math.min(...threads.filter(note).map((thread) => Date.parse(thread.root.createdAt)));
  if (!Number.isFinite(failAt)) {
    return { reason: "no pr-verify fail-note thread with a readable time" };
  }
  const stoppedAt = Math.max(...stops.map((stop) => stop.stoppedAt));
  const lane = (author) => author?.__typename === "Bot" && (author.login === bot || `${author.login}[bot]` === bot);
  const worked = threads.some(
    (thread) => !note(thread) && thread.comments.some((comment) => lane(comment?.author) && !(Date.parse(comment.createdAt) < failAt) && !(Date.parse(comment.createdAt) > stoppedAt)),
  );
  if (worked) {
    return { reason: "the lane answered a thread that is not a pr-verify fail note since the FAIL" };
  }
  const { editedByPeople } = await import("../pr-verify/resolve-pr.mjs");
  if (!(await editedByPeople(github, repo, pull.number, trusted, new Date(failAt).toISOString()))) {
    return { reason: "no trusted person edited the body since the FAIL, or someone else edited it or its links" };
  }
  if (reads.left <= 0) {
    return { reason: `the gate's reader waits: ${NATIVE_READS_PER_RUN} reader runs this run` };
  }
  reads.left -= 1;
  const evidence = await verify({ number: pull.number, headRefOid: head, baseRefOid: pull.base?.sha }, "C3");
  const passed = evidence?.head === head && evidence.refusal === null && PASS_VERDICTS.some((verdict) => evidence.atHead?.includes(verdict));
  const failedHere = threads.some((thread) => note(thread) && thread.root.originalCommit?.oid === head);
  if (!passed || (failedHere && evidence.supersededAtHead !== true)) {
    return { reason: `no counted pass at ${head} supersedes its FAIL (${verifyHold(evidence, head) ?? "the FAIL there stands"})` };
  }
  return { why: `pr-verify passed ${head} after a trusted body edit superseded its FAIL, and no review thread is open` };
}

async function sessionVerdict({ github, checks, repo, number, label, bot, trusted = null, verify, reads = { left: 0 } }) {
  const timeline = await paginate(github, `/repos/${repo}/issues/${number}/timeline`);
  const { labeled, since } = labelHistory(timeline, label, new Set());
  if (!isApp(labeled?.actor, bot)) {
    return { reason: `${label} was last added by ${labeled?.actor?.login ?? "no one on the timeline"}, not the lanes App` };
  }
  const stops = new Map();
  for (const item of timeline) {
    const activity = item.event === "commented" && isApp(item.user, bot) ? STOP_ACTIVITY.exec(lines(item.body)[0])?.[1] : undefined;
    if (activity !== undefined) {
      stops.set(activity, item);
    }
  }
  const routed = [];
  for (const [activity, item] of stops) {
    const stoppedAt = lastWrite(item);
    if (stoppedAt < since) {
      continue;
    }
    const body = String(item.body);
    const reason = REASON.exec(body)?.[1];
    const head = STOP_HEAD.exec(body)?.[1];
    if (reason === undefined || head === undefined || escalationActivity(reason) !== activity) {
      return { reason: `the ${activity} stop since ${label} went on names no reason, head or activity this script can read` };
    }
    if (ROUTES[reason].label === label) {
      routed.push({ activity, reason, head, stoppedAt });
    }
  }
  if (routed.length === 0) {
    return { reason: `no lane stop routed to ${label} since it went on` };
  }
  const guarded = async (fn) => {
    try {
      return await fn();
    } catch (error) {
      console.log(`::warning title=clear-escalations::#${number}: ${escapeCommand(error?.message ?? error)}`);
      return null;
    }
  };
  const why = [];
  const open = [];
  for (const stop of routed) {
    const context = stopContext(stop.activity);
    const statuses = await guarded(() => readStatuses(checks, repo, stop.head));
    if (statuses === null) {
      return { reason: `the statuses of ${stop.head} did not read` };
    }
    const own = laneStatus(statuses, context);
    if (own?.state === "success" && Date.parse(own.created_at) > stop.stoppedAt) {
      why.push(`${stop.reason} no longer fails ${context} at ${stop.head}`);
    } else {
      open.push({ ...stop, context, own });
    }
  }
  if (open.length === 0) {
    return { reason: null, why: why.join("; ") };
  }
  const pull = await guarded(() => github("GET", `/repos/${repo}/pulls/${number}`));
  const current = pull?.head?.sha;
  if (!SHA.test(String(current))) {
    return { reason: "the pull request's head did not read" };
  }
  if (routed.some(({ head }) => head === current)) {
    const mend = await guarded(() => verifierMend({ github, repo, pull, stops: open, bot, trusted, verify, reads }));
    if (mend?.why !== undefined) {
      why.push(mend.why);
      return { reason: null, why: why.join("; "), mended: current };
    }
    const { reason, context, head, own } = open[0];
    const state = own?.state === "success" ? "no success since the stop" : (own?.state ?? "no status");
    return { reason: `${reason} still fails ${context} at ${head} (${state}); not mended: ${mend?.reason ?? "a read failed"}` };
  }
  const now = await guarded(() => readStatuses(checks, repo, current));
  if (now === null) {
    return { reason: `the statuses of ${current} did not read` };
  }
  for (const { reason, context, head } of open) {
    if (SAME_HEAD_ONLY.includes(reason)) {
      return { reason: `${reason} stopped at ${head}, and only its lane's clear on that head lifts ${label}: green checks do not judge its workflow change` };
    }
    const newest = laneStatus(now, context);
    if (newest !== undefined && newest.state !== "success") {
      return { reason: `${reason}'s ${context} reads ${newest.state} at the new head ${current}` };
    }
    why.push(`${reason} stopped at ${head}, and no ${context} status fails at the new head ${current}`);
  }
  const held = await checksHeld((fn) => guarded(() => fn(checks)), repo, current);
  if (held !== null) {
    return { reason: `${label} stays at the new head: ${held}` };
  }
  why.push(`no check other than ${AGGREGATE} fails, runs or was cancelled at ${current}`);
  return { reason: null, why: why.join("; ") };
}

async function labeledPulls(github, repo, label) {
  return (await paginate(github, `/repos/${repo}/issues?state=open&labels=${encodeURIComponent(label)}`)).filter(
    (item) => item.pull_request && Number.isSafeInteger(item.number) && item.number > 0,
  );
}

async function clearSessionLabels({ github, checks, repo, bot, runNumber, trusted, verify, reads, mended }) {
  let failed = 0;
  for (const label of SESSION_LABELS) {
    for (const [index, { number }] of rotated(await labeledPulls(github, repo, label), runNumber).entries()) {
      if (index >= SESSION_CHECKS_PER_RUN) {
        console.log(`clear-escalations: #${number} ${label} not checked: ${SESSION_CHECKS_PER_RUN} read this run`);
        continue;
      }
      try {
        const result = await sessionVerdict({ github, checks, repo, number, label, bot, trusted, verify, reads });
        if (result.reason !== null) {
          console.log(`clear-escalations: #${number} ${label} kept: ${result.reason}`);
          continue;
        }
        if (result.mended !== undefined) {
          mended.push(result.mended);
          console.log(`clear-escalations: #${number} ${label} kept until its status clears: ${result.why}`);
          continue;
        }
        await github("DELETE", `/repos/${repo}/issues/${number}/labels/${encodeURIComponent(label)}`);
        console.log(`clear-escalations: #${number} ${label} cleared: ${result.why}`);
      } catch (error) {
        failed += 1;
        reportError(number, error);
      }
    }
  }
  return failed;
}

function trustedIds(env) {
  try {
    return new Set(loadTrustedList(trustedListPath(env, env.TRUSTED_ACTORS_PATH)).humans);
  } catch (error) {
    console.log(`clear-escalations: no stop clears on a trusted move: ${escapeCommand(error?.message ?? error)}`);
    return null;
  }
}

export async function main({ env = process.env, github, checks, verify, reader, laneReads } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("clear-escalations: the lanes kill switch stops this run; nothing read or removed");
      return 0;
    }
    const repo = env.GITHUB_REPOSITORY;
    const bot = env.LANES_BOT_LOGIN || DEFAULT_BOT;
    const label = humanGatedLabelFrom(env.TRACKER_CONFIG || ".base/docs/conventions/work-items.yaml");
    const client = (token) => createGitHub({ token, apiUrl: env.GITHUB_API_URL || undefined });
    github ??= client(env.GH_TOKEN);
    checks ??= client(env.CHECKS_TOKEN);
    const download = artifactDownload({ token: env.CHECKS_TOKEN, repo, apiUrl: env.GITHUB_API_URL || undefined });
    const checkers = new Map();
    const checkerFor = (number) => {
      if (!checkers.has(number)) {
        checkers.set(number, restLaneChecker({ read: checks, download, repo, pr: number, laneReads }));
      }
      return checkers.get(number);
    };
    verify ??= pythonVerify(env);
    const reads = { left: NATIVE_READS_PER_RUN };
    reader = env.BABYSIT_VERIFY_GH_TOKEN ? (reader ?? client(env.BABYSIT_VERIFY_GH_TOKEN)) : null;
    const trusted = trustedIds(env);
    const tip = SHA.test(env.MAIN_TIP_SHA ?? "") ? null : await github("GET", `/repos/${repo}/git/ref/heads/main`);
    const mainSha = tip === null ? env.MAIN_TIP_SHA : tip?.ref === "refs/heads/main" ? tip.object?.sha : undefined;
    if (!SHA.test(String(mainSha))) {
      throw new Error("main's tip has no commit SHA");
    }
    let failed = 0;
    let cleared = 0;
    for (const { number, labels } of rotated(await labeledPulls(github, repo, label), Number(env.GITHUB_RUN_NUMBER))) {
      if (outsideActorHeld(labels)) {
        console.log(`clear-escalations: #${number} kept: ${OUTSIDE_ACTOR_KEPT}`);
        continue;
      }
      if (cleared >= CLEARS_PER_RUN) {
        console.log(`clear-escalations: #${number} not checked: ${CLEARS_PER_RUN} cleared this run`);
        continue;
      }
      try {
        const readAt = Date.now();
        const result = await verdict({ github, checks, repo, number, label, bot, mainSha, lanePrs: env.LANE_PRS, verify, reads, reader, trusted, checkerFor });
        if (result.reason !== null) {
          console.log(`clear-escalations: #${number} kept: ${result.reason}`);
          continue;
        }
        const unsettled = await threadsSettled(github, repo, number, result.since, readAt, label);
        if (unsettled !== undefined) {
          console.log(`clear-escalations: #${number} kept: ${unsettled}`);
          continue;
        }
        const recheck = async () => (result.recorded === STALE_HOLD ? await staleHoldMoved({ github, repo, number, label, result, check: checkerFor(number) }) : null);
        let moved = await recheck();
        const base = `/repos/${repo}/issues/${number}`;
        if (moved === null && !result.explained) {
          await github("POST", `${base}/comments`, { body: clearedComment(result.recorded, result.head, result.why, label) });
          moved = await recheck();
        }
        if (moved !== null) {
          console.log(`clear-escalations: #${number} kept: ${moved}`);
          continue;
        }
        await github("DELETE", `${base}/labels/${encodeURIComponent(label)}`);
        cleared += 1;
        console.log(`clear-escalations: #${number} cleared: ${result.recorded} no longer holds at ${result.head}`);
      } catch (error) {
        failed += 1;
        reportError(number, error);
      }
    }
    const mended = [];
    failed += await clearSessionLabels({ github, checks, repo, bot, runNumber: Number(env.GITHUB_RUN_NUMBER), trusted, verify, reads, mended });
    if (mended.length > 0 && env.GITHUB_OUTPUT) {
      appendFileSync(env.GITHUB_OUTPUT, `${MENDED_OUTPUT}=${mended.join(" ")}\n`);
    }
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=clear-escalations::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
