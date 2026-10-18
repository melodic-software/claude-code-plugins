#!/usr/bin/env node
// refire-refused.mjs: gives a pull request a new head when a pr-refine or
// pr-unblock run on its current head failed at "Request the lane token"
// because the token broker refused it as workflow-modified. A rerun
// keeps its first event's workflow files, so no rerun can pass; a new head
// starts fresh pull_request events, which run main's files. No model.
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
// Environment:
//   GH_TOKEN             the lane App token (contents and pull-requests write)
//   ACTIONS_TOKEN        the job's GITHUB_TOKEN (actions: read, checks: read)
//   GITHUB_REPOSITORY    owner/repo
//   KILL_SWITCH          `proceed` from the kill-switch step; anything else stops
//   TRUSTED_ACTORS_PATH  trusted-actors.json from the default branch tip
//   LANES_BOT_LOGIN      the lanes App bot login, the only marker author this
//                        trusts (default melodic-automation-lanes[bot])
//   LANES_APP_SENDER_ID  the lanes App sender id; a run it started never counts
//   GITHUB_STEP_SUMMARY  each push is listed there when set
//   GITHUB_API_URL
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { GitHubError, createGitHub, loadTrustedList, paginate } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

const DEFAULT_BOT = "melodic-automation-lanes[bot]";
const DEPENDABOT_ID = 49699333;
// github-actions[bot], the actor of a run a GITHUB_TOKEN dispatch started.
const ACTIONS_BOT_ID = 41898282;
// A marker at the current head whose push has not landed within this long is
// left to a person, so a push that keeps failing is not retried for days.
const RETRY_MS = 60 * 60_000;
const STEP = "Request the lane token";
const WRITE_RUNNER = ".github/workflows/pr-run-activity-write.yml";
// Each lane workflow, the event its runs on a PR head come from, and the files
// the broker compares for it (the caller, the write runner, a dispatcher).
const LANES = Object.freeze({
  "pr-refine.yml": { events: ["pull_request"], files: [".github/workflows/pr-refine.yml", WRITE_RUNNER] },
  "pr-unblock.yml": {
    events: ["workflow_dispatch"],
    files: [
      ".github/workflows/pr-unblock.yml",
      WRITE_RUNNER,
      ".github/workflows/pr-unblock-dispatch.yml",
      ".github/workflows/pr-feedback-dispatch.yml",
    ],
  },
});
const REFUSED =
  /^lane-token-denied: the broker answered 403 with reason workflow-modified: (\.github\/workflows\/[A-Za-z0-9._-]+\.yml) differs from refs\/heads\/main$/;
const MARKER = /^<!-- pr-lane-refire (\.github\/workflows\/[A-Za-z0-9._-]+\.yml)@([0-9a-f]{40}) head ([0-9a-f]{40}) -->/;
const DISPATCH_TITLE = /^pr-unblock [a-z]+(?:-[a-z]+)* #([1-9][0-9]{0,9})$/;
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

// pr-unblock's conflict resolution is dispatched by pr-unblock-dispatch, which
// runs only on a push to main or a listed person's manual dispatch, so the
// empty commit alone starts nothing for that lane.
const WHEN = Object.freeze({
  "pr-unblock.yml":
    "pr-merge pushes an empty commit so the next run starts on main's files. The conflict-resolution run starts at the next push to main, or when a listed person runs `pr-unblock-dispatch` by hand; nothing starts until then.",
});
const NEW_RUNS = "pr-merge pushes an empty commit so new runs start on main's files.";

export const refireComment = (path, blob, head, file = "pr-refine.yml") =>
  `<!-- pr-lane-refire ${path}@${blob} head ${head} -->\nA lane run on this pull request's head failed because the token broker refused it as workflow-modified: \`${path}\` changed on main after the run's event, and a rerun keeps the old file. ${WHEN[file] ?? NEW_RUNS} It does this once per version of that file, so if a run fails the same way again, a person looks at it.`;

const commitMessage = (path) =>
  `chore: start the lane checks again on main's workflow files\n\nThe token broker refused a lane run on the previous head as workflow-modified (${path}). This commit changes no file.`;

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
async function pullOfRun({ actions, repo, run, lane, byHead, byNumber, ids, appId, mainSha }) {
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
  if (run.event !== "workflow_dispatch") {
    return run.head_repository?.full_name === repo ? byHead.get(run.head_sha) : undefined;
  }
  // A dispatched run is on main; its title names the PR, and the check its
  // report job posted on the PR's current head links back to it.
  const number = DISPATCH_TITLE.exec(String(run.display_title ?? ""))?.[1];
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
  const link = `/${repo}/actions/runs/${run.id}`;
  const linked = Array.isArray(checks) && checks.some((check) => check.conclusion === "failure" && String(check.details_url ?? "").endsWith(link));
  return linked ? pull : undefined;
}

// The workflow file the broker named when it refused this run's token, or null.
async function refusedFile({ actions, repo, run, lane }) {
  const jobs = (await actions("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`))?.jobs;
  if (!Array.isArray(jobs)) {
    throw new Error(`run ${run.id}'s jobs have an unexpected shape`);
  }
  for (const job of jobs) {
    const failedAtToken =
      job.conclusion === "failure" &&
      Array.isArray(job.steps) &&
      job.steps.some((step) => step.name === STEP && step.conclusion === "failure");
    if (!failedAtToken || !Number.isSafeInteger(job.id)) {
      continue;
    }
    const annotations = await actions("GET", `/repos/${repo}/check-runs/${job.id}/annotations?per_page=100`);
    for (const annotation of Array.isArray(annotations) ? annotations : []) {
      const path = REFUSED.exec(String(annotation.message ?? ""))?.[1];
      if (annotation.annotation_level === "failure" && path !== undefined && lane.files.includes(path)) {
        return path;
      }
    }
  }
  return null;
}

// Why `pull` is not re-fired for `path` now, or null with whether its marker
// is already posted.
async function refusal({ github, repo, pull, path, blob, bot, lane, now, mainSha }) {
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
  const comments = await paginate(github, `/repos/${repo}/issues/${pull.number}/comments`);
  const markers = comments
    .filter((comment) => comment.user?.login === bot)
    .map((comment) => ({ match: MARKER.exec(String(comment.body ?? "")), at: Date.parse(comment.created_at) }))
    .filter(({ match }) => match !== null && match[1] === path && match[2] === blob);
  if (markers.some(({ match }) => match[3] !== pull.head.sha)) {
    return { reason: `already re-fired for ${path} at ${blob}` };
  }
  if (markers.some(({ at }) => !(now - at < RETRY_MS))) {
    return { reason: `its push for ${path} at ${blob} did not land; a person looks` };
  }
  return { reason: null, recorded: markers.length > 0 };
}

// The head's tree, read after a fresh read of the PR: a PR closed, drafted,
// retargeted or pushed since the listing is left alone.
async function headTree(github, repo, pull) {
  const current = await github("GET", `/repos/${repo}/pulls/${pull.number}`);
  if (current?.head?.sha !== pull.head.sha || current.head.ref !== pull.head.ref || current.state !== "open" || current.draft === true || current.base?.ref !== "main") {
    throw new Error("the PR changed since it was listed; nothing pushed");
  }
  const head = await github("GET", `/repos/${repo}/git/commits/${pull.head.sha}`);
  if (!SHA.test(String(head?.tree?.sha))) {
    throw new Error(`the head ${pull.head.sha} has no tree`);
  }
  return head.tree.sha;
}

// An empty commit on the head, moved onto the branch only as a fast-forward,
// so a push since the read fails it.
async function pushEmptyCommit(github, repo, pull, path, tree) {
  const commit = await github("POST", `/repos/${repo}/git/commits`, {
    message: commitMessage(path),
    tree,
    parents: [pull.head.sha],
  });
  if (!SHA.test(String(commit?.sha))) {
    throw new Error("the new commit has no SHA");
  }
  const ref = pull.head.ref.split("/").map(encodeURIComponent).join("/");
  await github("PATCH", `/repos/${repo}/git/refs/heads/${ref}`, { sha: commit.sha, force: false });
  return commit.sha;
}

export async function main({ env = process.env, github, actions, now = Date.now() } = {}) {
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
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    actions ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });

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

    const open = (await paginate(github, `/repos/${repo}/pulls?state=open&base=main`)).filter((pull) => qualifies(pull, repo, ids));
    const byHead = new Map(open.map((pull) => [pull.head.sha, pull]));
    const byNumber = new Map(open.map((pull) => [pull.number, pull]));
    let failed = 0;
    // One refused file per PR, the first found.
    const refused = new Map();
    for (const [file, lane] of Object.entries(LANES)) {
      let runs;
      try {
        runs = await failedRuns(actions, repo, file, now);
      } catch (error) {
        failed += 1;
        reportError(file, error);
        continue;
      }
      for (const run of runs) {
        try {
          const pull = await pullOfRun({ actions, repo, run, lane, byHead, byNumber, ids, appId, mainSha });
          if (pull === undefined || refused.has(pull.number)) {
            continue;
          }
          const path = await refusedFile({ actions, repo, run, lane });
          if (path !== null) {
            refused.set(pull.number, { pull, path, lane, file, run: run.id });
          }
        } catch (error) {
          failed += 1;
          reportError(`run ${run.id}`, error);
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
    for (const [number, { pull, path, lane, file, run }] of [...refused].sort((a, b) => a[0] - b[0])) {
      try {
        const blob = await blobOf(path);
        const { reason, recorded } = await refusal({ github, repo, pull, path, blob, bot, lane, now, mainSha });
        if (reason !== null) {
          console.log(`refire-refused: #${number} not re-fired: ${reason}`);
          continue;
        }
        ready.push({ pull, path, blob, recorded, file, run });
      } catch (error) {
        failed += 1;
        reportError(`#${number}`, error);
      }
    }
    for (const { pull } of ready.slice(REFIRES_PER_RUN)) {
      console.log(`refire-refused: #${pull.number} deferred: ${REFIRES_PER_RUN} re-fires this run`);
    }
    for (const { pull, path, blob, recorded, file, run } of ready.slice(0, REFIRES_PER_RUN)) {
      try {
        // The fresh read first, so no marker is posted for a PR that changed;
        // then the record: a failed comment pushes nothing, so the bound holds.
        const tree = await headTree(github, repo, pull);
        if (!recorded) {
          await github("POST", `/repos/${repo}/issues/${pull.number}/comments`, { body: refireComment(path, blob, pull.head.sha, file) });
        }
        const sha = await pushEmptyCommit(github, repo, pull, path, tree);
        const line = `#${pull.number} moved from ${pull.head.sha} to ${sha} after run ${run} was refused for ${path} at ${blob}`;
        console.log(`refire-refused: ${line}`);
        if (env.GITHUB_STEP_SUMMARY) {
          appendFileSync(env.GITHUB_STEP_SUMMARY, `- refire-refused: ${line}\n`);
        }
      } catch (error) {
        failed += 1;
        reportError(`#${pull.number}`, error);
      }
    }
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=refire-refused::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
