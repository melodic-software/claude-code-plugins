#!/usr/bin/env node
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { GitHubError, createGitHub, paginate } from "../lib/github-client.mjs";
import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { budgetLatch, rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { postingRunId } from "../../actions/report-check-run/posting-run.mjs";
import { callers, listedJob } from "../lib/lane-registry.mjs";
import { changedPaths } from "./merge-holds.mjs";
import { PR_UNBLOCK_TITLE } from "../lib/run-title.mjs";
import { ACTIONS_BOT_ID, LANES_APP_LOGIN as DEFAULT_BOT } from "../lib/lane-vocabulary.mjs";

const DEPENDABOT_ID = 49699333;
const RETRY_MS = 60 * 60_000;
const STEP = "Request the lane token";
const WRITE_RUNNER = ".github/workflows/pr-run-activity-write.yml";
const LANES = Object.freeze({
  "pr-unblock.yml": {
    events: ["workflow_dispatch"],
    after: "pr-merge pushes an empty commit so the next pr-unblock run uses main's files.",
    starts:
      " The push starts no run itself: the conflict-resolution run starts at the next push to main or half-hourly `pr-unblock-dispatch` tick, or when a listed person runs it by hand, and an address-feedback run can start after both review lanes review the new head, if an unresolved thread is left for it.",
    files: [
      ".github/workflows/pr-unblock.yml",
      WRITE_RUNNER,
      ".github/workflows/pr-unblock-dispatch.yml",
      ".github/workflows/pr-dispatch-feedback.yml",
    ],
    writeCallers: callers("pr-unblock.yml", `./${WRITE_RUNNER}`).map((id) => listedJob("pr-unblock.yml", id, "run")),
    transientActivities: ["address-feedback"],
    dispatcherRefires: ["address-feedback"],
    transientStarts:
      " The push starts no run itself: both review lanes review the new head, and an address-feedback run starts after them if an unresolved thread is left for it.",
  },
});
const REFUSED =
  /^lane-token-denied: the broker answered 403 with reason workflow-modified: (\.github\/workflows\/[A-Za-z0-9._-]+\.yml) differs from refs\/heads\/main$/;
const TRANSIENT =
  /^(broker-unreachable): the lanes token broker gave no response|^lane-token-denied: the broker answered (5[0-9]{2}) with reason ([a-z]+(?:-[a-z]+)*)|^(the OIDC token request failed: (?:HTTP 5[0-9]{2}|curl exit [0-9]{1,2})) on attempt /;
export const TRANSIENT_PER_HEAD = 2;
const TRANSIENT_MARKER = /^<!-- pr-lane-refire transient run ([1-9][0-9]{0,19}) tree ([0-9a-f]{40}) head ([0-9a-f]{40}) -->/;
const MARKER = /^<!-- pr-lane-refire (\.github\/workflows\/[A-Za-z0-9._-]+\.yml)@([0-9a-f]{40}) head ([0-9a-f]{40}) -->/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const HEAD_REF = /^[A-Za-z0-9._/-]+$/;
const SHA = /^[0-9a-f]{40}$/;
export const LOOKBACK_HOURS = 72;
export const REFIRES_PER_RUN = 5;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const reportError = (what, error) =>
  console.log(`::error title=refire-refused::${what}: ${escapeCommand(error?.message ?? error)}`);
const reportWarning = (what, error) =>
  console.log(`::warning title=refire-refused::${what}: ${escapeCommand(error?.message ?? error)}`);
class PullFailure extends Error {}
class Fatal extends Error {
  constructor(what, error) {
    super(`${what}: ${error?.message ?? error}`);
  }
}

export function skipBranches(path) {
  if (!path) {
    throw new Error("RESOLVED_CONFIG_PATH is not set");
  }
  const skip = JSON.parse(readFileSync(path, "utf8"))?.merge?.["refire-skip-branches"];
  if (!Array.isArray(skip) || !skip.every((ref) => typeof ref === "string" && ref !== "")) {
    throw new Error("merge.refire-skip-branches in the resolved config is not a list of branch names");
  }
  return new Set(skip);
}

export function qualifies(pull, repo, ids) {
  return (
    pull?.state === "open" &&
    pull.draft !== true &&
    pull.base?.ref === "main" &&
    pull.head?.repo?.full_name === repo &&
    HEAD_REF.test(pull.head.ref ?? "") &&
    SHA.test(pull.head.sha ?? "") &&
    Number.isInteger(pull.user?.id) &&
    ids.has(pull.user.id) &&
    pull.user.id !== DEPENDABOT_ID
  );
}

export const refireComment = (path, blob, head, lane) =>
  `<!-- pr-lane-refire ${path}@${blob} head ${head} -->\nA lane run on this pull request's head failed because the token broker refused it as workflow-modified: \`${path}\` changed on main after the run's event, and a rerun keeps the old file. ${LANES[lane].after} It does this once per version of that file, so if a run fails the same way again, a person looks at it.${LANES[lane].starts ?? ""}`;

export const transientComment = (label, run, tree, head, lane) =>
  `<!-- pr-lane-refire transient run ${run} tree ${tree} head ${head} -->\nA lane run on this pull request's head failed to get its lane token (\`${label}\`), a failure the next run may not meet, and no dispatcher retries this activity on the same head. pr-merge pushes an empty commit so the activity can start again. It does this once per failed run and at most ${TRANSIENT_PER_HEAD} times per change, so if runs keep failing the same way, a person looks at it.${LANES[lane].transientStarts ?? ""}`;

const commitMessage = (refusal) =>
  refusal.kind === "transient"
    ? `chore: start the lane checks again after a lane token failure\n\nA lane run on the previous head could not get its lane token (${refusal.label}). This commit changes no file.`
    : `chore: start the lane checks again on main's workflow files\n\nThe token broker refused a lane run on the previous head as workflow-modified (${refusal.path}). This commit changes no file.`;

async function failedRuns(actions, repo, file, now) {
  const since = new Date(now - LOOKBACK_HOURS * 3_600_000).toISOString().replace(/\.\d{3}Z$/, "Z");
  const path = `/repos/${repo}/actions/workflows/${file}/runs?status=failure&created=${encodeURIComponent(`>=${since}`)}`;
  const runs = [];
  for (let page = 1; page <= 10; page += 1) {
    const batch = (await actions("GET", `${path}&per_page=100&page=${page}`))?.workflow_runs;
    if (!Array.isArray(batch)) {
      throw new Error(`the ${file} run listing has an unexpected shape`);
    }
    runs.push(...batch);
    if (batch.length < 100) {
      return runs;
    }
  }
  throw new Error(`the ${file} run listing has more than 10 pages`);
}

async function pullOfRun({ actions, repo, run, lane, byNumber, ids, appId, mainSha }) {
  if (!lane.events.includes(run.event) || run.repository?.full_name !== repo) {
    return undefined;
  }
  const listed = (user) => Number.isInteger(user?.id) && ids.has(user.id) && user.id !== appId;
  const dispatcher = (user) => run.event === "workflow_dispatch" && user?.id === ACTIONS_BOT_ID && run.run_attempt === 1;
  if (![run.actor, run.triggering_actor].every((user) => listed(user) || dispatcher(user))) {
    return undefined;
  }
  const number = PR_UNBLOCK_TITLE.exec(String(run.display_title ?? ""))?.[2];
  const pull = number === undefined || run.head_branch !== "main" ? undefined : byNumber.get(Number(number));
  if (pull === undefined || !SHA.test(String(run.head_sha))) {
    return undefined;
  }
  const compare = await actions("GET", `/repos/${repo}/compare/${run.head_sha}...${mainSha}`);
  if (compare?.status !== "ahead" && compare?.status !== "identical") {
    return undefined;
  }
  const checks = (await actions("GET", `/repos/${repo}/commits/${pull.head.sha}/check-runs?per_page=100`))?.check_runs;
  const linked = Array.isArray(checks) && checks.some((check) => check.conclusion === "failure" && postingRunId(check) === String(run.id));
  return linked ? pull : undefined;
}

async function refusedFile({ actions, repo, run, lane }) {
  const activity = PR_UNBLOCK_TITLE.exec(String(run.display_title ?? ""))?.[1];
  const jobs = (await actions("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
  if (!Array.isArray(jobs)) {
    throw new Error(`run ${run.id}'s jobs have an unexpected shape`);
  }
  const readAnnotations = (id) => actions("GET", `/repos/${repo}/check-runs/${id}/annotations?per_page=100`);
  const why = await tokenRefusal({ jobs, readAnnotations, lane, activity });
  return why?.kind === "workflow-modified" && (lane.dispatcherRefires ?? []).includes(activity) ? null : why;
}

export async function tokenRefusal({ jobs, readAnnotations, lane = LANES["pr-unblock.yml"], activity }) {
  const transientOk = (lane.transientActivities ?? []).includes(activity);
  let transient = null;
  for (const job of jobs) {
    const writer = lane.writeCallers.some(({ id, name }) => job.name === name || job.name === id);
    const token = (Array.isArray(job.steps) ? job.steps : []).find((step) => step.name === STEP);
    const failedAtToken = writer && job.conclusion === "failure" && (token === undefined || token.conclusion === "failure");
    if (!failedAtToken || !Number.isSafeInteger(job.id)) {
      continue;
    }
    const annotations = await readAnnotations(job.id);
    for (const annotation of Array.isArray(annotations) ? annotations : []) {
      if (annotation.annotation_level !== "failure") {
        continue;
      }
      const message = String(annotation.message ?? "");
      const path = REFUSED.exec(message)?.[1];
      if (path !== undefined && lane.files.includes(path)) {
        return { kind: "workflow-modified", path };
      }
      const match = transientOk && transient === null ? TRANSIENT.exec(message) : null;
      if (match !== null) {
        transient = { kind: "transient", label: match[1] ?? match[4] ?? `lane-token-denied ${match[2]} ${match[3]}` };
      }
    }
  }
  return transient;
}

async function refusal({ github, repo, pull, refused, run, blob, bot, lane, now, mainSha }) {
  const changed = await changedPaths(github, repo, await github("GET", `/repos/${repo}/compare/${mainSha}...${pull.head.sha}`), pull.head.sha, lane.files);
  if (changed === null) {
    return { reason: "its changed files cannot be listed in full" };
  }
  const touched = changed[0];
  if (touched !== undefined) {
    return { reason: `it changes ${touched}` };
  }
  const comments = (await paginate(github, `/repos/${repo}/issues/${pull.number}/comments`)).filter((comment) => comment.user?.login === bot);
  if (refused.kind === "transient") {
    return transientRefusal({ github, repo, pull, run, comments, now });
  }
  const { path } = refused;
  const markers = comments
    .map((comment) => ({ match: MARKER.exec(String(comment.body ?? "")), at: Date.parse(comment.created_at) }))
    .filter(({ match }) => match !== null && match[1] === path && match[2] === blob);
  if (markers.some(({ match }) => match[3] !== pull.head.sha)) {
    return { reason: `already re-fired for ${path} at ${blob}` };
  }
  if (markers.some(({ at }) => !(now - at < RETRY_MS))) {
    return { reason: `its push for ${path} at ${blob} did not land; a person looks`, warn: true };
  }
  return { reason: null, recorded: markers.length > 0 };
}

async function transientRefusal({ github, repo, pull, run, comments, now }) {
  const tree = await treeOf(github, repo, pull.head.sha);
  const markers = comments
    .map((comment) => ({ match: TRANSIENT_MARKER.exec(String(comment.body ?? "")), at: Date.parse(comment.created_at) }))
    .filter(({ match }) => match !== null);
  const mine = markers.filter(({ match }) => Number(match[1]) === run);
  if (mine.some(({ match }) => match[3] !== pull.head.sha)) {
    return { reason: `already re-fired for run ${run}` };
  }
  const others = new Set(markers.filter(({ match }) => match[2] === tree && Number(match[1]) !== run).map(({ match }) => match[1]));
  if (others.size >= TRANSIENT_PER_HEAD) {
    return { reason: `re-fired ${others.size} times for this change after lane token failures; a person looks`, warn: true };
  }
  if (mine.some(({ at }) => !(now - at < RETRY_MS))) {
    return { reason: `its push for run ${run} did not land; a person looks`, warn: true };
  }
  return { reason: null, recorded: mine.length > 0, tree };
}

async function treeOf(github, repo, sha) {
  const tree = (await github("GET", `/repos/${repo}/git/commits/${sha}`))?.tree?.sha;
  if (!SHA.test(String(tree))) {
    throw new Error(`the head ${sha} has no tree`);
  }
  return tree;
}

async function headTree(github, repo, pull) {
  const current = await github("GET", `/repos/${repo}/pulls/${pull.number}`);
  if (current?.head?.sha !== pull.head.sha || current.head.ref !== pull.head.ref || current.state !== "open" || current.draft === true || current.base?.ref !== "main") {
    throw new PullFailure("the PR changed since it was listed; nothing pushed");
  }
  return treeOf(github, repo, pull.head.sha);
}

async function pushEmptyCommit(github, repo, pull, why, tree) {
  const commit = await github("POST", `/repos/${repo}/git/commits`, {
    message: commitMessage(why),
    tree,
    parents: [pull.head.sha],
  });
  if (!SHA.test(String(commit?.sha))) {
    throw new Error("the new commit has no SHA");
  }
  const ref = pull.head.ref.split("/").map(encodeURIComponent).join("/");
  try {
    await github("PATCH", `/repos/${repo}/git/refs/heads/${ref}`, { sha: commit.sha, force: false });
  } catch (error) {
    if (!(error instanceof GitHubError && (error.status === 409 || error.status === 422))) {
      throw error;
    }
    let tip;
    try {
      tip = (await github("GET", `/repos/${repo}/git/ref/heads/${ref}`))?.object?.sha;
    } catch (reread) {
      if (reread instanceof GitHubError && reread.status === 404) {
        throw new PullFailure(error.message);
      }
      throw reread;
    }
    if (!SHA.test(String(tip))) {
      throw new Error(`${error.message}; the branch's tip cannot be read`);
    }
    if (tip !== pull.head.sha) {
      throw new PullFailure(error.message);
    }
    throw new Error(`${error.message}; the branch is still at ${tip}`);
  }
  return commit.sha;
}

export const actionsClient = (env, { latch = rateLimitLatch, fetchImpl } = {}) =>
  createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, latch: budgetLatch("github-token", latch), ...(fetchImpl ? { fetchImpl } : {}) });

export async function main({ env = process.env, github, actions, now = Date.now() } = {}) {
  let outcome = null;
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    if (env.KILL_SWITCH !== "proceed") {
      console.log("refire-refused: the lanes kill switch stops this run; nothing read or pushed");
      return 0;
    }
    const repo = env.GITHUB_REPOSITORY;
    const bot = env.LANES_BOT_LOGIN || DEFAULT_BOT;
    const { ids } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    const appId = /^[1-9][0-9]{0,14}$/.test(env.LANES_APP_SENDER_ID ?? "") ? Number(env.LANES_APP_SENDER_ID) : null;
    if (appId === null) {
      throw new Error("LANES_APP_SENDER_ID is not a positive integer");
    }
    const owned = skipBranches(env.RESOLVED_CONFIG_PATH);
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    actions ??= actionsClient(env);

    let tagAbsent = false;
    try {
      await github("GET", `/repos/${repo}/git/ref/tags/main`);
    } catch (error) {
      tagAbsent = error instanceof GitHubError && error.status === 404;
    }
    if (!tagAbsent) {
      throw new Error("a tag named main exists, or its absence could not be read; nothing pushed");
    }
    const tip = SHA.test(env.MAIN_TIP_SHA ?? "") ? null : await github("GET", `/repos/${repo}/git/ref/heads/main`);
    const mainSha = tip === null ? env.MAIN_TIP_SHA : tip?.ref === "refs/heads/main" ? tip.object?.sha : undefined;
    if (!SHA.test(String(mainSha))) {
      throw new Error("main's tip has no commit SHA");
    }

    const listed = (await paginate(github, `/repos/${repo}/pulls?state=open&base=main`)).filter((pull) => qualifies(pull, repo, ids));
    const open = [];
    outcome = { refired: 0, failed: 0, skippedOwned: 0, deferred: 0 };
    for (const pull of listed) {
      if (owned.has(pull.head.ref)) {
        outcome.skippedOwned += 1;
        console.log(`refire-refused: #${pull.number} not re-fired: its branch ${pull.head.ref} is owned by a workflow that rebuilds it`);
      } else {
        open.push(pull);
      }
    }
    const byNumber = new Map(open.map((pull) => [pull.number, pull]));
    let listingFailed = false;
    const refused = new Map();
    for (const [file, lane] of Object.entries(LANES)) {
      let runs;
      try {
        runs = await failedRuns(actions, repo, file, now);
      } catch (error) {
        listingFailed = true;
        reportError(file, error);
        continue;
      }
      for (const run of runs) {
        try {
          const pull = await pullOfRun({ actions, repo, run, lane, byNumber, ids, appId, mainSha });
          if (pull === undefined || refused.has(pull.number)) {
            continue;
          }
          const why = await refusedFile({ actions, repo, run, lane });
          if (why !== null) {
            refused.set(pull.number, { pull, why, file, lane, run: run.id });
          }
        } catch (error) {
          throw new Fatal(`run ${run.id}`, error);
        }
      }
    }
    const blobs = new Map();
    const blobOf = async (path) => {
      if (!blobs.has(path)) {
        const sha = (await github("GET", `/repos/${repo}/contents/${path}?ref=${mainSha}`))?.sha;
        if (!SHA.test(String(sha))) {
          throw new Error(`${path} on main has no blob SHA`);
        }
        blobs.set(path, sha);
      }
      return blobs.get(path);
    };
    const ready = [];
    for (const [number, { pull, why, file, lane, run }] of [...refused].sort((a, b) => a[0] - b[0])) {
      const blob = why.kind === "transient" ? null : await blobOf(why.path);
      let verdict;
      try {
        verdict = await refusal({ github, repo, pull, refused: why, run, blob, bot, lane, now, mainSha });
      } catch (error) {
        throw new Fatal(`#${number}`, error);
      }
      const { reason, recorded, warn } = verdict;
      if (reason !== null) {
        console.log(`${warn ? "::warning title=refire-refused::" : "refire-refused: "}#${number} not re-fired: ${reason}`);
        continue;
      }
      ready.push({ pull, why, file, blob, recorded, run });
    }
    const deferred = ready.slice(REFIRES_PER_RUN);
    outcome.deferred = deferred.length;
    for (const { pull } of deferred) {
      console.log(`refire-refused: #${pull.number} deferred: ${REFIRES_PER_RUN} re-fires this run`);
    }
    for (const { pull, why, file, blob, recorded, run } of ready.slice(0, REFIRES_PER_RUN)) {
      try {
        const tree = await headTree(github, repo, pull);
        if (!recorded) {
          const body =
            why.kind === "transient" ? transientComment(why.label, run, tree, pull.head.sha, file) : refireComment(why.path, blob, pull.head.sha, file);
          await github("POST", `/repos/${repo}/issues/${pull.number}/comments`, { body });
        }
        const sha = await pushEmptyCommit(github, repo, pull, why, tree);
        const cause = why.kind === "transient" ? `failed at the token step (${why.label})` : `was refused for ${why.path} at ${blob}`;
        const line = `#${pull.number} moved from ${pull.head.sha} to ${sha} after run ${run} ${cause}`;
        outcome.refired += 1;
        console.log(`refire-refused: ${line}`);
        if (env.GITHUB_STEP_SUMMARY) {
          appendFileSync(env.GITHUB_STEP_SUMMARY, `- refire-refused: ${line}\n`);
        }
      } catch (error) {
        if (!(error instanceof PullFailure)) {
          throw new Fatal(`#${pull.number}`, error);
        }
        outcome.failed += 1;
        reportWarning(`#${pull.number}`, error);
      }
    }
    return listingFailed ? 1 : 0;
  } catch (error) {
    console.log(`::error title=refire-refused::${escapeCommand(error?.message ?? error)}`);
    return 1;
  } finally {
    if (outcome !== null) {
      const line = `outcome re-fired=${outcome.refired} failed=${outcome.failed} skipped-owned=${outcome.skippedOwned} deferred=${outcome.deferred}`;
      console.log(`refire-refused: ${line}`);
      if (env.GITHUB_STEP_SUMMARY) {
        appendFileSync(env.GITHUB_STEP_SUMMARY, `- refire-refused: ${line}\n`);
      }
    }
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
