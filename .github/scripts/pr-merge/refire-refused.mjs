#!/usr/bin/env node
// refire-refused.mjs: gives a pull request a new head when a pr-unblock run
// on its current head failed at "Request the lane token" because the token
// broker refused it as workflow-modified. A rerun keeps its first event's
// workflow files, so no rerun can pass; after the new head, the next
// pr-unblock run uses main's files. No model.
//
// The new head is an empty commit: the head's own tree, the head as its only
// parent, made with the lanes App token through the Git Data API and moved
// onto the branch as a fast-forward only. update-branch would merge main in,
// which here always brings a .github/workflows/ change, and the lane token
// cannot write one (docs/conventions/pr-pipeline/pr-run-activity.md,
// `workflow-staged`).
//
// Only an open, non-draft pull request into main qualifies whose head
// check-trusted-trigger would trust: a branch of this repository, a well-formed
// head ref and SHA, and an author on the trusted-actor list. Dependabot's are
// left alone: a commit on its branch stops its own rebases, and pr-merge merges
// a Dependabot PR only while every commit is Dependabot's.
// The refused run counts only when a listed account other than the lanes App
// started it and any rerun (a dispatch: github-actions[bot] on its first
// attempt, its commit on main), and only when the PR changes none of the files
// the broker compares for that lane: a run then took them from main, so the
// refusal it reports came from main's code, and an empty commit can help.
//
// Each pull request is re-fired at most once per version (blob SHA on main) of
// the workflow file the broker named, recorded in a marker comment the App
// posts before the push. A marker whose head is the current head means the push
// did not land, so only the push is retried; any other marker for that version
// stops it, so a run that keeps failing the same way waits for a person or a
// new workflow version.
//
// A run of an activity no dispatcher tick re-dispatches (the lane's
// `transientActivities`; the pr-unblock-dispatch tick dispatches the others,
// so no head gets two retry paths) also gets the empty commit
// when its token step failed transiently: `broker-unreachable`, or
// `lane-token-denied` with a 5xx status. No 403 reason is transient, so a 403
// other than workflow-modified is never re-fired. The new head starts the
// review lanes, whose completion is the activity's own fresh event. Such a
// re-fire is recorded per run in a `transient` marker, and is capped at one
// per failed run and `TRANSIENT_PER_HEAD` per head tree (an empty commit keeps
// the tree, so a broker outage cannot chain re-fires on one change).
//
// Environment:
//   GH_TOKEN             the lane App token (contents and pull-requests write)
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN (actions: read, checks: read)
//   GITHUB_REPOSITORY    owner/repo
//   KILL_SWITCH          `proceed` from the kill-switch step; anything else stops
//   TRUSTED_ACTORS_PATH  trusted-actors.json from the default branch tip
//   LANES_BOT_LOGIN      the lanes App bot login, the only marker author this
//                        trusts (default melodic-automation-lanes[bot])
//   LANES_APP_SENDER_ID  the lanes App sender id; a run it started never counts
//   RESOLVED_CONFIG_PATH resolve-config's output; its merge.refire-skip-branches
//                        lists the branches a workflow owns and rebuilds, whose
//                        PRs this never comments on or pushes to
//   GITHUB_STEP_SUMMARY  each push and the outcome are listed there when set
//   GITHUB_API_URL
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { GitHubError, createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { budgetLatch, rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { postingRunId } from "../../actions/report-check-run/posting-run.mjs";
import { LANES_APP_LOGIN as DEFAULT_BOT } from "./merge-holds.mjs";

const DEPENDABOT_ID = 49699333;
// github-actions[bot], the actor of a run a GITHUB_TOKEN dispatch started.
const ACTIONS_BOT_ID = 41898282;
// A marker at the current head whose push has not landed within this long is
// left to a person, so a push that keeps failing is not retried for days.
const RETRY_MS = 60 * 60_000;
const STEP = "Request the lane token";
const WRITE_RUNNER = ".github/workflows/pr-run-activity-write.yml";
// Each lane workflow, the event its runs on a PR head come from, and the files
// the broker compares for it (the caller, the write runner, a dispatcher), and
// what the marker comment says starts after the empty commit.
const LANES = Object.freeze({
  // GitHub runs no pull_request workflow on a conflicting PR, and
  // pr-unblock-dispatch runs only on a push to main, its half-hourly tick or a
  // listed person's dispatch, so the empty commit starts no conflict-resolution
  // run itself.
  "pr-unblock.yml": {
    events: ["workflow_dispatch"],
    after: "pr-merge pushes an empty commit so the next pr-unblock run uses main's files.",
    starts:
      " The push starts no run itself: the conflict-resolution run starts at the next push to main or half-hourly `pr-unblock-dispatch` tick, or when a listed person runs it by hand, and an address-feedback run can start after both review lanes review the new head, if an unresolved thread is left for it.",
    files: [
      ".github/workflows/pr-unblock.yml",
      WRITE_RUNNER,
      ".github/workflows/pr-unblock-dispatch.yml",
      ".github/workflows/pr-feedback-dispatch.yml",
    ],
    // The jobs that call the write runner, whose `run` job alone requests the
    // lane token; the jobs API names each `<caller> / run`.
    writeCallers: [
      "apply-conflict-patch",
      "apply-feedback-patch",
      "publish-feedback",
      "apply-dependency-patch",
      "apply-dependency-verdict",
      "apply-patch",
      "apply-patch-rung-up",
      "apply-shared-copies",
      "report-escalation",
    ],
    // The activities the pr-unblock-dispatch tick does not dispatch: it
    // dispatches resolve-conflicts, review-dependency, fix-ci and
    // sync-shared-copies itself
    // (pr-unblock/dispatch.mjs), while address-feedback starts only when the
    // review lanes finish a head, and a failed check run there holds the head
    // (pr-unblock/feedback-dispatch.mjs).
    transientActivities: ["address-feedback"],
    transientStarts:
      " The push starts no run itself: both review lanes review the new head, and an address-feedback run starts after them if an unresolved thread is left for it.",
  },
});
const REFUSED =
  /^lane-token-denied: the broker answered 403 with reason workflow-modified: (\.github\/workflows\/[A-Za-z0-9._-]+\.yml) differs from refs\/heads\/main$/;
// A token step that failed for a reason the broker or the network may not
// give next time (request-lane-token/action.yml): no response at all, or a
// 5xx after the action's own retries. Group 1 is the label a marker records.
const TRANSIENT =
  /^(broker-unreachable): the lanes token broker gave no response|^lane-token-denied: the broker answered (5[0-9]{2}) with reason ([a-z]+(?:-[a-z]+)*)/;
// At most this many transient re-fires per head tree (judgment, owner decision
// on #8446: two per head).
export const TRANSIENT_PER_HEAD = 2;
const TRANSIENT_MARKER = /^<!-- pr-lane-refire transient run ([1-9][0-9]{0,19}) tree ([0-9a-f]{40}) head ([0-9a-f]{40}) -->/;
const MARKER = /^<!-- pr-lane-refire (\.github\/workflows\/[A-Za-z0-9._-]+\.yml)@([0-9a-f]{40}) head ([0-9a-f]{40}) -->/;
const DISPATCH_TITLE = /^pr-unblock ([a-z]+(?:-[a-z]+)*) #([1-9][0-9]{0,9})$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
// check-trusted-trigger's head checks.
const HEAD_REF = /^[A-Za-z0-9._/-]+$/;
const SHA = /^[0-9a-f]{40}$/;
// A failed run stays on the head until the head moves; three days covers a
// weekend of failures (judgment).
export const LOOKBACK_HOURS = 72;
// Each re-fire starts every pull_request workflow on the PR again (judgment).
export const REFIRES_PER_RUN = 5;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const reportError = (what, error) =>
  console.log(`::error title=refire-refused::${what}: ${escapeCommand(error?.message ?? error)}`);
// A failure that concerns one PR alone warns and leaves the others to go on:
// the PR changed since the listing, or its branch moved or went away under
// the push (a 409 or 422 on the ref update with the branch since read at
// another SHA or gone; run 41065454536's 422 on release/plugins). Any other
// failure would hit every PR the same way (an auth refusal, a 5xx after
// retries, any error on the commit write), so it stops the run and fails the
// step.
const reportWarning = (what, error) =>
  console.log(`::warning title=refire-refused::${what}: ${escapeCommand(error?.message ?? error)}`);
class PullFailure extends Error {}
class Fatal extends Error {
  constructor(what, error) {
    super(`${what}: ${error?.message ?? error}`);
  }
}

// merge.refire-skip-branches from resolve-config's output: the head refs a
// workflow owns and rebuilds, where an empty commit would race its rebuild.
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

// Whether check-trusted-trigger would trust this PR's head, and the lane may
// push to it.
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

// `lane` is the lane's workflow file, a key of LANES.
export const refireComment = (path, blob, head, lane) =>
  `<!-- pr-lane-refire ${path}@${blob} head ${head} -->\nA lane run on this pull request's head failed because the token broker refused it as workflow-modified: \`${path}\` changed on main after the run's event, and a rerun keeps the old file. ${LANES[lane].after} It does this once per version of that file, so if a run fails the same way again, a person looks at it.${LANES[lane].starts ?? ""}`;

// The marker and comment for a transient token-step failure: `label` is
// TRANSIENT's label, `run` the failed run's id.
export const transientComment = (label, run, tree, head, lane) =>
  `<!-- pr-lane-refire transient run ${run} tree ${tree} head ${head} -->\nA lane run on this pull request's head failed to get its lane token (\`${label}\`), a failure the next run may not meet, and no dispatcher retries this activity on the same head. pr-merge pushes an empty commit so the activity can start again. It does this once per failed run and at most ${TRANSIENT_PER_HEAD} times per change, so if runs keep failing the same way, a person looks at it.${LANES[lane].transientStarts ?? ""}`;

const commitMessage = (refusal) =>
  refusal.kind === "transient"
    ? `chore: start the lane checks again after a lane token failure\n\nA lane run on the previous head could not get its lane token (${refusal.label}). This commit changes no file.`
    : `chore: start the lane checks again on main's workflow files\n\nThe token broker refused a lane run on the previous head as workflow-modified (${refusal.path}). This commit changes no file.`;

// Failed runs of `file` created in the lookback window.
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

// The open PR whose current head the run is about, or undefined.
async function pullOfRun({ actions, repo, run, lane, byNumber, ids, appId, mainSha }) {
  if (!lane.events.includes(run.event) || run.repository?.full_name !== repo) {
    return undefined;
  }
  // The run was started, and any rerun, by a listed account other than the
  // lanes App, or for a dispatch by github-actions[bot] on its first attempt:
  // the actors check-trusted-trigger accepts.
  const listed = (user) => Number.isInteger(user?.id) && ids.has(user.id) && user.id !== appId;
  const dispatcher = (user) => run.event === "workflow_dispatch" && user?.id === ACTIONS_BOT_ID && run.run_attempt === 1;
  if (![run.actor, run.triggering_actor].every((user) => listed(user) || dispatcher(user))) {
    return undefined;
  }
  // A dispatched run is on main; its title names the PR, and the check its
  // report job posted on the PR's current head links back to it.
  const number = DISPATCH_TITLE.exec(String(run.display_title ?? ""))?.[2];
  const pull = number === undefined || run.head_branch !== "main" ? undefined : byNumber.get(Number(number));
  if (pull === undefined || !SHA.test(String(run.head_sha))) {
    return undefined;
  }
  // A run on a tag named main also reports head_branch main: its commit must
  // be on the branch.
  const compare = await actions("GET", `/repos/${repo}/compare/${run.head_sha}...${mainSha}`);
  if (compare?.status !== "ahead" && compare?.status !== "identical") {
    return undefined;
  }
  const checks = (await actions("GET", `/repos/${repo}/commits/${pull.head.sha}/check-runs?per_page=100`))?.check_runs;
  const linked = Array.isArray(checks) && checks.some((check) => check.conclusion === "failure" && postingRunId(check) === String(run.id));
  return linked ? pull : undefined;
}

// Why this run's token step failed, when an empty commit can help, or null:
// `{kind: "workflow-modified", path}` for the workflow file the broker named,
// else, for a run of one of the lane's `transientActivities`,
// `{kind: "transient", label}` for a TRANSIENT failure.
async function refusedFile({ actions, repo, run, lane }) {
  const activity = DISPATCH_TITLE.exec(String(run.display_title ?? ""))?.[1];
  const transientOk = (lane.transientActivities ?? []).includes(activity);
  let transient = null;
  const jobs = (await actions("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
  if (!Array.isArray(jobs)) {
    throw new Error(`run ${run.id}'s jobs have an unexpected shape`);
  }
  for (const job of jobs) {
    // Only a write runner job requests the token. The jobs API can list a
    // completed job's steps empty or cut short: such a job whose list lacks
    // the token step is judged by its annotations.
    const writer = lane.writeCallers.some((caller) => job.name === `${caller} / run`);
    const token = (Array.isArray(job.steps) ? job.steps : []).find((step) => step.name === STEP);
    const failedAtToken = writer && job.conclusion === "failure" && (token === undefined || token.conclusion === "failure");
    if (!failedAtToken || !Number.isSafeInteger(job.id)) {
      continue;
    }
    const annotations = await actions("GET", `/repos/${repo}/check-runs/${job.id}/annotations?per_page=100`);
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
        transient = { kind: "transient", label: match[1] ?? `lane-token-denied ${match[2]} ${match[3]}` };
      }
    }
  }
  return transient;
}

// Why `pull` is not re-fired for `refused` now, or null with whether its
// marker is already posted.
async function refusal({ github, repo, pull, refused, run, blob, bot, lane, now, mainSha }) {
  // A run on a head that changes a file the broker compares came from that
  // file, not main's: no empty commit can make it pass, and its refusal could
  // have been printed by the edited file itself.
  // The three-dot compare lists what the PR changes since its merge base; it
  // lists at most 300 files, so a longer list is not read as complete.
  const changed = (await github("GET", `/repos/${repo}/compare/${mainSha}...${pull.head.sha}`))?.files;
  if (!Array.isArray(changed) || changed.length >= 300) {
    return { reason: "its changed files cannot be listed in full" };
  }
  const touched = lane.files.find((file) => changed.some((entry) => entry.filename === file || entry.previous_filename === file));
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

// The transient caps: one re-fire per failed run, TRANSIENT_PER_HEAD per head
// tree. A marker for this run at the current head means its push did not land.
async function transientRefusal({ github, repo, pull, run, comments, now }) {
  const tree = (await github("GET", `/repos/${repo}/git/commits/${pull.head.sha}`))?.tree?.sha;
  if (!SHA.test(String(tree))) {
    throw new Error(`the head ${pull.head.sha} has no tree`);
  }
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

// The head's tree, read after a fresh read of the PR: a PR closed, drafted,
// retargeted or pushed since the listing is left alone.
async function headTree(github, repo, pull) {
  const current = await github("GET", `/repos/${repo}/pulls/${pull.number}`);
  if (current?.head?.sha !== pull.head.sha || current.head.ref !== pull.head.ref || current.state !== "open" || current.draft === true || current.base?.ref !== "main") {
    throw new PullFailure("the PR changed since it was listed; nothing pushed");
  }
  const head = await github("GET", `/repos/${repo}/git/commits/${pull.head.sha}`);
  if (!SHA.test(String(head?.tree?.sha))) {
    throw new Error(`the head ${pull.head.sha} has no tree`);
  }
  return head.tree.sha;
}

// An empty commit on the head, moved onto the branch only as a fast-forward,
// so a push since the read fails it.
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
    // Only a branch since moved or gone is this PR's alone; one still at the
    // head refused the fast-forward for a reason every PR would hit.
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

// The job token's client (ACTIONS_TOKEN). The step's API_BUDGET_TOKEN names the
// lane token, so this client is pinned to github-token: its readings and its
// read-floor plan (github-token's limit-cap) are the job token's.
export const actionsClient = (env, { latch = rateLimitLatch, fetchImpl } = {}) =>
  createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, latch: budgetLatch("github-token", latch), ...(fetchImpl ? { fetchImpl } : {}) });

export async function main({ env = process.env, github, actions, now = Date.now() } = {}) {
  // The outcome counts, logged when the PRs were listed, whether or not the
  // run then stopped.
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

    // Main's tip, read once, so every compare and blob read in this run sees
    // one commit. A tag named main would make `main` ambiguous, so one must not
    // exist; only a 404 proves that (as check-trusted-trigger checks).
    let tagAbsent = false;
    try {
      await github("GET", `/repos/${repo}/git/ref/tags/main`);
    } catch (error) {
      tagAbsent = error instanceof GitHubError && error.status === 404;
    }
    if (!tagAbsent) {
      throw new Error("a tag named main exists, or its absence could not be read; nothing pushed");
    }
    const tip = await github("GET", `/repos/${repo}/git/ref/heads/main`);
    const mainSha = tip?.ref === "refs/heads/main" ? tip.object?.sha : undefined;
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
    // A lane's run listing failing fails the step after the other lanes.
    let listingFailed = false;
    // One refused file per PR, the first found.
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
    // Main's blob SHA of each named file, read once per run.
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
        // The fresh read first, so no marker is posted for a PR that changed;
        // then the record: a failed comment pushes nothing, so the bound holds.
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
